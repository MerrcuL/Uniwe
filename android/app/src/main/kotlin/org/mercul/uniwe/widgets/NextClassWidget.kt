package org.mercul.uniwe.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.mercul.uniwe.R

/** The class that is running or comes next: what, when and where. */
class NextClassWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val strings = WidgetSupport.localized(context, widgetData)
        val timetable = WidgetSupport.timetable(widgetData)
        val now = System.currentTimeMillis()
        val today = WidgetSupport.today()

        val ahead = timetable.events.filter { it.endMillis > now }
        val next = ahead.firstOrNull { !it.cancelled }
        // A class that would have come first but is cancelled.
        val cancelled = ahead.firstOrNull {
            it.cancelled &&
                WidgetSupport.daysBetween(today, it.day) == 0 &&
                (next == null || it.startMillis <= next.startMillis)
        }

        val views = RemoteViews(context.packageName, R.layout.widget_next_class)
        views.setOnClickPendingIntent(
            android.R.id.background,
            WidgetSupport.launch(context, "timetable"),
        )

        if (next == null) {
            val message = when {
                !timetable.signedIn -> strings.getString(R.string.widget_sign_in)
                timetable.until == null ||
                    WidgetSupport.daysBetween(today, timetable.until) < 1 ->
                    strings.getString(R.string.widget_open_to_update)
                else -> strings.getString(
                    R.string.widget_no_classes_until,
                    WidgetSupport.shortDate(timetable.until),
                )
            }
            views.setTextViewText(R.id.widget_label, strings.getString(R.string.widget_next_class_name))
            views.setTextViewText(R.id.widget_title, message)
            views.setViewVisibility(R.id.widget_time, View.GONE)
            views.setViewVisibility(R.id.widget_room, View.GONE)
        } else {
            val running = next.startMillis <= now
            val label = when {
                running -> strings.getString(R.string.widget_now_until, clock(next.end))
                next.exam -> strings.getString(
                    R.string.widget_exam_on,
                    WidgetSupport.dayName(strings, next.day, today),
                )
                else -> WidgetSupport.dayName(strings, next.day, today)
            }
            views.setTextViewText(R.id.widget_label, label)
            views.setTextViewText(R.id.widget_title, next.title)
            views.setTextViewText(R.id.widget_time, next.time)
            views.setViewVisibility(R.id.widget_time, View.VISIBLE)
            views.setTextViewText(R.id.widget_room, next.room)
            views.setViewVisibility(
                R.id.widget_room,
                if (next.room.isEmpty()) View.GONE else View.VISIBLE,
            )
        }

        if (cancelled != null) {
            views.setTextViewText(
                R.id.widget_note,
                strings.getString(R.string.widget_cancelled_title, cancelled.title),
            )
            views.setViewVisibility(R.id.widget_note, View.VISIBLE)
        } else {
            views.setViewVisibility(R.id.widget_note, View.GONE)
        }

        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, views)
        }

        // Redraw when the shown class starts or ends, at the latest at
        // midnight ("Tomorrow" becomes "Today").
        var boundary = WidgetSupport.nextMidnight()
        if (next != null) {
            val change = if (next.startMillis > now) next.startMillis else next.endMillis
            if (change < boundary) boundary = change
        }
        WidgetSupport.scheduleRefresh(context, NextClassWidget::class.java, boundary)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        WidgetSupport.cancelRefresh(context, NextClassWidget::class.java)
    }
}
