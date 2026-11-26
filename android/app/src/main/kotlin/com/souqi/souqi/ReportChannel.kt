package com.souqi.souqi

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * The "souqi/report" method channel — the Android half of
 * lib/core/platform/report_platform.dart. Registered on BOTH engines: the
 * app's (MainActivity) and the one the background worker starts
 * ([DebtReportWorker]), so the same Dart job runs in either. Nothing here
 * opens a screen, and nothing uses the network.
 */
class ReportChannel(
    private val context: Context,
    messenger: BinaryMessenger,
    /** Set by the worker: the job has ended and the engine may go. */
    private val onWorkerFinished: (() -> Unit)? = null,
) : MethodChannel.MethodCallHandler {
    val channel = MethodChannel(messenger, NAME)
    private val io: ExecutorService = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        io.shutdown()
    }

    /** Runs [work] off the main thread and answers with its value. */
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        io.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: ReportUnavailableException) {
                main.post { result.error("UNAVAILABLE", e.message, null) }
            } catch (e: ReportWriteException) {
                main.post { result.error("WRITE_FAILED", e.message, null) }
            } catch (e: Exception) {
                main.post { result.error("FAILED", e.message, null) }
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.argument<String>("uri")
        when (call.method) {
            "tryBeginRun" -> result.success(ReportRunLock.tryAcquire())
            "endRun" -> {
                ReportRunLock.release()
                result.success(null)
            }
            "folderAvailable" -> background(result) {
                uri != null && ReportFiles.treeAvailable(context, uri)
            }
            "writeFile" -> {
                val name = call.argument<String>("name")
                val path = call.argument<String>("path")
                val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
                if (name.isNullOrEmpty() || path.isNullOrEmpty()) {
                    result.error("WRITE_FAILED", "missing name or path", null)
                    return
                }
                background(result) { ReportFiles.write(context, uri, name, File(path), mime) }
            }
            "listFiles" -> background(result) { ReportFiles.list(context, uri) }
            "deleteFile" -> {
                val name = call.argument<String>("name") ?: ""
                background(result) {
                    ReportFiles.delete(context, uri, name)
                    null
                }
            }
            "releaseFolder" -> {
                if (uri != null) ReportFiles.release(context, uri)
                result.success(null)
            }
            "schedule" -> {
                val minute = call.argument<Int>("minute") ?: (22 * 60)
                val replace = call.argument<Boolean>("replace") ?: false
                background(result) {
                    ReportScheduler.schedule(context, minute, replace)
                    null
                }
            }
            "cancelSchedule" -> background(result) {
                ReportScheduler.cancel(context)
                null
            }
            "notify" -> {
                ReportNotifications.show(context, call)
                result.success(null)
            }
            "notificationsAllowed" ->
                result.success(NotificationManagerCompat.from(context).areNotificationsEnabled())
            "batteryOptimizationIgnored" -> {
                val power = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                result.success(power?.isIgnoringBatteryOptimizations(context.packageName) ?: true)
            }
            "loadStatus" -> result.success(ReportStatusStore.load(context))
            "saveStatus" -> {
                call.argument<String>("json")?.let { ReportStatusStore.save(context, it) }
                result.success(null)
            }
            "takeLaunchAction" -> result.success(ReportLaunch.take())
            "workerFinished" -> {
                result.success(null)
                onWorkerFinished?.invoke()
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val NAME = "souqi/report"

        /** The app's own channel while its engine is up, for [pushToApp]. */
        @Volatile
        var appChannel: ReportChannel? = null

        /** Tells the app's Dart side (when it is running) that [method] happened. */
        fun pushToApp(method: String) {
            Handler(Looper.getMainLooper()).post {
                appChannel?.channel?.invokeMethod(method, null)
            }
        }
    }
}

/**
 * What the report notification was tapped for, held until the app's Dart
 * side takes it (`takeLaunchAction`): "debtors", "share" or "folder".
 */
object ReportLaunch {
    const val EXTRA = "souqi_report_action"

    @Volatile
    private var pending: String? = null

    /** Keeps the action [intent] carries; true when it carried one. */
    fun offer(intent: Intent?): Boolean {
        if (intent == null) return false
        // Reopened from the recent apps: the old tap is not asked again.
        if (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) {
            intent.removeExtra(EXTRA)
            return false
        }
        val action = intent.getStringExtra(EXTRA) ?: return false
        intent.removeExtra(EXTRA)
        pending = action
        return true
    }

    fun take(): String? {
        val action = pending
        pending = null
        return action
    }
}

/**
 * The one report notification: "Debt report ready — 42 debtors, …" with
 * Share and Open folder, or the fallback / failure explanation. Every text
 * comes from Dart, in the app language. The lock screen shows only the
 * title (the text names what customers owe).
 *
 * Every tap opens the APP, which then does the rest: the share sheet and
 * the file manager are opened from inside it, announced to the PIN locks.
 */
object ReportNotifications {
    private const val CHANNEL_ID = "debt_reports"
    private const val NOTIFICATION_ID = 4810

    private fun tap(context: Context, action: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setAction("com.souqi.souqi.REPORT_$action")
            .putExtra(ReportLaunch.EXTRA, action)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    @SuppressLint("MissingPermission")
    fun show(context: Context, call: MethodCall) {
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return
        val channelName = call.argument<String>("channelName") ?: "Reports"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val system = context.getSystemService(NotificationManager::class.java)
            system?.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, channelName, NotificationManager.IMPORTANCE_DEFAULT),
            )
        }
        val title = call.argument<String>("title") ?: ""
        val text = call.argument<String>("text") ?: ""
        val publicTitle = call.argument<String>("publicTitle") ?: title
        val public = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(publicTitle)
            .build()
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_monochrome)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(tap(context, "debtors", 1))
            .setAutoCancel(true)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(public)
        call.argument<String>("shareLabel")?.let {
            builder.addAction(0, it, tap(context, "share", 2))
        }
        call.argument<String>("openFolderLabel")?.let {
            builder.addAction(0, it, tap(context, "folder", 3))
        }
        try {
            manager.notify(NOTIFICATION_ID, builder.build())
        } catch (_: SecurityException) {
            // The notification permission was taken back in the meantime.
        }
    }
}
