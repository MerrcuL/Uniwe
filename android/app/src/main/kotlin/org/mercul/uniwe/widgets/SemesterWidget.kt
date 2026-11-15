package org.mercul.uniwe.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.mercul.uniwe.R
import java.util.Calendar

/**
 * How far the teaching period has come, and what is due next: the next
 * registered exam, else the next date of the academic calendar.
 */
class SemesterWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val strings = WidgetSupport.localized(context, widgetData)
        val data = WidgetSupport.semester(widgetData)
        val today = WidgetSupport.today()
        val start = WidgetSupport.parseDay(data.optString("start", ""))
        val end = WidgetSupport.parseDay(data.optString("end", ""))

        val views = RemoteViews(context.packageName, R.layout.widget_semester)
        views.setOnClickPendingIntent(
            android.R.id.background,
            WidgetSupport.launch(context, "semester"),
        )
        views.setTextViewText(
            R.id.widget_label,
            data.optString("name", "").ifEmpty { strings.getString(R.string.widget_semester_name) },
        )

        var progress = -1
        val headline: String = when {
            start == null || end == null ->
                strings.getString(R.string.widget_open_to_update)
            WidgetSupport.daysBetween(today, start) > 0 -> strings.getString(
                R.string.widget_lectures_start,
                WidgetSupport.inDays(strings, WidgetSupport.daysBetween(today, start)),
            )
            WidgetSupport.daysBetween(end, today) > 0 ->
                strings.getString(R.string.widget_lectures_over)
            else -> {
                // Weeks run Monday to Sunday, like the timetable.
                val firstMonday = (start.clone() as Calendar).apply {
                    add(Calendar.DAY_OF_MONTH, -((get(Calendar.DAY_OF_WEEK) + 5) % 7))
                }
                val week = WidgetSupport.daysBetween(firstMonday, today) / 7 + 1
                val total = WidgetSupport.daysBetween(firstMonday, end) / 7 + 1
                val days = WidgetSupport.daysBetween(start, end) + 1
                progress = WidgetSupport.daysBetween(start, today) * 1000 / days
                strings.getString(R.string.widget_week_of, week, total)
            }
        }
        views.setTextViewText(R.id.widget_title, headline)
        if (progress >= 0) {
            views.setProgressBar(R.id.widget_progress, 1000, progress, false)
            views.setViewVisibility(R.id.widget_progress, View.VISIBLE)
            views.setTextViewText(R.id.widget_percent, "${progress / 10} %")
            views.setViewVisibility(R.id.widget_percent, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.widget_progress, View.GONE)
            views.setViewVisibility(R.id.widget_percent, View.GONE)
        }

        // What is due next.
        val exam = WidgetSupport.exams(widgetData)
            .firstOrNull { WidgetSupport.daysBetween(today, it.day) >= 0 }
        var entry: WidgetDated? = null
        val next = data.optJSONArray("next") ?: JSONArray()
        for (i in 0 until next.length()) {
            val item = next.optJSONObject(i) ?: continue
            val day = WidgetSupport.parseDay(item.optString("date")) ?: continue
            if (WidgetSupport.daysBetween(today, day) < 0) continue
            entry = WidgetDated(item.optString("label"), day, item.optBoolean("active"))
            break
        }

        val note: String? = when {
            exam != null -> strings.getString(
                R.string.widget_exam_in,
                exam.label,
                WidgetSupport.inDays(strings, WidgetSupport.daysBetween(today, exam.day)),
            )
            entry != null -> {
                val days = WidgetSupport.daysBetween(today, entry.day)
                val time = if (entry.active) {
                    strings.getString(R.string.widget_until, WidgetSupport.shortDate(entry.day))
                } else {
                    WidgetSupport.inDays(strings, days)
                }
                "${entry.label} · $time"
            }
            else -> null
        }
        if (note == null) {
            views.setViewVisibility(R.id.widget_note, View.GONE)
        } else {
            views.setTextViewText(R.id.widget_note, note)
            views.setViewVisibility(R.id.widget_note, View.VISIBLE)
        }

        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, views)
        }
        WidgetSupport.scheduleRefresh(
            context,
            SemesterWidget::class.java,
            WidgetSupport.nextMidnight(),
        )
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        WidgetSupport.cancelRefresh(context, SemesterWidget::class.java)
    }
}
