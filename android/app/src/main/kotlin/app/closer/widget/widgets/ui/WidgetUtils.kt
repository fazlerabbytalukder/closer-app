package app.closer.widget.widgets.ui

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import java.io.File
import java.text.DateFormat
import java.util.Date
import kotlin.math.max

object WidgetUtils {
    private const val TAG = "CloserWidget"

    /**
     * Decodes [path] downsampled so the long side is at most ~[maxSidePx] (power-of-two
     * `inSampleSize`, then a final scale if still too big). Keeps the RemoteViews bitmap
     * memory well under the per-widget limit. Returns null if missing/undecodable.
     */
    fun decodeSampled(path: String, maxSidePx: Int): Bitmap? {
        if (path.isBlank()) return null
        val file = File(path)
        if (!file.isFile || file.length() == 0L) return null
        return try {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(path, bounds)
            val longSide = max(bounds.outWidth, bounds.outHeight)
            if (longSide <= 0) return null
            var sample = 1
            while (longSide / (sample * 2) >= maxSidePx) sample *= 2
            val opts = BitmapFactory.Options().apply {
                inSampleSize = sample
                inPreferredConfig = Bitmap.Config.RGB_565.takeIf { !path.endsWith(".png", true) }
                    ?: Bitmap.Config.ARGB_8888
            }
            val decoded = BitmapFactory.decodeFile(path, opts) ?: return null
            val decodedLong = max(decoded.width, decoded.height)
            if (decodedLong <= maxSidePx) return decoded
            val scale = maxSidePx.toFloat() / decodedLong
            val scaled = Bitmap.createScaledBitmap(
                decoded,
                (decoded.width * scale).toInt().coerceAtLeast(1),
                (decoded.height * scale).toInt().coerceAtLeast(1),
                true,
            )
            if (scaled !== decoded) decoded.recycle()
            scaled
        } catch (t: Throwable) {
            Log.w(TAG, "Could not decode widget image $path", t)
            null
        }
    }

    /** "now", "2m ago", "3h ago", "4d ago", or a short date for older items. */
    fun relativeTime(sentAtMillis: Long?, now: Long = System.currentTimeMillis()): String {
        if (sentAtMillis == null || sentAtMillis <= 0L) return ""
        val diff = (now - sentAtMillis).coerceAtLeast(0L)
        val min = diff / 60_000L
        return when {
            min < 1 -> "now"
            min < 60 -> "${min}m ago"
            min < 60 * 24 -> "${min / 60}h ago"
            min < 60 * 24 * 7 -> "${min / (60 * 24)}d ago"
            else -> DateFormat.getDateInstance(DateFormat.SHORT).format(Date(sentAtMillis))
        }
    }
}
