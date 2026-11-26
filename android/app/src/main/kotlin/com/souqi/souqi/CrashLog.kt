package com.souqi.souqi

import android.content.Context
import android.os.Build
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * The Android half of the local error log (lib/core/logging/error_log.dart).
 *
 * A crash in Kotlin/Java code — the printer thread, a channel handler, the
 * report worker — never reaches the Dart side: the process just dies. This
 * writes its stack trace to `<files>/logs/errors-native.log` first, the
 * folder the Dart log lives in, so "Share error log" sends it along. Then
 * the crash goes on to the system's own handler exactly as before.
 *
 * No network, no service: one small file, started over when it passes
 * [MAX_BYTES].
 */
object CrashLog {
    private const val FILE_NAME = "errors-native.log"
    private const val MAX_BYTES = 128 * 1024L

    @Volatile
    private var installed = false

    fun install(context: Context) {
        if (installed) return
        synchronized(this) {
            if (installed) return
            installed = true
        }
        val app = context.applicationContext
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                write(app, thread, error)
            } catch (_: Throwable) {
                // The log must never be the reason a crash is lost.
            }
            previous?.uncaughtException(thread, error)
        }
    }

    private fun write(context: Context, thread: Thread, error: Throwable) {
        val directory = File(context.filesDir, "logs")
        if (!directory.exists() && !directory.mkdirs()) return
        val file = File(directory, FILE_NAME)
        if (file.length() > MAX_BYTES) file.delete()

        val trace = StringWriter()
        error.printStackTrace(PrintWriter(trace))
        val version = try {
            val info = context.packageManager.getPackageInfo(context.packageName, 0)
            val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
            "${info.versionName}+$code"
        } catch (_: Exception) {
            "?"
        }
        val time = SimpleDateFormat("yyyy-MM-dd HH:mm:ss Z", Locale.US).format(Date())
        file.appendText(
            "#### $time [native] thread ${thread.name} · v$version · " +
                "Android ${Build.VERSION.RELEASE} (${Build.MANUFACTURER} ${Build.MODEL})\n" +
                trace.toString().take(12_000) + "\n\n",
        )
    }
}
