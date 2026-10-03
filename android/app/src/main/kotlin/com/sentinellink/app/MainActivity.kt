package com.sentinellink.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.PowerManager
import android.net.Uri
import android.provider.Settings

class MainActivity : FlutterActivity() {
    private var visible = false
    private var notificationPending = false
    private var backgroundSetupReady = false
    override fun onResume() {
        super.onResume(); visible = true
        window.decorView.post { prepareBackgroundPower() }
    }
    override fun onPause() { visible = false; super.onPause() }

    private fun prepareBackgroundPower() {
        if (!visible || !backgroundSetupReady || notificationPending || DutyLocationService.instance?.trackingDuty != true) return
        val power = getSystemService(POWER_SERVICE) as PowerManager
        val preferences = getSharedPreferences("duty_location_setup", MODE_PRIVATE)
        if (power.isIgnoringBatteryOptimizations(packageName) || preferences.getBoolean("powerRequested", false)) return
        // Guard safety tracking is the core on-duty function. Android asks the
        // person once; declining never creates a repeated prompt or retry loop.
        preferences.edit().putBoolean("powerRequested", true).apply()
        try { startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
            Uri.parse("package:$packageName"))) }
        catch (_: android.content.ActivityNotFoundException) { /* OEM settings may differ. */ }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 4107) {
            notificationPending = false
            window.decorView.post { prepareBackgroundPower() }
        }
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "sentinel/duty_location").setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    val end = call.argument<Number>("dutyEnd")?.toLong()
                    DutyLocationService.instance?.configure(end)
                    if (end != null && end > System.currentTimeMillis()) {
                        window.decorView.post { prepareBackgroundPower() }
                    }
                    result.success(null)
                }
                "notificationPermission" -> {
                    backgroundSetupReady = true
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        notificationPending = true
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4107)
                    } else prepareBackgroundPower()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        EventChannel(messenger, "sentinel/duty_location/positions").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                DutyLocationService.sink = events
                val end = ((arguments as? Map<*, *>)?.get("dutyEnd") as? Number)?.toLong()
                val existing = DutyLocationService.instance
                if (existing != null) { existing.configure(end); return }
                val intent = Intent(applicationContext, DutyLocationService::class.java)
                    .putExtra("dutyEnd", end ?: 0L)
                try {
                    if (Build.VERSION.SDK_INT >= 26) applicationContext.startForegroundService(intent)
                    else applicationContext.startService(intent)
                } catch (error: Exception) {
                    events.error("location_start", "Could not start duty location: ${error.javaClass.simpleName}", null)
                    DutyLocationService.sink = null
                }
            }
            override fun onCancel(arguments: Any?) {
                DutyLocationService.sink = null
                applicationContext.stopService(Intent(applicationContext, DutyLocationService::class.java))
            }
        })
    }
}
