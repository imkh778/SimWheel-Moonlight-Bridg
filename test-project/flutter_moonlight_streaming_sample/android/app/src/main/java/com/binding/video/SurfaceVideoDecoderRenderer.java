package com.limelight.binding.video;

import android.media.MediaCodec;
import android.media.MediaFormat;
import android.os.Build;
import android.view.Surface;

import com.limelight.nvstream.av.video.VideoDecoderRenderer;
import com.limelight.nvstream.jni.MoonBridge;

import java.nio.ByteBuffer;

/** Minimal low-latency MediaCodec renderer for Moonlight's decoded H.264/HEVC/AV1 units. */
public final class SurfaceVideoDecoderRenderer extends VideoDecoderRenderer {
    private final Object lock = new Object();
    private Surface surface;
    private MediaCodec codec;
    private Thread outputThread;
    private volatile boolean running;
    private String mime;

    public void setSurface(Surface value) {
        synchronized (lock) {
            surface = value;
        }
    }

    @Override
    public int setup(int format, int width, int height, int redrawRate) {
        synchronized (lock) {
            if (surface == null || !surface.isValid()) return -1;
            if ((format & MoonBridge.VIDEO_FORMAT_MASK_H265) != 0) mime = "video/hevc";
            else if ((format & MoonBridge.VIDEO_FORMAT_MASK_AV1) != 0) mime = "video/av01";
            else mime = "video/avc";

            try {
                codec = MediaCodec.createDecoderByType(mime);
                MediaFormat mediaFormat = MediaFormat.createVideoFormat(mime, width, height);
                if (Build.VERSION.SDK_INT >= 30) {
                    mediaFormat.setInteger(MediaFormat.KEY_LOW_LATENCY, 1);
                }
                codec.configure(mediaFormat, surface, null, 0);
                return 0;
            } catch (Exception error) {
                android.util.Log.e("SimWheelStream", "Could not configure video decoder", error);
                releaseCodec();
                return -1;
            }
        }
    }

    @Override
    public void start() {
        synchronized (lock) {
            if (codec == null) return;
            try {
                codec.start();
                running = true;
                outputThread = new Thread(this::drainOutput, "moonlight-video-output");
                outputThread.start();
            } catch (Exception error) {
                android.util.Log.e("SimWheelStream", "Could not start video decoder", error);
                running = false;
            }
        }
    }

    @Override
    public void stop() {
        running = false;
        Thread thread = outputThread;
        if (thread != null && thread != Thread.currentThread()) {
            try { thread.join(500); } catch (InterruptedException ignored) { Thread.currentThread().interrupt(); }
        }
        outputThread = null;
    }

    @Override
    public int submitDecodeUnit(byte[] data, int length, int type, int frameNumber,
                                int frameType, char hostLatency, long receiveTimeUs,
                                long enqueueTimeUs) {
        synchronized (lock) {
            if (codec == null || !running) return MoonBridge.DR_NEED_IDR;
            try {
                int index = codec.dequeueInputBuffer(10000);
                if (index < 0) return MoonBridge.DR_NEED_IDR;
                ByteBuffer input = codec.getInputBuffer(index);
                if (input == null || length > input.capacity()) {
                    codec.queueInputBuffer(index, 0, 0, 0, 0);
                    return MoonBridge.DR_NEED_IDR;
                }
                input.clear();
                input.put(data, 0, length);
                int flags = (type == MoonBridge.BUFFER_TYPE_SPS ||
                        type == MoonBridge.BUFFER_TYPE_PPS ||
                        type == MoonBridge.BUFFER_TYPE_VPS)
                        ? MediaCodec.BUFFER_FLAG_CODEC_CONFIG : 0;
                codec.queueInputBuffer(index, 0, length, System.nanoTime() / 1000L, flags);
                return MoonBridge.DR_OK;
            } catch (Exception error) {
                android.util.Log.e("SimWheelStream", "Video decode input failed", error);
                return MoonBridge.DR_NEED_IDR;
            }
        }
    }

    private void drainOutput() {
        MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
        while (running) {
            MediaCodec current = codec;
            if (current == null) break;
            try {
                int index = current.dequeueOutputBuffer(info, 10000);
                if (index >= 0) current.releaseOutputBuffer(index, true);
            } catch (Exception error) {
                if (running) android.util.Log.e("SimWheelStream", "Video decode output failed", error);
                break;
            }
        }
    }

    @Override
    public void cleanup() {
        stop();
        synchronized (lock) { releaseCodec(); }
    }

    private void releaseCodec() {
        if (codec != null) {
            try { codec.stop(); } catch (Exception ignored) { }
            try { codec.release(); } catch (Exception ignored) { }
            codec = null;
        }
    }

    @Override public int getCapabilities() { return 0; }
    @Override public void setHdrMode(boolean enabled, byte[] metadata) { }
}
