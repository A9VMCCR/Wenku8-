package org.mewx.wenku8_flutter

import android.app.Activity
import android.view.KeyEvent
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel

class ReaderControlsPlugin : FlutterPlugin, ActivityAware {
    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private var volumePaging = false
    private var lastPage = 0L
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "org.mewx.wenku8/reader_controls").also {
            it.setMethodCallHandler { call, result ->
                if (call.method == "brightness") {
                    val current = activity
                    if (current == null) { result.error("NO_ACTIVITY", "阅读页面未显示", null); return@setMethodCallHandler }
                    val windowValue = current.window.attributes.screenBrightness
                    val value = if (windowValue >= 0f) windowValue else
                        Settings.System.getInt(current.contentResolver, Settings.System.SCREEN_BRIGHTNESS, 128) / 255f
                    result.success(value.coerceIn(.03f, 1f).toDouble()); return@setMethodCallHandler
                }
                if (call.method != "apply") { result.notImplemented(); return@setMethodCallHandler }
                volumePaging = call.argument<Boolean>("volumePaging") == true
                val brightness = call.argument<Number>("brightness")?.toFloat() ?: -1f
                if (brightness != -1f && brightness !in .03f..1f) {
                    result.error("brightness", "阅读亮度超出范围", null); return@setMethodCallHandler
                }
                activity?.window?.let { window -> val attrs = window.attributes; attrs.screenBrightness = brightness; window.attributes = attrs }
                result.success(null)
            }
        }
    }
    fun dispatch(event: KeyEvent): Boolean {
        if (!volumePaging || activity?.hasWindowFocus() != true ||
            event.keyCode !in setOf(KeyEvent.KEYCODE_VOLUME_UP, KeyEvent.KEYCODE_VOLUME_DOWN)) return false
        if (event.action == KeyEvent.ACTION_DOWN && (event.repeatCount == 0 || event.eventTime - lastPage >= 160)) {
            lastPage = event.eventTime
            channel?.invokeMethod("page", if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP) -1 else 1)
        }
        return true
    }
    fun suspend() {
        volumePaging = false
        activity?.window?.let { window -> val attrs = window.attributes; attrs.screenBrightness = -1f; window.attributes = attrs }
    }
    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { suspend(); activity = null }
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) { suspend(); channel?.setMethodCallHandler(null); channel = null }
}
