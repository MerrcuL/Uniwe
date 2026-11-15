package org.mercul.uniwe.widgets

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.res.Configuration
import android.net.Uri
import android.os.Bundle
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import org.json.JSONArray
import org.json.JSONObject
import org.mercul.uniwe.MainActivity
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import kotlin.math.roundToInt

// Shared by all home screen widgets. The app (HomeWidgetService in Dart)
// leaves JSON strings in the widget preferences; the widgets are drawn from
// those at any later time, so everything relative to "now" (which class is
// next, how many days are left) is worked out here.

/** One class of the timetable on a concrete day. */
class WidgetEvent(
    val day: Calendar,
    val title: String,
    val start: Int,
    val end: Int,
    val room: String,
    val exam: Boolean,
    val cancelled: Boolean,
) {
    /** Start and end as points in time. */
    val startMillis: Long get() = day.timeInMillis + start * 60_000L
    val endMillis: Long get() = day.timeInMillis + end * 60_000L

    val time: String get() = "${clock(start)} – ${clock(end)}"
}

class WidgetTimetable(
    val signedIn: Boolean,
    /** Last day the data covers, or null when there is none. */
    val until: Calendar?,
    val events: List<WidgetEvent>,
)

class WidgetMeal(val name: String, val price: String)

class WidgetDated(val label: String, val day: Calendar, val active: Boolean = false)

object WidgetSupport {
    private const val DAY_MILLIS = 86_400_000.0

    /** A context whose strings are in the language chosen inside the app. */
    fun localized(context: Context, prefs: SharedPreferences): Context {
        val language = prefs.getString("locale", null) ?: return context
        val config = Configuration(context.resources.configuration)
        config.setLocale(Locale(language))
        return context.createConfigurationContext(config)
    }

    fun locale(context: Context): Locale =
        context.resources.configuration.locales[0] ?: Locale.getDefault()

    fun today(): Calendar = Calendar.getInstance().apply {
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }

    /** Parses "2026-11-16" as local midnight. */
    fun parseDay(text: String?): Calendar? {
        val parts = text?.split("-") ?: return null
        if (parts.size != 3) return null
        return try {
            today().apply {
                set(parts[0].toInt(), parts[1].toInt() - 1, parts[2].toInt())
            }
        } catch (e: NumberFormatException) {
            null
        }
    }

    /** Whole days from [from] to [to]; rounding absorbs DST changes. */
    fun daysBetween(from: Calendar, to: Calendar): Int =
        ((to.timeInMillis - from.timeInMillis) / DAY_MILLIS).roundToInt()

    private fun json(prefs: SharedPreferences, key: String): String? =
        prefs.getString(key, null)?.takeIf { it.isNotEmpty() }

    fun timetable(prefs: SharedPreferences): WidgetTimetable {
        val events = mutableListOf<WidgetEvent>()
        var signedIn = false
        var until: Calendar? = null
        try {
            val root = JSONObject(json(prefs, "timetable") ?: "{}")
            signedIn = root.optBoolean("signedIn", false)
            until = parseDay(root.optString("until", ""))
            val days = root.optJSONArray("days") ?: JSONArray()
            for (i in 0 until days.length()) {
                val dayObject = days.getJSONObject(i)
                val day = parseDay(dayObject.optString("date")) ?: continue
                val list = dayObject.optJSONArray("events") ?: continue
                for (j in 0 until list.length()) {
                    val e = list.getJSONObject(j)
                    events.add(
                        WidgetEvent(
                            day = day,
                            title = e.optString("title"),
                            start = e.optInt("start"),
                            end = e.optInt("end"),
                            room = e.optString("room"),
                            exam = e.optBoolean("exam"),
                            cancelled = e.optBoolean("cancelled"),
                        ),
                    )
                }
            }
        } catch (e: Exception) {
            // Unreadable data is no data.
        }
        events.sortBy { it.startMillis }
        return WidgetTimetable(signedIn, until, events)
    }

    /** Upcoming exams with a date, soonest first. */
    fun exams(prefs: SharedPreferences): List<WidgetDated> {
        val result = mutableListOf<WidgetDated>()
        try {
            val list = JSONArray(json(prefs, "exams") ?: "[]")
            for (i in 0 until list.length()) {
                val e = list.getJSONObject(i)
                val day = parseDay(e.optString("date")) ?: continue
                result.add(WidgetDated(e.optString("name"), day))
            }
        } catch (e: Exception) {
            // Unreadable data is no data.
        }
        return result
    }

    fun semester(prefs: SharedPreferences): JSONObject = try {
        JSONObject(json(prefs, "semester") ?: "{}")
    } catch (e: Exception) {
        JSONObject()
    }

    fun mensa(prefs: SharedPreferences): JSONObject = try {
        JSONObject(json(prefs, "mensa") ?: "{}")
    } catch (e: Exception) {
        JSONObject()
    }

    /** "Today", "Tomorrow" or the weekday of [day]. */
    fun dayName(context: Context, day: Calendar, today: Calendar): String =
        when (daysBetween(today, day)) {
            0 -> context.getString(org.mercul.uniwe.R.string.widget_today)
            1 -> context.getString(org.mercul.uniwe.R.string.widget_tomorrow)
            else -> SimpleDateFormat("EEEE", locale(context)).format(day.time)
        }

    /** "16.11." */
    fun shortDate(day: Calendar): String =
        String.format(
            Locale.ROOT,
            "%02d.%02d.",
            day.get(Calendar.DAY_OF_MONTH),
            day.get(Calendar.MONTH) + 1,
        )

    /** "today", "tomorrow", "in 12 days". */
    fun inDays(context: Context, days: Int): String = when {
        days <= 0 -> context.getString(org.mercul.uniwe.R.string.widget_today_lower)
        days == 1 -> context.getString(org.mercul.uniwe.R.string.widget_tomorrow_lower)
        else -> context.getString(org.mercul.uniwe.R.string.widget_in_days, days)
    }

    /** Opens the app at [destination] (an id of the app's navigation). */
    fun launch(context: Context, destination: String): PendingIntent =
        HomeWidgetLaunchIntent.getActivity(
            context,
            MainActivity::class.java,
            Uri.parse("uniwe://open/$destination"),
        )

    /** How many list rows fit into the widget at its current size. */
    fun rowsThatFit(
        options: Bundle?,
        headerDp: Int,
        rowDp: Int,
        fallback: Int,
    ): Int {
        // In portrait a widget is as tall as its maximum height.
        val height = options?.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT) ?: 0
        if (height <= 0) return fallback
        return ((height - headerDp) / rowDp).coerceIn(1, 10)
    }

    private fun refreshIntent(context: Context, widget: Class<*>): PendingIntent {
        val ids = AppWidgetManager.getInstance(context)
            .getAppWidgetIds(ComponentName(context, widget))
        val intent = Intent(context, widget)
            .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        return PendingIntent.getBroadcast(
            context,
            widget.name.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /**
     * Redraws [widget] at about [atMillis] — when the class that is shown
     * starts or ends, or the day changes. Inexact on purpose: it needs no
     * permission and does not wake the device.
     */
    fun scheduleRefresh(context: Context, widget: Class<*>, atMillis: Long) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        try {
            alarms.set(AlarmManager.RTC, atMillis + 20_000L, refreshIntent(context, widget))
        } catch (e: SecurityException) {
            // The periodic update still comes.
        }
    }

    fun cancelRefresh(context: Context, widget: Class<*>) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        alarms.cancel(refreshIntent(context, widget))
    }

    fun nextMidnight(): Long = today().apply { add(Calendar.DAY_OF_MONTH, 1) }.timeInMillis
}

/** Minutes since midnight as "08:05". */
fun clock(minutes: Int): String =
    String.format(Locale.ROOT, "%02d:%02d", minutes / 60, minutes % 60)
