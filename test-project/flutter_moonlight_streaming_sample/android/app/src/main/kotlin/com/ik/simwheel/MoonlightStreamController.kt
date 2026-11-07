package com.ik.simwheel

import android.media.MediaCodecList
import android.media.MediaFormat
import android.view.Surface
import com.limelight.binding.audio.AndroidPcmAudioRenderer
import com.limelight.binding.video.SurfaceVideoDecoderRenderer
import com.limelight.nvstream.NvConnectionListener
import com.limelight.nvstream.av.audio.AudioRenderer
import com.limelight.nvstream.jni.MoonBridge
import com.example.flutter_moonlight_streaming_sample.MainActivity

/** Owns the Moonlight connection and bridges it to a Flutter SurfaceView. */
object MoonlightStreamController : NvConnectionListener {
    private var surface: Surface? = null
    private var pendingOptions: Map<*, *>? = null
    private var queuedRestart: Map<*, *>? = null
    @Volatile private var started = false
    @Volatile private var stopping = false

    @Synchronized fun setSurface(value: Surface?) {
        surface = value
        if (value != null && pendingOptions != null && !started) startOnSurface(pendingOptions!!)
        if (value == null) stop()
    }

    @Synchronized fun start(options: Map<*, *>) {
        if (started || stopping) {
            queuedRestart = options
            if (started) requestStop()
            return
        }
        pendingOptions = options
        surface?.let { if (!started) startOnSurface(options) }
    }

    fun stop() {
        pendingOptions = null
        queuedRestart = null
        requestStop()
    }

    @Synchronized private fun requestStop() {
        if (!started || stopping) return
        stopping = true
        try { MoonBridge.interruptConnection() } catch (_: Exception) { }
        Thread {
            try {
                synchronized(MoonBridge::class.java) {
                    MoonBridge.stopConnection()
                    MoonBridge.cleanupBridge()
                }
            } catch (error: Exception) {
                android.util.Log.w("SimWheelStream", "Error stopping stream", error)
            }
            val restart = synchronized(this) {
                started = false
                stopping = false
                val next = queuedRestart
                queuedRestart = null
                next
            }
            if (restart != null && surface?.isValid == true) {
                synchronized(this) {
                    pendingOptions = restart
                    startOnSurface(restart)
                }
            }
        }.start()
    }

    private fun startOnSurface(options: Map<*, *>) {
        val targetSurface = surface ?: return
        val video = SurfaceVideoDecoderRenderer().also { it.setSurface(targetSurface) }
        val audioOutput = AndroidPcmAudioRenderer()
        started = true
        MoonBridge.setupBridge(video, audioOutput, this)

        val host = options["host"] as? String ?: return fail("Missing Sunshine host address")
        val version = options["appVersion"] as? String ?: return fail("Missing Sunshine server version")
        val gfeVersion = options["gfeVersion"] as? String
        val sessionUrl = (options["sessionUrl"] as? String)?.takeIf { it.isNotEmpty() }
        val codecMode = (options["codecMode"] as? Number)?.toInt() ?: 0
        val width = (options["width"] as? Number)?.toInt() ?: 1920
        val height = (options["height"] as? Number)?.toInt() ?: 1080
        val fps = (options["fps"] as? Number)?.toInt() ?: 60
        val bitrate = (options["bitrate"] as? Number)?.toInt() ?: 10000
        val preferHevc = options["preferHevc"] as? Boolean ?: false
        val supportedVideoFormats = if (
            preferHevc && supportsHevcDecoder(width, height)
        ) {
            MoonBridge.VIDEO_FORMAT_H264 or MoonBridge.VIDEO_FORMAT_H265
        } else {
            MoonBridge.VIDEO_FORMAT_H264
        }
        val key = bytes(options["riKey"]) ?: return fail("Missing session encryption key")
        val iv = bytes(options["riIv"]) ?: return fail("Missing session encryption IV")
        if (key.size != 16 || iv.size != 16) return fail("Invalid session encryption material")

        Thread {
            try {
                emit("connecting", "Starting Moonlight stream…")
                val status = synchronized(MoonBridge::class.java) {
                    MoonBridge.startConnection(
                        host, version, gfeVersion, sessionUrl, codecMode,
                        width, height, fps, bitrate, 1392, 0,
                        MoonBridge.AUDIO_CONFIGURATION_STEREO.toInt(),
                        supportedVideoFormats,
                        fps * 100, key, iv, 0,
                        MoonBridge.COLORSPACE_REC_709, MoonBridge.COLOR_RANGE_LIMITED
                    )
                }
                if (status != 0) {
                    emit("error", "Moonlight could not start the stream ($status)")
                    requestStop()
                }
            } catch (error: Exception) {
                emit("error", error.message ?: "Moonlight stream failed")
                requestStop()
            }
        }.start()
    }

    private fun fail(message: String) {
        started = false
        MoonBridge.cleanupBridge()
        emit("error", message)
    }

    private fun bytes(value: Any?): ByteArray? = when (value) {
        is ByteArray -> value
        is List<*> -> if (value.all { it is Number }) {
            value.map { (it as Number).toByte() }.toByteArray()
        } else null
        else -> null
    }

    private fun supportsHevcDecoder(width: Int, height: Int): Boolean {
        return try {
            val decoderList = MediaCodecList(MediaCodecList.REGULAR_CODECS)
            decoderList.codecInfos.any { codecInfo ->
                if (codecInfo.isEncoder) return@any false
                val hevcType = codecInfo.supportedTypes.firstOrNull {
                    it.equals("video/hevc", ignoreCase = true)
                } ?: return@any false
                codecInfo.getCapabilitiesForType(hevcType).videoCapabilities
                    ?.isSizeSupported(width, height) == true
            }
        } catch (error: Exception) {
            android.util.Log.w("SimWheelStream", "Unable to check HEVC decoder support", error)
            false
        }
    }

    private fun emit(state: String, message: String) {
        MainActivity.emitStreamEvent(mapOf("state" to state, "message" to message))
    }

    override fun stageStarting(stage: String) = emit("connecting", stage)
    override fun stageComplete(stage: String) = emit("connecting", stage)
    override fun stageFailed(stage: String, portFlags: Int, errorCode: Int) = emit("error", "$stage failed (error $errorCode)")
    override fun connectionStarted() = emit("connected", "Video stream connected")
    override fun connectionTerminated(errorCode: Int) {
        emit("disconnected", "Connection ended ($errorCode)")
        requestStop()
    }
    override fun connectionStatusUpdate(connectionStatus: Int) = Unit
    override fun displayMessage(message: String) = emit("error", message)
    override fun displayTransientMessage(message: String) = emit("connecting", message)
    override fun rumble(controllerNumber: Short, lowFreqMotor: Short, highFreqMotor: Short) = Unit
    override fun rumbleTriggers(controllerNumber: Short, leftTrigger: Short, rightTrigger: Short) = Unit
    override fun setHdrMode(enabled: Boolean, hdrMetadata: ByteArray?) = Unit
    override fun setMotionEventState(controllerNumber: Short, motionType: Byte, reportRateHz: Short) = Unit
    override fun setControllerLED(controllerNumber: Short, r: Byte, g: Byte, b: Byte) = Unit
}
