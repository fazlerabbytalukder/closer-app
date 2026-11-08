package app.closer.widget.widgets.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.glance.GlanceTheme
import androidx.glance.unit.ColorProvider

/** Colours used by every Closer widget. */
data class WidgetPalette(
    val bg: ColorProvider,
    val surface: ColorProvider,
    val primary: ColorProvider,
    val text: ColorProvider,
    val textMuted: ColorProvider,
    val accent: ColorProvider,
)

/**
 * Maps the `theme_id` widget key (see WidgetThemes in widget_contract.dart) to colours.
 * Mirrors the `widget_*` entries in res/values/colors.xml.
 */
object WidgetTheme {
    const val CLASSIC = "classic"
    const val BLUSH = "blush"
    const val MIDNIGHT = "midnight"
    const val MINT = "mint"
    const val SUNSET = "sunset"
    const val DYNAMIC = "dynamic"

    private fun fixed(bg: Long, surface: Long, primary: Long, text: Long, accent: Long): WidgetPalette {
        val t = Color(text)
        return WidgetPalette(
            bg = ColorProvider(Color(bg)),
            surface = ColorProvider(Color(surface)),
            primary = ColorProvider(Color(primary)),
            text = ColorProvider(t),
            textMuted = ColorProvider(t.copy(alpha = 0.62f)),
            accent = ColorProvider(Color(accent)),
        )
    }

    private val classic = fixed(0xFFFFFFFF, 0xFFE6F0FC, 0xFF2F7BE6, 0xFF1C2433, 0xFFFF6B8A)
    private val blush = fixed(0xFFFFF1F4, 0xFFFFDDE5, 0xFFFF6B8A, 0xFF3A1F27, 0xFFFF6B8A)
    private val midnight = fixed(0xFF141A2E, 0xFF222B45, 0xFF8FB4FF, 0xFFF2F4FA, 0xFFFF8FA6)
    private val mint = fixed(0xFFECF8EE, 0xFFD3F0D8, 0xFF2E9E52, 0xFF1D3323, 0xFFFF6B8A)
    private val sunset = fixed(0xFFFFF3E6, 0xFFFFE0C2, 0xFFF07B3F, 0xFF3B2416, 0xFFFF6B8A)

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
                accent = c.tertiary,
            )
        }
        else -> classic
    }
}
