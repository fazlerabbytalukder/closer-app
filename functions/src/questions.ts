/**
 * Daily question (F4) and "How well do you know me?" games (F10).
 */
import {onCall} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {DocumentReference} from "firebase-admin/firestore";
import {
  db,
  REGION,
  CALLABLE_OPTS,
  FieldValue,
  Timestamp,
  PairDoc,
  UserDoc,
  requireAuth,
  requirePair,
  isPremium,
  userError,
  limitError,
  str,
  firstName,
  localDateKey,
  localHour,
  notify,
  notifyMany,
  logger,
} from "./common";
import {markActivity} from "./streaks";
import {QUESTION_PACKS, DEFAULT_PACK} from "./content/questions";
import {GAME_PACKS, QUESTIONS_PER_GAME} from "./content/games";

/** Local hour at which the new question appears. */
export const QUESTION_HOUR = 7;

function hashOffset(s: string, mod: number): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) >>> 0;
  return mod > 0 ? h % mod : 0;
}

/**
 * Creates today's question for a pair if it doesn't exist yet. Returns true
 * when a new question was written.
 */
export async function assignQuestionForPair(
  pairRef: DocumentReference,
  opts: {force?: boolean; notifyMembers?: boolean} = {},
): Promise<boolean> {
  const now = new Date();
  let assigned = false as boolean;
  let members: string[] = [];
  await db.runTransaction(async (tx) => {
    const pair = (await tx.get(pairRef)).data() as PairDoc | undefined;
    if (!pair || pair.status !== "active") return;
    if (!opts.force && localHour(now, pair.timezone) < QUESTION_HOUR) return;
    const today = localDateKey(now, pair.timezone);
    const qRef = pairRef.collection("dailyQuestions").doc(today);
    if ((await tx.get(qRef)).exists) return;

    let packId = pair.questionPack && QUESTION_PACKS[pair.questionPack] ? pair.questionPack : DEFAULT_PACK;
    const pack = QUESTION_PACKS[packId];
    if (pack.premium && !isPremium(pair)) packId = DEFAULT_PACK;
    if (QUESTION_PACKS[packId].adult) {
      const users = await Promise.all(pair.memberIds.map((m) => tx.get(db.doc(`users/${m}`))));
      if (!users.every((u) => u.get("ageConfirmed18") === true)) packId = DEFAULT_PACK;
    }
    const chosen = QUESTION_PACKS[packId];
    const len = chosen.questions.length;
    const cursor = pair.questionCursor?.[packId] ?? hashOffset(pairRef.id, len);
    const question = chosen.questions[cursor % len];

    tx.create(qRef, {
      date: today,
      questionId: question.id,
      text: question.text,
      packId,
      answeredBy: [],
      revealed: false,
      answers: {},
      assignedAt: FieldValue.serverTimestamp(),
    });
    tx.update(pairRef, {[`questionCursor.${packId}`]: cursor + 1});
    members = pair.memberIds;
    assigned = true;
  });
  if (assigned && opts.notifyMembers) {
    await notifyMany(members, {
      channel: "daily_question",
      type: "question",
      title: "Today's question is here 💬",
      body: "Answer it to see what your person said.",
      data: {route: "/question", pairId: pairRef.id},
      prefKey: "questions",
    });
  }
  return assigned;
}

/** Hourly: new question at the pair's local morning (catches up if missed). */
export const assignDailyQuestions = onSchedule(
  {schedule: "every 60 minutes", region: REGION, timeoutSeconds: 540, memory: "512MiB"},
  async () => {
    const now = new Date();
    const pairs = await db.collection("pairs").where("status", "==", "active").get();
    let count = 0;
    for (const doc of pairs.docs) {
      const tz = (doc.get("timezone") as string | undefined) ?? "UTC";
      if (localHour(now, tz) < QUESTION_HOUR) continue;
      try {
        if (await assignQuestionForPair(doc.ref, {notifyMembers: true})) count++;
      } catch (e) {
        logger.error("assignQuestionForPair failed", {pairId: doc.id, e});
      }
    }
    logger.info("assignDailyQuestions", {pairs: pairs.size, assigned: count});
  },
);

/**
 * Saves the caller's private answer; when both have answered, copies both
 * answers onto the question doc and reveals it.
 */
export const submitAnswer = onCall<{pairId?: string; date?: string; answer?: string}>(
  CALLABLE_OPTS,
  async (req) => {
    const uid = requireAuth(req);
    const ctx = await requirePair(uid, req.data?.pairId);
    const answer = str(req.data?.answer, 500);
    if (!answer) throw userError("invalid-argument", "empty-answer", "Write an answer first.");

    const qCol = ctx.pairRef.collection("dailyQuestions");
    let qRef: DocumentReference;
    const date = str(req.data?.date, 10);
    if (/^\d{4}-\d{2}-\d{2}$/.test(date)) {
      qRef = qCol.doc(date);
    } else {
      const latest = await qCol.orderBy("assignedAt", "desc").limit(1).get();
      if (latest.empty) throw userError("not-found", "no-question", "There's no question yet today.");
      qRef = latest.docs[0].ref;
    }

    let revealed = false as boolean;
    let firstTime = false as boolean;
    await db.runTransaction(async (tx) => {
      const qSnap = await tx.get(qRef);
      if (!qSnap.exists) throw userError("not-found", "no-question", "That question doesn't exist.");
      const pairSnap = await tx.get(ctx.pairRef);
      const pair = pairSnap.data() as PairDoc;
      const answeredBy: string[] = qSnap.get("answeredBy") ?? [];
      const others = pair.memberIds.filter((m) => m !== uid);
      const otherPrivate = await Promise.all(others.map((m) => tx.get(qRef.collection("private").doc(m))));
      const alreadyRevealed = qSnap.get("revealed") === true;
      firstTime = !answeredBy.includes(uid);

      tx.set(qRef.collection("private").doc(uid), {
        answer,
        answeredAt: FieldValue.serverTimestamp(),
      });
      const all = Array.from(new Set([...answeredBy, uid]));
      const update: Record<string, unknown> = {answeredBy: all};
      const everyone = pair.memberIds.every((m) => all.includes(m));
      if (everyone) {
        const answers: Record<string, string> = {[uid]: answer};
        others.forEach((m, i) => {
          answers[m] = String(otherPrivate[i].get("answer") ?? "");
        });
        update.answers = answers;
        update.revealed = true;
        update.revealedAt = alreadyRevealed ? qSnap.get("revealedAt") ?? FieldValue.serverTimestamp() : FieldValue.serverTimestamp();
        if (!alreadyRevealed) {
          revealed = true;
          tx.update(ctx.pairRef, {"stats.questionsAnswered": FieldValue.increment(1)});
        }
      }
      tx.update(qRef, update);
    });

    if (firstTime) await markActivity(ctx.pairId, uid);

    const name = firstName(ctx.user);
    if (revealed) {
      await notifyMany(ctx.pair.memberIds, {
        channel: "daily_question",
        type: "question_revealed",
        title: "Answers revealed 💬",
        body: "You both answered today's question. Take a look!",
        data: {route: "/question", pairId: ctx.pairId, date: qRef.id},
        prefKey: "questions",
      });
    } else if (firstTime && ctx.partnerUid) {
      await notify(ctx.partnerUid, {
        channel: "daily_question",
        type: "question_answered",
        title: `${name} answered today's question`,
        body: "Answer too to unlock both answers.",
        data: {route: "/question", pairId: ctx.pairId, date: qRef.id},
        prefKey: "questions",
      });
    }
    return {date: qRef.id, revealed};
  },
);

// ------------------------------------------------------------------- games

function shuffle<T>(arr: T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

/** Starts a "know-me" game with the caller as the subject. */
export const startGame = onCall<{pairId?: string; packId?: string}>(CALLABLE_OPTS, async (req) => {
  const uid = requireAuth(req);
  const ctx = await requirePair(uid, req.data?.pairId);
  const packId = str(req.data?.packId, 40) || "starter";
  const pack = GAME_PACKS[packId];
  if (!pack) throw userError("not-found", "unknown-pack", "That game pack doesn't exist.");
  if (pack.premium && !isPremium(ctx.pair)) throw limitError("plus", "This pack is part of Closer Plus.");

  const questions = shuffle(pack.questions)
    .slice(0, QUESTIONS_PER_GAME)
    .map((qq) => ({text: qq.text, options: [...qq.options]}));
  const ref = ctx.pairRef.collection("games").doc();
  const createdAt = Timestamp.now();
  const game = {
    type: "know-me",
    packId,
    subjectUid: uid,
    guesserUid: ctx.partnerUid,
    questions,
    answers: {subject: [] as number[], guesser: [] as number[]},
    score: 0,
    status: "subjectTurn",
    createdAt,
    updatedAt: createdAt,
  };
  await ref.set(game);
  return {id: ref.id, ...game, createdAt: createdAt.toMillis(), updatedAt: createdAt.toMillis()};
});

/**
 * Subject submits their own answers (hidden from the guesser until the end),
 * then the guesser submits guesses and the score is computed.
 */
export const submitGameAnswers = onCall<{pairId?: string; gameId?: string; answers?: unknown}>(
  CALLABLE_OPTS,
  async (req) => {
    const uid = requireAuth(req);
    const ctx = await requirePair(uid, req.data?.pairId);
    const gameId = str(req.data?.gameId, 40);
    if (!gameId) throw userError("invalid-argument", "bad-game", "Missing game.");
    const ref = ctx.pairRef.collection("games").doc(gameId);
    const secretRef = ref.collection("private").doc("subject");

    let notifyUid = null as string | null;
    let notifyKind = "guesser_turn" as "guesser_turn" | "done";
    let finalScore = 0;
    let total = 0;

    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw userError("not-found", "bad-game", "That game doesn't exist.");
      const g = snap.data() as {
        subjectUid: string;
        guesserUid: string;
        questions: unknown[];
        status: string;
      };
      total = g.questions.length;
      const raw = req.data?.answers;
      if (!Array.isArray(raw) || raw.length !== total || !raw.every((n) => Number.isInteger(n) && n >= 0 && n < 4)) {
        throw userError("invalid-argument", "bad-answers", "Answer every question.");
      }
      const answers = raw as number[];

      if (uid === g.subjectUid && g.status === "subjectTurn") {
        tx.set(secretRef, {answers});
        tx.update(ref, {status: "guesserTurn", updatedAt: FieldValue.serverTimestamp()});
        notifyUid = g.guesserUid;
        notifyKind = "guesser_turn";
      } else if (uid === g.guesserUid && g.status === "guesserTurn") {
        const secret = await tx.get(secretRef);
        const subject: number[] = secret.get("answers") ?? [];
        finalScore = answers.reduce((s, a, i) => s + (a === subject[i] ? 1 : 0), 0);
        tx.update(ref, {
          "answers.subject": subject,
          "answers.guesser": answers,
          "score": finalScore,
          "status": "done",
          "updatedAt": FieldValue.serverTimestamp(),
        });
        tx.delete(secretRef);
        notifyUid = g.subjectUid;
        notifyKind = "done";
      } else {
        throw userError("failed-precondition", "not-your-turn", "It's not your turn.");
      }
    });

    const name = firstName(ctx.user as UserDoc);
    if (notifyUid) {
      await notify(notifyUid, {
        channel: "game_turns",
        type: notifyKind === "done" ? "game_done" : "game_turn",
        title: notifyKind === "done" ? `${name} finished guessing 🎯` : `${name} finished — your turn 🎲`,
        body:
          notifyKind === "done" ?
            `They got ${finalScore} of ${total} right. See the results!` :
            "How well do you know them? Make your guesses.",
        data: {route: `/games/${gameId}`, pairId: ctx.pairId, gameId},
      });
    }
    return {status: notifyKind === "done" ? "done" : "guesserTurn", score: finalScore};
  },
);
