package com.souqi.souqi

import android.Manifest
import android.annotation.SuppressLint
import android.app.DownloadManager
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothClass
import android.bluetooth.BluetoothManager
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioManager
import android.media.MediaScannerConnection
import android.media.ToneGenerator
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Hosts the Flutter UI and the "souqi/native" method channel — the Android
 * half of lib/core/platform/native_bridge.dart:
 *
 *  - Bluetooth receipt printing (paired devices, connect, chunked write),
 *  - the direct "send to this WhatsApp chat" intent,
 *  - saving a file to Downloads/Souqi,
 *  - picking a .txt / .csv file of card codes and reading it as text,
 *  - the beep that confirms a scanned card,
 *  - shortcuts into the system Bluetooth and app settings,
 *  - the daily debt report's screens: the folder picker, a file manager on
 *    the report folder, the battery-optimization exemption and the
 *    notification permission (its files, schedule and notification are on
 *    the "souqi/report" channel, [ReportChannel], which the background
 *    worker uses too), and the taps on its notification.
 *
 * Nothing here uses the network.
 */
class MainActivity : FlutterActivity() {
    private val printer = PrinterConnection()

    /** One thread for all blocking work, so print jobs never interleave. */
    private val io: ExecutorService = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** Completion of the runtime-permission request in flight, if any. */
    private var pendingPermission: ((Boolean) -> Unit)? = null

    /** The "pick a text file" call waiting for the system picker to return. */
    private var pendingPick: MethodChannel.Result? = null

    /** The "pick a folder" call waiting for the folder picker to return. */
    private var pendingFolder: MethodChannel.Result? = null

    /** The "pick any file" call (a backup to restore) waiting likewise. */
    private var pendingAnyFile: MethodChannel.Result? = null

    private var reportChannel: ReportChannel? = null

    /** Created on the first beep and kept: creating one per beep is slow. */
    private var tone: ToneGenerator? = null

    private val adapter: BluetoothAdapter?
        get() = (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(::onMethodCall)
        reportChannel?.dispose()
        reportChannel = ReportChannel(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
            .also { ReportChannel.appChannel = it }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (ReportChannel.appChannel === reportChannel) ReportChannel.appChannel = null
        reportChannel?.dispose()
        reportChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Opened from the report notification: the Dart side takes it after
        // its first frame.
        ReportLaunch.offer(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Already running: tell the Dart side now.
        if (ReportLaunch.offer(intent)) ReportChannel.pushToApp("launchAction")
    }

    override fun onDestroy() {
        io.execute { printer.close() }
        io.shutdown()
        tone?.release()
        tone = null
        super.onDestroy()
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "btStatus" -> result.success(
                mapOf(
                    "supported" to (adapter != null),
                    "enabled" to bluetoothEnabled(),
                    "permission" to hasBluetoothPermission(),
                ),
            )
            "btRequestPermission" -> requestBluetoothPermission(result)
            "btPairedDevices" -> pairedDevices(result)
            "btPrint" -> print(call, result)
            "btDisconnect" -> io.execute {
                printer.close()
                main.post { result.success(null) }
            }
            "openBluetoothSettings" -> {
                open(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                result.success(null)
            }
            "openAppSettings" -> {
                open(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.fromParts("package", packageName, null),
                    ),
                )
                result.success(null)
            }
            "whatsAppPackages" -> result.success(WHATSAPP_PACKAGES.filter(::isInstalled))
            "sendToWhatsApp" -> sendToWhatsApp(call, result)
            "openWhatsAppChat" -> openWhatsAppChat(call, result)
            "dial" -> dial(call, result)
            "saveToDownloads" -> saveToDownloads(call, result)
            "pickTextFile" -> pickTextFile(result)
            "pickFile" -> pickFile(result)
            "beep" -> {
                beep()
                result.success(null)
            }
            "pickFolder" -> pickFolder(result)
            "openFolder" -> result.success(openFolder(call.argument<String>("uri")))
            "requestBatteryExemption" -> result.success(requestBatteryExemption())
            "requestNotificationPermission" -> requestNotificationPermission(result)
            "requestLegacyStoragePermission" -> requestLegacyStoragePermission(result)
            else -> result.notImplemented()
        }
    }

    // ---- Runtime permissions ------------------------------------------

    /**
     * Android 12+ guards Bluetooth behind the "Nearby devices" runtime
     * permissions. Older versions grant BLUETOOTH / BLUETOOTH_ADMIN at
     * install time, so there is nothing to ask.
     */
    private fun hasBluetoothPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return BLUETOOTH_PERMISSIONS.all {
            checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED
        }
    }

    private fun requestBluetoothPermission(result: MethodChannel.Result) {
        if (hasBluetoothPermission()) {
            result.success(true)
            return
        }
        askPermissions(BLUETOOTH_PERMISSIONS) { granted -> result.success(granted) }
    }

    private fun askPermissions(permissions: Array<String>, done: (Boolean) -> Unit) {
        // A second request while one is open: answer the first as denied.
        pendingPermission?.invoke(false)
        pendingPermission = done
        requestPermissions(permissions, REQUEST_PERMISSIONS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_PERMISSIONS) return
        val done = pendingPermission ?: return
        pendingPermission = null
        done(
            grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED },
        )
    }

    // ---- Bluetooth printer --------------------------------------------

    private fun bluetoothEnabled(): Boolean = try {
        adapter?.isEnabled == true
    } catch (_: SecurityException) {
        false
    }

    /** Replies with an error and returns null unless Bluetooth is usable. */
    private fun usableAdapter(result: MethodChannel.Result): BluetoothAdapter? {
        val adapter = adapter
        when {
            adapter == null -> result.error(BT_UNSUPPORTED, null, null)
            !hasBluetoothPermission() -> result.error(BT_PERMISSION, null, null)
            !bluetoothEnabled() -> result.error(BT_OFF, null, null)
            else -> return adapter
        }
        return null
    }

    /**
     * Devices already paired in the system settings. The app never scans —
     * pairing stays where the user expects it, and no location permission
     * is needed on any Android version.
     */
    @SuppressLint("MissingPermission")
    private fun pairedDevices(result: MethodChannel.Result) {
        val adapter = usableAdapter(result) ?: return
        try {
            val devices = adapter.bondedDevices.orEmpty().map { device ->
                mapOf(
                    "name" to (device.name ?: ""),
                    "address" to device.address,
                    "imaging" to (device.bluetoothClass?.majorDeviceClass ==
                        BluetoothClass.Device.Major.IMAGING),
                )
            }
            result.success(devices)
        } catch (e: SecurityException) {
            result.error(BT_PERMISSION, e.message, null)
        }
    }

    private fun print(call: MethodCall, result: MethodChannel.Result) {
        val address = call.argument<String>("address")
        val bytes = call.argument<ByteArray>("bytes")
        if (address.isNullOrEmpty() || bytes == null) {
            result.error(PrinterConnection.UNREACHABLE, "missing address or data", null)
            return
        }
        val chunkSize = call.argument<Int>("chunkSize") ?: 1024
        val chunkDelayMs = (call.argument<Int>("chunkDelayMs") ?: 0).toLong()
        val adapter = usableAdapter(result) ?: return
        io.execute {
            try {
                printer.write(adapter, address, bytes, chunkSize, chunkDelayMs)
                main.post { result.success(null) }
            } catch (e: PrinterException) {
                main.post { result.error(e.code, e.message, null) }
            } catch (e: SecurityException) {
                main.post { result.error(BT_PERMISSION, e.message, null) }
            } catch (e: Exception) {
                main.post { result.error(PrinterConnection.WRITE, e.message, null) }
            }
        }
    }

    // ---- System screens -----------------------------------------------

    private fun open(intent: Intent) {
        try {
            startActivity(intent)
        } catch (_: ActivityNotFoundException) {
        }
    }

    // ---- WhatsApp ------------------------------------------------------

    private fun isInstalled(packageName: String): Boolean = try {
        packageManager.getPackageInfo(packageName, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    /**
     * Opens WhatsApp (or WhatsApp Business) directly on one chat with the
     * file attached: ACTION_SEND restricted to the app's package, plus the
     * "jid" extra naming the chat (international number, digits only).
     *
     * The "jid" extra is not a documented API. It has worked for years, but
     * a WhatsApp build may ignore it and show its contact picker instead —
     * the file is still attached. If the intent cannot be started at all,
     * this replies false and the Dart side falls back to the share sheet.
     */
    private fun sendToWhatsApp(call: MethodCall, result: MethodChannel.Result) {
        val target = call.argument<String>("package")
        val phone = call.argument<String>("phone")
        val path = call.argument<String>("path")
        val text = call.argument<String>("text")
        if (target !in WHATSAPP_PACKAGES || phone.isNullOrEmpty() || path.isNullOrEmpty()) {
            result.success(false)
            return
        }
        try {
            val uri = FileProvider.getUriForFile(this, "$packageName.souqi.files", File(path))
            val intent = Intent(Intent.ACTION_SEND).apply {
                setPackage(target)
                type = call.argument<String>("mimeType") ?: "image/png"
                putExtra(Intent.EXTRA_STREAM, uri)
                if (!text.isNullOrEmpty()) putExtra(Intent.EXTRA_TEXT, text)
                putExtra("jid", "$phone@s.whatsapp.net")
                // Carries the read grant on every Android version.
                clipData = ClipData.newRawUri(null, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(intent)
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            result.success(false)
        } catch (_: IllegalArgumentException) {
            // The file is outside the folder SouqiFileProvider exposes.
            result.success(false)
        } catch (_: SecurityException) {
            result.success(false)
        }
    }

    /**
     * Opens WhatsApp (or WhatsApp Business) on one chat with a message
     * already typed into the box, ready to edit and send: WhatsApp's own
     * "send" link, handed straight to the installed app by package name.
     * Souqi sends nothing itself and opens no browser.
     *
     * The app-scheme link is tried first and the https form second — which
     * of the two a given WhatsApp build accepts has changed over the years.
     * Replies false when neither can be started.
     */
    private fun openWhatsAppChat(call: MethodCall, result: MethodChannel.Result) {
        val target = call.argument<String>("package")
        val phone = call.argument<String>("phone")
        val text = call.argument<String>("text").orEmpty()
        if (target !in WHATSAPP_PACKAGES || phone.isNullOrEmpty()) {
            result.success(false)
            return
        }
        val links = listOf(
            Uri.Builder().scheme("whatsapp").authority("send"),
            Uri.Builder().scheme("https").authority("api.whatsapp.com").path("send"),
        ).map { builder ->
            builder.appendQueryParameter("phone", phone)
            if (text.isNotEmpty()) builder.appendQueryParameter("text", text)
            builder.build()
        }
        for (link in links) {
            try {
                startActivity(Intent(Intent.ACTION_VIEW, link).setPackage(target))
                result.success(true)
                return
            } catch (_: ActivityNotFoundException) {
            } catch (_: SecurityException) {
            }
        }
        result.success(false)
    }

    // ---- Phone ---------------------------------------------------------

    /**
     * Opens the dialer with the number filled in. ACTION_DIAL, not
     * ACTION_CALL: the seller presses the call button, so the app needs no
     * CALL_PHONE permission.
     */
    private fun dial(call: MethodCall, result: MethodChannel.Result) {
        val phone = call.argument<String>("phone")
        if (phone.isNullOrBlank()) {
            result.success(false)
            return
        }
        try {
            startActivity(Intent(Intent.ACTION_DIAL, Uri.fromParts("tel", phone, null)))
            result.success(true)
        } catch (_: ActivityNotFoundException) {
            result.success(false)
        }
    }

    // ---- Save to phone -------------------------------------------------

    private fun saveToDownloads(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val name = call.argument<String>("fileName")
        val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
        // "Souqi/Backups" for a backup; only our own folders under Downloads.
        val subfolder = call.argument<String>("subfolder")
            ?.takeIf { it == FOLDER || it.startsWith("$FOLDER/") && !it.contains("..") }
            ?: FOLDER
        if (path.isNullOrEmpty() || name.isNullOrEmpty()) {
            result.error(SAVE_FAILED, "missing path or file name", null)
            return
        }
        val save = {
            io.execute {
                try {
                    val shown = copyToDownloads(File(path), name, mime, subfolder)
                    main.post { result.success(shown) }
                } catch (e: Exception) {
                    main.post { result.error(SAVE_FAILED, e.message, null) }
                }
            }
        }
        // Android 10+ needs no permission to add a file to Downloads through
        // MediaStore. Android 9 and older write the file directly and need
        // the (legacy) storage permission.
        val needsPermission = Build.VERSION.SDK_INT < Build.VERSION_CODES.Q &&
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) !=
            PackageManager.PERMISSION_GRANTED
        if (!needsPermission) {
            save()
            return
        }
        askPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE)) { granted ->
            if (granted) save() else result.error(STORAGE_PERMISSION, null, null)
        }
    }

    /** Copies [source] into Downloads/[folderName]; returns the path to show. */
    private fun copyToDownloads(source: File, name: String, mime: String, folderName: String = FOLDER): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, mime)
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    "${Environment.DIRECTORY_DOWNLOADS}/$folderName",
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val collection =
                MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            val uri = contentResolver.insert(collection, values)
                ?: throw IOException("could not create the file")
            try {
                val out = contentResolver.openOutputStream(uri)
                    ?: throw IOException("could not open the file")
                out.use { stream -> source.inputStream().use { it.copyTo(stream) } }
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                contentResolver.update(uri, values, null, null)
            } catch (e: Exception) {
                contentResolver.delete(uri, null, null)
                throw e
            }
            // MediaStore renames duplicates ("invoice-12 (1).png").
            val shown = contentResolver.query(
                uri,
                arrayOf(MediaStore.MediaColumns.DISPLAY_NAME),
                null,
                null,
                null,
            )?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
            return "${Environment.DIRECTORY_DOWNLOADS}/$folderName/${shown ?: name}"
        }

        @Suppress("DEPRECATION")
        val downloads =
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val folder = File(downloads, folderName)
        if (!folder.exists() && !folder.mkdirs()) {
            throw IOException("could not create ${folder.path}")
        }
        val base = name.substringBeforeLast('.')
        val extension = name.substringAfterLast('.', "")
        var target = File(folder, name)
        var copy = 1
        while (target.exists()) {
            val suffix = if (extension.isEmpty()) "" else ".$extension"
            target = File(folder, "$base ($copy)$suffix")
            copy++
        }
        source.copyTo(target)
        MediaScannerConnection.scanFile(this, arrayOf(target.absolutePath), arrayOf(mime), null)
        return "${Environment.DIRECTORY_DOWNLOADS}/$folderName/${target.name}"
    }

    // ---- Card codes: file import and the scan beep ----------------------

    /**
     * Opens the system file picker (Storage Access Framework — no storage
     * permission on any Android version) and replies with the chosen file
     * as text: {"name": …, "content": …}, or null when the user backs out.
     *
     * Any file can be chosen: phones disagree on the MIME type of a .csv, so
     * filtering by type would grey out real card lists. What is read is
     * checked instead — at most [MAX_TEXT_BYTES], and it must be text.
     */
    private fun pickTextFile(result: MethodChannel.Result) {
        // A second pick while one is open: answer the first as cancelled.
        pendingPick?.success(null)
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQUEST_PICK_TEXT)
        } catch (e: ActivityNotFoundException) {
            pendingPick = null
            result.error(PICK_FAILED, e.message, null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_PICK_FOLDER) {
            onFolderPicked(resultCode, data)
            return
        }
        if (requestCode == REQUEST_PICK_FILE) {
            onFilePicked(resultCode, data)
            return
        }
        if (requestCode != REQUEST_PICK_TEXT) return
        val result = pendingPick ?: return
        pendingPick = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        io.execute {
            try {
                val picked = mapOf("name" to displayName(uri), "content" to readText(uri))
                main.post { result.success(picked) }
            } catch (e: Exception) {
                main.post { result.error(PICK_FAILED, e.message, null) }
            }
        }
    }

    /**
     * Any file (a backup to restore): the system picker, then a copy into
     * cache/picked/ — the picker's read permission ends with this activity,
     * the restore takes longer. Replies {"name", "path"} or null.
     */
    private fun pickFile(result: MethodChannel.Result) {
        pendingAnyFile?.success(null)
        pendingAnyFile = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            // A .souqi file has no MIME type a phone knows: offer everything.
            type = "*/*"
        }
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQUEST_PICK_FILE)
        } catch (e: ActivityNotFoundException) {
            pendingAnyFile = null
            result.error(PICK_FAILED, e.message, null)
        }
    }

    private fun onFilePicked(resultCode: Int, data: Intent?) {
        val result = pendingAnyFile ?: return
        pendingAnyFile = null
        val uri = data?.data
        if (resultCode != RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        io.execute {
            try {
                val name = displayName(uri)
                val folder = File(cacheDir, "picked")
                folder.deleteRecursively()
                if (!folder.mkdirs()) throw IOException("could not create ${folder.path}")
                // Never a path from the provider: a fixed name in our folder.
                val target = File(folder, "picked-file")
                val input = contentResolver.openInputStream(uri)
                    ?: throw IOException("could not open the file")
                input.use { stream -> target.outputStream().use { stream.copyTo(it) } }
                val picked = mapOf("name" to name, "path" to target.absolutePath)
                main.post { result.success(picked) }
            } catch (e: Exception) {
                main.post { result.error(PICK_FAILED, e.message, null) }
            }
        }
    }

    private fun displayName(uri: Uri): String {
        val name = contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
        return name ?: uri.lastPathSegment ?: ""
    }

    /** Reads [uri] as text: UTF-8, or UTF-16 when it starts with that BOM. */
    private fun readText(uri: Uri): String {
        val bytes = contentResolver.openInputStream(uri)?.use { stream ->
            val buffer = ByteArray(MAX_TEXT_BYTES + 1)
            var total = 0
            while (total < buffer.size) {
                val read = stream.read(buffer, total, buffer.size - total)
                if (read < 0) break
                total += read
            }
            if (total > MAX_TEXT_BYTES) throw IOException("the file is too large")
            buffer.copyOf(total)
        } ?: throw IOException("could not open the file")
        val utf16le = bytes.size >= 2 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xFE.toByte()
        val utf16be = bytes.size >= 2 && bytes[0] == 0xFE.toByte() && bytes[1] == 0xFF.toByte()
        val text = when {
            utf16le -> String(bytes, 2, bytes.size - 2, Charsets.UTF_16LE)
            utf16be -> String(bytes, 2, bytes.size - 2, Charsets.UTF_16BE)
            else -> String(bytes, Charsets.UTF_8)
        }
        // A picture or a spreadsheet file picked by mistake: text has no NUL.
        if (text.indexOf(Char(0)) >= 0) throw IOException("not a text file")
        return text
    }

    /** A short beep, at the phone's notification volume. */
    private fun beep() {
        try {
            val generator = tone
                ?: ToneGenerator(AudioManager.STREAM_NOTIFICATION, 80).also { tone = it }
            generator.startTone(ToneGenerator.TONE_PROP_BEEP, 120)
        } catch (_: RuntimeException) {
            // No tone generator on this device: the vibration still confirms.
        }
    }

    // ---- The daily debt report -------------------------------------------

    /**
     * The system folder picker (Storage Access Framework): internal storage,
     * an SD card, a USB drive, or any cloud app that offers folders. The
     * write permission is made persistent, so the background job can still
     * use it after a reboot. Replies {"uri", "name", "kind"} or null.
     */
    private fun pickFolder(result: MethodChannel.Result) {
        pendingFolder?.success(null)
        pendingFolder = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
        )
        try {
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQUEST_PICK_FOLDER)
        } catch (e: ActivityNotFoundException) {
            pendingFolder = null
            result.error(PICK_FAILED, e.message, null)
        }
    }

    private fun onFolderPicked(resultCode: Int, data: Intent?) {
        val result = pendingFolder ?: return
        pendingFolder = null
        val tree = data?.data
        if (resultCode != RESULT_OK || tree == null) {
            result.success(null)
            return
        }
        try {
            contentResolver.takePersistableUriPermission(
                tree,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (e: SecurityException) {
            // A provider that does not let its folders be kept.
            result.error(PICK_FAILED, e.message, null)
            return
        }
        io.execute {
            val picked = mapOf(
                "uri" to tree.toString(),
                "name" to ReportFiles.folderName(this, tree),
                "kind" to ReportFiles.folderKind(tree),
            )
            main.post { result.success(picked) }
        }
    }

    /**
     * Shows the report folder in a file manager: the chosen folder, or
     * Download/Souqi/Reports. False when nothing on the phone can.
     */
    private fun openFolder(uri: String?): Boolean {
        val folder = try {
            ReportFiles.folderDocument(uri)
        } catch (_: Exception) {
            null
        }
        val attempts = mutableListOf<Intent>()
        if (folder != null) {
            attempts.add(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(folder, DocumentsContract.Document.MIME_TYPE_DIR)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
            )
            attempts.add(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(folder, "resource/folder")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
            )
        }
        if (uri == null) attempts.add(Intent(DownloadManager.ACTION_VIEW_DOWNLOADS))
        for (intent in attempts) {
            try {
                startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
            } catch (_: SecurityException) {
            }
        }
        return false
    }

    /**
     * Android's own "let this app run in the background?" dialog, or the
     * battery-optimization list where a phone does not offer the dialog.
     */
    @SuppressLint("BatteryLife")
    private fun requestBatteryExemption(): Boolean {
        val attempts = listOf(
            Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.fromParts("package", packageName, null),
            ),
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
        )
        for (intent in attempts) {
            try {
                startActivity(intent)
                return true
            } catch (_: ActivityNotFoundException) {
            } catch (_: SecurityException) {
            }
        }
        return false
    }

    private fun notificationsEnabled() =
        NotificationManagerCompat.from(this).areNotificationsEnabled()

    /** Android 13+ asks; older versions answer whether they are on. */
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(notificationsEnabled())
            return
        }
        askPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS)) { granted ->
            result.success(granted && notificationsEnabled())
        }
    }

    /** Android 9 and older: writing to Downloads needs the storage permission. */
    private fun requestLegacyStoragePermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
            checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        askPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE)) { granted ->
            result.success(granted)
        }
    }

    companion object {
        private const val CHANNEL = "souqi/native"
        private const val FOLDER = "Souqi"
        private const val REQUEST_PERMISSIONS = 48731
        private const val REQUEST_PICK_TEXT = 48732
        private const val REQUEST_PICK_FOLDER = 48733
        private const val REQUEST_PICK_FILE = 48734

        /** Far more than any card list: 100,000 codes are about 2 MB. */
        private const val MAX_TEXT_BYTES = 4 * 1024 * 1024
        private const val PICK_FAILED = "PICK_FAILED"

        private const val BT_UNSUPPORTED = "BT_UNSUPPORTED"
        private const val BT_OFF = "BT_OFF"
        private const val BT_PERMISSION = "BT_PERMISSION"
        private const val STORAGE_PERMISSION = "STORAGE_PERMISSION"
        private const val SAVE_FAILED = "SAVE_FAILED"

        private val BLUETOOTH_PERMISSIONS = arrayOf(
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_SCAN,
        )
        private val WHATSAPP_PACKAGES = listOf("com.whatsapp", "com.whatsapp.w4b")
    }
}
