/**
 * Shared helpers for all Closer functions: Firebase Admin handles, auth and
 * membership checks, timezone maths and FCM sending (with quiet hours).
 */
import {initializeApp, getApps} from "firebase-admin/app";
import {getFirestore, FieldValue, Timestamp, DocumentReference, DocumentData} from "firebase-admin/firestore";
import {getStorage} from "firebase-admin/storage";
import {getMessaging, MulticastMessage} from "firebase-admin/messaging";
import {setGlobalOptions} from "firebase-functions/v2";
import {HttpsError, CallableRequest} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

if (getApps().length === 0) initializeApp();

export const db = getFirestore();
db.settings({ignoreUndefinedProperties: true});
export const bucket = () => getStorage().bucket();
export {FieldValue, Timestamp, logger};

/** All functions live next to the eur3 Firestore database. */
export const REGION = "europe-west1";

setGlobalOptions({region: REGION, maxInstances: 20});

/**
 * Flip to true once App Check (Play Integrity) is configured in the app and
 * enforcement is turned on in the console (plan section 12).
 */
export const ENFORCE_APP_CHECK = false;

export const CALLABLE_OPTS = {
  region: REGION,
  enforceAppCheck: ENFORCE_APP_CHECK,
} as const;

/** Free-tier limits (mirrors lib/core/data/closer_backend.dart FreeLimits). */
export const FREE = {
  sendsPerDay: 10,
  rewardedExtraSends: 3,
  rewardedGrantsPerDay: 1,
  countdowns: 3,
  tapCooldownMs: 10_000,
  /** Sanity cap even for Plus, against abuse. */
  plusSendsPerDay: 300,
} as const;

export type PairMode = "couple" | "friends";

export interface NotificationPrefs {
  taps?: boolean;
  questions?: boolean;
  reminders?: boolean;
  quietHours?: {start?: number | null; end?: number | null};
}

export interface UserDoc {
  displayName?: string;
  photoUrl?: string | null;
  pairId?: string | null;
  timezone?: string;
  ageConfirmed18?: boolean;
  notificationPrefs?: NotificationPrefs;
  pendingMode?: PairMode | null;
}

export interface PremiumState {
  active: boolean;
  source: "subscription";
  ownerUid: string | null;
  expiresAt: Timestamp | null;
}

export interface PairDoc {
  memberIds: string[];
  mode: PairMode;
  status: "active" | "unpaired";
  pairedAt: Timestamp;
  timezone?: string;
  premium?: PremiumState;
  questionPack?: string;
  questionCursor?: Record<string, number>;
  streak?: Record<string, unknown>;
  plant?: Record<string, unknown>;
  lastTapByUser?: Record<string, Timestamp>;
  ownedPacks?: string[];
}

// ------------------------------------------------------------------ errors

/** Error codes the Flutter app maps to LimitReachedException(limit). */
export function limitError(limit: string, message: string, extra: Record<string, unknown> = {}): HttpsError {
  return new HttpsError("resource-exhausted", message, {limit, ...extra});
}

/** User-facing error with a stable `reason` the app can switch on. */
export function userError(
  code: "invalid-argument" | "failed-precondition" | "not-found" | "already-exists" | "permission-denied",
  reason: string,
  message: string,
): HttpsError {
  return new HttpsError(code, message, {reason});
}

export function requireAuth(req: CallableRequest<unknown>): string {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Please sign in again.");
  return uid;
}

export function str(v: unknown, max: number, fallback = ""): string {
  if (typeof v !== "string") return fallback;
  return v.trim().slice(0, max);
}

// ------------------------------------------------------------------- pairs

export interface PairContext {
  uid: string;
  user: UserDoc;
  pairId: string;
  pairRef: DocumentReference<DocumentData>;
  pair: PairDoc;
  partnerUid: string;
}

/**
 * Loads the caller's active pair. If [pairId] is given it must match the
 * caller's current pair.
 */
export async function requirePair(uid: string, pairId?: unknown): Promise<PairContext> {
  const userSnap = await db.doc(`users/${uid}`).get();
  const user = (userSnap.data() ?? {}) as UserDoc;
  const current = user.pairId;
  if (!current) throw userError("failed-precondition", "not-paired", "You're not connected to anyone yet.");
  if (typeof pairId === "string" && pairId && pairId !== current) {
    throw userError("permission-denied", "wrong-pair", "That pair is no longer yours.");
  }
  const pairRef = db.doc(`pairs/${current}`);
  const pairSnap = await pairRef.get();
  const pair = pairSnap.data() as PairDoc | undefined;
  if (!pair || pair.status === "unpaired" || !pair.memberIds?.includes(uid)) {
    throw userError("failed-precondition", "not-paired", "You're not connected to anyone yet.");
  }
  const partnerUid = pair.memberIds.find((m) => m !== uid) ?? "";
  return {uid, user, pairId: current, pairRef, pair, partnerUid};
}

/**
 * Closer Plus, free-tier limits and ads. While false every pair is treated
 * as premium (no limits, all packs/themes). Keep in sync with
 * `AppConfig.monetizationEnabled` in lib/core/config.dart.
 */
export const MONETIZATION_ENABLED = false;

export function isPremium(pair: PairDoc | undefined, now = Date.now()): boolean {
  if (!MONETIZATION_ENABLED) return true;
  const p = pair?.premium;
  if (!p?.active) return false;
  return !p.expiresAt || p.expiresAt.toMillis() > now;
}

export async function getUser(uid: string): Promise<UserDoc> {
  const snap = await db.doc(`users/${uid}`).get();
  return (snap.data() ?? {}) as UserDoc;
}

export function firstName(user: UserDoc | undefined, fallback = "Your person"): string {
  const n = (user?.displayName ?? "").trim();
  return n ? n.split(/\s+/)[0] : fallback;
}

// -------------------------------------------------------------------- time

export function safeTz(tz: unknown): string {
  if (typeof tz !== "string" || !tz) return "UTC";
  try {
    new Intl.DateTimeFormat("en-US", {timeZone: tz});
    return tz;
  } catch {
    return "UTC";
  }
}

export interface ZonedParts {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
}

export function zoned(date: Date, tz: unknown): ZonedParts {
  const f = new Intl.DateTimeFormat("en-US", {
    timeZone: safeTz(tz),
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
  });
  const p: Record<string, string> = {};
  for (const part of f.formatToParts(date)) p[part.type] = part.value;
  return {
    year: Number(p.year),
    month: Number(p.month),
    day: Number(p.day),
    hour: Number(p.hour) % 24,
    minute: Number(p.minute),
  };
}

const pad = (n: number) => String(n).padStart(2, "0");

/** yyyy-mm-dd of [date] in [tz]. */
export function localDateKey(date: Date, tz: unknown): string {
  const z = zoned(date, tz);
  return `${z.year}-${pad(z.month)}-${pad(z.day)}`;
}

export function localHour(date: Date, tz: unknown): number {
  return zoned(date, tz).hour;
}

/** Adds [n] days to a yyyy-mm-dd key. */
export function addDays(key: string, n: number): string {
  const [y, m, d] = key.split("-").map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}

/** Whole days from key [a] to key [b] (b - a). */
export function daysBetween(a: string, b: string): number {
  const [ay, am, ad] = a.split("-").map(Number);
  const [by, bm, bd] = b.split("-").map(Number);
  return Math.round((Date.UTC(by, bm - 1, bd) - Date.UTC(ay, am - 1, ad)) / 86_400_000);
}

/** Offset of [tz] from UTC at [date], in ms (positive east of Greenwich). */
export function tzOffsetMs(date: Date, tz: unknown): number {
  const z = zoned(date, tz);
  const asUtc = Date.UTC(z.year, z.month - 1, z.day, z.hour, z.minute);
  const truncated = Math.floor(date.getTime() / 60_000) * 60_000;
  return asUtc - truncated;
}

/** The next local midnight in [tz] after [date]. */
export function nextLocalMidnight(date: Date, tz: unknown): Date {
  const z = zoned(date, tz);
  const offset = tzOffsetMs(date, tz);
  return new Date(Date.UTC(z.year, z.month - 1, z.day + 1) - offset);
}

export function inQuietHours(prefs: NotificationPrefs | undefined, tz: unknown, now = new Date()): boolean {
  const start = prefs?.quietHours?.start;
  const end = prefs?.quietHours?.end;
  if (typeof start !== "number" || typeof end !== "number" || start === end) return false;
  const h = localHour(now, tz);
  return start < end ? h >= start && h < end : h >= start || h < end;
}

// --------------------------------------------------------------------- FCM

export type Channel =
  | "partner_items"
  | "taps"
  | "daily_question"
  | "streak"
  | "countdowns"
  | "game_turns"
  | "account";

type PrefKey = "taps" | "questions" | "reminders";

export async function getTokens(uid: string): Promise<string[]> {
  const snap = await db.doc(`devices/${uid}`).get();
  const tokens = snap.get("tokens");
  return Array.isArray(tokens) ? tokens.filter((t): t is string => typeof t === "string") : [];
}

async function sendMulticast(uid: string, message: Omit<MulticastMessage, "tokens">): Promise<void> {
  const tokens = await getTokens(uid);
  if (tokens.length === 0) return;
  try {
    const res = await getMessaging().sendEachForMulticast({...message, tokens});
    const dead: string[] = [];
    res.responses.forEach((r, i) => {
      const code = r.error?.code;
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token"
      ) {
        dead.push(tokens[i]);
      } else if (r.error) {
        logger.warn("FCM send failed", {uid, code, msg: r.error.message});
      }
    });
    if (dead.length > 0) {
      await db.doc(`devices/${uid}`).set({tokens: FieldValue.arrayRemove(...dead)}, {merge: true});
    }
  } catch (e) {
    logger.error("FCM multicast error", {uid, e});
  }
}

/**
 * Data-only, high-priority message (no `notification` block) so the Dart
 * background handler always runs and can update the home-screen widget.
 * `silent: "1"` tells the app to skip the visible notification (quiet hours
 * or the user's per-type preference).
 */
export async function sendWidgetData(
  uid: string,
  data: Record<string, string>,
  opts: {prefKey?: PrefKey; user?: UserDoc; ttlMs?: number} = {},
): Promise<void> {
  const user = opts.user ?? (await getUser(uid));
  const prefs = user.notificationPrefs;
  const prefOff = opts.prefKey ? prefs?.[opts.prefKey] === false : false;
  const silent = prefOff || inQuietHours(prefs, user.timezone);
  await sendMulticast(uid, {
    data: {...data, silent: silent ? "1" : "0"},
    android: {priority: "high", ttl: opts.ttlMs ?? 24 * 3600 * 1000},
  });
}

/**
 * Visible notification on a channel. Suppressed entirely during the user's
 * quiet hours or when the matching preference is off.
 */
export async function notify(
  uid: string,
  n: {
    channel: Channel;
    title: string;
    body: string;
    type: string;
    data?: Record<string, string>;
    prefKey?: PrefKey;
    ignoreQuiet?: boolean;
    user?: UserDoc;
  },
): Promise<void> {
  const user = n.user ?? (await getUser(uid));
  const prefs = user.notificationPrefs;
  if (n.prefKey && prefs?.[n.prefKey] === false) return;
  if (!n.ignoreQuiet && inQuietHours(prefs, user.timezone)) return;
  await sendMulticast(uid, {
    notification: {title: n.title, body: n.body},
    data: {type: n.type, channel: n.channel, ...(n.data ?? {})},
    android: {
      priority: "normal",
      notification: {channelId: n.channel, tag: `${n.type}`},
    },
  });
}

export async function notifyMany(uids: string[], n: Parameters<typeof notify>[1]): Promise<void> {
  await Promise.all(uids.filter(Boolean).map((u) => notify(u, {...n, user: undefined})));
}
