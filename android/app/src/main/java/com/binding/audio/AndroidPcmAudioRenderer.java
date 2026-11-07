package com.limelight.binding.audio;

import android.media.AudioFormat;
import android.media.AudioManager;
import android.media.AudioTrack;

import com.limelight.nvstream.av.audio.AudioRenderer;
import com.limelight.nvstream.jni.MoonBridge;

public final class AndroidPcmAudioRenderer implements AudioRenderer {
    private AudioTrack track;

    @Override
    public int setup(MoonBridge.AudioConfiguration configuration, int sampleRate, int samplesPerFrame) {
        int channels = configuration.channelCount > 1 ? AudioFormat.CHANNEL_OUT_STEREO : AudioFormat.CHANNEL_OUT_MONO;
        int minBytes = AudioTrack.getMinBufferSize(sampleRate, channels, AudioFormat.ENCODING_PCM_16BIT);
        if (minBytes <= 0) return -1;
        try {
            track = new AudioTrack(AudioManager.STREAM_MUSIC, sampleRate, channels,
                    AudioFormat.ENCODING_PCM_16BIT, Math.max(minBytes, samplesPerFrame * 4),
                    AudioTrack.MODE_STREAM);
            return track.getState() == AudioTrack.STATE_INITIALIZED ? 0 : -1;
        } catch (Exception error) {
            android.util.Log.e("SimWheelStream", "Could not initialize audio output", error);
            track = null;
            return -1;
        }
    }

    @Override public void start() { if (track != null) track.play(); }
    @Override public void stop() { if (track != null) { try { track.pause(); track.flush(); } catch (Exception ignored) { } } }
    @Override public void playDecodedAudio(short[] audioData) { if (track != null) track.write(audioData, 0, audioData.length); }
    @Override public void cleanup() { if (track != null) { track.release(); track = null; } }
}
