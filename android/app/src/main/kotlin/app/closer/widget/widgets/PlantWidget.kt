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
import androidx.glance.currentState
import androidx.glance.layout.Alignment
import androidx.glance.layout.Column
import androidx.glance.layout.ContentScale
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
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

/** Shared plant at its current stage + streak. S 2×2, M 4×2. Tap → closer://plant. */
class PlantWidget : GlanceAppWidget() {

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
        val onClick = actionStartActivity<MainActivity>(context, Uri.parse(WidgetLinks.PLANT))

        if (!prefs.bool(WidgetKeys.PAIRED)) {
            WidgetContainer(palette, onClick) {
                WidgetMessage(palette, context.getString(R.string.widget_not_paired), emoji = "🌱")
            }
            return
        }

        val stage = (prefs.int(WidgetKeys.PLANT_STAGE) ?: 0).coerceIn(0, 8)
        val wilted = prefs.str(WidgetKeys.PLANT_HEALTH).equals("wilted", ignoreCase = true)
        val streak = prefs.int(WidgetKeys.STREAK_COUNT) ?: 0
        val drawable = plantDrawable(stage, wilted)
        val streakText = if (streak > 0) {
            context.getString(R.string.widget_streak, streak.toString())
        } else {
            context.getString(R.string.widget_streak_start)
        }
        val subtitle = if (wilted) context.getString(R.string.widget_plant_wilted) else null
        val plantCd = context.getString(R.string.widget_plant_cd)

        WidgetContainer(palette, onClick, padding = 10.dp) {
            if (WidgetSizes.isWide(LocalSize.current)) {
                Row(modifier = GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                    Image(
                        provider = ImageProvider(drawable),
                        contentDescription = plantCd,
                        contentScale = ContentScale.Fit,
                        modifier = GlanceModifier.fillMaxHeight().width(110.dp),
                    )
                    Spacer(GlanceModifier.width(10.dp))
                    Column(modifier = GlanceModifier.defaultWeight()) {
                        StreakText(streakText, palette, 18, TextAlign.Start)
                        if (subtitle != null) SubText(subtitle, palette, TextAlign.Start)
                    }
                }
            } else {
                Column(
                    modifier = GlanceModifier.fillMaxSize(),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Image(
                        provider = ImageProvider(drawable),
                        contentDescription = plantCd,
                        contentScale = ContentScale.Fit,
                        modifier = GlanceModifier.fillMaxWidth().defaultWeight(),
                    )
                    Spacer(GlanceModifier.height(2.dp))
                    StreakText(streakText, palette, 13, TextAlign.Center)
                    if (subtitle != null) SubText(subtitle, palette, TextAlign.Center)
                }
            }
        }
    }

    @Composable
    private fun StreakText(text: String, palette: WidgetPalette, sizeSp: Int, align: TextAlign) {
        Text(
            text = text,
            maxLines = 1,
            style = TextStyle(
                color = palette.text,
                fontSize = sizeSp.sp,
                fontWeight = FontWeight.Bold,
                textAlign = align,
            ),
        )
    }

    @Composable
    private fun SubText(text: String, palette: WidgetPalette, align: TextAlign) {
        Text(
            text = text,
            maxLines = 1,
            style = TextStyle(color = palette.textMuted, fontSize = 12.sp, textAlign = align),
        )
    }

    companion object {
        private val HEALTHY = intArrayOf(
            R.drawable.plant_stage_0, R.drawable.plant_stage_1, R.drawable.plant_stage_2,
            R.drawable.plant_stage_3, R.drawable.plant_stage_4, R.drawable.plant_stage_5,
            R.drawable.plant_stage_6, R.drawable.plant_stage_7, R.drawable.plant_stage_8,
        )
        private val WILTED = intArrayOf(
            R.drawable.plant_wilted_0, R.drawable.plant_wilted_1, R.drawable.plant_wilted_2,
            R.drawable.plant_wilted_3, R.drawable.plant_wilted_4, R.drawable.plant_wilted_5,
            R.drawable.plant_wilted_6, R.drawable.plant_wilted_7, R.drawable.plant_wilted_8,
        )

        fun plantDrawable(stage: Int, wilted: Boolean): Int =
            (if (wilted) WILTED else HEALTHY)[stage.coerceIn(0, 8)]
    }
}

class PlantWidgetReceiver : HomeWidgetGlanceWidgetReceiver<PlantWidget>() {
    override val glanceAppWidget = PlantWidget()

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        WidgetRefreshWorker.schedule(context)
    }
}
