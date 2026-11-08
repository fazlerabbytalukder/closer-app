/**
 * Pairing (F1): invites, accepting, unpairing.
 */
import {randomInt} from "node:crypto";
import {onCall} from "firebase-functions/v2/https";
import {
  db,
  CALLABLE_OPTS,
  FieldValue,
  Timestamp,
  PairDoc,
  PairMode,
  UserDoc,
  requireAuth,
  userError,
  safeTz,
  localDateKey,
  firstName,
  notify,
  sendWidgetData,
  logger,
  MONETIZATION_ENABLED,
} from "./common";

/** Relationship labels, keep in sync with RelationLabel in models.dart. */
const LABELS: Record<PairMode, string[]> = {
  couple: ["girlfriend", "boyfriend", "partner", "wife", "husband", "fiance"],
  friends: ["best_friend", "bff", "bestie", "sibling"],
};
import {readPairPremium} from "./premium";
import {initialStreak, INITIAL_PLANT} from "./streaks";
import {assignQuestionForPair} from "./questions";

/** No 0/O/1/I/L to keep codes easy to read aloud. */
const ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
const CODE_LEN = 6;
const INVITE_TTL_MS = 48 * 3600 * 1000;
export const UNPAIR_GRACE_MS = 7 * 86_400_000;
export const INVITE_BASE_URL = "https://closer.app/i/";

function makeCode(): string {
  let s = "";
  for (let i = 0; i < CODE_LEN; i++) s += ALPHABET[randomInt(ALPHABET.length)];
  return s;
}

export function normaliseCode(raw: unknown): string {
  if (typeof raw !== "string") return "";
  // Accept full links too: https://closer.app/i/ABC123
  const tail = raw.trim().split("/").filter(Boolean).pop() ?? "";
  return tail.toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, CODE_LEN);
}

export const createInvite = onCall<{mode?: string}>(CALLABLE_OPTS, async (req) => {
  const uid = requireAuth(req);
  const mode: PairMode = req.data?.mode === "friends" ? "friends" : "couple";
  const user = (await db.doc(`users/${uid}`).get()).data() as UserDoc | undefined;
  if (!user) throw userError("failed-precondition", "no-profile", "Finish your profile first.");
  if (user.pairId) throw userError("failed-precondition", "already-paired", "You're already connected.");

  // Supersede older open invites from this user.
  const open = await db.collection("invites").where("inviterUid", "==", uid).where("usedBy", "==", null).get();

  const expiresAt = Timestamp.fromMillis(Date.now() + INVITE_TTL_MS);
  for (let attempt = 0; attempt < 8; attempt++) {
    const code = makeCode();
    const ref = db.doc(`invites/${code}`);
    try {
      await db.runTransaction(async (tx) => {
        const existing = await tx.get(ref);
        if (existing.exists) throw new Error("collision");
        tx.create(ref, {
          inviterUid: uid,
          mode,
          expiresAt,
          usedBy: null,
          createdAt: FieldValue.serverTimestamp(),
        });
        for (const d of open.docs) tx.update(d.ref, {usedBy: "superseded"});
        tx.update(db.doc(`users/${uid}`), {pendingMode: mode});
      });
      return {
        code,
        inviterUid: uid,
        mode,
        expiresAt: expiresAt.toMillis(),
        usedBy: null,
        link: `${INVITE_BASE_URL}${code}`,
      };
    } catch (e) {
      if (e instanceof Error && e.message === "collision") continue;
      throw e;
    }
  }
  throw userError("failed-precondition", "busy", "Couldn't create a code, please try again.");
});

export const acceptInvite = onCall<{code?: string}>(CALLABLE_OPTS, async (req) => {
  const uid = requireAuth(req);
  const code = normaliseCode(req.data?.code);
  if (code.length !== CODE_LEN) throw userError("invalid-argument", "bad-code", "That code doesn't look right.");
  const inviteRef = db.doc(`invites/${code}`);

  const result = await db.runTransaction(async (tx) => {
    // ---- reads
    const invite = await tx.get(inviteRef);
    if (!invite.exists) throw userError("not-found", "unknown", "We couldn't find that code.");
    const inviterUid = invite.get("inviterUid") as string;
    const usedBy = invite.get("usedBy") as string | null;
    const expiresAt = invite.get("expiresAt") as Timestamp | undefined;

    if (inviterUid === uid) throw userError("invalid-argument", "self", "That's your own code — send it to your person.");

    const meRef = db.doc(`users/${uid}`);
    const themRef = db.doc(`users/${inviterUid}`);
    const [me, them] = await Promise.all([tx.get(meRef), tx.get(themRef)]);
    const myPair = me.get("pairId") as string | null | undefined;
    const theirPair = them.get("pairId") as string | null | undefined;

    // Idempotent: already paired with each other (e.g. double tap, or both
    // accepted each other's code at the same time).
    if (myPair && myPair === theirPair) return {pairId: myPair, created: false, inviterUid};

    if (usedBy) {
      throw userError("already-exists", "used", "That code has already been used.");
    }
    if (!expiresAt || expiresAt.toMillis() < Date.now()) {
      throw userError("failed-precondition", "expired", "That code has expired. Ask for a new one.");
    }
    if (!me.exists) throw userError("failed-precondition", "no-profile", "Finish your profile first.");
    if (!them.exists) throw userError("not-found", "unknown", "We couldn't find that code.");
    if (myPair) throw userError("failed-precondition", "already-paired", "You're already connected to someone.");
    if (theirPair) {
      throw userError("failed-precondition", "inviter-paired", "This person is already connected to someone else.");
    }

    // Both inviting at once: retire any open invites from either person.
    const openMine = await tx.get(db.collection("invites").where("inviterUid", "==", uid).where("usedBy", "==", null));
    const openTheirs = await tx.get(
      db.collection("invites").where("inviterUid", "==", inviterUid).where("usedBy", "==", null),
    );
    const memberIds = [inviterUid, uid];
    const {premium, ownedPacks} = await readPairPremium(tx, memberIds);

    // ---- writes
    const pairRef = db.collection("pairs").doc();
    const timezone = safeTz((them.data() as UserDoc).timezone ?? (me.data() as UserDoc).timezone);
    const today = localDateKey(new Date(), timezone);
    const mode: PairMode = (invite.get("mode") as PairMode) === "friends" ? "friends" : "couple";
    // Each member's onboarding choice ("they are my girlfriend") carries over
    // when it fits the invite's mode.
    const relationLabels: Record<string, string> = {};
    for (const [memberUid, snap] of [[inviterUid, them], [uid, me]] as const) {
      const label = snap.get("pendingLabel");
      if (typeof label === "string" && LABELS[mode].includes(label)) relationLabels[memberUid] = label;
    }
    const pair: PairDoc & Record<string, unknown> = {
      memberIds,
      mode,
      status: "active",
      pairedAt: Timestamp.now(),
      timezone,
      relationLabels,
      nicknames: {},
      latestItemByUser: {},
      streak: {...initialStreak(today, premium.active || !MONETIZATION_ENABLED)},
      plant: {...INITIAL_PLANT},
      premium,
      ownedPacks,
      widgetTheme: {},
      stats: {itemsSent: 0, questionsAnswered: 0, tapsSent: 0},
      questionPack: "everyday",
      questionCursor: {},
      lastTapByUser: {},
    };
    tx.create(pairRef, pair);
    const clearPending = {pendingMode: FieldValue.delete(), pendingLabel: FieldValue.delete()};
    tx.update(meRef, {pairId: pairRef.id, ...clearPending});
    tx.update(themRef, {pairId: pairRef.id, ...clearPending});
    tx.update(inviteRef, {usedBy: uid, usedAt: FieldValue.serverTimestamp()});
    for (const d of [...openMine.docs, ...openTheirs.docs]) {
      if (d.id !== code) tx.update(d.ref, {usedBy: "superseded"});
    }
    return {pairId: pairRef.id, created: true, inviterUid};
  });

  if (result.created) {
    try {
      await assignQuestionForPair(db.doc(`pairs/${result.pairId}`), {force: true});
    } catch (e) {
      logger.error("first question failed", {pairId: result.pairId, e});
    }
    const me = (await db.doc(`users/${uid}`).get()).data() as UserDoc | undefined;
    await notify(result.inviterUid, {
      channel: "account",
      type: "paired",
      title: "You're connected 💞",
      body: `${firstName(me)} joined you on Closer.`,
      data: {route: "/home", pairId: result.pairId},
      ignoreQuiet: false,
    });
  }
  return {pairId: result.pairId};
});

/**
 * Unlinks both members from [pairId] and schedules its deletion after the
 * export window (see dailyCleanup). Used by `unpair` and `deleteAccount`.
 */
export async function unpairInternal(pairId: string, byUid: string): Promise<string[]> {
  const pairRef = db.doc(`pairs/${pairId}`);
  let members: string[] = [];
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(pairRef);
    const pair = snap.data() as PairDoc | undefined;
    if (!pair) return;
    members = pair.memberIds ?? [];
    const users = await Promise.all(members.map((m) => tx.get(db.doc(`users/${m}`))));
    if (pair.status !== "unpaired") {
      tx.update(pairRef, {
        status: "unpaired",
        unpairedAt: FieldValue.serverTimestamp(),
        unpairedBy: byUid,
        deleteAfter: Timestamp.fromMillis(Date.now() + UNPAIR_GRACE_MS),
        // Plus stays with the buyer only (their entitlement is untouched).
        premium: {active: false, source: "subscription", ownerUid: null, expiresAt: null},
      });
    }
    users.forEach((u) => {
      if (u.exists && u.get("pairId") === pairId) tx.update(u.ref, {pairId: null});
    });
  });
  // Clear the widgets on both phones.
  await Promise.all(members.map((m) => sendWidgetData(m, {type: "unpaired", pairId})));
  return members;
}

export const unpair = onCall<{pairId?: string}>(CALLABLE_OPTS, async (req) => {
  const uid = requireAuth(req);
  const user = (await db.doc(`users/${uid}`).get()).data() as UserDoc | undefined;
  const pairId = user?.pairId;
  if (!pairId) return {ok: true};
  const members = await unpairInternal(pairId, uid);
  const partner = members.find((m) => m !== uid);
  if (partner) {
    await notify(partner, {
      channel: "account",
      type: "unpaired",
      title: "Closer",
      body: `${firstName(user)} disconnected. Your memories can be exported for 7 days.`,
      data: {route: "/home", pairId},
    });
  }
  return {ok: true, deleteAfterMs: Date.now() + UNPAIR_GRACE_MS};
});
