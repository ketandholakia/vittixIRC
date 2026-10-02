package io.github.ketandholakia.virc

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "vittix_irc/volume_keys"
    private val eventChannelName = "vittix_irc/volume_keys/events"
    private val keepAliveChannelName = "vittix_irc/keep_alive"

    private var volumeKeysEnabled = false
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            methodChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    volumeKeysEnabled = call.argument<Boolean>("enabled") ?: false
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            keepAliveChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            KEEP_ALIVE_PERMISSION_REQUEST
                        )
                    }

                    val intent = Intent(this, KeepAliveService::class.java)
                    intent.putExtra(
                        KeepAliveService.EXTRA_TITLE,
                        call.argument<String>("title") ?: KeepAliveService.DEFAULT_TITLE
                    )

                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("keep_alive_error", e.message, null)
                    }
                }

                "stop" -> {
                    stopService(Intent(this, KeepAliveService::class.java))
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            eventChannelName
        ).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean {
        if (!volumeKeysEnabled) {
            return super.onKeyDown(keyCode, event)
        }

        return when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> {
                eventSink?.success("volume_up")
                true
            }

            KeyEvent.KEYCODE_VOLUME_DOWN -> {
                eventSink?.success("volume_down")
                true
            }

            else -> super.onKeyDown(keyCode, event)
        }
    }

    companion object {
        private const val KEEP_ALIVE_PERMISSION_REQUEST = 4712
    }
}
