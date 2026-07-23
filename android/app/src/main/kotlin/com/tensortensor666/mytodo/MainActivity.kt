package com.tensortensor666.mytodo

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HOME_WIDGET_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateWidget" -> {
                    val snapshot = call.arguments as? String
                    if (snapshot == null) {
                        result.error("invalid_snapshot", "Widget snapshot is missing", null)
                        return@setMethodCallHandler
                    }
                    TodoAppWidgetProvider.saveSnapshot(this, snapshot)
                    TodoAppWidgetProvider.updateAll(this)
                    result.success(null)
                }
                "requestPinWidget" -> result.success(requestPinWidget())
                else -> result.notImplemented()
            }
        }
    }

    private fun requestPinWidget(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return false
        }
        val manager = AppWidgetManager.getInstance(this)
        if (!manager.isRequestPinAppWidgetSupported) {
            return false
        }
        return manager.requestPinAppWidget(
            ComponentName(this, TodoAppWidgetProvider::class.java),
            null,
            null,
        )
    }

    companion object {
        private const val HOME_WIDGET_CHANNEL =
            "com.tensortensor666.mytodo/home_widget"
    }
}
