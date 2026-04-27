package com.example.moto_gps

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.*
import android.util.Log
import androidx.core.app.NotificationCompat

class LocationForegroundService : Service() {

    companion object {
        const val CHANNEL_ID        = "moto_gps_location_channel"
        const val NOTIFICATION_ID   = 1001
        const val ACTION_START      = "ACTION_START"
        const val ACTION_STOP       = "ACTION_STOP"
        const val ACTION_UPDATE_TXT = "ACTION_UPDATE_TXT"
        const val EXTRA_INSTRUCTION = "instruction"
        private const val TAG       = "MotoGPS_Service"

        var onLocationUpdate: ((Double, Double, Float, Float) -> Unit)? = null
    }

    private lateinit var locationManager: LocationManager
    private lateinit var notificationManager: NotificationManager
    private var currentInstruction = "Navegando..."

    private val locationListener = object : LocationListener {
        override fun onLocationChanged(location: Location) {
            onLocationUpdate?.invoke(
                location.latitude,
                location.longitude,
                location.speed,
                location.bearing
            )
        }
        @Deprecated("Deprecated in Java")
        override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
        override fun onProviderEnabled(provider: String) {}
        override fun onProviderDisabled(provider: String) {}
    }

    // ── Ciclo de vida ────────────────────────────────────────────────

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        locationManager    = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        createNotificationChannel()
        Log.d(TAG, "Servicio creado")
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                startForegroundService()
                startLocationUpdates()
                Log.d(TAG, "Servicio iniciado")
            }
            ACTION_STOP -> {
                stopSelf()
                Log.d(TAG, "Servicio detenido")
            }
            ACTION_UPDATE_TXT -> {
                currentInstruction = intent.getStringExtra(EXTRA_INSTRUCTION)
                    ?: "Navegando..."
                updateNotification(currentInstruction)
                Log.d(TAG, "Instrucción: $currentInstruction")
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        locationManager.removeUpdates(locationListener)
        onLocationUpdate = null
        Log.d(TAG, "Servicio destruido")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    // ── Foreground Service ───────────────────────────────────────────

    private fun startForegroundService() {
        val notification = buildNotification(currentInstruction)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    // ── Notificación ─────────────────────────────────────────────────

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "GPS Navegación",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Rastreo GPS activo para navegación en moto"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(instruction: String): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🏍️ Moto GPS activo")
            .setContentText(instruction)
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    private fun updateNotification(instruction: String) {
        notificationManager.notify(NOTIFICATION_ID, buildNotification(instruction))
    }

    // ── GPS nativo ───────────────────────────────────────────────────

    @Suppress("MissingPermission")
    private fun startLocationUpdates() {
        val providers = listOf(
            LocationManager.GPS_PROVIDER,
            LocationManager.NETWORK_PROVIDER
        )
        providers.forEach { provider ->
            if (locationManager.isProviderEnabled(provider)) {
                locationManager.requestLocationUpdates(
                    provider,
                    1000L,   // cada 1 segundo
                    3f,      // mínimo 3 metros
                    locationListener,
                    Looper.getMainLooper()
                )
                Log.d(TAG, "GPS iniciado con provider: $provider")
            }
        }
    }
}
