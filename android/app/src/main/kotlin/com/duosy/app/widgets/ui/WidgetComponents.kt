package com.duosy.app.widgets.ui

import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.ColorFilter
import androidx.glance.GlanceModifier
import androidx.glance.ImageProvider
import androidx.glance.action.Action
import androidx.glance.action.clickable
import androidx.glance.appwidget.appWidgetBackground
import androidx.glance.appwidget.cornerRadius
import androidx.glance.background
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.duosy.app.R

/** Responsive breakpoints shared by all widgets: S 2×2, M 4×2, L 4×4. */
object WidgetSizes {
    val SMALL = DpSize(110.dp, 110.dp)
    val MEDIUM = DpSize(250.dp, 110.dp)
    val LARGE = DpSize(250.dp, 250.dp)

    fun isWide(size: DpSize) = size.width >= MEDIUM.width
    fun isTall(size: DpSize) = size.height >= LARGE.height
}

private val rounded = Build.VERSION.SDK_INT >= Build.VERSION_CODES.S

/** Rounds [this] on Android 12+ (older versions can't clip RemoteViews). */
fun GlanceModifier.roundedIfSupported(radius: Dp): GlanceModifier = if (rounded) cornerRadius(radius) else this

/**
 * Themed widget root: the theme's gradient (with soft light bubbles) or a solid
 * colour, rounded with the system widget radius on Android 12+.
 */
@Composable
fun WidgetContainer(
    palette: WidgetPalette,
    onClick: Action?,
    padding: Dp = 12.dp,
    contentAlignment: Alignment = Alignment.TopStart,
    content: @Composable () -> Unit,
) {
    var modifier = GlanceModifier.fillMaxSize().appWidgetBackground()
    val bgRes = palette.bgRes
    modifier = when {
        bgRes != null -> modifier.background(ImageProvider(bgRes), contentScale = ContentScale.FillBounds)
        rounded -> modifier.background(palette.bg)
        else -> modifier.background(ImageProvider(R.drawable.widget_rounded_bg), colorFilter = ColorFilter.tint(palette.bg))
    }
    if (rounded) modifier = modifier.cornerRadius(R.dimen.widget_corner_radius)
    if (onClick != null) modifier = modifier.clickable(onClick)
    Box(modifier = modifier.padding(padding), contentAlignment = contentAlignment) {
        content()
    }
}

/** Centered emoji + message used for empty / not-paired states. */
@Composable
fun WidgetMessage(
    palette: WidgetPalette,
    text: String,
    emoji: String? = null,
    textSize: TextUnit = 14.sp,
) {
    Column(
        modifier = GlanceModifier.fillMaxSize(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (!emoji.isNullOrEmpty()) EmojiBubble(emoji, palette, size = 48.dp, emojiSize = 24.sp)
        Text(
            text = text,
            modifier = GlanceModifier.fillMaxWidth().padding(top = 8.dp),
            maxLines = 3,
            style = TextStyle(
                color = palette.text,
                fontSize = textSize,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
            ),
        )
    }
}

/** Frosted chip ("💕 Next date", "🔥 12 days"). */
@Composable
fun Chip(
    text: String,
    palette: WidgetPalette,
    modifier: GlanceModifier = GlanceModifier,
    bg: ColorProvider = palette.surface,
    fg: ColorProvider = palette.text,
    textSize: TextUnit = 11.sp,
) {
    Box(modifier = modifier.background(bg).roundedIfSupported(999.dp).padding(horizontal = 9.dp, vertical = 4.dp)) {
        Text(
            text = text,
            maxLines = 1,
            style = TextStyle(color = fg, fontSize = textSize, fontWeight = FontWeight.Bold),
        )
    }
}

/** Kept for older call sites: a chip with explicit colours. */
@Composable
fun Pill(text: String, bg: ColorProvider, fg: ColorProvider, modifier: GlanceModifier = GlanceModifier) {
    Box(modifier = modifier.background(bg).roundedIfSupported(999.dp).padding(horizontal = 9.dp, vertical = 4.dp)) {
        Text(text = text, maxLines = 1, style = TextStyle(color = fg, fontSize = 11.sp, fontWeight = FontWeight.Bold))
    }
}

/** Pink heart badge for a fresh "thinking of you" tap. */
@Composable
fun HeartBadge(emoji: String, palette: WidgetPalette) {
    Box(
        modifier = GlanceModifier.size(30.dp).background(palette.heart).roundedIfSupported(999.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(emoji, style = TextStyle(fontSize = 14.sp, textAlign = TextAlign.Center))
    }
}

/** An emoji in a frosted circle. */
@Composable
fun EmojiBubble(emoji: String, palette: WidgetPalette, size: Dp = 44.dp, emojiSize: TextUnit = 22.sp) {
    Box(
        modifier = GlanceModifier.size(size).background(palette.surface).roundedIfSupported(999.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(emoji, style = TextStyle(fontSize = emojiSize, textAlign = TextAlign.Center))
    }
}

/** Dark fade behind text laid over a photo. */
val ScrimModifier: GlanceModifier
    get() = GlanceModifier.background(ImageProvider(R.drawable.widget_scrim), contentScale = ContentScale.FillBounds)

/** White text over a photo scrim. */
val OnPhoto = ColorProvider(androidx.compose.ui.graphics.Color.White)
val OnPhotoMuted = ColorProvider(androidx.compose.ui.graphics.Color.White.copy(alpha = 0.82f))
