/**
 * Love capsules: the "100 reasons", letters from the future and surprises.
 *
 * pairs/{pairId}/capsules/{id}
 *   kind: "reason" | "letter" | "surprise", authorId, forUid, title,
 *   surpriseType, createdAt, unlockAt, openedAt, notified
 * pairs/{pairId}/capsules/{id}/content/main
 *   text, photoPath, giftId — readable by the receiver only once
 *   unlockAt has passed (firestore.rules).
 *
 * The app writes capsules directly (rules-checked). These functions only
 * notify: right away when a capsule is created already unlocked, and from
 * a 15-minute job when a sealed one opens.
 */
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {DocumentData, DocumentReference} from "firebase-admin/firestore";
import {db, REGION, Timestamp, PairDoc, getUser, firstName, notify, safeTz, logger} from "./common";
import {markActivity} from "./streaks";

/** Treat capsules unlocking within this window as "now". */
const NOW_SLACK_MS = 60_000;

async function notifyUnlocked(pairId: string, id: string, d: DocumentData): Promise<void> {
  const forUid = String(d.forUid ?? "");
  if (!forUid) return;
  const author = await getUser(String(d.authorId ?? ""));
  const name = firstName(author);
  const base = {channel: "partner_items" as const, data: {pairId, capsuleId: id}};
  switch (d.kind) {
    case "reason":
      await notify(forUid, {
        ...base,
        type: "reason_unlocked",
        title: `A new reason from ${name} 💗`,
        body: "Today's reason is ready. Tap to read it.",
        data: {...base.data, route: "/reasons"},
      });
      return;
    case "letter":
      await notify(forUid, {
        ...base,
        type: "letter_unlocked",
        title: `A letter from ${name} just opened 💌`,
        body: d.title ? `“${d.title}” — tap to read it` : "Tap to read it",
        data: {...base.data, route: `/letters/${id}`},
      });
      return;
    default:
      await notify(forUid, {
        ...base,
        type: "surprise_unlocked",
        title: `${name} sent you a surprise 🎁`,
        body: "Tap to unwrap it",
        data: {...base.data, route: "/surprises"},
      });
  }
}

/** Marks a capsule notified (once) and notifies; false if already done. */
async function claimAndNotify(ref: DocumentReference, pairId: string): Promise<boolean> {
  const claimed = await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.get("notified") === true) return null;
    tx.update(ref, {notified: true});
    return snap.data() ?? null;
  });
  if (!claimed) return false;
  const pair = (await db.doc(`pairs/${pairId}`).get()).data() as PairDoc | undefined;
  if (!pair || pair.status !== "active") return false;
  await notifyUnlocked(pairId, ref.id, claimed);
  return true;
}

export const onCapsuleCreated = onDocumentCreated(
  {document: "pairs/{pairId}/capsules/{capsuleId}", region: REGION},
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const d = snap.data();
    const pairId = event.params.pairId;
    const authorId = String(d.authorId ?? "");
    if (authorId) {
      try {
        await markActivity(pairId, authorId);
      } catch (e) {
        logger.warn("markActivity failed for capsule", {pairId, e});
      }
    }
    const unlockAt = d.unlockAt instanceof Timestamp ? d.unlockAt.toMillis() : 0;
    if (unlockAt <= Date.now() + NOW_SLACK_MS) {
      await claimAndNotify(snap.ref, pairId);
      return;
    }
    // A sealed letter: tell them one is waiting (but not what it says).
    if (d.kind === "letter" && d.forUid) {
      const [author, receiver] = await Promise.all([getUser(authorId), getUser(String(d.forUid))]);
      const when = new Intl.DateTimeFormat("en-GB", {
        day: "numeric",
        month: "long",
        year: "numeric",
        timeZone: safeTz(receiver.timezone),
      }).format(new Date(unlockAt));
      await notify(String(d.forUid), {
        channel: "partner_items",
        type: "letter_sealed",
        title: `${firstName(author)} wrote you a letter 💌`,
        body: `It opens on ${when}. No peeking!`,
        data: {route: "/letters", pairId, capsuleId: snap.id},
        user: receiver,
      });
    }
  },
);

/** Every 15 minutes: notify receivers of capsules that just unlocked. */
export const capsuleUnlocks = onSchedule(
  {schedule: "every 15 minutes", region: REGION, timeoutSeconds: 300, memory: "256MiB"},
  async () => {
    const due = await db
      .collectionGroup("capsules")
      .where("notified", "==", false)
      .where("unlockAt", "<=", Timestamp.now())
      .limit(500)
      .get();
    let sent = 0;
    for (const doc of due.docs) {
      const pairId = doc.ref.parent.parent?.id;
      if (!pairId) continue;
      try {
        if (await claimAndNotify(doc.ref, pairId)) sent++;
      } catch (e) {
        logger.error("capsule unlock notify failed", {path: doc.ref.path, e});
      }
    }
    logger.info("capsuleUnlocks", {due: due.size, sent});
  },
);
