package com.fknotes.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

internal class FileLibraryBridge(private val activity: Activity, messenger: BinaryMessenger) {
    companion object { private const val PICK_REQUEST = 7314 }
    private val channel = MethodChannel(messenger, "fknotes/file_library")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val cancelled = ConcurrentHashMap.newKeySet<String>()
    private var picker: MethodChannel.Result? = null
    @Volatile private var disposed = false

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickFiles" -> {
                    if (picker != null) result.error("busy", "A picker is already open", null)
                    else {
                        picker = result
                        try {
                            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "*/*"
                                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }, PICK_REQUEST)
                        } catch (_: Exception) {
                            picker = null
                            result.error("picker_failed", "Could not open file picker", null)
                        }
                    }
                }
                "cancel" -> {
                    call.argument<String>("token")?.let { cancelled.add(it) }
                    result.success(null)
                }
                "copyFile" -> {
                    val uri = call.argument<String>("uri")
                    val destination = call.argument<String>("destination")
                    val token = call.argument<String>("token")
                    if (uri == null || destination == null || token == null) {
                        result.error("invalid", "Missing file information", null)
                    } else worker.execute { copyFile(uri, destination, token, result) }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != PICK_REQUEST) return
        val result = picker ?: return
        picker = null
        if (resultCode != Activity.RESULT_OK || data == null) { result.success(emptyList<Any>()); return }
        val uris = linkedSetOf<Uri>()
        data.data?.let { uris.add(it) }
        data.clipData?.let { clip -> for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri) }
        worker.execute {
            try {
                val files = uris.map { uri ->
                    var name = uri.lastPathSegment ?: "file"
                    var size = 0L
                    activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                            val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
                            if (nameIndex >= 0 && !cursor.isNull(nameIndex)) name = cursor.getString(nameIndex)
                            if (sizeIndex >= 0 && !cursor.isNull(sizeIndex)) size = cursor.getLong(sizeIndex).coerceAtLeast(0)
                        }
                    }
                    mapOf("uri" to uri.toString(), "name" to name, "size" to size)
                }
                main.post { if (!disposed) result.success(files) }
            } catch (_: Exception) { main.post { if (!disposed) result.error("picker_failed", "Could not read selected files", null) } }
        }
    }

    private fun copyFile(uriText: String, destination: String, token: String, result: MethodChannel.Result) {
        var output: File? = null
        try {
            val root = File(activity.filesDir, "notes/files/library/data").canonicalFile
            val file = File(destination).canonicalFile
            require(file.parentFile == root && Regex("[0-9a-f-]{36}(\\.[a-z0-9]{1,16})?\\.part").matches(file.name))
            val uri = Uri.parse(uriText)
            require(uri.scheme == "content")
            output = file
            file.parentFile?.mkdirs()
            var total = 0L
            activity.contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) total = cursor.getLong(0).coerceAtLeast(0)
            }
            var bytes = 0L
            var lastProgress = 0L
            val input = activity.contentResolver.openInputStream(uri) ?: throw IOException("Source unavailable")
            input.use { source ->
                file.outputStream().use { target ->
                    val buffer = ByteArray(256 * 1024)
                    while (true) {
                        if (disposed || cancelled.contains(token)) throw InterruptedException()
                        val count = source.read(buffer)
                        if (count < 0) break
                        target.write(buffer, 0, count)
                        bytes += count
                        val now = android.os.SystemClock.elapsedRealtime()
                        if (now - lastProgress >= 100) {
                            lastProgress = now
                            val copied = bytes
                            val length = total
                            main.post { if (!disposed) channel.invokeMethod("progress", mapOf("token" to token, "bytes" to copied, "total" to length)) }
                        }
                    }
                    target.flush()
                    target.fd.sync()
                }
            }
            if (disposed || cancelled.contains(token)) throw InterruptedException()
            main.post { if (!disposed) result.success(bytes) }
        } catch (error: Exception) {
            output?.delete()
            main.post { if (!disposed) result.error(if (error is InterruptedException) "cancelled" else "import_failed", "File import did not complete", null) }
        } finally { cancelled.remove(token) }
    }

    fun dispose() {
        disposed = true
        picker?.error("cancelled", "Picker closed", null)
        picker = null
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }
}
