package com.signal.signal_brief

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter host activity. Besides the usual engine setup it forwards text or
 * links shared from other apps (the `ACTION_SEND` intent filter is declared in
 * AndroidManifest.xml) to Dart over the `signal/share` channel.
 */
class MainActivity : FlutterActivity() {

    private var pendingShare: String? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "signal/share")
            .also { ch ->
                ch.setMethodCallHandler { call, result ->
                    when (call.method) {
                        "getInitial" -> {
                            result.success(pendingShare)
                            pendingShare = null
                        }
                        else -> result.notImplemented()
                    }
                }
            }

        // A share that launched the app arrives in the creation intent.
        handleShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // App was already running; deliver the new share straight away.
        handleShare(intent)
    }

    private fun handleShare(intent: Intent?) {
        if (intent == null) return
        if (intent.action != Intent.ACTION_SEND && intent.action != Intent.ACTION_VIEW) return

        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
            ?: intent.getStringExtra(Intent.EXTRA_SUBJECT)
            ?: intent.dataString
        if (text.isNullOrBlank()) return

        val ch = channel
        if (ch != null) {
            ch.invokeMethod("shared", text)
        } else {
            // Engine not ready yet; hand it over when Dart asks.
            pendingShare = text
        }
    }
}
