package app.closer.widget.widgets

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.GlanceTheme
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.background
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.width
import androidx.glance.state.GlanceStateDefinition
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextStyle
import app.closer.widget.MainActivity
import app.closer.widget.R
import app.closer.widget.widgets.ui.Chip
import app.closer.widget.widgets.ui.OnPhoto
import app.closer.widget.widgets.ui.ScrimModifier
import app.closer.widget.widgets.ui.WidgetContainer
import app.closer.widget.widgets.ui.WidgetMessage
import app.closer.widget.widgets.ui.WidgetPalette
import app.closer.widget.widgets.ui.WidgetSizes
import app.closer.widget.widgets.ui.WidgetTheme
import app.closer.widget.widgets.ui.WidgetUtils
import app.closer.widget.widgets.ui.roundedIfSupported
import app.closer.widget.work.WidgetRefreshWorker
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import es.antonborri.home_widget.actionStartActivity

/**
 * "Always with me": a memory photo of the day, a sweet line (or the partner's latest one-tap
 * message) and the time since you last met. S 2×2, M 4×2, L 4×4. Tap → closer://always.
 *
 * The time since you met is computed here from [WidgetKeys.LAST_MET_AT], so it stays right
 * between app launches (the periodic refresh worker redraws it).
 */
class AlwaysWithMeWidget : GlanceAppWidget() {

    override val stateDefinition: GlanceStateDefinition<*> = HomeWidgetGlanceStateDefinition()

    override val sizeMode: SizeMode = SizeMode.Responsive(
        setOf(WidgetSizes.SMALL, WidgetSizes.MEDIUM, WidgetSizes.LARGE),
    )

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent {
            GlanceTheme {
                Content(currentState<HomeWidgetGlanceState>())
            }
        }
    }

    private data class State(
        val image: ImageProvider?,
        val partner: String,
        val message: String,
        val since: String,
    )

    @Composable
    private fun Content(state: HomeWidgetGlanceState) {
        val context = LocalContext.current
        val prefs = state.preferences
        val size = LocalSize.current
        val palette = WidgetTheme.palette(prefs.str(WidgetKeys.THEME_ID))
        val onClick = actionStartActivity<MainActivity>(context, Uri.parse(WidgetLinks.ALWAYS))

        if (!prefs.bool(WidgetKeys.PAIRED)) {
            WidgetContainer(palette, onClick) {
                WidgetMessage(palette, context.getString(R.string.widget_not_paired), emoji = "💞")
            }
            return
        }

        val wide = WidgetSizes.isWide(size)
        val tall = WidgetSizes.isTall(size)
        val bitmap = WidgetUtils.decodeSampled(
            prefs.str(WidgetKeys.ALWAYS_PHOTO_PATH),
            if (wide && tall) 600 else 400,
        )
        val s = State(
            image = bitmap?.let { ImageProvider(it) },
            partner = prefs.str(WidgetKeys.PARTNER_NAME).ifEmpty { context.getString(R.string.widget_partner_fallback) },
            message = prefs.str(WidgetKeys.ALWAYS_MESSAGE),
            since = sinceLabel(context, prefs.long(WidgetKeys.LAST_MET_AT)),
        )

        WidgetContainer(palette, onClick, padding = 6.dp) {
            when {
                wide && tall -> LargeLayout(s, palette)
                wide -> MediumLayout(s, palette)
                else -> SmallLayout(s, palette)
            }
        }
    }

    /** Memory photo (or a big 💞), optionally with the "since" line on a dark fade. */
    @Composable
    private fun Photo(s: State, palette: WidgetPalette, modifier: GlanceModifier, sinceOnPhoto: Boolean) {
        Box(modifier = modifier.roundedIfSupported(16.dp).background(palette.surface), contentAlignment = Alignment.Center) {
            if (s.image != null) {
                Image(
                    provider = s.image,
                    contentDescription = LocalContext.current.getString(R.string.widget_always_cd, s.partner),
                    contentScale = ContentScale.Crop,
                    modifier = GlanceModifier.fillMaxSize(),
                )
            } else {
                Text("💞", style = TextStyle(fontSize = 40.sp))
            }
            if (sinceOnPhoto) {
                Column(modifier = GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.Bottom) {
                    Box(modifier = ScrimModifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, top = 16.dp, bottom = 8.dp)) {
                        Text(
                            text = s.since,
                            maxLines = 1,
                            style = TextStyle(color = OnPhoto, fontSize = 12.sp, fontWeight = FontWeight.Bold),
                        )
                    }
                }
            }
        }
    }

    @Composable
    private fun Message(s: State, palette: WidgetPalette, maxLines: Int, sizeSp: Int, modifier: GlanceModifier = GlanceModifier) {
        if (s.message.isEmpty()) return
        Text(
            text = "“${s.message}”",
            maxLines = maxLines,
            modifier = modifier,
            style = TextStyle(color = palette.text, fontSize = sizeSp.sp, fontWeight = FontWeight.Bold),
        )
    }

    @Composable
    private fun SmallLayout(s: State, palette: WidgetPalette) {
        Photo(s, palette, GlanceModifier.fillMaxSize(), sinceOnPhoto = true)
    }

    /** Photo left; "Always with me" chip, the sweet line and time since you met. */
    @Composable
    private fun MediumLayout(s: State, palette: WidgetPalette) {
        Row(modifier = GlanceModifier.fillMaxSize()) {
            Photo(s, palette, GlanceModifier.fillMaxHeight().width(140.dp), sinceOnPhoto = false)
            Spacer(GlanceModifier.width(10.dp))
            Column(modifier = GlanceModifier.fillMaxHeight().defaultWeight().padding(top = 4.dp, bottom = 4.dp, end = 4.dp)) {
                Chip(LocalContext.current.getString(R.string.widget_always_chip), palette)
                Spacer(GlanceModifier.height(6.dp))
                Box(modifier = GlanceModifier.fillMaxWidth().defaultWeight()) {
                    Message(s, palette, maxLines = 3, sizeSp = 14)
                }
                Text(
                    text = s.since,
                    maxLines = 1,
                    style = TextStyle(color = palette.textMuted, fontSize = 11.sp, fontWeight = FontWeight.Bold),
                )
            }
        }
    }

    @Composable
    private fun LargeLayout(s: State, palette: WidgetPalette) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Box(modifier = GlanceModifier.fillMaxWidth().defaultWeight()) {
                Photo(s, palette, GlanceModifier.fillMaxSize(), sinceOnPhoto = true)
                Box(modifier = GlanceModifier.padding(8.dp)) {
                    Chip(LocalContext.current.getString(R.string.widget_always_chip), palette)
                }
            }
            Spacer(GlanceModifier.height(8.dp))
            Message(s, palette, maxLines = 3, sizeSp = 15, modifier = GlanceModifier.padding(horizontal = 4.dp))
        }
    }

    companion object {
        /** Mirrors AlwaysWithMe.sinceLabel in lib/core/services/always_with_me.dart. */
        fun sinceLabel(context: Context, lastMetAt: Long?, now: Long = System.currentTimeMillis()): String {
            if (lastMetAt == null || lastMetAt <= 0L) return context.getString(R.string.widget_always_unset)
            val minutes = (now - lastMetAt) / 60_000L
            return when {
                minutes < 60 -> context.getString(R.string.widget_always_now)
                minutes < 60 * 24 -> context.getString(R.string.widget_always_hours, (minutes / 60).toInt())
                else -> {
                    val days = (minutes / (60 * 24)).toInt()
                    context.resources.getQuantityString(R.plurals.widget_always_days, days, days)
                }
            }
        }
    }
}

class AlwaysWithMeWidgetReceiver : HomeWidgetGlanceWidgetReceiver<AlwaysWithMeWidget>() {
    override val glanceAppWidget = AlwaysWithMeWidget()

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        WidgetRefreshWorker.schedule(context)
    }
}
