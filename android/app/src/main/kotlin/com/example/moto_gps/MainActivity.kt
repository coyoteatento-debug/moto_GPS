package com.coyoteatento.motogps

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "com.coyoteatento.motogps/background"
    private val EVENT_CHANNEL  = "com.coyoteatento.motogps/location"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── MethodChannel: comandos Flutter → Android ────────────────
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            METHOD_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    val intent = Intent(this, LocationForegroundService::class.java).apply {
                        action = LocationForegroundService.ACTION_START
                    }
                    startForegroundService(intent)
                    result.success(null)
                }
                "stopService" -> {
                    val intent = Intent(this, LocationForegroundService::class.java).apply {
                        action = LocationForegroundService.ACTION_STOP
                    }
                    startService(intent)
                    result.success(null)
                }
                "updateInstruction" -> {
                    val instruction = call.argument<String>("instruction") ?: "Navegando..."
                    val intent = Intent(this, LocationForegroundService::class.java).apply {
                        action = LocationForegroundService.ACTION_UPDATE_TXT
                        putExtra(LocationForegroundService.EXTRA_INSTRUCTION, instruction)
                    }
                    startService(intent)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // ── EventChannel: GPS Android → Flutter ──────────────────────
        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            EVENT_CHANNEL
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                LocationForegroundService.onLocationUpdate = { lat, lng, speed, bearing ->
                    runOnUiThread {
                        events?.success(mapOf(
                            "latitude"  to lat,
                            "longitude" to lng,
                            "speed"     to speed,
                            "heading"   to bearing
                        ))
                    }
                }
            }
            override fun onCancel(arguments: Any?) {
                LocationForegroundService.onLocationUpdate = null
            }
        })
    }
}
