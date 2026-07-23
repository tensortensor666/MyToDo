package com.tensortensor666.mytodo

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class TodoAppWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { widgetId ->
            appWidgetManager.updateAppWidget(widgetId, buildViews(context))
        }
    }

    companion object {
        private const val PREFERENCES_NAME = "mytodo_home_widget"
        private const val SNAPSHOT_KEY = "snapshot"

        private val rowIds = intArrayOf(
            R.id.widget_task_1,
            R.id.widget_task_2,
            R.id.widget_task_3,
            R.id.widget_task_4,
            R.id.widget_task_5,
        )
        private val titleIds = intArrayOf(
            R.id.widget_task_title_1,
            R.id.widget_task_title_2,
            R.id.widget_task_title_3,
            R.id.widget_task_title_4,
            R.id.widget_task_title_5,
        )
        private val metaIds = intArrayOf(
            R.id.widget_task_meta_1,
            R.id.widget_task_meta_2,
            R.id.widget_task_meta_3,
            R.id.widget_task_meta_4,
            R.id.widget_task_meta_5,
        )

        fun saveSnapshot(context: Context, snapshot: String) {
            context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(SNAPSHOT_KEY, snapshot)
                .apply()
        }

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, TodoAppWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach { widgetId ->
                manager.updateAppWidget(widgetId, buildViews(context))
            }
        }

        private fun buildViews(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.todo_home_widget)
            val snapshot = readSnapshot(context)
            val tasks = snapshot.optJSONArray("tasks")
            val activeCount = snapshot.optInt("activeCount", tasks?.length() ?: 0)
            val shownCount = minOf(tasks?.length() ?: 0, rowIds.size)

            views.setTextViewText(R.id.widget_count, "$activeCount 条未完成")
            views.setViewVisibility(
                R.id.widget_empty,
                if (shownCount == 0) View.VISIBLE else View.GONE,
            )
            views.setOnClickPendingIntent(R.id.widget_root, openAppIntent(context, 0))

            rowIds.indices.forEach { index ->
                if (index >= shownCount) {
                    views.setViewVisibility(rowIds[index], View.GONE)
                    return@forEach
                }
                val task = tasks?.optJSONObject(index) ?: JSONObject()
                views.setViewVisibility(rowIds[index], View.VISIBLE)
                views.setTextViewText(titleIds[index], task.optString("title", "未命名任务"))
                views.setTextViewText(metaIds[index], taskMeta(task))
                val important = task.optBoolean("important", false)
                views.setTextColor(
                    titleIds[index],
                    if (important) Color.rgb(166, 70, 43) else Color.rgb(20, 20, 19),
                )
                views.setOnClickPendingIntent(
                    rowIds[index],
                    openAppIntent(context, index + 1),
                )
            }
            return views
        }

        private fun readSnapshot(context: Context): JSONObject {
            val raw = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
                .getString(SNAPSHOT_KEY, null)
                ?: return JSONObject()
            return try {
                JSONObject(raw)
            } catch (_: Exception) {
                JSONObject()
            }
        }

        private fun taskMeta(task: JSONObject): String {
            val parts = mutableListOf(task.optString("listName", "收件箱"))
            if (!task.isNull("dueAt")) {
                val dueAt = task.optLong("dueAt")
                val label = if (dueAt < System.currentTimeMillis()) {
                    "已逾期"
                } else {
                    SimpleDateFormat("M月d日 HH:mm", Locale.getDefault())
                        .format(Date(dueAt))
                }
                parts.add(label)
            }
            return parts.joinToString(" · ")
        }

        private fun openAppIntent(context: Context, requestCode: Int): PendingIntent {
            val intent = Intent(context, MainActivity::class.java).apply {
                action = "com.tensortensor666.mytodo.OPEN_WIDGET_$requestCode"
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            return PendingIntent.getActivity(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
