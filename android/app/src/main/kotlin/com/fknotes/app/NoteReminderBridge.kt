package com.fknotes.app

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** One serialized owner for alarms, including receivers launched without Flutter. */
internal object NoteReminders {
    const val FIRE = "com.fknotes.app.NOTE_REMINDER"
    const val DISMISS = "com.fknotes.app.DISMISS_REMINDER"
    const val OPEN = "com.fknotes.app.OPEN_REMINDER"
    const val CHANNEL = "note_reminders"
    val executor = Executors.newSingleThreadExecutor()

    private fun prefs(context: Context) = context.getSharedPreferences("note_reminders", Context.MODE_PRIVATE)
    private fun alarms(context: Context) = context.getSystemService(AlarmManager::class.java)
    private fun notifications(context: Context) = context.getSystemService(NotificationManager::class.java)
    fun validId(value: String?): Boolean = try {
        value != null && UUID.fromString(value).toString() == value
    } catch (_: IllegalArgumentException) { false }

    fun createChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= 26) {
            notifications(context).createNotificationChannel(
                NotificationChannel(CHANNEL, context.getString(R.string.reminder_channel), NotificationManager.IMPORTANCE_HIGH).apply {
                    description = context.getString(R.string.reminder_channel_description)
                    enableVibration(true)
                    lockscreenVisibility = NotificationCompat.VISIBILITY_PRIVATE
                },
            )
        }
    }

    fun notificationsAllowed(context: Context): Boolean {
        createChannel(context)
        return NotificationManagerCompat.from(context).areNotificationsEnabled() &&
            (Build.VERSION.SDK_INT < 26 ||
                notifications(context).getNotificationChannel(CHANNEL)?.importance != NotificationManager.IMPORTANCE_NONE)
    }

    fun exactAllowed(context: Context) =
        Build.VERSION.SDK_INT < 31 || alarms(context).canScheduleExactAlarms()

    fun access(context: Context): String = when {
        !notificationsAllowed(context) -> "notificationsDisabled"
        !exactAllowed(context) -> "exactAlarmDisabled"
        else -> "ready"
    }

    @Synchronized
    fun initialize(context: Context, path: String) {
        val file = File(path).canonicalFile
        require(file.name == "fknotes.db" && file.path.startsWith(File(context.applicationInfo.dataDir).canonicalPath + "/"))
        prefs(context).edit().putString("database", file.path).putBoolean("suspended", false).commit()
        synchronize(context)
    }

    private data class Reminder(val id: String, val at: Long, val title: String = "", val document: String = "", val privateNote: Boolean = false)

    private fun read(context: Context, id: String? = null, content: Boolean = false): List<Reminder> {
        val path = prefs(context).getString("database", null) ?: return emptyList()
        if (!File(path).isFile) return emptyList()
        return SQLiteDatabase.openDatabase(path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
            // Old databases are left untouched until Dart has migrated them.
            db.rawQuery("PRAGMA table_info(notes)", null).use { columns ->
                var migrated = false
                while (columns.moveToNext()) if (columns.getString(1) == "reminder_at") migrated = true
                if (!migrated) return emptyList()
            }
            val columns = if (content) "id, reminder_at, title, document_json, is_private" else "id, reminder_at"
            val condition = if (id == null) "reminder_at > ?" else "id = ? AND reminder_at IS NOT NULL"
            db.rawQuery(
                "SELECT $columns FROM notes WHERE $condition",
                arrayOf(id ?: System.currentTimeMillis().toString()),
            ).use { rows ->
                buildList {
                    while (rows.moveToNext()) {
                        add(if (content) Reminder(rows.getString(0), rows.getLong(1), rows.getString(2), rows.getString(3), rows.getInt(4) == 1)
                            else Reminder(rows.getString(0), rows.getLong(1)))
                    }
                }
            }
        }
    }

    private fun intent(context: Context, id: String, action: String) =
        Intent(context, NoteReminderReceiver::class.java).apply {
            this.action = action
            data = Uri.parse("fknotes-reminder://note/$id")
            putExtra("id", id)
        }

    private fun cancelAlarm(context: Context, id: String) {
        PendingIntent.getBroadcast(context, 0, intent(context, id, FIRE), PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)?.let {
            alarms(context).cancel(it)
            it.cancel()
        }
    }

    private fun tracked(context: Context) = prefs(context).getStringSet("scheduled", emptySet())!!.toMutableSet()
    private fun track(context: Context, id: String, add: Boolean) {
        val ids = tracked(context)
        if (add) ids.add(id) else ids.remove(id)
        prefs(context).edit().putStringSet("scheduled", ids).commit()
    }

    private fun schedule(context: Context, reminder: Reminder): Boolean {
        if (!validId(reminder.id) || reminder.at <= System.currentTimeMillis() || access(context) != "ready") return false
        val pending = PendingIntent.getBroadcast(
            context, 0, intent(context, reminder.id, FIRE).putExtra("at", reminder.at),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // Persist tracking first so a process death cannot leave an orphan alarm.
        track(context, reminder.id, true)
        try {
            alarms(context).setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, reminder.at, pending)
        } catch (_: SecurityException) {
            cancelAlarm(context, reminder.id)
            track(context, reminder.id, false)
            return false
        }
        return true
    }

    @Synchronized
    fun syncNote(context: Context, id: String): Boolean {
        require(validId(id))
        notifications(context).cancel(id, 0)
        cancelAlarm(context, id)
        track(context, id, false)
        if (prefs(context).getBoolean("suspended", false)) return false
        val note = read(context, id).singleOrNull()
        if (note == null) prefs(context).edit().remove("delivered_$id").apply()
        return note?.let { schedule(context, it) } ?: false
    }

    @Synchronized
    fun synchronize(context: Context) {
        if (prefs(context).getBoolean("suspended", false)) return
        val future = read(context).filter { it.at > System.currentTimeMillis() }
        val ids = future.map { it.id }.toSet()
        for (id in tracked(context) - ids) {
            cancelAlarm(context, id)
            track(context, id, false)
        }
        for (note in future) {
            if (!schedule(context, note)) {
                cancelAlarm(context, note.id)
                track(context, note.id, false)
            }
        }
    }

    @Synchronized
    fun suspend(context: Context) {
        prefs(context).edit().putBoolean("suspended", true).commit()
        for (id in tracked(context)) cancelAlarm(context, id)
        prefs(context).edit().putStringSet("scheduled", emptySet()).commit()
        notifications(context).cancelAll()
    }

    private fun appLocked(context: Context): Boolean {
        val path = prefs(context).getString("database", null) ?: return true
        val file = File(File(path).parentFile, "settings/app-lock.json")
        return try {
            file.exists() && JSONObject(file.readText()).optBoolean("enabled", true)
        } catch (_: Exception) { true }
    }

    private fun preview(document: String): String = try {
        val ops = JSONObject(document).getJSONArray("delta")
        buildString {
            for (index in 0 until ops.length()) {
                val insert = ops.getJSONObject(index).opt("insert")
                if (insert is String) append(insert)
                if (length >= 200) break
            }
        }.replace(Regex("\\s+"), " ").trim().take(160)
    } catch (_: Exception) { "" }

    @Synchronized
    fun fire(context: Context, id: String, expected: Long) {
        if (!validId(id) || prefs(context).getBoolean("suspended", false)) return
        val note = read(context, id, content = true).singleOrNull() ?: return
        if (note.at != expected || prefs(context).getLong("delivered_$id", -1) == expected) return
        // A clock change must never make a future reminder fire early.
        if (note.at > System.currentTimeMillis() + 1000) {
            schedule(context, note)
            return
        }
        if (!notificationsAllowed(context)) return
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return
        launch.action = OPEN
        launch.data = Uri.parse("fknotes-reminder://note/$id")
        launch.putExtra("reminderNoteId", id)
        launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val view = PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val dismiss = PendingIntent.getBroadcast(context, 0, intent(context, id, DISMISS), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val hidden = note.privateNote || appLocked(context)
        val generic = context.getString(R.string.reminder_private_body)
        val body = if (hidden) generic else preview(note.document).ifBlank { note.title }.ifBlank { context.getString(R.string.reminder_empty_body) }
        val title = if (hidden || note.title.isBlank()) context.getString(R.string.reminder_title) else note.title.take(120)
        val publicVersion = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_note_reminder)
            .setContentTitle(context.getString(R.string.reminder_title))
            .setContentText(generic).build()
        val notification = NotificationCompat.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_note_reminder)
            .setContentTitle(title).setContentText(body)
            .setSubText(context.getString(R.string.reminder_title))
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPublicVersion(publicVersion)
            .setWhen(note.at).setShowWhen(true)
            .setContentIntent(view).setAutoCancel(true)
            .addAction(0, context.getString(R.string.reminder_dismiss), dismiss)
            .addAction(0, context.getString(R.string.reminder_view), view)
            .build()
        try {
            notifications(context).notify(id, 0, notification)
            prefs(context).edit().putLong("delivered_$id", expected).commit()
            track(context, id, false)
        } catch (_: SecurityException) { /* Notification access was revoked. */ }
    }

    fun dismiss(context: Context, id: String) {
        if (validId(id)) notifications(context).cancel(id, 0)
    }
}

class NoteReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        NoteReminders.executor.execute {
            try {
                when (intent.action) {
                    NoteReminders.FIRE -> NoteReminders.fire(context, intent.getStringExtra("id") ?: "", intent.getLongExtra("at", -1))
                    NoteReminders.DISMISS -> NoteReminders.dismiss(context, intent.getStringExtra("id") ?: "")
                    Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED,
                    Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED,
                    AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED -> NoteReminders.synchronize(context)
                }
            } catch (_: Exception) {
                // Missing/corrupt/restoring DBs must never reveal stale note text.
                android.util.Log.w("NoteReminders", "Reminder delivery or synchronization failed")
            } finally { pending.finish() }
        }
    }
}

internal class NoteReminderBridge(private val activity: Activity, messenger: BinaryMessenger) {
    companion object {
        const val NOTIFICATION_REQUEST = 7401
        const val SETTINGS_REQUEST = 7402
    }
    private val channel = MethodChannel(messenger, "fknotes/note_reminders")
    private val main = Handler(Looper.getMainLooper())
    private var pendingAccess: MethodChannel.Result? = null
    private var pendingNote: String? = null
    private var requestedSettings: String? = null

    init {
        onIntent(activity.intent, notify = false)
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestAccess" -> requestAccess(result)
                "takePendingNote" -> {
                    result.success(pendingNote)
                    pendingNote = null
                }
                "initialize", "synchronize", "syncNote", "suspend" ->
                    NoteReminders.executor.execute {
                        try {
                            val value: Any? = when (call.method) {
                                "initialize" -> {
                                    NoteReminders.initialize(activity.applicationContext, requireNotNull(call.argument<String>("databasePath")))
                                    null
                                }
                                "synchronize" -> { NoteReminders.synchronize(activity.applicationContext); null }
                                "suspend" -> { NoteReminders.suspend(activity.applicationContext); null }
                                else -> NoteReminders.syncNote(activity.applicationContext, requireNotNull(call.argument<String>("id")))
                            }
                            main.post { result.success(value) }
                        } catch (_: Exception) {
                            main.post { result.error("reminder_failed", "Could not synchronize note reminders", null) }
                        }
                    }
                else -> result.notImplemented()
            }
        }
    }

    fun onIntent(intent: Intent?, notify: Boolean = true) {
        if (intent?.action != NoteReminders.OPEN) return
        val id = intent.getStringExtra("reminderNoteId")
        if (!NoteReminders.validId(id)) return
        pendingNote = id
        // Consume the launch payload so activity recreation cannot reopen it.
        intent.removeExtra("reminderNoteId")
        NoteReminders.dismiss(activity, id!!)
        if (notify) channel.invokeMethod("reminderOpened", null)
    }

    private fun requestAccess(result: MethodChannel.Result) {
        if (pendingAccess != null) {
            result.error("reminder_busy", "Permission request already in progress", null)
            return
        }
        pendingAccess = result
        try {
            if (!NoteReminders.notificationsAllowed(activity)) {
                val prefs = activity.getSharedPreferences("note_reminders", Context.MODE_PRIVATE)
                if (Build.VERSION.SDK_INT >= 33 &&
                    activity.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED &&
                    !prefs.getBoolean("askedNotifications", false)) {
                    prefs.edit().putBoolean("askedNotifications", true).apply()
                    activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), NOTIFICATION_REQUEST)
                } else {
                    requestedSettings = "notifications"
                    activity.startActivityForResult(
                        if (Build.VERSION.SDK_INT >= 26) {
                            val action = if (NotificationManagerCompat.from(activity).areNotificationsEnabled())
                                Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS else Settings.ACTION_APP_NOTIFICATION_SETTINGS
                            Intent(action).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
                                .putExtra(Settings.EXTRA_CHANNEL_ID, NoteReminders.CHANNEL)
                        }
                        else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + activity.packageName)),
                        SETTINGS_REQUEST,
                    )
                }
            } else requestExact()
        } catch (_: Exception) { completeAccess() }
    }

    private fun requestExact() {
        if (!NoteReminders.notificationsAllowed(activity)) { completeAccess(); return }
        if (Build.VERSION.SDK_INT >= 31 && !NoteReminders.exactAllowed(activity)) {
            requestedSettings = "exact"
            try {
                activity.startActivityForResult(
                    Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:" + activity.packageName)),
                    SETTINGS_REQUEST,
                )
            } catch (_: Exception) { completeAccess() }
        } else completeAccess()
    }

    fun onPermissionsResult(requestCode: Int) {
        if (requestCode == NOTIFICATION_REQUEST && pendingAccess != null) requestExact()
    }

    fun onActivityResult(requestCode: Int) {
        if (requestCode != SETTINGS_REQUEST || pendingAccess == null) return
        val kind = requestedSettings
        requestedSettings = null
        if (kind == "notifications") requestExact() else completeAccess()
    }

    private fun completeAccess() {
        pendingAccess?.success(NoteReminders.access(activity))
        pendingAccess = null
    }

    fun dispose() {
        pendingAccess?.error("reminder_interrupted", "Permission request was interrupted", null)
        pendingAccess = null
        channel.setMethodCallHandler(null)
    }
}
