package org.mercul.uniwe.widgets

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetProvider
import org.json.JSONArray
import org.mercul.uniwe.R
import java.util.Calendar

/** The main dishes of the canteen today, or on its next open day. */
class MensaWidget : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val strings = WidgetSupport.localized(context, widgetData)
        val data = WidgetSupport.mensa(widgetData)
        val today = WidgetSupport.today()
        val campus = data.optString("campus", "")

        // The first day that is not over.
        var day: Calendar? = null
        val meals = mutableListOf<WidgetMeal>()
        val days = data.optJSONArray("days") ?: JSONArray()
        for (i in 0 until days.length()) {
            val entry = days.optJSONObject(i) ?: continue
            val date = WidgetSupport.parseDay(entry.optString("date")) ?: continue
            if (WidgetSupport.daysBetween(today, date) < 0) continue
            val list = entry.optJSONArray("meals") ?: continue
            for (j in 0 until list.length()) {
                val meal = list.optJSONObject(j) ?: continue
                meals.add(WidgetMeal(meal.optString("name"), meal.optString("price")))
            }
            if (meals.isNotEmpty()) {
                day = date
                break
            }
        }

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.widget_list)
            views.setOnClickPendingIntent(
                android.R.id.background,
                WidgetSupport.launch(context, "mensa"),
            )
            views.removeAllViews(R.id.widget_rows)
            views.setTextViewText(
                R.id.widget_header,
                if (campus.isEmpty()) {
                    strings.getString(R.string.widget_mensa_name)
                } else {
                    "${strings.getString(R.string.widget_mensa_name)} $campus"
                },
            )

            if (day == null) {
                views.setTextViewText(R.id.widget_subheader, "")
                views.setTextViewText(R.id.widget_empty, strings.getString(R.string.widget_no_menu))
                views.setViewVisibility(R.id.widget_empty, View.VISIBLE)
                views.setViewVisibility(R.id.widget_more, View.GONE)
            } else {
                views.setTextViewText(
                    R.id.widget_subheader,
                    "${WidgetSupport.dayName(strings, day, today)}, ${WidgetSupport.shortDate(day)}",
                )
                views.setViewVisibility(R.id.widget_empty, View.GONE)

                val rows = WidgetSupport.rowsThatFit(
                    appWidgetManager.getAppWidgetOptions(id),
                    headerDp = 60,
                    rowDp = 44,
                    fallback = 3,
                )
                val shown = if (meals.size > rows) maxOf(rows - 1, 1) else meals.size
                for (meal in meals.take(shown)) {
                    val row = RemoteViews(context.packageName, R.layout.widget_row_meal)
                    row.setTextViewText(R.id.widget_row_title, meal.name)
                    row.setTextViewText(R.id.widget_row_price, meal.price)
                    row.setViewVisibility(
                        R.id.widget_row_price,
                        if (meal.price.isEmpty()) View.GONE else View.VISIBLE,
                    )
                    views.addView(R.id.widget_rows, row)
                }
                if (meals.size > shown) {
                    views.setTextViewText(
                        R.id.widget_more,
                        strings.getString(R.string.widget_more, meals.size - shown),
                    )
                    views.setViewVisibility(R.id.widget_more, View.VISIBLE)
                } else {
                    views.setViewVisibility(R.id.widget_more, View.GONE)
                }
            }
            appWidgetManager.updateAppWidget(id, views)
        }

        WidgetSupport.scheduleRefresh(
            context,
            MensaWidget::class.java,
            WidgetSupport.nextMidnight(),
        )
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        onUpdate(context, appWidgetManager, intArrayOf(appWidgetId))
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        WidgetSupport.cancelRefresh(context, MensaWidget::class.java)
    }
}
