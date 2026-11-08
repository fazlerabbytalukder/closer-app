/**
 * Widget thumbnails (plan section 5 / 7): ~600 px JPEG at 80 % with all
 * EXIF/GPS metadata removed. Also re-encodes the raw upload once to strip
 * its metadata.
 *
 * Storage layout:
 *   pairs/{pairId}/raw/{itemId}.jpg     (uploaded by the app)
 *   pairs/{pairId}/thumbs/{itemId}.jpg  (written here)
 */
import {randomUUID} from "node:crypto";
import sharp from "sharp";
import {onObjectFinalized} from "firebase-functions/v2/storage";
import {bucket, logger, REGION} from "./common";

export const THUMB_SIZE = 600;
const RAW_RE = /^pairs\/([^/]+)\/raw\/([^/]+)\.jpg$/;

export const rawPath = (pairId: string, itemId: string) => `pairs/${pairId}/raw/${itemId}.jpg`;
export const thumbPath = (pairId: string, itemId: string) => `pairs/${pairId}/thumbs/${itemId}.jpg`;

/** Public, unguessable Firebase download URL for a file with a token. */
export function downloadUrl(bucketName: string, path: string, token: string): string {
  return `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/${encodeURIComponent(path)}` +
    `?alt=media&token=${token}`;
}

function tokenOf(meta: {metadata?: Record<string, unknown> | null}): string | null {
  const raw = meta.metadata?.firebaseStorageDownloadTokens;
  if (typeof raw !== "string" || !raw) return null;
  return raw.split(",")[0];
}

/**
 * Makes the thumbnail if missing and returns its path plus a download URL
 * the receiving phone can fetch without signing in (used in the FCM data).
 * Idempotent: safe to call from both sendItem and the storage trigger.
 */
export async function ensureThumbnail(
  pairId: string,
  itemId: string,
): Promise<{thumbPath: string; thumbUrl: string}> {
  const b = bucket();
  const tPath = thumbPath(pairId, itemId);
  const thumb = b.file(tPath);
  const [exists] = await thumb.exists();
  if (exists) {
    const [meta] = await thumb.getMetadata();
    const token = tokenOf(meta as {metadata?: Record<string, unknown>});
    if (token) return {thumbPath: tPath, thumbUrl: downloadUrl(b.name, tPath, token)};
  }
  const [buf] = await b.file(rawPath(pairId, itemId)).download();
  const out = await sharp(buf, {failOn: "none"})
    .rotate() // apply EXIF orientation before metadata is dropped
    .resize({width: THUMB_SIZE, height: THUMB_SIZE, fit: "inside", withoutEnlargement: true})
    .flatten({background: "#ffffff"}) // PNG notes/doodles with transparency
    .jpeg({quality: 80, mozjpeg: true})
    .toBuffer(); // sharp drops EXIF/GPS/ICC metadata unless asked to keep it
  const token = randomUUID();
  await thumb.save(out, {
    resumable: false,
    contentType: "image/jpeg",
    metadata: {
      cacheControl: "private, max-age=31536000",
      metadata: {firebaseStorageDownloadTokens: token},
    },
  });
  return {thumbPath: tPath, thumbUrl: downloadUrl(b.name, tPath, token)};
}

/**
 * Storage trigger. NOTE: the function region must be compatible with the
 * default bucket's location (create the bucket in europe-west1 or the EU
 * multi-region).
 */
export const makeThumbnail = onObjectFinalized(
  {region: REGION, memory: "1GiB", timeoutSeconds: 120},
  async (event) => {
    const obj = event.data;
    const m = RAW_RE.exec(obj.name ?? "");
    if (!m) return;
    const [, pairId, itemId] = m;
    const b = bucket();
    const file = b.file(obj.name);

    if (Number(obj.size ?? 0) > 10 * 1024 * 1024 || !(obj.contentType ?? "").startsWith("image/")) {
      logger.warn("Rejecting raw upload", {name: obj.name, size: obj.size, type: obj.contentType});
      await file.delete({ignoreNotFound: true});
      return;
    }

    // 1) Strip metadata from the full-size image (once).
    if (obj.metadata?.closerSanitized !== "true") {
      try {
        const [buf] = await file.download();
        const img = sharp(buf, {failOn: "none"}).rotate();
        const isPng = obj.contentType === "image/png";
        const out = isPng ? await img.png().toBuffer() : await img.jpeg({quality: 90, mozjpeg: true}).toBuffer();
        const keep: Record<string, string> = {closerSanitized: "true"};
        const token = obj.metadata?.firebaseStorageDownloadTokens;
        if (token) keep.firebaseStorageDownloadTokens = token;
        await file.save(out, {
          resumable: false,
          contentType: isPng ? "image/png" : "image/jpeg",
          metadata: {metadata: keep},
        });
      } catch (e) {
        logger.error("Sanitising raw image failed", {name: obj.name, e});
      }
      // The re-save fires this trigger again; the thumbnail is made then.
      return;
    }

    // 2) Widget thumbnail.
    try {
      await ensureThumbnail(pairId, itemId);
    } catch (e) {
      logger.error("Thumbnail failed", {name: obj.name, e});
    }
  },
);
