package com.fknotes.app

import android.app.Activity
import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

internal class IncomingShareBridge(private val activity: Activity, messenger: BinaryMessenger) {
    companion object {
        // Survives activity recreation, so old/new engines never race over an entry.
        private val executor = Executors.newSingleThreadExecutor()
        // Read and updated on the main thread, including across recreation.
        private var receivingCount = 0
    }
    private val channel = MethodChannel(messenger, "fknotes/incoming_share")
    private val main = Handler(Looper.getMainLooper())
    private val inbox = IncomingShareInbox(activity.applicationContext)
    private var disposed = false

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method == "openAttachment") {
                try {
                    val key = requireNotNull(call.argument<String>("storageKey"))
                    val root = File(activity.filesDir, "notes/files").canonicalFile
                    val file = File(activity.filesDir, key).canonicalFile
                    require(file.path.startsWith(root.path + File.separator) && file.isFile)
                    val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.fileprovider", file)
                    val view = Intent(Intent.ACTION_VIEW).setDataAndType(uri, call.argument<String>("mimeType") ?: "application/octet-stream")
                        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    activity.startActivity(Intent.createChooser(view, null))
                    result.success(null)
                } catch (_: Exception) {
                    result.error("open_failed", "Could not open attachment", null)
                }
            } else if (call.method == "peek" || call.method == "finish") {
                if (call.method == "peek" && receivingCount > 0) channel.invokeMethod("receiving", null)
                executor.execute {
                    try {
                        val value = if (call.method == "peek") inbox.peek() else {
                            inbox.finish(requireNotNull(call.argument<String>("id")))
                            null
                        }
                        main.post { if (!disposed) result.success(value) }
                    } catch (_: Exception) {
                        main.post { if (!disposed) result.error("share_failed", "Could not read shared content", null) }
                    }
                }
            } else result.notImplemented()
        }
    }

    fun onIntent(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND && intent?.action != Intent.ACTION_SEND_MULTIPLE) return
        val snapshot = Intent(intent)
        intent.action = null
        intent.removeExtra(Intent.EXTRA_STREAM)
        intent.removeExtra(Intent.EXTRA_TEXT)
        intent.removeExtra(Intent.EXTRA_HTML_TEXT)
        intent.clipData = null
        receivingCount++
        channel.invokeMethod("receiving", null)
        executor.execute {
            var failed = false
            try {
                inbox.receive(snapshot)
            } catch (_: Exception) {
                failed = true
            } finally {
                main.post {
                    receivingCount--
                    if (!disposed) channel.invokeMethod(if (failed) "receiveFailed" else "changed", null)
                }
            }
        }
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
    }
}
