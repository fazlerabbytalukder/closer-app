package app.closer.widget.widgets.ui

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
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.padding
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import app.closer.widget.R

/** Responsive breakpoints shared by all widgets: S 2×2, M 4×2, L 4×4. */
object WidgetSizes {
    val SMALL = DpSize(110.dp, 110.dp)
    val MEDIUM = DpSize(250.dp, 110.dp)
    val LARGE = DpSize(250.dp, 250.dp)

    fun isWide(size: DpSize) = size.width >= MEDIUM.width
    fun isTall(size: DpSize) = size.height >= LARGE.height
}

/**
 * Rounded, themed widget root. Uses the system widget radius on Android 12+
 * (`cornerRadius` + `appWidgetBackground`) and a tinted rounded shape before that.
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
    modifier = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        modifier.background(palette.bg).cornerRadius(R.dimen.widget_corner_radius)
    } else {
        modifier.background(
            ImageProvider(R.drawable.widget_rounded_bg),
            colorFilter = ColorFilter.tint(palette.bg),
        )
    }
    if (onClick != null) modifier = modifier.clickable(onClick)
    Box(modifier = modifier.padding(padding), contentAlignment = contentAlignment) {
        content()
    }
}

/** Centered one- or two-line message used for empty / not-paired states. */
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
        if (!emoji.isNullOrEmpty()) {
            Text(text = emoji, style = TextStyle(fontSize = 28.sp, textAlign = TextAlign.Center))
        }
        Text(
            text = text,
            modifier = GlanceModifier.fillMaxWidth().padding(top = 4.dp),
            maxLines = 3,
            style = TextStyle(
                color = palette.text,
                fontSize = textSize,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center,
            ),
        )
    }
}

/** Small pill (e.g. heart badge) drawn on the surface colour. */
@Composable
fun Pill(text: String, bg: ColorProvider, fg: ColorProvider, modifier: GlanceModifier = GlanceModifier) {
    var m = modifier.background(bg)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) m = m.cornerRadius(999.dp)
    Box(modifier = m.padding(horizontal = 8.dp, vertical = 3.dp)) {
        Text(text = text, maxLines = 1, style = TextStyle(color = fg, fontSize = 12.sp, fontWeight = FontWeight.Medium))
    }
}
