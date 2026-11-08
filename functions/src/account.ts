/**
 * Account management (F13): FCM token registration, memories export,
 * account deletion (Play requirement) and the daily cleanup job.
 */
import {randomUUID} from "node:crypto";
import archiver from "archiver";
import {onCall} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {getAuth} from "firebase-admin/auth";
import {DocumentData, Query, QueryDocumentSnapshot} from "firebase-admin/firestore";
import {
  db,
  bucket,
  REGION,
  CALLABLE_OPTS,
  FieldValue,
  Timestamp,
  UserDoc,
  requireAuth,
  userError,
  safeTz,
  str,
  logger,
} from "./common";
import {downloadUrl} from "./thumbnails";
import {unpairInternal} from "./pairing";

const MAX_TOKENS = 10;
const EXPORT_TTL_MS = 7 * 86_400_000;

/** Adds (or with `remove: true` removes) a device token for the caller. */
export const registerFcmToken = onCall<{token?: string; remove?: boolean; timezone?: string}>(
  CALLABLE_OPTS,
  async (req) => {
    const uid = requireAuth(req);
    const token = str(req.data?.token, 4096);
    if (!token) throw userError("invalid-argument", "bad-token", "Missing token.");
    const ref = db.doc(`devices/${uid}`);
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const current: string[] = (snap.get("tokens") as string[] | undefined) ?? [];
      let tokens = current.filter((t) => t !== token);
      if (!req.data?.remove) tokens = [...tokens, token].slice(-MAX_TOKENS);
      tx.set(ref, {tokens, updatedAt: FieldValue.serverTimestamp()}, {merge: true});
    });
    // Remove the token from any other account that used this device before.
    if (!req.data?.remove) {
      const others = await db.collection("devices").where("tokens", "array-contains", token).get();
      await Promise.all(
        others.docs.filter((d) => d.id !== uid).map((d) => d.ref.update({tokens: FieldValue.arrayRemove(token)})),
      );
    }
    const tz = req.data?.timezone;
    if (typeof tz === "string" && tz && safeTz(tz) === tz) {
      await db.doc(`users/${uid}`).set({timezone: tz}, {merge: true});
    }
    return {ok: true};
  },
);

function tsToIso(v: unknown): unknown {
  if (v instanceof Timestamp) return v.toDate().toISOString();
  if (Array.isArray(v)) return v.map(tsToIso);
  if (v && typeof v === "object") {
    return Object.fromEntries(Object.entries(v as Record<string, unknown>).map(([k, x]) => [k, tsToIso(x)]));
  }
  return v;
}

const plain = (d: QueryDocumentSnapshot<DocumentData>) => ({id: d.id, ...(tsToIso(d.data()) as object)});

/**
 * Builds a zip with every memory photo + a memories.json and returns a link
 * valid for 7 days. Works for the current pair and, during the 7-day window
 * after unpairing, for the previous one (pass `pairId`).
 */
export const exportMemories = onCall<{pairId?: string}>(
  {...CALLABLE_OPTS, memory: "1GiB", timeoutSeconds: 540},
  async (req) => {
    const uid = requireAuth(req);
    const user = (await db.doc(`users/${uid}`).get()).data() as UserDoc | undefined;
    const pairId = str(req.data?.pairId, 128) || user?.pairId;
    if (!pairId) throw userError("failed-precondition", "not-paired", "There are no memories to export yet.");
    const pairRef = db.doc(`pairs/${pairId}`);
    const pair = await pairRef.get();
    if (!pair.exists || !((pair.get("memberIds") as string[] | undefined) ?? []).includes(uid)) {
      throw userError("permission-denied", "wrong-pair", "You can't export these memories.");
    }

    const [items, questions, countdowns] = await Promise.all([
      pairRef.collection("items").orderBy("createdAt", "asc").get(),
      pairRef.collection("dailyQuestions").where("revealed", "==", true).get(),
      pairRef.collection("countdowns").get(),
    ]);

    const b = bucket();
    const date = new Date().toISOString().slice(0, 10);
    const path = `exports/${uid}/closer-memories-${date}-${Date.now()}.zip`;
    const out = b.file(path);
    const token = randomUUID();
    const writeStream = out.createWriteStream({
      resumable: false,
      contentType: "application/zip",
      metadata: {metadata: {firebaseStorageDownloadTokens: token}},
    });
    const archive = archiver("zip", {zlib: {level: 1}}); // photos are already compressed
    const done = new Promise<void>((resolve, reject) => {
      writeStream.on("finish", () => resolve());
      writeStream.on("error", reject);
      archive.on("error", reject);
    });
    archive.pipe(writeStream);

    const json = {
      exportedAt: new Date().toISOString(),
      pair: {id: pairId, mode: pair.get("mode"), pairedAt: tsToIso(pair.get("pairedAt"))},
      items: items.docs.map(plain),
      dailyQuestions: questions.docs.map(plain),
      countdowns: countdowns.docs.map(plain),
    };
    archive.append(JSON.stringify(json, null, 2), {name: "memories.json"});

    for (const item of items.docs) {
      const storagePath = item.get("storagePath");
      if (typeof storagePath !== "string") continue;
      const f = b.file(storagePath);
      const [exists] = await f.exists();
      if (!exists) continue;
      const created = item.get("createdAt") as Timestamp | undefined;
      const prefix = created ? created.toDate().toISOString().slice(0, 10) : "undated";
      archive.append(f.createReadStream(), {name: `photos/${prefix}_${item.id}.jpg`});
    }
    await archive.finalize();
    await done;

    let url: string;
    try {
      // Needs the "Service Account Token Creator" role for signBlob.
      [url] = await out.getSignedUrl({action: "read", expires: Date.now() + EXPORT_TTL_MS});
    } catch (e) {
      logger.warn("getSignedUrl failed, using token URL (deleted after 7 days by dailyCleanup)", {e});
      url = downloadUrl(b.name, path, token);
    }
    return {url, expiresAt: Date.now() + EXPORT_TTL_MS, items: items.size};
  },
);

/** BulkWriter ops return promises; log failures instead of leaving them unhandled. */
function quiet(p: Promise<unknown>): void {
  p.catch((e) => logger.warn("bulk write failed", {e}));
}

async function deleteQuery(q: Query): Promise<number> {
  const snap = await q.get();
  const writer = db.bulkWriter();
  snap.docs.forEach((d) => quiet(writer.delete(d.ref)));
  await writer.close();
  return snap.size;
}

/**
 * Deletes the caller's account: unpairs, removes their items, answers,
 * files, tokens and profile, then deletes the Auth user.
 */
export const deleteAccount = onCall(
  {...CALLABLE_OPTS, timeoutSeconds: 540, memory: "512MiB"},
  async (req) => {
    const uid = requireAuth(req);
    const user = (await db.doc(`users/${uid}`).get()).data() as UserDoc | undefined;
    if (user?.pairId) {
      try {
        await unpairInternal(user.pairId, uid);
      } catch (e) {
        logger.error("unpair during delete failed", {uid, e});
      }
    }
    const b = bucket();

    // Everything this user contributed to any pair they were part of.
    const pairs = await db.collection("pairs").where("memberIds", "array-contains", uid).get();
    for (const pair of pairs.docs) {
      const items = await pair.ref.collection("items").where("senderId", "==", uid).get();
      for (const item of items.docs) {
        for (const p of [item.get("storagePath"), item.get("thumbPath")]) {
          if (typeof p === "string") await b.file(p).delete({ignoreNotFound: true});
        }
      }
      const writer = db.bulkWriter();
      items.docs.forEach((d) => quiet(writer.delete(d.ref)));
      const taps = await pair.ref.collection("taps").where("senderId", "==", uid).get();
      taps.docs.forEach((d) => quiet(writer.delete(d.ref)));
      const qs = await pair.ref.collection("dailyQuestions").get();
      qs.docs.forEach((q) => {
        quiet(writer.delete(q.ref.collection("private").doc(uid)));
        quiet(writer.update(q.ref, {[`answers.${uid}`]: FieldValue.delete()}));
      });
      quiet(writer.update(pair.ref, {[`latestItemByUser.${uid}`]: FieldValue.delete()}));
      await writer.close();
    }

    await deleteQuery(db.collection("usage").where("uid", "==", uid));
    await deleteQuery(db.collection("invites").where("inviterUid", "==", uid));
    await Promise.all([
      db.doc(`devices/${uid}`).delete(),
      db.doc(`entitlements/${uid}`).delete(),
      db.recursiveDelete(db.doc(`users/${uid}`)),
      b.deleteFiles({prefix: `users/${uid}/`}),
      b.deleteFiles({prefix: `exports/${uid}/`}),
    ]);
    try {
      await getAuth().deleteUser(uid);
    } catch (e) {
      logger.error("Auth deleteUser failed", {uid, e});
    }
    logger.info("Account deleted", {uid});
    return {ok: true};
  },
);

/**
 * Daily: delete pairs whose post-unpair export window has passed, old
 * exports and expired invites.
 */
export const dailyCleanup = onSchedule(
  {schedule: "30 3 * * *", timeZone: "Europe/London", region: REGION, timeoutSeconds: 540, memory: "512MiB"},
  async () => {
    const now = Timestamp.now();
    const b = bucket();

    const due = await db.collection("pairs").where("status", "==", "unpaired").where("deleteAfter", "<=", now).get();
    for (const pair of due.docs) {
      try {
        await b.deleteFiles({prefix: `pairs/${pair.id}/`});
        await db.recursiveDelete(pair.ref);
      } catch (e) {
        logger.error("pair cleanup failed", {pairId: pair.id, e});
      }
    }

    const [files] = await b.getFiles({prefix: "exports/"});
    const cutoff = Date.now() - EXPORT_TTL_MS;
    for (const f of files) {
      const created = Date.parse(String((f.metadata as {timeCreated?: string}).timeCreated ?? ""));
      if (!Number.isNaN(created) && created < cutoff) await f.delete({ignoreNotFound: true});
    }

    const invites = await deleteQuery(db.collection("invites").where("expiresAt", "<=", Timestamp.fromMillis(Date.now() - 86_400_000)));
    logger.info("dailyCleanup", {pairs: due.size, invites});
  },
);
