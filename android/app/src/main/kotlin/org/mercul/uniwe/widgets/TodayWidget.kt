package org.mercul.uniwe.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Paint
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.mercul.uniwe.R

/** The classes of today — or of the next day that has any. */
class TodayWidget : HomeWidgetProvider() {
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

        // The day of the first class that is not over yet.
        val day = timetable.events.firstOrNull { it.endMillis > now }?.day
        val events = if (day == null) {
            emptyList()
        } else {
            timetable.events.filter {
                it.day.timeInMillis == day.timeInMillis && it.endMillis > now
            }
        }

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_list)
            views.setOnClickPendingIntent(
                android.R.id.background,
                WidgetSupport.launch(context, "timetable"),
            )
            views.removeAllViews(R.id.widget_rows)

            if (day == null) {
                views.setTextViewText(R.id.widget_header, strings.getString(R.string.widget_today_name))
                views.setTextViewText(R.id.widget_subheader, "")
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
                views.setTextViewText(R.id.widget_empty, message)
                views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
                views.setViewVisibility(R.id.widget_more, View.GONE)
            } else {
                views.setTextViewText(
                    R.id.widget_header,
                    WidgetSupport.dayName(strings, day, today),
                )
                views.setTextViewText(R.id.widget_subheader, WidgetSupport.shortDate(day))
                views.setViewVisibility(R.id.widget_empty, View.GONE)

                val rows = WidgetSupport.rowsThatFit(
                    appWidgetManager.getAppWidgetOptions(id),
                    headerDp = 60,
                    rowDp = 48,
                    fallback = 3,
                )
                // Leave the last row to "+2 more" when not everything fits.
                val shown = if (events.size > rows) maxOf(rows - 1, 1) else events.size
                for (event in events.take(shown)) {
                    val row = RemoteViews(
                        context.packageName,
                        when {
                            event.cancelled -> R.layout.widget_row_class_cancelled
                            event.exam -> R.layout.widget_row_class_exam
                            else -> R.layout.widget_row_class
                        },
                    )
                    row.setTextViewText(R.id.widget_row_start, clock(event.start))
                    row.setTextViewText(R.id.widget_row_end, clock(event.end))
                    row.setTextViewText(R.id.widget_row_title, event.title)
                    row.setTextViewText(
                        R.id.widget_row_detail,
                        if (event.cancelled) {
                            strings.getString(R.string.widget_cancelled)
                        } else {
                            event.room
                        },
                    )
                    if (event.cancelled) {
                        row.setInt(
                            R.id.widget_row_title,
                            "setPaintFlags",
                            Paint.STRIKE_THRU_TEXT_FLAG or Paint.ANTI_ALIAS_FLAG,
                        )
                    }
                    views.addView(R.id.widget_rows, row)
                }
                if (events.size > shown) {
                    views.setTextViewText(
                        R.id.widget_more,
                        strings.getString(R.string.widget_more, events.size - shown),
                    )
                    views.setViewVisibility(R.id.widget_more, View.VISIBLE)
                } else {
                    views.setViewVisibility(R.id.widget_more, View.GONE)
                }
            }
            appWidgetManager.updateAppWidget(id, views)
        }

        // Redraw when the first listed class is over, at the latest at
        // midnight.
        var boundary = WidgetSupport.nextMidnight()
        events.firstOrNull()?.let { if (it.endMillis < boundary) boundary = it.endMillis }
        WidgetSupport.scheduleRefresh(context, TodayWidget::class.java, boundary)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        // Resized: a different number of rows fits.
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId))
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        WidgetSupport.cancelRefresh(context, TodayWidget::class.java)
    }
}
