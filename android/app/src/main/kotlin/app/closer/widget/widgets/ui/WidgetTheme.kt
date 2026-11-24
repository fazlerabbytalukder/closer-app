package app.closer.widget.widgets.ui

import androidx.annotation.DrawableRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.glance.GlanceTheme
import androidx.glance.unit.ColorProvider
import app.closer.widget.R

/**
 * Colours used by every Duosy widget.
 *
 * Gradient themes ([bgRes] set) draw white text on a diagonal gradient with
 * frosted [surface] chips; Material You uses the system's solid colours.
 */
data class WidgetPalette(
    val bg: ColorProvider,
    /** Chips, frames and bubbles drawn over [bg]. */
    val surface: ColorProvider,
    val primary: ColorProvider,
    val text: ColorProvider,
    val textMuted: ColorProvider,
    val accent: ColorProvider,
    /** The heart badge fill. */
    val heart: ColorProvider = ColorProvider(Color(0xFFFF4F7B)),
    /** Gradient background (layer-list drawable), or null for a solid [bg]. */
    @DrawableRes val bgRes: Int? = null,
)

/**
 * Maps the `theme_id` widget key (see WidgetThemes in widget_contract.dart) to colours.
 * Keep in sync with `widgetPalettes` in lib/features/me/widget_previews.dart.
 */
object WidgetTheme {
    const val CLASSIC = "classic"
    const val BLUSH = "blush"
    const val MIDNIGHT = "midnight"
    const val MINT = "mint"
    const val SUNSET = "sunset"
    const val DYNAMIC = "dynamic"

    private val white = Color(0xFFFFFFFF)

    private fun gradient(@DrawableRes res: Int, start: Long): WidgetPalette = WidgetPalette(
        bg = ColorProvider(Color(start)),
        surface = ColorProvider(white.copy(alpha = 0.22f)),
        primary = ColorProvider(white),
        text = ColorProvider(white),
        textMuted = ColorProvider(white.copy(alpha = 0.8f)),
        accent = ColorProvider(white),
        bgRes = res,
    )

    private val classic = gradient(R.drawable.widget_bg_classic, 0xFF1737E2)
    private val blush = gradient(R.drawable.widget_bg_blush, 0xFFFF5C8A)
    private val midnight = gradient(R.drawable.widget_bg_midnight, 0xFF141033)
    private val mint = gradient(R.drawable.widget_bg_mint, 0xFF0E9F85)
    private val sunset = gradient(R.drawable.widget_bg_sunset, 0xFFFF5E62)

    /** Must be called inside a [GlanceTheme] so `dynamic` resolves to Material You colours. */
    @Composable
    fun palette(themeId: String): WidgetPalette = when (themeId.lowercase()) {
        BLUSH -> blush
        MIDNIGHT -> midnight
        MINT -> mint
        SUNSET -> sunset
        DYNAMIC -> {
            val c = GlanceTheme.colors
            WidgetPalette(
                bg = c.widgetBackground,
                surface = c.secondaryContainer,
                primary = c.primary,
                text = c.onSurface,
                textMuted = c.onSurfaceVariant,
                accent = c.primary,
            )
        }
        else -> classic
    }
}
