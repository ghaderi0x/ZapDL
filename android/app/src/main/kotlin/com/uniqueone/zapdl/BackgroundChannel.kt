package com.uniqueone.zapdl

import android.content.Context
import android.content.Intent
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Bridges Dart (`dev.zapdl/background`) to [DownloadService]. */
class BackgroundChannel(private val context: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "update" -> {
                val intent = Intent(context, DownloadService::class.java)
                    .putExtra("title", call.argument<String>("title"))
                    .putExtra("text", call.argument<String>("text"))
                    .putExtra("progress", call.argument<Int>("progress") ?: -1)
                try {
                    if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
                    else context.startService(intent)
                    result.success(null)
                } catch (e: Exception) {
                    // e.g. Android 12+ refuses to start a foreground service from the background.
                    result.error("start_failed", e.message, null)
                }
            }
            "stop" -> {
                context.stopService(Intent(context, DownloadService::class.java))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
