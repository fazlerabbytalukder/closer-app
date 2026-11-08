/**
 * Streak + shared plant (plan F8) and the scheduled reminder jobs.
 *
 * A day counts when BOTH members interacted (item, tap or daily answer) in
 * the pair's timezone. Missed days use a streak freeze (1/month free,
 * 3/month Plus); with no freeze left the streak resets and the plant wilts.
 * The plant never dies and never shrinks: interacting again revives it.
 */
import {onSchedule} from "firebase-functions/v2/scheduler";
import {
  db,
  REGION,
  FieldValue,
  Timestamp,
  PairDoc,
  logger,
  isPremium,
  localDateKey,
  localHour,
  addDays,
  daysBetween,
  notify,
  notifyMany,
  getUser,
} from "./common";

export const MILESTONES = [1, 3, 7, 14, 30, 60, 100, 365];

export function stageForStreak(n: number): number {
  return MILESTONES.filter((m) => n >= m).length;
}

export interface StreakState {
  count: number;
  best: number;
  lastBothActiveDate: string | null;
  freezesLeft: number;
  freezesMonth: string | null;
  activeToday: string[];
  activeDate: string | null;
  checkedThrough: string | null;
}

export interface PlantState {
  stage: number;
  health: "healthy" | "wilted";
  species: string;
}

export function readStreak(pair: PairDoc): StreakState {
  const s = (pair.streak ?? {}) as Partial<StreakState>;
  return {
    count: typeof s.count === "number" ? s.count : 0,
    best: typeof s.best === "number" ? s.best : 0,
    lastBothActiveDate: s.lastBothActiveDate ?? null,
    freezesLeft: typeof s.freezesLeft === "number" ? s.freezesLeft : 1,
    freezesMonth: s.freezesMonth ?? null,
    activeToday: Array.isArray(s.activeToday) ? s.activeToday : [],
    activeDate: s.activeDate ?? null,
    checkedThrough: s.checkedThrough ?? null,
  };
}

export function readPlant(pair: PairDoc): PlantState {
  const p = (pair.plant ?? {}) as Partial<PlantState>;
  return {
    stage: typeof p.stage === "number" ? p.stage : 0,
    health: p.health === "wilted" ? "wilted" : "healthy",
    species: typeof p.species === "string" ? p.species : "sprout",
  };
}

export function initialStreak(today: string, premium: boolean): StreakState {
  return {
    count: 0,
    best: 0,
    lastBothActiveDate: null,
    freezesLeft: premium ? 3 : 1,
    freezesMonth: today.slice(0, 7),
    activeToday: [],
    activeDate: today,
    checkedThrough: addDays(today, -1),
  };
}

export const INITIAL_PLANT: PlantState = {stage: 0, health: "healthy", species: "sprout"};

/**
 * Settles every finished day up to yesterday: refreshes monthly freezes,
 * spends freezes on missed days, or breaks the streak (plant wilts).
 * Pure function: mutates and returns copies.
 */
export function settle(
  streakIn: StreakState,
  plantIn: PlantState,
  today: string,
  premium: boolean,
): {streak: StreakState; plant: PlantState; changed: boolean; broke: boolean; frozeDays: number} {
  const streak = {...streakIn, activeToday: [...streakIn.activeToday]};
  const plant = {...plantIn};
  let changed = false;
  let broke = false;
  let frozeDays = 0;

  const month = today.slice(0, 7);
  if (streak.freezesMonth !== month) {
    streak.freezesMonth = month;
    streak.freezesLeft = premium ? 3 : 1;
    changed = true;
  }

  if (streak.activeDate !== today) {
    streak.activeDate = today;
    streak.activeToday = [];
    changed = true;
  }

  const yesterday = addDays(today, -1);
  if (streak.checkedThrough && streak.checkedThrough >= yesterday) {
    return {streak, plant, changed, broke, frozeDays};
  }

  if (streak.count > 0 && streak.lastBothActiveDate) {
    let from = streak.lastBothActiveDate;
    if (streak.checkedThrough && streak.checkedThrough > from) from = streak.checkedThrough;
    const missed = Math.max(0, daysBetween(from, yesterday));
    if (missed > 400) {
      streak.count = 0;
      broke = true;
    } else {
      for (let i = 0; i < missed && streak.count > 0; i++) {
        if (streak.freezesLeft > 0) {
          streak.freezesLeft -= 1;
          frozeDays += 1;
        } else {
          streak.count = 0;
          broke = true;
        }
      }
    }
    if (broke) plant.health = "wilted";
  }
  streak.checkedThrough = yesterday;
  changed = true;
  return {streak, plant, changed, broke, frozeDays};
}

/**
 * Marks [uid] as active today in [pairId]. When both members are active
 * the streak grows (once per day) and the plant may reach a new stage.
 */
export async function markActivity(pairId: string, uid: string): Promise<void> {
  const pairRef = db.doc(`pairs/${pairId}`);
  let grewTo = null as number | null;
  let members: string[] = [];
  let count = 0;
  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(pairRef);
      const pair = snap.data() as PairDoc | undefined;
      if (!pair || pair.status === "unpaired") return;
      members = pair.memberIds;
      const today = localDateKey(new Date(), pair.timezone);
      const s = settle(readStreak(pair), readPlant(pair), today, isPremium(pair));
      const streak = s.streak;
      const plant = s.plant;
      if (!streak.activeToday.includes(uid)) streak.activeToday.push(uid);
      const bothActive = pair.memberIds.every((m) => streak.activeToday.includes(m));
      if (bothActive && streak.lastBothActiveDate !== today) {
        streak.count = streak.count > 0 ? streak.count + 1 : 1;
        streak.best = Math.max(streak.best, streak.count);
        streak.lastBothActiveDate = today;
        const stage = Math.max(plant.stage, stageForStreak(streak.count));
        if (stage > plant.stage) grewTo = stage;
        plant.stage = stage;
        plant.health = "healthy";
        count = streak.count;
      }
      tx.update(pairRef, {streak, plant});
    });
  } catch (e) {
    // Activity tracking must never fail the user's action.
    logger.error("markActivity failed", {pairId, uid, e});
    return;
  }
  if (grewTo !== null) {
    await notifyMany(members, {
      channel: "streak",
      type: "plant_grew",
      title: "Your plant grew 🌱",
      body: `${count} day${count === 1 ? "" : "s"} together in a row. Keep it going!`,
      data: {route: "/plant", stage: String(grewTo), streak: String(count)},
      prefKey: "reminders",
    });
  }
}

/**
 * Hourly: settle finished days for every pair, and at 20:00 local time nudge
 * members who have not interacted yet today while a streak is running.
 */
export const updateStreaks = onSchedule(
  {schedule: "every 60 minutes", region: REGION, timeoutSeconds: 540, memory: "512MiB"},
  async () => {
    const now = new Date();
    const pairs = await db.collection("pairs").where("status", "==", "active").get();
    let settled = 0;
    for (const doc of pairs.docs) {
      const pair = doc.data() as PairDoc;
      const today = localDateKey(now, pair.timezone);
      const current = readStreak(pair);
      if (!(current.checkedThrough && current.checkedThrough >= addDays(today, -1) && current.activeDate === today)) {
        try {
          await db.runTransaction(async (tx) => {
            const fresh = (await tx.get(doc.ref)).data() as PairDoc | undefined;
            if (!fresh || fresh.status !== "active") return;
            const t = localDateKey(new Date(), fresh.timezone);
            const s = settle(readStreak(fresh), readPlant(fresh), t, isPremium(fresh));
            if (s.changed) tx.update(doc.ref, {streak: s.streak, plant: s.plant});
          });
          settled++;
        } catch (e) {
          logger.error("settle failed", {pairId: doc.id, e});
        }
      }

      if (localHour(now, pair.timezone) === 20 && current.count > 0 && current.lastBothActiveDate !== today) {
        const active = current.activeDate === today ? current.activeToday : [];
        const sleepy = pair.memberIds.filter((m) => !active.includes(m));
        for (const uid of sleepy) {
          await notify(uid, {
            channel: "streak",
            type: "streak_reminder",
            title: "Your plant needs water 🌱",
            body: `Send something today to keep your ${current.count}-day streak.`,
            data: {route: "/plant"},
            prefKey: "reminders",
          });
        }
      }
    }
    logger.info("updateStreaks done", {pairs: pairs.size, settled});
  },
);

/** Next occurrence of a countdown date key (yyyy-mm-dd) on/after [today]. */
export function nextOccurrence(dateKey: string, repeatsYearly: boolean, today: string): string {
  if (!repeatsYearly) return dateKey;
  const [, m, d] = dateKey.split("-");
  let year = Number(today.slice(0, 4));
  let key = `${year}-${m}-${d}`;
  if (key < today) {
    year += 1;
    key = `${year}-${m}-${d}`;
  }
  return key;
}

/**
 * Daily: remind both members [remindDaysBefore] days before a countdown and
 * on the day itself. Uses the `dateKey` (yyyy-mm-dd) written by the app,
 * falling back to the `date` Timestamp in the pair's timezone.
 */
export const countdownReminders = onSchedule(
  {schedule: "0 8 * * *", timeZone: "Europe/London", region: REGION, timeoutSeconds: 540},
  async () => {
    const now = new Date();
    const pairs = await db.collection("pairs").where("status", "==", "active").get();
    for (const pairDoc of pairs.docs) {
      const pair = pairDoc.data() as PairDoc;
      const today = localDateKey(now, pair.timezone);
      const countdowns = await pairDoc.ref.collection("countdowns").get();
      for (const c of countdowns.docs) {
        const data = c.data();
        const rawDate = data.date;
        const dateKey: string | null =
          typeof data.dateKey === "string" ?
            data.dateKey :
            rawDate instanceof Timestamp ?
              localDateKey(rawDate.toDate(), pair.timezone) :
              typeof rawDate === "number" ?
                localDateKey(new Date(rawDate), pair.timezone) :
                null;
        if (!dateKey) continue;
        const next = nextOccurrence(dateKey, data.repeatsYearly === true, today);
        const left = daysBetween(today, next);
        const before = typeof data.remindDaysBefore === "number" ? data.remindDaysBefore : 1;
        if (left !== 0 && left !== before) continue;
        if (c.get("lastRemindedFor") === `${next}:${left}`) continue;
        const title = `${data.emoji ?? "📅"} ${data.title ?? "Countdown"}`;
        const body = left === 0 ? "It's today! 🎉" : `${left} day${left === 1 ? "" : "s"} to go`;
        for (const uid of pair.memberIds) {
          const user = await getUser(uid);
          await notify(uid, {
            channel: "countdowns",
            type: "countdown",
            title,
            body,
            data: {route: "/countdowns", countdownId: c.id, pairId: pairDoc.id},
            prefKey: "reminders",
            user,
          });
        }
        await c.ref.update({lastRemindedFor: `${next}:${left}`, lastRemindedAt: FieldValue.serverTimestamp()});
      }
    }
  },
);
