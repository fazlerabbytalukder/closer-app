/**
 * Closer Plus via RevenueCat (plan section 11). One subscription covers the
 * pair: `pairs/{pairId}.premium` is active while ANY member has an active
 * `plus` entitlement. One-time packs are stored per user and their union is
 * mirrored to `pairs/{pairId}.ownedPacks` so the partner gets them too.
 */
import {timingSafeEqual} from "node:crypto";
import {onRequest} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import {Transaction, DocumentSnapshot} from "firebase-admin/firestore";
import {db, REGION, FieldValue, Timestamp, PremiumState, logger} from "./common";

/** Set with: firebase functions:secrets:set REVENUECAT_WEBHOOK_AUTH */
export const REVENUECAT_WEBHOOK_AUTH = defineSecret("REVENUECAT_WEBHOOK_AUTH");

/** RevenueCat entitlement identifier for Closer Plus. */
export const PLUS_ENTITLEMENT = "plus";

const NO_PREMIUM: PremiumState = {active: false, source: "subscription", ownerUid: null, expiresAt: null};

interface Entitlements {
  plus?: {active?: boolean; expiresAt?: Timestamp | null};
  packs?: string[];
}

function activePlus(e: Entitlements | undefined, now: number): boolean {
  if (!e?.plus?.active) return false;
  const exp = e.plus.expiresAt;
  return !exp || exp.toMillis() > now;
}

/** Computes the pair premium + packs from members' entitlement snapshots. */
export function computePairPremium(
  memberIds: string[],
  snaps: DocumentSnapshot[],
): {premium: PremiumState; ownedPacks: string[]} {
  const now = Date.now();
  let premium = NO_PREMIUM;
  const packs = new Set<string>();
  memberIds.forEach((uid, i) => {
    const e = snaps[i]?.data() as Entitlements | undefined;
    (e?.packs ?? []).forEach((p) => packs.add(p));
    if (!premium.active && activePlus(e, now)) {
      premium = {active: true, source: "subscription", ownerUid: uid, expiresAt: e?.plus?.expiresAt ?? null};
    }
  });
  return {premium, ownedPacks: [...packs].sort()};
}

/** Reads members' entitlements inside [tx] (reads only — call before writes). */
export async function readPairPremium(
  tx: Transaction,
  memberIds: string[],
): Promise<{premium: PremiumState; ownedPacks: string[]}> {
  const snaps = await Promise.all(memberIds.map((m) => tx.get(db.doc(`entitlements/${m}`))));
  return computePairPremium(memberIds, snaps);
}

/** Recomputes and stores premium for the user's current pair, if any. */
export async function refreshPairPremiumForUser(uid: string): Promise<void> {
  const user = await db.doc(`users/${uid}`).get();
  const pairId = user.get("pairId");
  if (typeof pairId !== "string" || !pairId) return;
  const pairRef = db.doc(`pairs/${pairId}`);
  await db.runTransaction(async (tx) => {
    const pair = await tx.get(pairRef);
    if (!pair.exists || pair.get("status") !== "active") return;
    const memberIds: string[] = pair.get("memberIds") ?? [];
    const {premium, ownedPacks} = await readPairPremium(tx, memberIds);
    tx.update(pairRef, {premium, ownedPacks});
  });
}

function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a);
  const bb = Buffer.from(b);
  return ab.length === bb.length && timingSafeEqual(ab, bb);
}

const ACTIVATING = new Set([
  "INITIAL_PURCHASE",
  "RENEWAL",
  "PRODUCT_CHANGE",
  "UNCANCELLATION",
  "NON_RENEWING_PURCHASE",
  "SUBSCRIPTION_EXTENDED",
  "TEMPORARY_ENTITLEMENT_GRANT",
  // Still entitled until expiration_at_ms:
  "CANCELLATION",
  "BILLING_ISSUE",
  "SUBSCRIPTION_PAUSED",
]);

interface RcEvent {
  type?: string;
  app_user_id?: string;
  original_app_user_id?: string;
  aliases?: string[];
  transferred_from?: string[];
  transferred_to?: string[];
  entitlement_ids?: string[] | null;
  entitlement_id?: string | null;
  product_id?: string;
  expiration_at_ms?: number | null;
  environment?: string;
}

const isRealUid = (id: unknown): id is string =>
  typeof id === "string" && id.length > 0 && !id.startsWith("$RCAnonymousID");

/**
 * RevenueCat webhook. Configure in RevenueCat → Integrations → Webhooks with
 * Authorization header value equal to the REVENUECAT_WEBHOOK_AUTH secret
 * (either the raw value or "Bearer <value>"). The app must configure
 * Purchases with appUserID = Firebase uid.
 */
export const revenuecatWebhook = onRequest(
  {region: REGION, secrets: [REVENUECAT_WEBHOOK_AUTH], cors: false},
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method not allowed");
      return;
    }
    const secret = REVENUECAT_WEBHOOK_AUTH.value();
    const header = req.get("authorization") ?? "";
    if (!secret || !(safeEqual(header, secret) || safeEqual(header, `Bearer ${secret}`))) {
      res.status(401).send("Unauthorized");
      return;
    }

    const event = (req.body?.event ?? {}) as RcEvent;
    const type = event.type ?? "";
    if (type === "TEST") {
      res.status(200).send({ok: true, test: true});
      return;
    }

    try {
      const entitlementIds = event.entitlement_ids ?? (event.entitlement_id ? [event.entitlement_id] : []);
      const affectsPlus =
        entitlementIds.includes(PLUS_ENTITLEMENT) || (event.product_id ?? "").startsWith("closer_plus");
      const now = Date.now();
      const touched = new Set<string>();

      if (type === "TRANSFER") {
        for (const uid of (event.transferred_from ?? []).filter(isRealUid)) {
          await db.doc(`entitlements/${uid}`).set(
            {plus: {active: false, expiresAt: null, updatedAt: FieldValue.serverTimestamp()}},
            {merge: true},
          );
          touched.add(uid);
        }
        // The new owner's state arrives with their next purchase/restore event.
      } else {
        const uids = new Set(
          [event.app_user_id, event.original_app_user_id, ...(event.aliases ?? [])].filter(isRealUid),
        );
        const exp = typeof event.expiration_at_ms === "number" ? event.expiration_at_ms : null;
        for (const uid of uids) {
          const ref = db.doc(`entitlements/${uid}`);
          const update: Record<string, unknown> = {updatedAt: FieldValue.serverTimestamp()};
          if (affectsPlus) {
            const active = type === "EXPIRATION" ? false : ACTIVATING.has(type) && (exp === null || exp > now);
            update.plus = {
              active,
              expiresAt: exp ? Timestamp.fromMillis(exp) : null,
              productId: event.product_id ?? null,
              lastEvent: type,
              environment: event.environment ?? null,
              updatedAt: FieldValue.serverTimestamp(),
            };
          }
          const productId = event.product_id ?? "";
          if (productId.startsWith("pack_") && type === "NON_RENEWING_PURCHASE") {
            update.packs = FieldValue.arrayUnion(productId);
          }
          await ref.set(update, {merge: true});
          touched.add(uid);
        }
      }

      for (const uid of touched) await refreshPairPremiumForUser(uid);
      res.status(200).send({ok: true});
    } catch (e) {
      logger.error("revenuecatWebhook failed", {type, e});
      // Non-2xx makes RevenueCat retry.
      res.status(500).send({ok: false});
    }
  },
);
