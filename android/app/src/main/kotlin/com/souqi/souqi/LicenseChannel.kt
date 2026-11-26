package com.souqi.souqi

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

/**
 * The "souqi/license" method channel — the Android half of
 * lib/core/platform/license_platform.dart. Offline licensing asks it two
 * things:
 *
 *  - who this device is: Settings.Secure.ANDROID_ID and the package name.
 *    The Dart side hashes them (with a fixed salt) into the device hash a
 *    license is bound to, and shows 80 bits of it as the REQUEST CODE.
 *    On Android 8+ ANDROID_ID is per app signing key, per user, per device:
 *    another app cannot learn it, a factory reset changes it, and so does a
 *    build signed with another key.
 *  - who signed the APK that is running: the SHA-256 of each signing
 *    certificate, which the Dart side compares with the developer's.
 *
 * Registered on BOTH engines — the app's (MainActivity) and the background
 * worker's (DebtReportWorker) — because the daily job checks the license
 * too. Nothing here opens a screen, and nothing uses the network.
 */
class LicenseChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, NAME)

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "deviceIdentity" -> result.success(
                mapOf(
                    "androidId" to androidId(),
                    "packageName" to context.packageName,
                ),
            )
            "signingCertificates" -> try {
                result.success(signingCertificates())
            } catch (e: Exception) {
                result.error("FAILED", e.message, null)
            }
            else -> result.notImplemented()
        }
    }

    /** Empty on the rare device that has none. */
    @SuppressLint("HardwareIds")
    private fun androidId(): String = try {
        Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID) ?: ""
    } catch (_: Exception) {
        ""
    }

    /** SHA-256 of every certificate that signed the installed APK, hex. */
    private fun signingCertificates(): List<String> {
        val manager = context.packageManager
        val signatures: Array<Signature> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val info = manager.getPackageInfo(
                context.packageName,
                PackageManager.GET_SIGNING_CERTIFICATES,
            )
            info.signingInfo?.apkContentsSigners ?: emptyArray()
        } else {
            @Suppress("DEPRECATION")
            val info = manager.getPackageInfo(context.packageName, PackageManager.GET_SIGNATURES)
            @Suppress("DEPRECATION")
            info.signatures ?: emptyArray()
        }
        return signatures.map { signature ->
            MessageDigest.getInstance("SHA-256")
                .digest(signature.toByteArray())
                .joinToString("") { byte -> "%02x".format(byte) }
        }
    }

    companion object {
        const val NAME = "souqi/license"
    }
}
