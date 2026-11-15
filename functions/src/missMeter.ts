/**
 * "How much do you miss me?" — each person privately picks 0..100 for the
 * day; both values are revealed together once both have answered.
 *
 * pairs/{pairId}/missMeters/{yyyy-mm-dd}
 *   date, answeredBy: [uid…], revealed, values: {uid: n} (only when revealed)
 * pairs/{pairId}/missMeters/{date}/private/{uid}
 *   value, answeredAt (owner-readable only)
 */
import {onCall} from "firebase-functions/v2/https";
import {
  db,
  CALLABLE_OPTS,
  FieldValue,
  PairDoc,
  requireAuth,
  requirePair,
  userError,
  firstName,
  localDateKey,
  daysBetween,
  notify,
  notifyMany,
} from "./common";
import {markActivity} from "./streaks";

const MAX = 100;

export const submitMissMeter = onCall<{pairId?: string; value?: unknown; date?: string}>(
  CALLABLE_OPTS,
  async (req) => {
    const uid = requireAuth(req);
    const ctx = await requirePair(uid, req.data?.pairId);
    const raw = Number(req.data?.value);
    if (!Number.isFinite(raw)) throw userError("invalid-argument", "bad-value", "Pick how much first.");
    const value = Math.max(0, Math.min(MAX, Math.round(raw)));

    // Use the device's date when it's within a day of the pair's date, so a
    // late-night answer counts for the day the person meant.
    const pairToday = localDateKey(new Date(), ctx.pair.timezone);
    const asked = typeof req.data?.date === "string" ? req.data.date : "";
    const date =
      /^\d{4}-\d{2}-\d{2}$/.test(asked) && Math.abs(daysBetween(pairToday, asked)) <= 1 ? asked : pairToday;

    const ref = ctx.pairRef.collection("missMeters").doc(date);
    let revealed = false as boolean;
    let firstTime = false as boolean;
    let values: Record<string, number> = {};
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (snap.get("revealed") === true) {
        throw userError("failed-precondition", "revealed", "Already revealed today — come back tomorrow!");
      }
      const pair = (await tx.get(ctx.pairRef)).data() as PairDoc;
      const answeredBy: string[] = snap.get("answeredBy") ?? [];
      const others = pair.memberIds.filter((m) => m !== uid);
      const otherPrivate = await Promise.all(others.map((m) => tx.get(ref.collection("private").doc(m))));
      firstTime = !answeredBy.includes(uid);

      tx.set(ref.collection("private").doc(uid), {value, answeredAt: FieldValue.serverTimestamp()});
      const all = Array.from(new Set([...answeredBy, uid]));
      const doc: Record<string, unknown> = {date, answeredBy: all, revealed: false, values: {}};
      if (pair.memberIds.every((m) => all.includes(m))) {
        values = {[uid]: value};
        others.forEach((m, i) => {
          values[m] = Number(otherPrivate[i].get("value") ?? 0);
        });
        doc.values = values;
        doc.revealed = true;
        doc.revealedAt = FieldValue.serverTimestamp();
        revealed = true;
      }
      tx.set(ref, doc, {merge: true});
    });

    if (firstTime) await markActivity(ctx.pairId, uid);

    const name = firstName(ctx.user);
    if (revealed) {
      await notifyMany(ctx.pair.memberIds, {
        channel: "daily_question",
        type: "miss_meter_revealed",
        title: "Miss-o-meter revealed 🥺",
        body: "You both answered. Who misses who more?",
        data: {route: "/miss-meter", pairId: ctx.pairId, date},
        prefKey: "questions",
      });
    } else if (firstTime && ctx.partnerUid) {
      await notify(ctx.partnerUid, {
        channel: "daily_question",
        type: "miss_meter_answered",
        title: `How much do you miss ${name}?`,
        body: `${name} already answered. Answer to see theirs 👀`,
        data: {route: "/miss-meter", pairId: ctx.pairId, date},
        prefKey: "questions",
      });
    }
    return {date, revealed, values: revealed ? values : {}};
  },
);
