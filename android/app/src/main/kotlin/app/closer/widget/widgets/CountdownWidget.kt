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
        val emoji = prefs.str(WidgetKeys.COUNTDOWN_EMOJI)
        val wide = WidgetSizes.isWide(LocalSize.current)

        WidgetContainer(palette, onClick, contentAlignment = Alignment.Center) {
            if (days == 0L) {
                Today(palette, emoji, title, context)
            } else if (wide) {
                Row(
                    modifier = GlanceModifier.fillMaxSize(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    if (emoji.isNotEmpty()) {
                        Text(emoji, style = TextStyle(fontSize = 40.sp))
                        Spacer(GlanceModifier.width(12.dp))
                    }
                    Column(horizontalAlignment = Alignment.Start) {
                        BigNumber(days, palette)
                        Label(daysLabel(context, days, title), palette, TextAlign.Start)
                    }
                }
            } else {
                Column(
                    modifier = GlanceModifier.fillMaxSize(),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    if (emoji.isNotEmpty()) Text(emoji, style = TextStyle(fontSize = 22.sp))
                    BigNumber(days, palette)
                    Label(daysLabel(context, days, title), palette, TextAlign.Center)
                }
            }
        }
    }

    @Composable
    private fun BigNumber(days: Long, palette: WidgetPalette) {
        Text(
            text = days.toString(),
            maxLines = 1,
            style = TextStyle(
                color = palette.primary,
                fontSize = if (days >= 1000) 34.sp else 44.sp,
                fontWeight = FontWeight.Bold,
            ),
        )
    }

    @Composable
    private fun Label(text: String, palette: WidgetPalette, align: TextAlign) {
        Text(
            text = text,
            maxLines = 2,
            modifier = if (align == TextAlign.Center) GlanceModifier.fillMaxWidth() else GlanceModifier,
            style = TextStyle(color = palette.text, fontSize = 13.sp, fontWeight = FontWeight.Medium, textAlign = align),
        )
    }

    @Composable
    private fun Today(palette: WidgetPalette, emoji: String, title: String, context: Context) {
        Column(
            modifier = GlanceModifier.fillMaxSize(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (emoji.isNotEmpty()) Text(emoji, style = TextStyle(fontSize = 28.sp))
            Text(
                text = context.getString(R.string.widget_countdown_today),
                maxLines = 1,
                style = TextStyle(color = palette.primary, fontSize = 24.sp, fontWeight = FontWeight.Bold),
            )
            if (title.isNotEmpty()) Label(title, palette, TextAlign.Center)
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
