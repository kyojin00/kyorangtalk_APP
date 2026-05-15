package com.kyorang.kyorang_talk

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.kyorang.kyorang_talk/media"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "scanFile") {
                    val path = call.argument<String>("path")
                    if (path != null) {
                        val uri = Uri.fromFile(java.io.File(path))
                        val intent = Intent(Intent.ACTION_MEDIA_SCANNER_SCAN_FILE, uri)
                        sendBroadcast(intent)
                        result.success(true)
                    } else {
                        result.error("INVALID_PATH", "Path is null", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}