/**
 * Sending photos / notes / doodles (F3), thinking-of-you taps (F5) and the
 * rewarded-ad bonus sends.
 */
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {
  db,
  bucket,
  CALLABLE_OPTS,
  FREE,
  FieldValue,
  Timestamp,
  PairDoc,
  requireAuth,
  requirePair,
  isPremium,
  limitError,
  userError,
  str,
  firstName,
  localDateKey,
  nextLocalMidnight,
  sendWidgetData,
  getUser,
  notify,
  logger,
} from "./common";
import {ensureThumbnail, rawPath, thumbPath} from "./thumbnails";
import {markActivity} from "./streaks";

const ITEM_TYPES = ["photo", "note", "doodle", "location"] as const;
type ItemType = (typeof ITEM_TYPES)[number];
const ID_RE = /^[A-Za-z0-9_-]{6,40}$/;
const NOTE_BGS = /^[a-z0-9_-]{1,24}$/;

function usageRef(uid: string, dateKey: string) {
  return db.doc(`usage/${uid}_${dateKey}`);
}

interface SendItemInput {
  pairId?: string;
  itemId?: string;
  type?: string;
  caption?: string;
  text?: string;
  noteStyle?: {bg?: string; font?: string};
  geo?: {lat?: unknown; lng?: unknown; place?: unknown};
  saveToMemories?: boolean;
  secret?: boolean;
}

/** Shown instead of the sender's name on secret-admirer items. */
const ADMIRER_NAME = "A secret admirer";

/**
 * The app uploads the image to pairs/{pairId}/raw/{itemId}.jpg first, then
 * calls this. Returns the item as JSON (dates in millis).
 */
export const sendItem = onCall<SendItemInput>(
  {...CALLABLE_OPTS, memory: "1GiB", timeoutSeconds: 60},
  async (req) => {
    const uid = requireAuth(req);
    const input = req.data ?? {};
    const ctx = await requirePair(uid, input.pairId);
    const {pairId, pairRef, partnerUid} = ctx;

    const itemId = str(input.itemId, 40);
    if (!ID_RE.test(itemId)) throw userError("invalid-argument", "bad-item", "Invalid item id.");
    const type: ItemType = ITEM_TYPES.includes(input.type as ItemType) ? (input.type as ItemType) : "photo";
    const caption = str(input.caption, 40);
    const text = type === "note" ? str(input.text, 500) || null : null;
    const noteStyle =
      input.noteStyle && typeof input.noteStyle === "object" ?
        {
          bg: NOTE_BGS.test(String(input.noteStyle.bg)) ? String(input.noteStyle.bg) : "blush",
          font: NOTE_BGS.test(String(input.noteStyle.font)) ? String(input.noteStyle.font) : "rounded",
        } :
        null;
    const geo = type === "location" ? parseGeo(input.geo) : null;
    if (type === "location" && !geo) throw userError("invalid-argument", "bad-geo", "Missing location.");
    const saveToMemories = input.saveToMemories !== false;
    const secret = input.secret === true;

    const raw = bucket().file(rawPath(pairId, itemId));
    const [rawExists] = await raw.exists();
    if (!rawExists) throw userError("failed-precondition", "upload-missing", "The upload didn't finish. Try again.");

    // Idempotent retries (offline queue): return the existing item.
    const itemRef = pairRef.collection("items").doc(itemId);
    const existing = await itemRef.get();
    if (existing.exists) return serializeItem(itemId, existing.data() ?? {});

    // Fast-fail on the limit before doing image work.
    const premiumNow = isPremium(ctx.pair);
    const now = new Date();
    const today = localDateKey(now, ctx.pair.timezone);
    const usageSnap = await usageRef(uid, today).get();
    const sends = Number(usageSnap.get("sends") ?? 0);
    const bonus = Number(usageSnap.get("bonusSends") ?? 0);
    const max = premiumNow ? FREE.plusSendsPerDay : FREE.sendsPerDay + bonus;
    if (sends >= max) {
      await raw.delete({ignoreNotFound: true});
      throw limitError("sends", "You've used today's free sends.", {used: sends, max});
    }

    let thumb: {thumbPath: string; thumbUrl: string};
    try {
      thumb = await ensureThumbnail(pairId, itemId);
    } catch (e) {
      logger.error("ensureThumbnail failed", {pairId, itemId, e});
      throw new HttpsError("internal", "Couldn't process that image.");
    }

    const createdAt = Timestamp.fromDate(now);
    const item = {
      type,
      senderId: uid,
      storagePath: rawPath(pairId, itemId),
      thumbPath: thumb.thumbPath,
      caption,
      text,
      noteStyle,
      geo,
      saveToMemories,
      reactions: {},
      secret,
      revealedAt: null,
      createdAt,
    };

    await db.runTransaction(async (tx) => {
      const pairSnap = await tx.get(pairRef);
      const pair = pairSnap.data() as PairDoc | undefined;
      if (!pair || pair.status !== "active") {
        throw userError("failed-precondition", "not-paired", "You're not connected to anyone yet.");
      }
      const itemSnap = await tx.get(itemRef);
      if (itemSnap.exists) return;
      const uRef = usageRef(uid, today);
      const u = await tx.get(uRef);
      const used = Number(u.get("sends") ?? 0);
      const extra = Number(u.get("bonusSends") ?? 0);
      const premium = isPremium(pair);
      const limit = premium ? FREE.plusSendsPerDay : FREE.sendsPerDay + extra;
      if (used >= limit) throw limitError("sends", "You've used today's free sends.", {used, max: limit});
      tx.set(
        uRef,
        {
          uid,
          date: today,
          sends: used + 1,
          expiresAt: Timestamp.fromDate(nextLocalMidnight(now, pair.timezone)),
          updatedAt: FieldValue.serverTimestamp(),
        },
        {merge: true},
      );
      tx.create(itemRef, item);
      tx.update(pairRef, {
        [`latestItemByUser.${uid}`]: {
          itemId,
          type,
          thumbPath: thumb.thumbPath,
          caption,
          secret,
          sentAt: createdAt,
        },
        "stats.itemsSent": FieldValue.increment(1),
      });
    });

    await markActivity(pairId, uid);

    if (partnerUid) {
      const partner = await getUser(partnerUid);
      await sendWidgetData(
        partnerUid,
        {
          type: "item",
          pairId,
          itemId,
          itemType: type,
          thumbUrl: thumb.thumbUrl,
          caption,
          senderName: secret ? ADMIRER_NAME : firstName(ctx.user),
          secret: secret ? "1" : "0",
          sentAt: String(createdAt.toMillis()),
        },
        {user: partner},
      );
    }

    return serializeItem(itemId, item);
  },
);

/** Validates {lat, lng, place} from the app; null when unusable. */
function parseGeo(g: SendItemInput["geo"]): {lat: number; lng: number; place: string} | null {
  if (!g || typeof g !== "object") return null;
  const lat = Number(g.lat);
  const lng = Number(g.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  return {lat, lng, place: str(g.place, 80)};
}

function serializeItem(id: string, d: Record<string, unknown>) {
  const created = d.createdAt instanceof Timestamp ? d.createdAt.toMillis() : Date.now();
  return {
    id,
    type: d.type ?? "photo",
    senderId: d.senderId ?? "",
    storagePath: d.storagePath ?? null,
    thumbPath: d.thumbPath ?? null,
    caption: d.caption ?? "",
    text: d.text ?? null,
    noteStyle: d.noteStyle ?? null,
    geo: d.geo ?? null,
    saveToMemories: d.saveToMemories !== false,
    reactions: d.reactions ?? {},
    secret: d.secret === true,
    revealedAt: d.revealedAt instanceof Timestamp ? d.revealedAt.toMillis() : null,
    createdAt: created,
  };
}

/** Keep in sync with `reactionEmojis` in lib/core/models/models.dart. */
const REACTIONS = ["❤️", "😍", "🥹", "😂", "😘", "🔥", "👏"];

const ITEM_WORD: Record<string, string> = {
  photo: "photo",
  note: "note",
  doodle: "doodle",
  location: "location photo",
};

/** Sets or (emoji = null) clears the caller's reaction on an item. */
export const reactItem = onCall<{pairId?: string; itemId?: string; emoji?: string | null}>(
  CALLABLE_OPTS,
  async (req) => {
    const uid = requireAuth(req);
    const ctx = await requirePair(uid, req.data?.pairId);
    const itemId = str(req.data?.itemId, 40);
    if (!ID_RE.test(itemId)) throw userError("invalid-argument", "bad-item", "Invalid item id.");
    const emoji = req.data?.emoji ?? null;
    if (emoji !== null && !REACTIONS.includes(String(emoji))) {
      throw userError("invalid-argument", "bad-reaction", "Unknown reaction.");
    }
    const itemRef = ctx.pairRef.collection("items").doc(itemId);
    const snap = await itemRef.get();
    if (!snap.exists) throw userError("not-found", "no-item", "That memory is gone.");
    const previous = snap.get(`reactions.${uid}`) as string | undefined;
    await itemRef.update({[`reactions.${uid}`]: emoji === null ? FieldValue.delete() : emoji});

    const senderId = String(snap.get("senderId") ?? "");
    if (emoji !== null && emoji !== previous && senderId && senderId !== uid) {
      const what = ITEM_WORD[String(snap.get("type"))] ?? "photo";
      await notify(senderId, {
        channel: "taps",
        type: "reaction",
        title: `${firstName(ctx.user)} reacted ${emoji}`,
        body: `to your ${what}`,
        data: {route: `/item/${itemId}`, pairId: ctx.pairId, itemId},
        prefKey: "taps",
      });
    }
    return {itemId, emoji};
  },
);

/** The sender of a secret-admirer item reveals who they are. */
export const revealAdmirer = onCall<{pairId?: string; itemId?: string}>(CALLABLE_OPTS, async (req) => {
  const uid = requireAuth(req);
  const ctx = await requirePair(uid, req.data?.pairId);
  const itemId = str(req.data?.itemId, 40);
  if (!ID_RE.test(itemId)) throw userError("invalid-argument", "bad-item", "Invalid item id.");
  const itemRef = ctx.pairRef.collection("items").doc(itemId);
  let changed = false as boolean;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(itemRef);
    if (!snap.exists) throw userError("not-found", "no-item", "That note is gone.");
    if (snap.get("senderId") !== uid) {
      throw userError("permission-denied", "not-sender", "Only the sender can reveal this.");
    }
    if (snap.get("secret") !== true || snap.get("revealedAt")) return;
    const pair = (await tx.get(ctx.pairRef)).data() as
      (PairDoc & {latestItemByUser?: Record<string, {itemId?: string}>}) | undefined;
    tx.update(itemRef, {revealedAt: FieldValue.serverTimestamp()});
    if (pair?.latestItemByUser?.[uid]?.itemId === itemId) {
      tx.update(ctx.pairRef, {[`latestItemByUser.${uid}.secret`]: false});
    }
    changed = true;
  });
  if (changed && ctx.partnerUid) {
    await notify(ctx.partnerUid, {
      channel: "partner_items",
      type: "admirer_revealed",
      title: `Your secret admirer was ${firstName(ctx.user)} 💘`,
      body: "Of course it was. Tap to see the note again.",
      data: {route: `/item/${itemId}`, pairId: ctx.pairId, itemId},
    });
  }
  return {itemId, revealed: true};
});

const TAP_KIND_RE = /^[a-z0-9_-]{1,24}$/;

/**
 * One-tap messages everyone gets ("I can't stop thinking about you").
 * Keep in sync with TapKind.all in lib/core/models/models.dart. Any other
 * kind is a custom tap (Plus).
 */
const TAP_KINDS: Record<string, string> = {
  heart: "is thinking of you 💗",
  thinking: "can't stop thinking about you 💭",
  miss: "misses you so much 🥺",
  hug: "sent you a big warm hug 🤗",
  kiss: "sent you a kiss 😘",
  proud: "is so proud of you 🌟",
  love: "loves you ❤️",
};

/** Thinking-of-you tap, rate limited to one per 10 s per sender. */
export const sendTap = onCall<{pairId?: string; kind?: string}>(CALLABLE_OPTS, async (req) => {
  const uid = requireAuth(req);
  const ctx = await requirePair(uid, req.data?.pairId);
  const {pairId, pairRef, partnerUid} = ctx;
  const kind = TAP_KIND_RE.test(String(req.data?.kind ?? "heart")) ? String(req.data?.kind ?? "heart") : "heart";
  if (!(kind in TAP_KINDS) && !isPremium(ctx.pair)) {
    throw limitError("plus", "Custom taps are part of Duosy Plus.");
  }

  const tapRef = pairRef.collection("taps").doc();
  const now = Timestamp.now();
  await db.runTransaction(async (tx) => {
    const pair = (await tx.get(pairRef)).data() as PairDoc | undefined;
    if (!pair || pair.status !== "active") {
      throw userError("failed-precondition", "not-paired", "You're not connected to anyone yet.");
    }
    const last = pair.lastTapByUser?.[uid];
    if (last && now.toMillis() - last.toMillis() < FREE.tapCooldownMs) {
      throw limitError("taps", "Easy there, wait a few seconds 💗", {
        retryAfterMs: FREE.tapCooldownMs - (now.toMillis() - last.toMillis()),
      });
    }
    tx.create(tapRef, {
      senderId: uid,
      kind,
      createdAt: now,
      // TTL policy on taps.expireAt deletes taps after 30 days.
      expireAt: Timestamp.fromMillis(now.toMillis() + 30 * 86_400_000),
    });
    tx.update(pairRef, {
      [`lastTapByUser.${uid}`]: now,
      "stats.tapsSent": FieldValue.increment(1),
    });
  });

  await markActivity(pairId, uid);

  if (partnerUid) {
    await sendWidgetData(
      partnerUid,
      {
        type: "tap",
        pairId,
        tapId: tapRef.id,
        kind,
        message: TAP_KINDS[kind] ?? TAP_KINDS.heart,
        senderName: firstName(ctx.user),
        sentAt: String(now.toMillis()),
      },
      {prefKey: "taps", ttlMs: 3600 * 1000},
    );
  }
  return {id: tapRef.id, senderId: uid, kind, createdAt: now.toMillis()};
});

/**
 * +3 sends today after a rewarded ad, at most once per day.
 * TODO(prod): switch to AdMob server-side verification (SSV) callbacks so
 * the reward cannot be claimed without watching an ad.
 */
export const grantRewardedSends = onCall<{pairId?: string}>(CALLABLE_OPTS, async (req) => {
  const uid = requireAuth(req);
  const ctx = await requirePair(uid, req.data?.pairId);
  const now = new Date();
  const today = localDateKey(now, ctx.pair.timezone);
  const ref = usageRef(uid, today);
  return db.runTransaction(async (tx) => {
    const u = await tx.get(ref);
    const grants = Number(u.get("rewardedGrants") ?? 0);
    if (grants >= FREE.rewardedGrantsPerDay) {
      throw limitError("rewarded", "No more bonus sends today. Come back tomorrow!");
    }
    const bonus = Number(u.get("bonusSends") ?? 0) + FREE.rewardedExtraSends;
    tx.set(
      ref,
      {
        uid,
        date: today,
        sends: Number(u.get("sends") ?? 0),
        bonusSends: bonus,
        rewardedGrants: grants + 1,
        expiresAt: Timestamp.fromDate(nextLocalMidnight(now, ctx.pair.timezone)),
        updatedAt: FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    return {bonusSends: bonus, maxToday: FREE.sendsPerDay + bonus};
  });
});

// Re-exported for account deletion.
export {rawPath, thumbPath};
