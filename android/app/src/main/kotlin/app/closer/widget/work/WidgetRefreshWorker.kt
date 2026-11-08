package app.closer.widget.work

import android.content.Context
import android.util.Log
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.state.updateAppWidgetState
import androidx.glance.appwidget.updateAll
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import app.closer.widget.widgets.CountdownWidget
import app.closer.widget.widgets.PartnerPhotoWidget
import app.closer.widget.widgets.PlantWidget
import es.antonborri.home_widget.HomeWidgetGlanceState
import es.antonborri.home_widget.HomeWidgetGlanceStateDefinition
import java.time.Duration
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import java.util.concurrent.TimeUnit

/**
 * Re-renders all Closer widgets from the saved home_widget state, even if Flutter never
 * starts. Scheduled as a 15-minute periodic job plus a self-re-enqueuing job at local midnight
 * (so countdowns roll over on time).
 */
class WidgetRefreshWorker(
    context: Context,
    params: WorkerParameters,
) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        try {
            refreshAll(applicationContext)
        } catch (t: Throwable) {
            Log.w(TAG, "Widget refresh failed", t)
        }
        if (inputData.getBoolean(KEY_MIDNIGHT, false)) scheduleMidnight(applicationContext)
        return Result.success()
    }

    companion object {
        private const val TAG = "CloserWidget"
        private const val KEY_MIDNIGHT = "midnight"
        const val PERIODIC_WORK = "closer_widget_refresh_periodic"
        const val MIDNIGHT_WORK = "closer_widget_refresh_midnight"
        const val HEART_WORK = "closer_widget_refresh_heart"

        /** Idempotent: keeps existing work. Call from receivers' onEnabled and MainActivity.onCreate. */
        fun schedule(context: Context) {
            val wm = WorkManager.getInstance(context.applicationContext)
            wm.enqueueUniquePeriodicWork(
                PERIODIC_WORK,
                ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequestBuilder<WidgetRefreshWorker>(15, TimeUnit.MINUTES).build(),
            )
            scheduleMidnight(context, ExistingWorkPolicy.KEEP)
        }

        /** One-time refresh just after the next local midnight; re-enqueues itself when it runs. */
        fun scheduleMidnight(context: Context, policy: ExistingWorkPolicy = ExistingWorkPolicy.REPLACE) {
            val now = ZonedDateTime.now(ZoneId.systemDefault())
            val next = LocalDate.now(now.zone).plusDays(1).atStartOfDay(now.zone).plusSeconds(30)
            val delay = Duration.between(now, next).toMillis().coerceAtLeast(60_000L)
            WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
                MIDNIGHT_WORK,
                policy,
                OneTimeWorkRequestBuilder<WidgetRefreshWorker>()
                    .setInitialDelay(delay, TimeUnit.MILLISECONDS)
                    .setInputData(workDataOf(KEY_MIDNIGHT to true))
                    .build(),
            )
        }

        /** Refresh once the heart badge expires (heart_until). */
        fun scheduleHeartExpiry(context: Context, delayMillis: Long) {
            WorkManager.getInstance(context.applicationContext).enqueueUniqueWork(
                HEART_WORK,
                ExistingWorkPolicy.REPLACE,
                OneTimeWorkRequestBuilder<WidgetRefreshWorker>()
                    .setInitialDelay(delayMillis + 1_000L, TimeUnit.MILLISECONDS)
                    .build(),
            )
        }

        /** Re-reads home_widget state and redraws every placed instance of each widget. */
        suspend fun refreshAll(context: Context) {
            refresh(context, PartnerPhotoWidget())
            refresh(context, CountdownWidget())
            refresh(context, PlantWidget())
        }

        private suspend fun refresh(context: Context, widget: GlanceAppWidget) {
            val ids = GlanceAppWidgetManager(context).getGlanceIds(widget.javaClass)
            for (id in ids) {
                // Same as HomeWidgetGlanceWidgetReceiver.onUpdate: touch the state so Glance
                // re-reads SharedPreferences, then redraw them all.
                updateAppWidgetState(context, HomeWidgetGlanceStateDefinition(), id) { state: HomeWidgetGlanceState ->
                    state
                }
            }
            widget.updateAll(context)
        }
    }
}
