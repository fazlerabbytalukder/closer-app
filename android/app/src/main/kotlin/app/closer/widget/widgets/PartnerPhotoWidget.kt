package app.closer.widget.widgets

import android.content.Context
import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
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
import androidx.glance.unit.ColorProvider
import app.closer.widget.MainActivity
import app.closer.widget.R
import app.closer.widget.widgets.ui.Chip
import app.closer.widget.widgets.ui.HeartBadge
import app.closer.widget.widgets.ui.OnPhoto
import app.closer.widget.widgets.ui.OnPhotoMuted
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
 * Partner's latest photo / note / doodle in a gradient frame, with "💌 Sam · 2m" on a
 * dark fade. S 2×2, M 4×2, L 4×4. Tap → closer://reply.
 */
class PartnerPhotoWidget : GlanceAppWidget() {

    override val stateDefinition: GlanceStateDefinition<*> = HomeWidgetGlanceStateDefinition()

    override val sizeMode: SizeMode = SizeMode.Responsive(
        setOf(WidgetSizes.SMALL, WidgetSizes.MEDIUM, WidgetSizes.LARGE),
    )

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        // Make sure the heart badge disappears on time even if nothing else refreshes us.
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val heartUntil = prefs.long(WidgetKeys.HEART_UNTIL) ?: 0L
        val now = System.currentTimeMillis()
        if (heartUntil > now) WidgetRefreshWorker.scheduleHeartExpiry(context, heartUntil - now)

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
        val size = LocalSize.current
        val palette = WidgetTheme.palette(prefs.str(WidgetKeys.THEME_ID))
        val onClick = actionStartActivity<MainActivity>(context, Uri.parse(WidgetLinks.REPLY))

        val partner = prefs.str(WidgetKeys.PARTNER_NAME)

        if (!prefs.bool(WidgetKeys.PAIRED)) {
            WidgetContainer(palette, onClick) {
                WidgetMessage(palette, context.getString(R.string.widget_not_paired), emoji = "💞")
            }
            return
        }

        val path = prefs.str(WidgetKeys.LATEST_PATH)
        val caption = prefs.str(WidgetKeys.LATEST_CAPTION)
        val type = prefs.str(WidgetKeys.LATEST_TYPE)
        val sentAt = prefs.long(WidgetKeys.LATEST_SENT_AT)

        val wide = WidgetSizes.isWide(size)
        val tall = WidgetSizes.isTall(size)
        val maxSide = when {
            wide && tall -> 600
            wide -> 400
            else -> 300
        }
        val bitmap = WidgetUtils.decodeSampled(path, maxSide)

        if (bitmap == null && caption.isEmpty()) {
            val name = partner.ifEmpty { context.getString(R.string.widget_partner_fallback) }
            WidgetContainer(palette, onClick) {
                WidgetMessage(palette, context.getString(R.string.widget_waiting_first, name), emoji = "💌")
            }
            return
        }

        val item = Item(
            image = bitmap?.let { ImageProvider(it) },
            caption = caption,
            isNote = type == "note",
            partner = partner,
            time = WidgetUtils.relativeTime(sentAt),
            heart = (prefs.long(WidgetKeys.HEART_UNTIL) ?: 0L) > System.currentTimeMillis(),
            heartEmoji = prefs.str(WidgetKeys.TAP_EMOJI).ifEmpty { "❤️" },
            mood = prefs.str(WidgetKeys.PARTNER_MOOD),
            imageDescription = context.getString(
                R.string.widget_photo_cd,
                partner.ifEmpty { context.getString(R.string.widget_partner_fallback) },
            ),
        )

        WidgetContainer(palette, onClick, padding = 6.dp) {
            when {
                wide && tall -> LargeLayout(item, palette)
                wide -> MediumLayout(item, palette)
                else -> SmallLayout(item, palette, size)
            }
        }
    }

    private data class Item(
        val image: ImageProvider?,
        val caption: String,
        val isNote: Boolean,
        val partner: String,
        val time: String,
        val heart: Boolean,
        val heartEmoji: String,
        val mood: String,
        val imageDescription: String,
    )

    /**
     * The photo in a thin gradient frame, with a dark fade at the bottom for
     * "💌 Sam · 2m" (and the caption when [showCaption]). A text-only note
     * becomes a big quote instead.
     */
    @Composable
    private fun Media(item: Item, palette: WidgetPalette, modifier: GlanceModifier, showCaption: Boolean, noteMaxLines: Int) {
        Box(modifier = modifier.roundedIfSupported(16.dp).background(palette.surface)) {
            if (item.image != null) {
                Image(
                    provider = item.image,
                    contentDescription = item.imageDescription,
                    contentScale = ContentScale.Crop,
                    modifier = GlanceModifier.fillMaxSize(),
                )
                Column(modifier = GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.Bottom) {
                    Column(modifier = ScrimModifier.fillMaxWidth().padding(start = 10.dp, end = 10.dp, top = 18.dp, bottom = 8.dp)) {
                        if (showCaption && item.caption.isNotEmpty()) {
                            Text(
                                text = item.caption,
                                maxLines = 2,
                                style = TextStyle(color = OnPhoto, fontSize = 13.sp, fontWeight = FontWeight.Bold),
                            )
                        }
                        FromRow(item, OnPhoto, OnPhotoMuted)
                    }
                }
            } else {
                NoteCard(item, palette, noteMaxLines)
            }
            if (item.heart) {
                Box(modifier = GlanceModifier.fillMaxSize().padding(7.dp), contentAlignment = Alignment.TopEnd) {
                    HeartBadge(item.heartEmoji, palette)
                }
            }
        }
    }

    /** Text-only note: a big quote signed by the partner. */
    @Composable
    private fun NoteCard(item: Item, palette: WidgetPalette, maxLines: Int) {
        Column(
            modifier = GlanceModifier.fillMaxSize().padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("❝", style = TextStyle(color = palette.textMuted, fontSize = 22.sp, fontWeight = FontWeight.Bold))
            Text(
                text = item.caption,
                maxLines = maxLines,
                style = TextStyle(color = palette.text, fontSize = 16.sp, fontWeight = FontWeight.Bold),
            )
            Spacer(GlanceModifier.height(6.dp))
            FromRow(item, palette.text, palette.textMuted)
        }
    }

    /** "💌 Sam" · "2m ago". */
    @Composable
    private fun FromRow(item: Item, fg: ColorProvider, muted: ColorProvider) {
        Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = "💌 ${item.partner}",
                maxLines = 1,
                modifier = GlanceModifier.defaultWeight(),
                style = TextStyle(color = fg, fontSize = 12.sp, fontWeight = FontWeight.Bold),
            )
            if (item.time.isNotEmpty()) {
                Text(text = item.time, maxLines = 1, style = TextStyle(color = muted, fontSize = 11.sp))
            }
        }
    }

    @Composable
    private fun SmallLayout(item: Item, palette: WidgetPalette, size: DpSize) {
        Media(item, palette, GlanceModifier.fillMaxSize(), showCaption = size.height >= 170.dp, noteMaxLines = 4)
    }

    /** Photo on the left; "From Sam" chip, caption and mood on the gradient. */
    @Composable
    private fun MediumLayout(item: Item, palette: WidgetPalette) {
        Row(modifier = GlanceModifier.fillMaxSize()) {
            Media(item, palette, GlanceModifier.fillMaxHeight().width(140.dp), showCaption = false, noteMaxLines = 4)
            Spacer(GlanceModifier.width(10.dp))
            Column(modifier = GlanceModifier.fillMaxHeight().defaultWeight().padding(top = 4.dp, bottom = 4.dp, end = 4.dp)) {
                Chip("💕 From ${item.partner}", palette)
                Spacer(GlanceModifier.height(6.dp))
                Box(modifier = GlanceModifier.fillMaxWidth().defaultWeight()) {
                    if (item.image != null && item.caption.isNotEmpty()) {
                        Text(
                            text = item.caption,
                            maxLines = 3,
                            style = TextStyle(color = palette.text, fontSize = 15.sp, fontWeight = FontWeight.Bold),
                        )
                    } else if (item.image != null) {
                        Text(
                            text = "Thinking of you 💭",
                            maxLines = 2,
                            style = TextStyle(color = palette.text, fontSize = 15.sp, fontWeight = FontWeight.Bold),
                        )
                    }
                }
                Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = item.mood,
                        maxLines = 1,
                        modifier = GlanceModifier.defaultWeight(),
                        style = TextStyle(color = palette.textMuted, fontSize = 11.sp, fontWeight = FontWeight.Medium),
                    )
                    if (item.time.isNotEmpty()) {
                        Text(item.time, maxLines = 1, style = TextStyle(color = palette.textMuted, fontSize = 11.sp))
                    }
                }
            }
        }
    }

    /** Big photo with the caption on the fade, mood chip underneath. */
    @Composable
    private fun LargeLayout(item: Item, palette: WidgetPalette) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Media(item, palette, GlanceModifier.fillMaxWidth().defaultWeight(), showCaption = true, noteMaxLines = 8)
            if (item.mood.isNotEmpty()) {
                Spacer(GlanceModifier.height(6.dp))
                Chip(item.mood, palette)
            }
        }
    }

    companion object {
        /** SharedPreferences file written by home_widget. */
        const val PREFS = "HomeWidgetPreferences"
    }
}

class PartnerPhotoWidgetReceiver : HomeWidgetGlanceWidgetReceiver<PartnerPhotoWidget>() {
    override val glanceAppWidget = PartnerPhotoWidget()

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        WidgetRefreshWorker.schedule(context)
    }
}
