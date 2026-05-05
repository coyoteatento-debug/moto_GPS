package com.coyoteatento.motogps

import android.app.*
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.*
import android.util.Log
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*

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

    private lateinit var fusedClient: FusedLocationProviderClient
    private lateinit var notificationManager: NotificationManager
    private var currentInstruction = "Navegando..."

    private val locationCallback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            val location = result.lastLocation ?: return
            onLocationUpdate?.invoke(
                location.latitude,
                location.longitude,
                location.speed,
                location.bearing
            )
        }
    }

    override fun onCreate() {
        super.onCreate()
        notificationManager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        fusedClient = LocationServices.getFusedLocationProviderClient(this)
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
        fusedClient.removeLocationUpdates(locationCallback)
        onLocationUpdate = null
        Log.d(TAG, "Servicio destruido")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

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

    private fun startLocationUpdates() {
        val request = LocationRequest.Builder(
            Priority.PRIORITY_HIGH_ACCURACY, 1000L
        ).apply {
            setMinUpdateIntervalMillis(500L)
            setMinUpdateDistanceMeters(3f)
        }.build()

        try {
            fusedClient.requestLocationUpdates(
                request,
                locationCallback,
                Looper.getMainLooper()
            )
        } catch (e: SecurityException) {
            Log.e(TAG, "Sin permiso de ubicación: ${e.message}")
        }
    }

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
            this, 0,
            packageManager.getLaunchIntentForPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("🏍️ Moto GPS activo")
            .setContentText(instruction)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun updateNotification(instruction: String) {
        val notification = buildNotification(instruction)
        notificationManager.notify(NOTIFICATION_ID, notification)
    }
}
