package com.souqi.souqi

import android.content.Context
import android.os.SystemClock
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import org.json.JSONObject
import java.util.Calendar
import java.util.concurrent.TimeUnit
import kotlin.math.abs

/**
 * Plans the daily debt report with WorkManager: ONE one-time request for
 * the next occurrence of the chosen time, which plans the next one when it
 * has run (see [DebtReportWorker]). Not a 24-hour periodic request: those
 * drift by however late each run was, and a time-zone change would move
 * the report for good.
 *
 * WorkManager keeps the plan across reboots (its own boot receiver) and app
 * updates. No exact-alarm permission: the run may come late under battery
 * saving, which the app makes up for with its catch-up rule on the next
 * start.
 */
object ReportScheduler {
    private const val WORK = "souqi-debt-report"
    private const val PREFS = "souqi_report"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_MINUTE = "minute"
    private const val KEY_NEXT = "next_run_at"

    fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** The next [minuteOfDay] on the local wall clock, strictly after [now]. */
    fun nextRunAt(now: Long, minuteOfDay: Int): Long {
        val calendar = Calendar.getInstance()
        calendar.timeInMillis = now
        calendar.set(Calendar.HOUR_OF_DAY, minuteOfDay / 60)
        calendar.set(Calendar.MINUTE, minuteOfDay % 60)
        calendar.set(Calendar.SECOND, 0)
        calendar.set(Calendar.MILLISECOND, 0)
        if (calendar.timeInMillis <= now) calendar.add(Calendar.DAY_OF_YEAR, 1)
        return calendar.timeInMillis
    }

    /**
     * Plans the run at [minuteOfDay]. Without [replace] an existing plan for
     * the same time is kept — what the app does on every start; it is
     * re-planned only when it is missing or no longer matches the clock
     * (a time-zone change). Blocking: call off the main thread.
     */
    fun schedule(context: Context, minuteOfDay: Int, replace: Boolean) {
        val prefs = prefs(context)
        val now = System.currentTimeMillis()
        val next = nextRunAt(now, minuteOfDay)
        if (!replace &&
            prefs.getBoolean(KEY_ENABLED, false) &&
            prefs.getInt(KEY_MINUTE, -1) == minuteOfDay &&
            abs(prefs.getLong(KEY_NEXT, 0) - next) < 60_000 &&
            hasPlan(context)
        ) {
            return
        }
        prefs.edit()
            .putBoolean(KEY_ENABLED, true)
            .putInt(KEY_MINUTE, minuteOfDay)
            .putLong(KEY_NEXT, next)
            .apply()
        enqueue(context, next - now, ExistingWorkPolicy.REPLACE)
    }

    /**
     * Called by the worker while it is still running: the next run is
     * APPENDED to it, so it is not cancelled by its own successor, and its
     * delay starts when this one ends.
     */
    fun scheduleNextFromWorker(context: Context) {
        val prefs = prefs(context)
        if (!prefs.getBoolean(KEY_ENABLED, false)) return
        val minute = prefs.getInt(KEY_MINUTE, 22 * 60)
        val now = System.currentTimeMillis()
        val next = nextRunAt(now, minute)
        prefs.edit().putLong(KEY_NEXT, next).apply()
        enqueue(context, next - now, ExistingWorkPolicy.APPEND_OR_REPLACE)
    }

    fun cancel(context: Context) {
        prefs(context).edit().putBoolean(KEY_ENABLED, false).remove(KEY_NEXT).apply()
        WorkManager.getInstance(context).cancelUniqueWork(WORK)
    }

    private fun hasPlan(context: Context): Boolean = try {
        WorkManager.getInstance(context)
            .getWorkInfosForUniqueWork(WORK)
            .get(5, TimeUnit.SECONDS)
            .any { !it.state.isFinished }
    } catch (_: Exception) {
        false
    }

    private fun enqueue(context: Context, delayMs: Long, policy: ExistingWorkPolicy) {
        val request = OneTimeWorkRequestBuilder<DebtReportWorker>()
            .setInitialDelay(delayMs.coerceAtLeast(0), TimeUnit.MILLISECONDS)
            .addTag(WORK)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(WORK, policy, request)
    }
}

/**
 * One report run at a time across the app's engine and the worker's (both
 * live in this process). A lock older than the longest a run may take is
 * stale — its holder died — and is taken over.
 */
object ReportRunLock {
    private const val STALE_MS = 10 * 60 * 1000L
    private var heldSince = 0L

    @Synchronized
    fun tryAcquire(): Boolean {
        val now = SystemClock.elapsedRealtime()
        if (heldSince != 0L && now - heldSince < STALE_MS) return false
        heldSince = now
        return true
    }

    @Synchronized
    fun release() {
        heldSince = 0L
    }
}

/**
 * The status of the last run, as JSON written by the Dart job — kept here
 * rather than in the database, which the background engine only reads.
 */
object ReportStatusStore {
    private const val KEY_STATUS = "status"

    fun load(context: Context): String? =
        ReportScheduler.prefs(context).getString(KEY_STATUS, null)

    fun save(context: Context, json: String) {
        ReportScheduler.prefs(context).edit().putString(KEY_STATUS, json).apply()
    }

    /** The worker's engine never reported back: record a failed attempt. */
    fun recordWorkerFailure(context: Context) {
        val status = try {
            JSONObject(load(context) ?: "{}")
        } catch (_: Exception) {
            JSONObject()
        }
        status.put("attemptAt", System.currentTimeMillis())
        status.put("outcome", "FAILED")
        status.put("problem", "UNKNOWN")
        save(context, status.toString())
    }
}
