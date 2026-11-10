package com.fknotes.app

import android.app.DownloadManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

/** DownloadManager owns the transfer, even when Flutter or the activity exits. */
internal object AppUpdateDownloads {
    const val OPEN_UPDATE = "com.fknotes.app.OPEN_UPDATE"
    private const val CHANNEL = "app_updates"
    private const val NOTIFICATION_ID = 7304
    val executor = Executors.newSingleThreadExecutor()

    private fun prefs(context: Context) = context.getSharedPreferences("app_update_download", Context.MODE_PRIVATE)
    private fun manager(context: Context) = context.getSystemService(DownloadManager::class.java)

    private fun record(context: Context): JSONObject? = try {
        prefs(context).getString("pending", null)?.let(::JSONObject)
    } catch (_: Exception) { null }

    @Synchronized
    fun start(context: Context, arguments: Any?): Long {
        val args = arguments as? Map<*, *> ?: error("Missing update download")
        val url = Uri.parse(args["url"] as? String ?: "")
        val sha256 = args["sha256"] as? String ?: ""
        val size = (args["size"] as? Number)?.toLong() ?: 0
        val versionCode = (args["versionCode"] as? Number)?.toLong() ?: 0
        val manifest = args["manifest"] as? String ?: ""
        val artifactId = args["artifactId"] as? String ?: ""
        require(url.scheme == "https" && !url.host.isNullOrBlank() && url.userInfo == null)
        require(sha256.matches(Regex("[0-9a-f]{64}")) && size > 0 && versionCode > 0)
        require(manifest.length <= 256 * 1024 && JSONObject(manifest).getString("app") == "fknotes")
        require(artifactId.matches(Regex("android-[a-z0-9_-]+")))
        val key = "$versionCode-$sha256"
        val existing = snapshot(context)
        if (existing != null && existing["status"] != "failed" && args["restart"] != true) {
            require(record(context)?.getString("key") == key) { "Another update is already downloading" }
            return (existing["id"] as Number).toLong()
        }
        clear(context)
        val parent = context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)
            ?: error("Download storage is unavailable")
        val directory = File(parent, "updates")
        check(directory.mkdirs() || directory.isDirectory)
        // A DownloadManager notification must never open an unverified APK in
        // the installer. Only our private, verified cache copy is installable.
        val file = File(directory, "$key.download")
        if (file.exists()) check(file.delete())
        val request = DownloadManager.Request(url)
            .setTitle(context.getString(R.string.app_update_download_title))
            .setDescription(context.getString(R.string.app_update_download_description))
            .setMimeType("application/octet-stream")
            .setDestinationUri(Uri.fromFile(file))
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setAllowedOverRoaming(false)
        val id = manager(context).enqueue(request)
        val pending = JSONObject().put("id", id).put("key", key)
            .put("size", size).put("versionCode", versionCode)
            .put("manifest", manifest).put("artifactId", artifactId)
        if (!prefs(context).edit().putString("pending", pending.toString()).commit()) {
            manager(context).remove(id)
            error("Could not persist update download")
        }
        return id
    }

    @Synchronized
    fun snapshot(context: Context): Map<String, Any>? {
        val pending = record(context) ?: return null
        @Suppress("DEPRECATION")
        val installed = context.packageManager.getPackageInfo(context.packageName, 0)
        @Suppress("DEPRECATION")
        val currentVersion = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
        if (currentVersion >= pending.getLong("versionCode")) {
            clear(context)
            return null
        }
        val id = pending.getLong("id")
        val result = mutableMapOf<String, Any>(
            "id" to id, "manifest" to pending.getString("manifest"),
            "artifactId" to pending.getString("artifactId"),
            "totalBytes" to pending.getLong("size"), "downloadedBytes" to 0L,
            "status" to "failed", "errorCode" to "UPDATE_DOWNLOAD_MISSING",
        )
        manager(context).query(DownloadManager.Query().setFilterById(id))?.use { cursor ->
            if (cursor.moveToFirst()) {
                val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
                val downloaded = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                val reason = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))
                result["downloadedBytes"] = downloaded.coerceAtLeast(0)
                result["status"] = when (status) {
                    DownloadManager.STATUS_SUCCESSFUL -> "downloaded"
                    DownloadManager.STATUS_FAILED -> "failed"
                    DownloadManager.STATUS_PAUSED -> "paused"
                    else -> "downloading"
                }
                result["errorCode"] = "UPDATE_DOWNLOAD_$reason"
                if (downloaded > pending.getLong("size")) {
                    manager(context).remove(id)
                    result["status"] = "failed"
                    result["errorCode"] = "UPDATE_SIZE_MISMATCH"
                }
            }
        }
        return result
    }

    @Synchronized
    fun materialize(context: Context, id: Long): String {
        val state = snapshot(context) ?: error("No pending download")
        check(state["id"] == id && state["status"] == "downloaded")
        val pending = record(context) ?: error("Missing download metadata")
        val directory = File(context.cacheDir, "updates")
        check(directory.mkdirs() || directory.isDirectory)
        val destination = File(directory, "${pending.getString("key")}.apk")
        val partial = File(directory, "${pending.getString("key")}.part")
        val expectedSize = pending.getLong("size")
        try {
            manager(context).openDownloadedFile(id).use { descriptor ->
                android.os.ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { input ->
                    partial.outputStream().use { output ->
                        val buffer = ByteArray(64 * 1024)
                        var bytes = 0L
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            bytes += count
                            check(bytes <= expectedSize) { "Update size mismatch" }
                            output.write(buffer, 0, count)
                        }
                        check(bytes == expectedSize) { "Update size mismatch" }
                    }
                }
            }
            if (destination.exists()) check(destination.delete())
            check(partial.renameTo(destination))
            return destination.absolutePath
        } finally {
            partial.delete()
        }
    }

    @Synchronized
    fun clear(context: Context) {
        record(context)?.let { pending ->
            manager(context).remove(pending.optLong("id", -1))
            val key = pending.optString("key")
            if (key.matches(Regex("[0-9]+-[0-9a-f]{64}"))) {
                File(context.cacheDir, "updates/$key.apk").delete()
                File(context.cacheDir, "updates/$key.part").delete()
            }
        }
        prefs(context).edit().remove("pending").commit()
        NotificationManagerCompat.from(context).cancel(NOTIFICATION_ID)
    }

    fun notifyCompleted(context: Context, id: Long) {
        val state = snapshot(context) ?: return
        if (state["id"] != id || state["status"] != "downloaded") return
        val notifications = NotificationManagerCompat.from(context)
        if (!notifications.areNotificationsEnabled()) return
        if (Build.VERSION.SDK_INT >= 26) {
            notifications.createNotificationChannel(NotificationChannel(
                CHANNEL, context.getString(R.string.app_update_channel), NotificationManager.IMPORTANCE_DEFAULT,
            ))
        }
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        launch.putExtra(OPEN_UPDATE, true).addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val content = PendingIntent.getActivity(context, NOTIFICATION_ID, launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(context.getString(R.string.app_update_download_complete))
            .setContentText(context.getString(R.string.app_update_download_complete_description))
            .setContentIntent(content).setAutoCancel(true).build()
        try { notifications.notify(NOTIFICATION_ID, notification) } catch (_: SecurityException) {
            // Notification permission can be revoked during the transfer. The
            // saved task is still restored and surfaced the next time the app opens.
        }
    }
}

class AppUpdateDownloadReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != DownloadManager.ACTION_DOWNLOAD_COMPLETE) return
        val id = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1)
        val pending = goAsync()
        AppUpdateDownloads.executor.execute {
            try { AppUpdateDownloads.notifyCompleted(context.applicationContext, id) }
            catch (_: Exception) { /* The task can still be recovered in-app. */ }
            finally { pending.finish() }
        }
    }
}
