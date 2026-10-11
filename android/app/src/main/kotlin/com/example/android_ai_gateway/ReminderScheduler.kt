package com.example.android_ai_gateway

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

internal object ReminderScheduler {
    private const val TAG = "Reminder"
    private const val PREFS = "reminders"
    private const val ITEMS = "items"

    @Synchronized
    fun create(context: Context, message: String, delayMinutes: Int): Map<String, Any> {
        require(message.isNotBlank()) { "Reminder message is empty" }
        require(delayMinutes in 1..43_200) { "Reminder delay is out of range" }

        val id = UUID.randomUUID().toString()
        val scheduledAt = System.currentTimeMillis() + delayMinutes * 60_000L
        val reminder = JSONObject()
            .put("id", id)
            .put("message", message.trim())
            .put("scheduledAt", scheduledAt)

        val items = readItems(context).put(reminder)
        writeItems(context, items)
        schedule(context, id, message.trim(), scheduledAt)
        val notificationsEnabled = notificationsEnabled(context)
        Log.i(TAG, "created id=$id delay_min=$delayMinutes notifications=$notificationsEnabled")
        return mapOf(
            "success" to true,
            "id" to id,
            "message" to message.trim(),
            "scheduledAt" to scheduledAt,
            "notificationsEnabled" to notificationsEnabled,
        )
    }

    @Synchronized
    fun cancel(context: Context, id: String): Boolean {
        val items = readItems(context)
        var removed = false
        val kept = JSONArray()
        for (index in 0 until items.length()) {
            val reminder = items.optJSONObject(index) ?: continue
            if (reminder.optString("id") == id) {
                removed = true
            } else {
                kept.put(reminder)
            }
        }
        if (removed) {
            alarmManager(context)?.cancel(pendingIntent(context, id, ""))
            pendingIntent(context, id, "").cancel()
            writeItems(context, kept)
            Log.i(TAG, "cancelled id=$id")
        }
        return removed
    }

    @Synchronized
    fun list(context: Context): List<Map<String, Any>> = buildList {
        val items = readItems(context)
        for (index in 0 until items.length()) {
            val item = items.optJSONObject(index) ?: continue
            add(
                mapOf(
                    "id" to item.optString("id"),
                    "message" to item.optString("message"),
                    "scheduledAt" to item.optLong("scheduledAt"),
                    "notificationsEnabled" to notificationsEnabled(context),
                )
            )
        }
    }

    @Synchronized
    fun onAlarmFired(context: Context, id: String) {
        val items = readItems(context)
        val kept = JSONArray()
        for (index in 0 until items.length()) {
            val reminder = items.optJSONObject(index) ?: continue
            if (reminder.optString("id") != id) kept.put(reminder)
        }
        writeItems(context, kept)
    }

    @Synchronized
    fun rescheduleAll(context: Context) {
        val items = readItems(context)
        for (index in 0 until items.length()) {
            val item = items.optJSONObject(index) ?: continue
            schedule(
                context,
                item.optString("id"),
                item.optString("message"),
                item.optLong("scheduledAt"),
            )
        }
    }

    fun notificationsEnabled(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
            android.content.pm.PackageManager.PERMISSION_GRANTED

    private fun schedule(context: Context, id: String, message: String, scheduledAt: Long) {
        val alarm = alarmManager(context) ?: error("AlarmManager unavailable")
        alarm.setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            scheduledAt,
            pendingIntent(context, id, message),
        )
    }

    private fun pendingIntent(context: Context, id: String, message: String): PendingIntent {
        val intent = Intent(context, ReminderReceiver::class.java)
            .setAction("$TAG.FIRE")
            .setData(Uri.parse("reminder://$id"))
            .putExtra("id", id)
            .putExtra("message", message)
        val requestCode = id.toIntOrNull() ?: id.hashCode()
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun alarmManager(context: Context): AlarmManager? =
        context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager

    private fun readItems(context: Context): JSONArray = try {
        JSONArray(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(ITEMS, "[]"))
    } catch (_: Exception) {
        JSONArray()
    }

    private fun writeItems(context: Context, items: JSONArray) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(ITEMS, items.toString())
            .commit()
    }
}
