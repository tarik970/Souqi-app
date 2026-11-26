package com.souqi.souqi

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException

/** The chosen folder is gone (permission revoked, SD card / USB drive out). */
class ReportUnavailableException(message: String?) : Exception(message)

/** The folder is there but the file could not be written. */
class ReportWriteException(message: String?) : Exception(message)

/**
 * Report files: in a folder chosen with the system folder picker (Storage
 * Access Framework, a persisted tree permission — an SD card, a USB drive or
 * a cloud app's folder), or in Download/Souqi/Reports (MediaStore, no
 * permission on Android 10+).
 *
 * A file of the same name is OVERWRITTEN: one report per day.
 */
object ReportFiles {
    private const val SUBFOLDER = "Souqi/Reports"

    /** What the user is shown for the Downloads destination. */
    val downloadsLabel = "${Environment.DIRECTORY_DOWNLOADS}/$SUBFOLDER"

    private const val EXTERNAL_STORAGE = "com.android.externalstorage.documents"

    // ---- A chosen folder (tree) ----------------------------------------

    private fun rootDocument(tree: Uri): Uri =
        DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )

    /** The permission is still held and the storage behind it answers. */
    fun treeAvailable(context: Context, uri: String): Boolean {
        val tree = Uri.parse(uri)
        val held = context.contentResolver.persistedUriPermissions.any {
            it.uri == tree && it.isWritePermission
        }
        if (!held) return false
        return try {
            context.contentResolver.query(
                rootDocument(tree),
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
                null,
                null,
                null,
            )?.use { it.moveToFirst() } ?: false
        } catch (_: Exception) {
            false
        }
    }

    /** The folder's own name, as the picker showed it. */
    fun folderName(context: Context, tree: Uri): String = try {
        context.contentResolver.query(
            rootDocument(tree),
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { if (it.moveToFirst()) it.getString(0) else null }
    } catch (_: Exception) {
        null
    } ?: (tree.lastPathSegment ?: "")

    /**
     * PHONE (internal storage), REMOVABLE (SD card, USB drive), CLOUD (a
     * cloud app) or OTHER — for the warning that the phone's own storage
     * does not survive the phone.
     */
    fun folderKind(tree: Uri): String {
        val authority = tree.authority ?: return "OTHER"
        return when {
            authority == EXTERNAL_STORAGE ->
                if (DocumentsContract.getTreeDocumentId(tree).startsWith("primary:")) {
                    "PHONE"
                } else {
                    "REMOVABLE"
                }
            authority == "com.android.mtp.documents" -> "REMOVABLE"
            authority.startsWith("com.android.providers.") -> "PHONE"
            CLOUD_HINTS.any { authority.contains(it) } -> "CLOUD"
            else -> "OTHER"
        }
    }

    private val CLOUD_HINTS = listOf(
        "com.google.android.apps.docs",
        "dropbox",
        "skydrive",
        "onedrive",
        "nextcloud",
        "owncloud",
        "mega",
        "box.android",
        "pcloud",
        "yandex",
    )

    private fun treeChildren(context: Context, tree: Uri): List<Pair<String, Uri>> {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        val out = mutableListOf<Pair<String, Uri>>()
        context.contentResolver.query(
            children,
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val id = cursor.getString(0) ?: continue
                val name = cursor.getString(1) ?: continue
                out.add(name to DocumentsContract.buildDocumentUriUsingTree(tree, id))
            }
        } ?: throw ReportUnavailableException("the folder cannot be listed")
        return out
    }

    private fun copy(context: Context, source: File, target: Uri, mode: String) {
        val out = context.contentResolver.openOutputStream(target, mode)
            ?: throw IOException("could not open the file")
        out.use { stream -> source.inputStream().use { it.copyTo(stream) } }
    }

    private fun writeTree(context: Context, uri: String, name: String, source: File, mime: String): String {
        if (!treeAvailable(context, uri)) throw ReportUnavailableException("folder not available")
        val tree = Uri.parse(uri)
        val existing = treeChildren(context, tree).firstOrNull { it.first == name }?.second
        if (existing != null) {
            try {
                copy(context, source, existing, "wt")
                return folderName(context, tree)
            } catch (_: Exception) {
                // A provider without "wt": replace the file instead.
                try {
                    DocumentsContract.deleteDocument(context.contentResolver, existing)
                } catch (_: Exception) {
                }
            }
        }
        val created = DocumentsContract.createDocument(
            context.contentResolver,
            rootDocument(tree),
            mime,
            name,
        ) ?: throw ReportWriteException("could not create the file")
        try {
            copy(context, source, created, "w")
        } catch (e: Exception) {
            try {
                DocumentsContract.deleteDocument(context.contentResolver, created)
            } catch (_: Exception) {
            }
            throw e
        }
        return folderName(context, tree)
    }

    // ---- Download/Souqi/Reports ----------------------------------------

    private val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/$SUBFOLDER/"

    private fun legacyFolder(): File {
        @Suppress("DEPRECATION")
        val downloads =
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        return File(downloads, SUBFOLDER)
    }

    private fun legacyAllowed(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED

    /** (name, uri) of this app's files in Download/Souqi/Reports. */
    private fun downloadEntries(context: Context): List<Pair<String, Uri>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return emptyList()
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val out = mutableListOf<Pair<String, Uri>>()
        context.contentResolver.query(
            collection,
            arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME),
            "${MediaStore.MediaColumns.RELATIVE_PATH} = ?",
            arrayOf(relativePath),
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val name = cursor.getString(1) ?: continue
                out.add(name to ContentUris.withAppendedId(collection, cursor.getLong(0)))
            }
        }
        return out
    }

    private fun writeDownloads(context: Context, name: String, source: File, mime: String): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            if (!legacyAllowed(context)) throw ReportUnavailableException("no storage permission")
            val folder = legacyFolder()
            if (!folder.exists() && !folder.mkdirs()) throw ReportWriteException("could not create ${folder.path}")
            val target = File(folder, name)
            source.copyTo(target, overwrite = true)
            MediaScannerConnection.scanFile(context, arrayOf(target.absolutePath), arrayOf(mime), null)
            return downloadsLabel
        }
        val resolver = context.contentResolver
        val existing = downloadEntries(context).firstOrNull { it.first == name }?.second
        if (existing != null) {
            try {
                copy(context, source, existing, "wt")
                return downloadsLabel
            } catch (_: Exception) {
                resolver.delete(existing, null, null)
            }
        }
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = resolver.insert(collection, values)
            ?: throw ReportWriteException("could not create the file")
        try {
            copy(context, source, uri, "w")
            values.clear()
            values.put(MediaStore.MediaColumns.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
        return downloadsLabel
    }

    // ---- Both -----------------------------------------------------------

    /**
     * Writes [source] as [name] into the folder [uri] (null = Downloads) and
     * returns where it went. Throws [ReportUnavailableException] or
     * [ReportWriteException].
     */
    fun write(context: Context, uri: String?, name: String, source: File, mime: String): String {
        try {
            return if (uri == null) {
                writeDownloads(context, name, source, mime)
            } else {
                writeTree(context, uri, name, source, mime)
            }
        } catch (e: ReportUnavailableException) {
            throw e
        } catch (e: ReportWriteException) {
            throw e
        } catch (e: SecurityException) {
            throw ReportUnavailableException(e.message)
        } catch (e: FileNotFoundException) {
            throw if (uri != null && !treeAvailable(context, uri)) {
                ReportUnavailableException(e.message)
            } else {
                ReportWriteException(e.message)
            }
        } catch (e: Exception) {
            throw ReportWriteException(e.message)
        }
    }

    fun list(context: Context, uri: String?): List<String> = if (uri == null) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            legacyFolder().list()?.toList() ?: emptyList()
        } else {
            downloadEntries(context).map { it.first }
        }
    } else {
        treeChildren(context, Uri.parse(uri)).map { it.first }
    }

    fun delete(context: Context, uri: String?, name: String) {
        if (uri == null) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                File(legacyFolder(), name).delete()
            } else {
                downloadEntries(context).filter { it.first == name }.forEach {
                    context.contentResolver.delete(it.second, null, null)
                }
            }
            return
        }
        treeChildren(context, Uri.parse(uri)).filter { it.first == name }.forEach {
            DocumentsContract.deleteDocument(context.contentResolver, it.second)
        }
    }

    /** Gives up the persisted permission of a folder no longer used. */
    fun release(context: Context, uri: String) {
        try {
            context.contentResolver.releasePersistableUriPermission(
                Uri.parse(uri),
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        } catch (_: SecurityException) {
        }
    }

    /** The document a file manager is asked to show for [uri] (null = Downloads). */
    fun folderDocument(uri: String?): Uri = if (uri == null) {
        DocumentsContract.buildDocumentUri(
            EXTERNAL_STORAGE,
            "primary:${Environment.DIRECTORY_DOWNLOADS}/$SUBFOLDER",
        )
    } else {
        rootDocument(Uri.parse(uri))
    }
}
