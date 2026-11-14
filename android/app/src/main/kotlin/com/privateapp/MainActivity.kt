package com.privateapp

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** FlutterFragmentActivity is required because BiometricPrompt hosts its UI in a Fragment. */
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PlatformChannel.NAME)
            .setMethodCallHandler(PlatformChannel(this))
    }
}
