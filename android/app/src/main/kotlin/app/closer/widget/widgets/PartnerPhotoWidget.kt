package app.closer.widget.widgets

import android.content.Context
import android.net.Uri
import android.os.Build
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
import androidx.glance.appwidget.cornerRadius
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
import app.closer.widget.widgets.ui.Pill
import app.closer.widget.widgets.ui.WidgetContainer
import app.closer.widget.widgets.ui.WidgetMessage
import app.closer.widget.widgets.ui.WidgetPalette
import app.closer.widget.widgets.ui.WidgetSizes
import app.closer.widget.widgets.ui.WidgetTheme
import app.closer.widget.widgets.ui.WidgetUtils
import app.closer.widget.work.WidgetRefreshWorker
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver
import es.antonborri.home_widget.actionStartActivity

/** Partner's latest photo / note / doodle. S 2×2, M 4×2, L 4×4. Tap → closer://reply. */
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
                WidgetMessage(palette, context.getString(R.string.widget_waiting_first, name))
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
            mood = prefs.str(WidgetKeys.PARTNER_MOOD),
            imageDescription = context.getString(
                R.string.widget_photo_cd,
                partner.ifEmpty { context.getString(R.string.widget_partner_fallback) },
            ),
        )

        WidgetContainer(palette, onClick, padding = 8.dp) {
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
        val mood: String,
        val imageDescription: String,
    )

    /** Photo (or note card) with the heart badge overlaid in the top-left corner. */
    @Composable
    private fun Media(item: Item, palette: WidgetPalette, modifier: GlanceModifier, noteMaxLines: Int) {
        var m = modifier
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) m = m.cornerRadius(R.dimen.widget_inner_radius)
        Box(modifier = m.background(palette.surface)) {
            if (item.image != null) {
                Image(
                    provider = item.image,
                    contentDescription = item.imageDescription,
                    contentScale = ContentScale.Crop,
                    modifier = GlanceModifier.fillMaxSize(),
                )
            } else {
                // Text-only note: show the caption as the card itself.
                Box(
                    modifier = GlanceModifier.fillMaxSize().padding(10.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = item.caption,
                        maxLines = noteMaxLines,
                        style = TextStyle(color = palette.text, fontSize = 16.sp, fontWeight = FontWeight.Medium),
                    )
                }
            }
            if (item.heart) {
                Box(modifier = GlanceModifier.padding(6.dp)) {
                    Pill("❤️", bg = palette.bg, fg = palette.accent)
                }
            }
        }
    }

    @Composable
    private fun NameRow(item: Item, palette: WidgetPalette) {
        Row(modifier = GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = item.partner,
                maxLines = 1,
                modifier = GlanceModifier.defaultWeight(),
                style = TextStyle(color = palette.text, fontSize = 13.sp, fontWeight = FontWeight.Bold),
            )
            if (item.time.isNotEmpty()) {
                Text(
                    text = item.time,
                    maxLines = 1,
                    style = TextStyle(color = palette.textMuted, fontSize = 12.sp),
                )
            }
        }
    }

    @Composable
    private fun CaptionText(item: Item, palette: WidgetPalette, maxLines: Int) {
        if (item.caption.isEmpty() || item.image == null) return
        Text(
            text = item.caption,
            maxLines = maxLines,
            style = TextStyle(color = palette.text, fontSize = 13.sp),
        )
    }

    @Composable
    private fun MoodText(item: Item, palette: WidgetPalette) {
        if (item.mood.isEmpty()) return
        Text(
            text = item.mood,
            maxLines = 1,
            style = TextStyle(color = palette.textMuted, fontSize = 12.sp),
        )
    }

    @Composable
    private fun SmallLayout(item: Item, palette: WidgetPalette, size: DpSize) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Media(item, palette, GlanceModifier.fillMaxWidth().defaultWeight(), noteMaxLines = 4)
            Spacer(GlanceModifier.height(4.dp))
            NameRow(item, palette)
            if (size.height >= 170.dp) CaptionText(item, palette, maxLines = 1)
        }
    }

    @Composable
    private fun MediumLayout(item: Item, palette: WidgetPalette) {
        Row(modifier = GlanceModifier.fillMaxSize()) {
            Media(item, palette, GlanceModifier.fillMaxHeight().width(130.dp), noteMaxLines = 4)
            Spacer(GlanceModifier.width(10.dp))
            Column(modifier = GlanceModifier.fillMaxHeight().defaultWeight()) {
                NameRow(item, palette)
                Spacer(GlanceModifier.height(4.dp))
                Box(modifier = GlanceModifier.fillMaxWidth().defaultWeight()) {
                    CaptionText(item, palette, maxLines = 3)
                }
                MoodText(item, palette)
            }
        }
    }

    @Composable
    private fun LargeLayout(item: Item, palette: WidgetPalette) {
        Column(modifier = GlanceModifier.fillMaxSize()) {
            Media(item, palette, GlanceModifier.fillMaxWidth().defaultWeight(), noteMaxLines = 8)
            Spacer(GlanceModifier.height(6.dp))
            CaptionText(item, palette, maxLines = 2)
            NameRow(item, palette)
            MoodText(item, palette)
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
