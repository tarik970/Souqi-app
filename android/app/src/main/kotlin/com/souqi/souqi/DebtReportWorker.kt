package com.souqi.souqi

import android.content.Context
import android.os.Handler
import android.os.Looper
import androidx.work.Worker
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The daily debt report, run by WorkManager. Starts a Flutter engine with
 * no screen on the Dart entry point `debtReportWorkerMain` (lib/main.dart),
 * which does all the work — the same `DailyReportJob` the app runs — and
 * answers "workerFinished" on the souqi/report channel. Then the next run
 * is planned.
 *
 * Always ends as a SUCCESS for WorkManager: a failed report is recorded in
 * the status (and notified) by the job itself, and a failed work request
 * would also fail the next run appended to it.
 *
 * Our own worker and channel rather than a plugin, like the printer: the
 * one dependency is androidx.work from Google Maven, which builds through
 * the Aliyun mirrors like everything else.
 */
class DebtReportWorker(context: Context, params: WorkerParameters) :
    Worker(context, params) {

    override fun doWork(): Result {
        val context = applicationContext
        val main = Handler(Looper.getMainLooper())
        val done = CountDownLatch(1)
        val reported = AtomicBoolean(false)
        var engine: FlutterEngine? = null
        var channel: ReportChannel? = null

        main.post {
            try {
                val loader = FlutterInjector.instance().flutterLoader()
                if (!loader.initialized()) loader.startInitialization(context)
                loader.ensureInitializationComplete(context, null)
                val created = FlutterEngine(context)
                channel = ReportChannel(context, created.dartExecutor.binaryMessenger) {
                    reported.set(true)
                    done.countDown()
                }
                created.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(
                        loader.findAppBundlePath(),
                        ENTRY_POINT,
                    ),
                )
                engine = created
            } catch (_: Throwable) {
                done.countDown()
            }
        }

        try {
            // WorkManager stops a worker after 10 minutes.
            done.await(9, TimeUnit.MINUTES)
        } catch (_: InterruptedException) {
        }

        val teardown = CountDownLatch(1)
        main.post {
            try {
                channel?.dispose()
                engine?.destroy()
            } finally {
                teardown.countDown()
            }
        }
        try {
            teardown.await(10, TimeUnit.SECONDS)
        } catch (_: InterruptedException) {
        }

        if (!reported.get()) ReportStatusStore.recordWorkerFailure(context)
        ReportScheduler.scheduleNextFromWorker(context)
        // The app may be open on the settings page: refresh its status line.
        ReportChannel.pushToApp("jobFinished")
        return Result.success()
    }

    companion object {
        private const val ENTRY_POINT = "debtReportWorkerMain"
    }
}
