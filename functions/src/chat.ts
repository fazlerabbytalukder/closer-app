/**
 * Private chat (F11) and the goodnight ritual (F10).
 *
 * pairs/{pairId}/messages/{id}   written by the app (rules-checked)
 * pairs/{pairId}/chatState/{uid} readAt, typingUntil (each member their own)
 * pairs/{pairId}/goodnights/{yyyy-mm-dd} entries: {uid: {...}}
 *
 * These functions notify the partner, count chat and goodnights as streak
 * activity, and send the evening goodnight reminder.
 */
import {onDocumentCreated, onDocumentDeleted, onDocumentUpdated, onDocumentWritten} from "firebase-functions/v2/firestore";
import {Timestamp} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {db, REGION, PairDoc, getUser, firstName, notify, notifyChat, localDateKey, localHour, logger} from "./common";
import {markActivity} from "./streaks";

/** Local hour the goodnight reminder goes out. */
const GOODNIGHT_HOUR = 21;

function preview(d: FirebaseFirestore.DocumentData): string {
  switch (d.type) {
    case "photo":
      return d.text ? `📷 ${String(d.text).slice(0, 80)}` : "📷 Photo";
    case "voice":
      return "🎤 Voice message";
    case "snap":
      return "👻 Sent you a snap";
    case "event": {
      const snap = String(d.replyTo?.preview ?? "").startsWith("👻");
      if (d.event === "saved") return "⬇️ Saved your photo";
      if (d.event === "ttl") return "⏱️ Changed disappearing messages";
      return d.replyTo ? `📸 Took a screenshot of your ${snap ? "snap" : "photo"}` : "📸 Took a screenshot of the chat";
    }
    default: {
      const t = String(d.text ?? "");
      return t.length > 120 ? `${t.slice(0, 119)}…` : t;
    }
  }
}

export const onMessageCreated = onDocumentCreated(
  {document: "pairs/{pairId}/messages/{messageId}", region: REGION},
  async (event) => {
    const d = event.data?.data();
    if (!d) return;
    const pairId = event.params.pairId;
    const sender = String(d.senderId ?? "");
    const pair = (await db.doc(`pairs/${pairId}`).get()).data() as PairDoc | undefined;
    if (!pair || pair.status !== "active") return;
    const to = pair.memberIds.find((m) => m !== sender);
    // Screenshot / save notices aren't "talking" for the streak.
    if (d.type !== "event") {
      try {
        await markActivity(pairId, sender);
      } catch (e) {
        logger.warn("markActivity failed for chat", {pairId, e});
      }
    }
    if (!to) return;
    const user = await getUser(sender);
    // The app shows it as a chat head (Android) or iOS shows the alert.
    await notifyChat(to, {
      title: firstName(user),
      body: preview(d),
      data: {route: "/chat", pairId, messageId: event.params.messageId, senderPhoto: user.photoUrl ?? ""},
    });
  },
);

/**
 * A snap that has been opened as many times as allowed: delete the photo
 * and clear its ref, so it can't be opened again.
 */
export const onSnapOpened = onDocumentUpdated(
  {document: "pairs/{pairId}/messages/{messageId}", region: REGION},
  async (event) => {
    const after = event.data?.after.data();
    if (!after || after.type !== "snap" || !after.mediaPath) return;
    if (Number(after.views ?? 0) < Number(after.viewLimit ?? 1)) return;
    try {
      await getStorage().bucket().file(String(after.mediaPath)).delete({ignoreNotFound: true});
    } catch (e) {
      logger.warn("snap media delete failed", {path: after.mediaPath, e});
    }
    await event.data!.after.ref.update({mediaPath: null});
  },
);

/** Disappearing messages: days each timed setting keeps a message. */
const TTL_DAYS: Record<string, number> = {day: 1, week: 7, month: 30, year: 365};

/**
 * Hourly: deletes chat messages past their disappearing time. Their photos
 * and voice files go with them (onMessageDeleted). "After viewing"
 * messages are deleted by the app when the reader leaves the chat.
 */
export const chatCleanup = onSchedule(
  {schedule: "every 60 minutes", region: REGION, timeoutSeconds: 540, memory: "256MiB"},
  async () => {
    let deleted = 0;
    for (const [ttl, days] of Object.entries(TTL_DAYS)) {
      const cutoff = Timestamp.fromMillis(Date.now() - days * 86_400_000);
      for (;;) {
        const q = await db.collectionGroup("messages")
          .where("ttl", "==", ttl)
          .where("createdAt", "<", cutoff)
          .limit(400)
          .get();
        if (q.empty) break;
        const batch = db.batch();
        q.docs.forEach((d) => batch.delete(d.ref));
        await batch.commit();
        deleted += q.size;
        if (q.size < 400) break;
      }
    }
    if (deleted > 0) logger.info("chatCleanup", {deleted});
  },
);

/** A deleted chat message takes its photo / voice file with it. */
export const onMessageDeleted = onDocumentDeleted(
  {document: "pairs/{pairId}/messages/{messageId}", region: REGION},
  async (event) => {
    const path = event.data?.data()?.mediaPath;
    if (typeof path !== "string" || path.length === 0) return;
    try {
      await getStorage().bucket().file(path).delete({ignoreNotFound: true});
    } catch (e) {
      logger.warn("chat media delete failed", {path, e});
    }
  },
);

export const onGoodnightWritten = onDocumentWritten(
  {document: "pairs/{pairId}/goodnights/{night}", region: REGION},
  async (event) => {
    const before = (event.data?.before.data()?.entries ?? {}) as Record<string, unknown>;
    const after = (event.data?.after.data()?.entries ?? {}) as Record<string, unknown>;
    const added = Object.keys(after).filter((uid) => !(uid in before));
    if (added.length === 0) return;
    const pairId = event.params.pairId;
    const pair = (await db.doc(`pairs/${pairId}`).get()).data() as PairDoc | undefined;
    if (!pair || pair.status !== "active") return;
    for (const uid of added) {
      try {
        await markActivity(pairId, uid);
      } catch (e) {
        logger.warn("markActivity failed for goodnight", {pairId, e});
      }
      const to = pair.memberIds.find((m) => m !== uid);
      if (!to) continue;
      const both = to in after;
      const user = await getUser(uid);
      await notify(to, {
        channel: "chat",
        type: "goodnight",
        title: `${firstName(user)} said goodnight 🌙`,
        body: both ? "Sweet dreams, you two 💫" : "Say goodnight back",
        data: {route: "/goodnight", pairId},
        prefKey: "chat",
        // A goodnight is expected late; don't drop it for quiet hours.
        ignoreQuiet: !both,
      });
    }
  },
);

/** Hourly: at 21:00 pair-local time, nudge whoever hasn't said goodnight. */
export const goodnightReminders = onSchedule(
  {schedule: "every 60 minutes", region: REGION, timeoutSeconds: 300, memory: "256MiB"},
  async () => {
    const now = new Date();
    const pairs = await db.collection("pairs").where("status", "==", "active").get();
    let sent = 0;
    for (const doc of pairs.docs) {
      const pair = doc.data() as PairDoc;
      if (localHour(now, pair.timezone) !== GOODNIGHT_HOUR) continue;
      const night = localDateKey(now, pair.timezone);
      try {
        const entries = ((await doc.ref.collection("goodnights").doc(night).get()).get("entries") ?? {}) as Record<string, unknown>;
        for (const uid of pair.memberIds) {
          if (uid in entries) continue;
          const partner = pair.memberIds.find((m) => m !== uid);
          const partnerName = partner ? firstName(await getUser(partner)) : "your person";
          await notify(uid, {
            channel: "chat",
            type: "goodnight_reminder",
            title: "Time to say goodnight 🌙",
            body: partner && partner in entries ?
              `${partnerName} already did. Say goodnight back` :
              `Share the best moment of your day with ${partnerName}`,
            data: {route: "/goodnight", pairId: doc.id},
            prefKey: "chat",
          });
          sent++;
        }
      } catch (e) {
        logger.error("goodnight reminder failed", {pairId: doc.id, e});
      }
    }
    logger.info("goodnightReminders", {sent});
  },
);
