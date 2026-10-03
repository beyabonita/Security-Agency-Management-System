package com.sentinellink.app

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.wifi.WifiManager
import android.os.*
import io.flutter.plugin.common.EventChannel

/** Keeps providers alive during acquisition and screen lock. Never stores GPS. */
class DutyLocationService : Service() {
    companion object {
        var sink: EventChannel.EventSink? = null
        var instance: DutyLocationService? = null
            private set
        private const val CHANNEL = "duty_location"
        private const val NOTIFICATION = 4107
    }
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var locations: LocationManager
    private val listeners = mutableMapOf<String, LocationListener>()
    private val providerFixes = mutableMapOf<String, Long>()
    private var last: Location? = null
    private var deadline = 0L
    private var onDuty = false
    val trackingDuty: Boolean get() = onDuty && System.currentTimeMillis() < deadline
    private var wakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private val expiry = Runnable { finish() }
    private val recovery = object : Runnable {
        override fun run() {
            if (System.currentTimeMillis() >= deadline) { finish(); return }
            // Re-register only a silent provider. Keep the foreground service,
            // other providers, and their in-progress GPS acquisition alive.
            availableProviders().forEach { provider ->
                if (SystemClock.elapsedRealtime() - (providerFixes[provider] ?: 0L) > 120_000) {
                    listeners.remove(provider)?.let { locations.removeUpdates(it) }
                    register(provider)
                }
            }
            handler.postDelayed(this, 30_000)
        }
    }

    override fun onCreate() {
        super.onCreate()
        instance = this
        locations = getSystemService(LOCATION_SERVICE) as LocationManager
        if (Build.VERSION.SDK_INT >= 26) {
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).createNotificationChannel(
                NotificationChannel(CHANNEL, "Duty location", NotificationManager.IMPORTANCE_LOW)
            )
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val end = intent?.getLongExtra("dutyEnd", 0L) ?: 0L
        configure(end.takeIf { it > 0 })
        if (deadline <= System.currentTimeMillis()) { finish(); return START_NOT_STICKY }
        try {
            if (Build.VERSION.SDK_INT >= 29) startForeground(NOTIFICATION, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
            else startForeground(NOTIFICATION, notification())
            acquireLocks()
            availableProviders().forEach { register(it) }
            handler.removeCallbacks(recovery)
            handler.postDelayed(recovery, 30_000)
        } catch (error: SecurityException) {
            sink?.error("location_permission", "Location permission is required for duty tracking.", null)
            finish()
        }
        // A stopped/killed process must not resurrect an unverified duty.
        return START_NOT_STICKY
    }

    fun configure(end: Long?) {
        onDuty = end != null
        // Attendance acquisition is temporary. Only a verified duty can extend
        // collection through a full shift; UI requests renew this short lease.
        deadline = end ?: (System.currentTimeMillis() + 120_000)
        handler.removeCallbacks(expiry)
        handler.postDelayed(expiry, (deadline - System.currentTimeMillis()).coerceAtLeast(0))
        if (wakeLock != null) (getSystemService(NOTIFICATION_SERVICE) as NotificationManager).notify(NOTIFICATION, notification())
    }

    private fun availableProviders() = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER, "fused")
        .filter { locations.allProviders.contains(it) }

    @Suppress("MissingPermission")
    private fun register(provider: String) {
        if (listeners.containsKey(provider)) return
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) { accept(location) }
            override fun onProviderEnabled(name: String) {
                // This listener stays registered while GPS is toggled off/on.
                providerFixes[name] = SystemClock.elapsedRealtime()
            }
            override fun onProviderDisabled(name: String) { }
            @Deprecated("Android compatibility callback")
            override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) { }
        }
        try {
            locations.requestLocationUpdates(provider, 5_000L, 0f, listener, Looper.getMainLooper())
            listeners[provider] = listener
            providerFixes[provider] = SystemClock.elapsedRealtime()
            // Preserve the original measured timestamp; Dart enforces freshness.
            locations.getLastKnownLocation(provider)?.let { accept(it) }
        } catch (_: IllegalArgumentException) { /* Provider temporarily unavailable. */ }
          catch (_: SecurityException) { /* Permission is rechecked by the app. */ }
    }

    @Suppress("DEPRECATION")
    private fun accept(location: Location) {
        if (System.currentTimeMillis() >= deadline) { finish(); return }
        providerFixes[location.provider ?: ""] = SystemClock.elapsedRealtime()
        if (!location.hasAccuracy()) return
        val previous = last
        val mocked = if (Build.VERSION.SDK_INT >= 31) location.isMock else location.isFromMockProvider
        if (!mocked && previous != null) {
            if (location.time <= previous.time) return
            // Do not jump from a precise fix to a much coarser network estimate.
            if (location.time - previous.time < 10_000 && location.accuracy > previous.accuracy * 2) return
        }
        if (!mocked && location.time <= System.currentTimeMillis() + 5_000 &&
            location.time >= System.currentTimeMillis() - 30_000) last = location
        sink?.success(mapOf(
            "latitude" to location.latitude, "longitude" to location.longitude,
            "timestamp" to location.time, "accuracy" to location.accuracy.toDouble(),
            "altitude" to location.altitude, "heading" to location.bearing.toDouble(),
            "speed" to location.speed.toDouble(), "is_mocked" to mocked
        ))
    }

    private fun notification(): Notification {
        val launch = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val pending = PendingIntent.getActivity(this, 0, launch, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        return builder.setSmallIcon(R.drawable.ic_duty_location)
            .setContentTitle(if (onDuty) "On-duty location sharing" else "Verifying attendance location")
            .setContentText(if (onDuty) "Location updates automatically until Time Out or duty end." else "Acquiring your location for attendance.")
            .setContentIntent(pending).setOngoing(true).setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE).build()
    }

    @Suppress("WakelockTimeout", "DEPRECATION")
    private fun acquireLocks() {
        if (wakeLock == null) {
            wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "sentinel:duty-location")
                .apply { setReferenceCounted(false); acquire() }
        }
        if (wifiLock == null) {
            wifiLock = (applicationContext.getSystemService(WIFI_SERVICE) as WifiManager)
                .createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "sentinel:duty-upload")
                .apply { setReferenceCounted(false); acquire() }
        }
    }

    private fun finish() { stopSelf() }
    override fun onBind(intent: Intent?) = null
    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        listeners.values.forEach { locations.removeUpdates(it) }
        listeners.clear()
        wakeLock?.let { if (it.isHeld) it.release() }; wakeLock = null
        wifiLock?.let { if (it.isHeld) it.release() }; wifiLock = null
        last = null
        instance = null
        sink?.endOfStream()
        sink = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
