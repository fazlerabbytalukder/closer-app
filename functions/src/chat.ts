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
import {onDocumentCreated, onDocumentWritten} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {db, REGION, PairDoc, getUser, firstName, notify, localDateKey, localHour, logger} from "./common";
import {markActivity} from "./streaks";

/** Local hour the goodnight reminder goes out. */
const GOODNIGHT_HOUR = 21;

function preview(d: FirebaseFirestore.DocumentData): string {
  switch (d.type) {
    case "photo":
      return d.text ? `📷 ${String(d.text).slice(0, 80)}` : "📷 Photo";
    case "voice":
      return "🎤 Voice message";
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
    try {
      await markActivity(pairId, sender);
    } catch (e) {
      logger.warn("markActivity failed for chat", {pairId, e});
    }
    if (!to) return;
    const user = await getUser(sender);
    // One "chat" notification at a time (same tag): the newest replaces it.
    await notify(to, {
      channel: "chat",
      type: "chat",
      title: firstName(user),
      body: preview(d),
      data: {route: "/chat", pairId, messageId: event.params.messageId},
      prefKey: "chat",
    });
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
