package app.closer.widget.widgets

import android.content.SharedPreferences

/**
 * Mirror of `lib/core/services/widget_contract.dart` (WidgetKeys). Keep in sync.
 *
 * Flutter writes these with `HomeWidget.saveWidgetData` into the
 * `HomeWidgetPreferences` SharedPreferences file. Every value is a String except
 * [PAIRED] (Boolean). Timestamps are epoch millis stored as String.
 */
object WidgetKeys {
    const val PAIRED = "paired"
    const val PARTNER_NAME = "partner_name"
    const val MODE = "mode"

    const val LATEST_PATH = "latest_path"
    const val LATEST_TYPE = "latest_type"
    const val LATEST_CAPTION = "latest_caption"
    const val LATEST_SENT_AT = "latest_sent_at"
    const val HEART_UNTIL = "heart_until"
    const val PARTNER_MOOD = "partner_mood"

    const val THEME_ID = "theme_id"

    const val COUNTDOWN_TITLE = "countdown_title"
    const val COUNTDOWN_EMOJI = "countdown_emoji"
    const val COUNTDOWN_DATE = "countdown_date"

    const val STREAK_COUNT = "streak_count"
    const val PLANT_STAGE = "plant_stage"
    const val PLANT_HEALTH = "plant_health"
}

/** Mirror of WidgetLinks in widget_contract.dart. */
object WidgetLinks {
    const val REPLY = "closer://reply"
    const val COUNTDOWNS = "closer://countdowns"
    const val PLANT = "closer://plant"
}

/**
 * Defensive readers: the contract says Strings, but never crash the widget if a
 * value arrives with another type (e.g. an Int/Long/Boolean from an older build).
 */
internal fun SharedPreferences.str(key: String): String {
    val v = all[key] ?: return ""
    return v.toString().trim()
}

internal fun SharedPreferences.long(key: String): Long? = when (val v = all[key]) {
    is Number -> v.toLong()
    is String -> v.trim().toLongOrNull() ?: v.trim().toDoubleOrNull()?.toLong()
    else -> null
}

internal fun SharedPreferences.int(key: String): Int? = long(key)?.toInt()

internal fun SharedPreferences.bool(key: String): Boolean = when (val v = all[key]) {
    is Boolean -> v
    is String -> v.equals("true", ignoreCase = true) || v == "1"
    is Number -> v.toInt() != 0
    else -> false
}
