package com.example.flutter_moonlight_streaming_sample

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import android.view.Surface
import com.ik.simwheel.MoonlightStreamController

class MainActivity : FlutterActivity() {
    private var textureEntry: io.flutter.view.TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null
    companion object {
        @Volatile private var eventSink: EventChannel.EventSink? = null
        fun emitStreamEvent(event: Map<String, Any>) { runOnUiThreadStatic { eventSink?.success(event) } }
        private fun runOnUiThreadStatic(block: () -> Unit) { instance?.runOnUiThread(block) }
        @Volatile private var instance: MainActivity? = null
    }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        instance = this
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "simwheel/moonlight_events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { eventSink = events }
            override fun onCancel(arguments: Any?) { eventSink = null }
        })
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "simwheel/moonlight").setMethodCallHandler { call, result ->
            when (call.method) {
                "createTexture" -> {
                    if (textureEntry == null) {
                        textureEntry = flutterEngine.renderer.createSurfaceTexture()
                        surface = Surface(textureEntry!!.surfaceTexture())
                        MoonlightStreamController.setSurface(surface)
                    }
                    result.success(textureEntry!!.id())
                }
                "startStream" -> { @Suppress("UNCHECKED_CAST") val options = call.arguments as? Map<String, Any>; if (options == null) result.error("BAD_ARGS", "Missing stream options", null) else { MoonlightStreamController.start(options); result.success(true) } }
                "stopStream", "releaseTexture" -> { MoonlightStreamController.stop(); MoonlightStreamController.setSurface(null); surface?.release(); surface = null; textureEntry?.release(); textureEntry = null; result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    override fun onDestroy() { MoonlightStreamController.stop(); surface?.release(); textureEntry?.release(); instance = null; super.onDestroy() }
}
