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
  /** Most recent missed day a freeze covered. */
  lastFrozeDate: string | null;
  /** Length of the streak that last broke, and the day it broke. */
  lostCount: number;
  brokeDate: string | null;
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
    lastFrozeDate: s.lastFrozeDate ?? null,
    lostCount: typeof s.lostCount === "number" ? s.lostCount : 0,
    brokeDate: s.brokeDate ?? null,
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
    lastFrozeDate: null,
    lostCount: 0,
    brokeDate: null,
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
    let brokeOn: string | null = null;
    if (missed > 400) {
      brokeOn = yesterday;
    } else {
      for (let i = 0; i < missed; i++) {
        if (streak.freezesLeft > 0) {
          streak.freezesLeft -= 1;
          frozeDays += 1;
          streak.lastFrozeDate = addDays(from, i + 1);
        } else {
          brokeOn = addDays(from, i + 1);
          break;
        }
      }
    }
    if (brokeOn) {
      // Streak resets; best, plant size and history are kept.
      streak.lostCount = streak.count;
      streak.brokeDate = brokeOn;
      streak.count = 0;
      broke = true;
      plant.health = "wilted";
    }
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
  let newYear = false;
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
        newYear = streak.count >= 730 && streak.count % 365 === 0;
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
    const bloom = grewTo >= 8;
    await notifyMany(members, {
      channel: "streak",
      type: "plant_grew",
      title: bloom ? "Full bloom! 🌸 One whole year" : "Your plant grew 🌱",
      body: bloom ?
        "365 days in a row together. Your plant is fully grown. Keep going for bloom year 2!" :
        `${count} day${count === 1 ? "" : "s"} together in a row. Keep it going!`,
      data: {route: "/plant", stage: String(grewTo), streak: String(count)},
      prefKey: "reminders",
    });
  } else if (newYear) {
    const years = Math.floor(count / 365);
    await notifyMany(members, {
      channel: "streak",
      type: "plant_year",
      title: `${years} years in bloom 🌸`,
      body: `${count} days in a row together. That's incredible.`,
      data: {route: "/plant", streak: String(count)},
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
        let outcome: {broke: boolean; frozeDays: number; streak: StreakState} | null = null;
        try {
          await db.runTransaction(async (tx) => {
            outcome = null;
            const fresh = (await tx.get(doc.ref)).data() as PairDoc | undefined;
            if (!fresh || fresh.status !== "active") return;
            const t = localDateKey(new Date(), fresh.timezone);
            const s = settle(readStreak(fresh), readPlant(fresh), t, isPremium(fresh));
            if (s.changed) tx.update(doc.ref, {streak: s.streak, plant: s.plant});
            outcome = {broke: s.broke, frozeDays: s.frozeDays, streak: s.streak};
          });
          settled++;
        } catch (e) {
          logger.error("settle failed", {pairId: doc.id, e});
        }
        const o = outcome as {broke: boolean; frozeDays: number; streak: StreakState} | null;
        if (o?.broke) {
          await notifyMany(pair.memberIds, {
            channel: "streak",
            type: "streak_broken",
            title: "Your plant is thirsty 💧",
            body: `Your ${o.streak.lostCount}-day streak ended. Both show up today to revive it.`,
            data: {route: "/plant"},
            prefKey: "reminders",
          });
        } else if (o && o.frozeDays > 0) {
          const n = o.frozeDays;
          await notifyMany(pair.memberIds, {
            channel: "streak",
            type: "streak_frozen",
            title: "A freeze saved your streak 🧊",
            body: `${n === 1 ? "A missed day was" : `${n} missed days were`} covered. ` +
              `Your ${o.streak.count}-day streak is safe · ${o.streak.freezesLeft} freeze${o.streak.freezesLeft === 1 ? "" : "s"} left this month.`,
            data: {route: "/plant"},
            prefKey: "reminders",
          });
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
            body: current.freezesLeft > 0 ?
              `Send something today to keep your ${current.count}-day streak.` :
              `No freezes left: send something before midnight or your ${current.count}-day streak ends.`,
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
        // Countdowns with a time of day are handled by countdownTimedReminders.
        if (data.hasTime === true) continue;
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

/** "15 minutes", "2 hours", "3 days" (largest whole unit). */
export function describeLead(ms: number): string {
  const mins = Math.max(1, Math.round(ms / 60000));
  const unit = (n: number, w: string) => `${n} ${w}${n === 1 ? "" : "s"}`;
  if (mins % 1440 === 0) return unit(mins / 1440, "day");
  if (mins >= 1440) return unit(Math.round(mins / 1440), "day");
  if (mins % 60 === 0 || mins >= 120) return unit(Math.round(mins / 60), "hour");
  return unit(mins, "minute");
}

function addYear(d: Date): Date {
  const n = new Date(d.getTime());
  n.setUTCFullYear(n.getUTCFullYear() + 1);
  return n;
}

/**
 * What a due countdown reminder is for, and when the next one is.
 * [eventAt] is the stored moment (first occurrence); [remindAt] the due
 * nextRemindAt. Returns null for next when a one-off countdown is done.
 */
export function planTimedReminder(
  eventAt: Date,
  remindAt: Date,
  remindMinutes: number,
  repeatsYearly: boolean,
  now: Date,
): {occurrence: Date; isMoment: boolean; next: Date | null} {
  let occurrence = eventAt;
  if (repeatsYearly) {
    while (occurrence.getTime() < remindAt.getTime() - 30000) occurrence = addYear(occurrence);
  }
  const isMoment = remindAt.getTime() >= occurrence.getTime() - 30000;
  let next: Date | null;
  if (!isMoment) {
    next = occurrence;
  } else if (repeatsYearly) {
    const following = addYear(occurrence);
    const before = new Date(following.getTime() - remindMinutes * 60000);
    next = remindMinutes > 0 && before > now ? before : following;
  } else {
    next = null;
  }
  return {occurrence, isMoment, next};
}

/**
 * Every minute: send countdown reminders that have a time of day, e.g.
 * "15 minutes to go" and "It's time!". The app writes nextRemindAt; this
 * job claims each due doc in a transaction, then advances it.
 */
export const countdownTimedReminders = onSchedule(
  {schedule: "every 1 minutes", region: REGION, timeoutSeconds: 120},
  async () => {
    const now = new Date();
    const due = await db.collectionGroup("countdowns")
      .where("nextRemindAt", "<=", Timestamp.fromDate(now))
      .limit(200)
      .get();
    const pairs = new Map<string, PairDoc | null>();
    for (const c of due.docs) {
      const pairRef = c.ref.parent.parent;
      if (!pairRef) continue;
      if (!pairs.has(pairRef.id)) {
        const p = await pairRef.get();
        pairs.set(pairRef.id, p.exists ? (p.data() as PairDoc) : null);
      }
      const pair = pairs.get(pairRef.id);

      const claim = await db.runTransaction(async (tx) => {
        const snap = await tx.get(c.ref);
        const data = snap.data();
        const remindTs = data?.nextRemindAt;
        if (!data || !(remindTs instanceof Timestamp) || remindTs.toMillis() > now.getTime()) return null;
        if (!pair || pair.status !== "active" || !(data.date instanceof Timestamp)) {
          tx.update(c.ref, {nextRemindAt: FieldValue.delete()});
          return null;
        }
        const minutes = typeof data.remindMinutesBefore === "number" ? data.remindMinutesBefore : 0;
        const plan = planTimedReminder(data.date.toDate(), remindTs.toDate(), minutes, data.repeatsYearly === true, now);
        tx.update(c.ref, {
          nextRemindAt: plan.next ? Timestamp.fromDate(plan.next) : FieldValue.delete(),
          lastRemindedFor: `${plan.occurrence.toISOString()}:${plan.isMoment ? 0 : minutes}`,
          lastRemindedAt: FieldValue.serverTimestamp(),
        });
        // Don't send reminders that are hours late (e.g. after an outage).
        const stale = now.getTime() - remindTs.toMillis() > 6 * 3600 * 1000;
        return stale ? null : {data, plan};
      });
      if (!claim || !pair) continue;

      const {data, plan} = claim;
      const title = `${data.emoji ?? "📅"} ${data.title ?? "Countdown"}`;
      const body = plan.isMoment ?
        "It's time! 🎉" :
        `${describeLead(plan.occurrence.getTime() - now.getTime())} to go`;
      for (const uid of pair.memberIds) {
        const user = await getUser(uid);
        await notify(uid, {
          channel: "countdowns",
          type: "countdown",
          title,
          body,
          data: {route: "/countdowns", countdownId: c.id, pairId: pairRef.id},
          prefKey: "reminders",
          user,
        });
      }
    }
    if (due.size > 0) logger.info("countdownTimedReminders", {due: due.size});
  },
);
