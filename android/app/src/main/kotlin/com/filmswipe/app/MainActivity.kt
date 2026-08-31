package com.filmswipe.app

import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.filmswipe.app/share",
        ).setMethodCallHandler { call, result ->
            if (call.method != "shareText") {
                result.notImplemented()
                return@setMethodCallHandler
            }

            val text = call.argument<String>("text")?.trim()
            val title = call.argument<String>("title")?.trim().orEmpty()
            if (text.isNullOrEmpty()) {
                result.error("invalid-argument", "No hay contenido para compartir.", null)
                return@setMethodCallHandler
            }

            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
                putExtra(Intent.EXTRA_TITLE, title)
            }
            startActivity(Intent.createChooser(shareIntent, title))
            result.success(null)
        }
    }
}
