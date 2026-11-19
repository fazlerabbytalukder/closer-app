package app.closer.widget.widgets

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.padding
import androidx.glance.layout.height
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.width
import androidx.glance.state.GlanceStateDefinition
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextAlign
import androidx.glance.text.TextStyle
import app.closer.widget.MainActivity
import app.closer.widget.R
import app.closer.widget.widgets.ui.Chip
import app.closer.widget.widgets.ui.EmojiBubble
import app.closer.widget.widgets.ui.WidgetContainer
import app.closer.widget.widgets.ui.WidgetMessage
import app.closer.widget.widgets.ui.WidgetPalette
import app.closer.widget.widgets.ui.WidgetSizes
import app.closer.widget.widgets.ui.WidgetTheme
import app.closer.widget.work.WidgetRefreshWorker
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import es.antonborri.home_widget.actionStartActivity
import java.time.LocalDate
import java.time.temporal.ChronoUnit

/** Days until the next countdown date. S 2×2, M 4×2. Tap → closer://countdowns. */
class CountdownWidget : GlanceAppWidget() {

    override val stateDefinition: GlanceStateDefinition<*> = HomeWidgetGlanceStateDefinition()

    override val sizeMode: SizeMode = SizeMode.Responsive(setOf(WidgetSizes.SMALL, WidgetSizes.MEDIUM))

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            GlanceTheme {
                Content(currentState<HomeWidgetGlanceState>())
            }
        }
    }

    @Composable
    private fun Content(state: HomeWidgetGlanceState) {
        val context = LocalContext.current
        val prefs = state.preferences
        val palette = WidgetTheme.palette(prefs.str(WidgetKeys.THEME_ID))
        val onClick = actionStartActivity<MainActivity>(context, Uri.parse(WidgetLinks.COUNTDOWNS))

        if (!prefs.bool(WidgetKeys.PAIRED)) {
            WidgetContainer(palette, onClick) {
                WidgetMessage(palette, context.getString(R.string.widget_not_paired), emoji = "💞")
            }
            return
        }

        val days = daysUntil(prefs.str(WidgetKeys.COUNTDOWN_DATE))
        if (days == null || days < 0) {
            WidgetContainer(palette, onClick) {
                WidgetMessage(palette, context.getString(R.string.widget_countdown_empty), emoji = "📅")
            }
            return
        }

        val title = prefs.str(WidgetKeys.COUNTDOWN_TITLE)
        val emoji = prefs.str(WidgetKeys.COUNTDOWN_EMOJI).ifEmpty { "💕" }
        val wide = WidgetSizes.isWide(LocalSize.current)

        WidgetContainer(palette, onClick, padding = 14.dp) {
            when {
                days == 0L -> Today(palette, emoji, title, context)
                wide -> Row(
                    modifier = GlanceModifier.fillMaxSize(),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    EmojiBubble(emoji, palette, size = 68.dp, emojiSize = 32.sp)
                    Spacer(GlanceModifier.width(14.dp))
                    Column(modifier = GlanceModifier.defaultWeight()) {
                        Chip(context.getString(R.string.widget_countdown_chip), palette)
                        Row(verticalAlignment = Alignment.Bottom) {
                            BigNumber(days, palette, 44)
                            Spacer(GlanceModifier.width(6.dp))
                            Text(
                                text = context.resources.getQuantityString(R.plurals.widget_days_unit, days.toInt()),
                                maxLines = 1,
                                modifier = GlanceModifier.padding(bottom = 8.dp),
                                style = TextStyle(color = palette.textMuted, fontSize = 14.sp, fontWeight = FontWeight.Bold),
                            )
                        }
                        if (title.isNotEmpty()) Label(title, palette, TextAlign.Start, 14)
                    }
                }
                else -> Column(modifier = GlanceModifier.fillMaxSize()) {
                    Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        EmojiBubble(emoji, palette, size = 34.dp, emojiSize = 17.sp)
                        Spacer(GlanceModifier.defaultWeight())
                        Text("💕", style = TextStyle(fontSize = 12.sp))
                    }
                    Spacer(GlanceModifier.defaultWeight())
                    BigNumber(days, palette, 40)
                    Label(daysLabel(context, days, title), palette, TextAlign.Start, 12)
                }
            }
        }
    }

    @Composable
    private fun BigNumber(days: Long, palette: WidgetPalette, sizeSp: Int) {
        Text(
            text = days.toString(),
            maxLines = 1,
            style = TextStyle(
                color = palette.text,
                fontSize = if (days >= 1000) (sizeSp - 10).sp else sizeSp.sp,
                fontWeight = FontWeight.Bold,
            ),
        )
    }

    @Composable
    private fun Label(text: String, palette: WidgetPalette, align: TextAlign, sizeSp: Int) {
        Text(
            text = text,
            maxLines = 2,
            modifier = if (align == TextAlign.Center) GlanceModifier.fillMaxWidth() else GlanceModifier,
            style = TextStyle(color = palette.textMuted, fontSize = sizeSp.sp, fontWeight = FontWeight.Bold, textAlign = align),
        )
    }

    @Composable
    private fun Today(palette: WidgetPalette, emoji: String, title: String, context: Context) {
        Column(
            modifier = GlanceModifier.fillMaxSize(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            EmojiBubble(emoji, palette, size = 48.dp, emojiSize = 24.sp)
            Spacer(GlanceModifier.height(6.dp))
            Text(
                text = context.getString(R.string.widget_countdown_today),
                maxLines = 1,
                style = TextStyle(color = palette.text, fontSize = 22.sp, fontWeight = FontWeight.Bold),
            )
            if (title.isNotEmpty()) Label(title, palette, TextAlign.Center, 13)
        }
    }

    companion object {
        /** Whole days from today (local) to [date] (yyyy-MM-dd); null if blank/invalid. */
        fun daysUntil(date: String, today: LocalDate = LocalDate.now()): Long? {
            if (date.isBlank()) return null
            return try {
                // Accept "yyyy-MM-dd" and tolerate a trailing time part ("yyyy-MM-ddTHH:mm...").
                ChronoUnit.DAYS.between(today, LocalDate.parse(date.trim().take(10)))
            } catch (_: Exception) {
                null
            }
        }

        /** "12 days to Paris" / "1 day to Paris" / "12 days left". */
        fun daysLabel(context: Context, days: Long, title: String): String {
            val n = days.toInt()
            return if (title.isEmpty()) {
                context.resources.getQuantityString(R.plurals.widget_days_left, n)
            } else {
                context.resources.getQuantityString(R.plurals.widget_days_to, n, title)
            }
        }
    }
}

class CountdownWidgetReceiver : HomeWidgetGlanceWidgetReceiver<CountdownWidget>() {
    override val glanceAppWidget = CountdownWidget()

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        WidgetRefreshWorker.schedule(context)
    }
}
