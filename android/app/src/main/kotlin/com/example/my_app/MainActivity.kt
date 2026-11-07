package com.example.my_app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var vault: BiometricVault? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        vault = BiometricVault(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "spendtrail/biometric")
            .setMethodCallHandler { call, result -> vault!!.handle(call, result) }
    }
    override fun onDestroy() {
        vault?.cancel()
        super.onDestroy()
    }
}
