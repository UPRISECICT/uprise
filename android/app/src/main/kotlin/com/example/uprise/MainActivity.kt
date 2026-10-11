package com.example.uprise

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val downloadChannel = "com.example.uprise/downloads"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "saveToDownloads" -> saveToDownloads(call, result)
                    "openDownload" -> openDownload(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveToDownloads(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val bytes = call.argument<ByteArray>("bytes")
        val fileName = call.argument<String>("fileName")
        if (bytes == null || fileName.isNullOrBlank()) {
            result.error("invalid_download", "Missing file data or name.", null)
            return
        }

        var downloadUri: Uri? = null
        try {
            val extension = fileName.substringAfterLast('.', "").lowercase()
            val mimeType = MimeTypeMap.getSingleton()
                .getMimeTypeFromExtension(extension) ?: "application/octet-stream"
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
            }
            val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Downloads.EXTERNAL_CONTENT_URI
            } else {
                MediaStore.Files.getContentUri("external")
            }
            val insertedUri = contentResolver.insert(collection, values)
                ?: throw IllegalStateException("Could not create the download file.")
            downloadUri = insertedUri
            contentResolver.openOutputStream(insertedUri, "w")!!.use { stream ->
                stream.write(bytes)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                contentResolver.update(
                    insertedUri,
                    ContentValues().apply {
                        put(MediaStore.MediaColumns.IS_PENDING, 0)
                    },
                    null,
                    null,
                )
            }
            result.success(mapOf("uri" to insertedUri.toString(), "name" to fileName))
        } catch (error: Exception) {
            downloadUri?.let { contentResolver.delete(it, null, null) }
            result.error("download_failed", error.message, null)
        }
    }

    private fun openDownload(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        val uriValue = call.argument<String>("uri")
        if (uriValue.isNullOrBlank()) {
            result.error("invalid_download", "Missing file location.", null)
            return
        }
        try {
            val uri = Uri.parse(uriValue)
            val mimeType = contentResolver.getType(uri) ?: "application/octet-stream"
            startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, mimeType)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                },
            )
            result.success(null)
        } catch (error: Exception) {
            result.error("open_failed", error.message, null)
        }
    }
}
