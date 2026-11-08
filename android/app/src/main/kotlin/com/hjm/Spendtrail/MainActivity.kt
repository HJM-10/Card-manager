package com.hjm.Spendtrail

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var vault: BiometricVault? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                "spendtrail_transactions", "Transaction alerts", NotificationManager.IMPORTANCE_HIGH
            )
            channel.description = "Purchase, decline and refund alerts"
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
        }
        vault = BiometricVault(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "spendtrail/biometric")
            .setMethodCallHandler { call, result -> vault!!.handle(call, result) }
    }
    override fun onDestroy() {
        vault?.cancel()
        super.onDestroy()
    }
}
