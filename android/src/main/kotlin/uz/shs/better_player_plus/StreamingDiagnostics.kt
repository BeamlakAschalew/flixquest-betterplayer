package uz.shs.better_player_plus

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DecoderReuseEvaluation
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.source.LoadEventInfo
import androidx.media3.exoplayer.source.MediaLoadData
import androidx.media3.exoplayer.upstream.BandwidthMeter
import java.io.IOException
import java.util.Locale

/** Opt-in local diagnostics. Never log source URLs, request headers or credentials. */
@UnstableApi
internal class StreamingDiagnostics(
    private val player: ExoPlayer,
    private val bandwidthMeter: BandwidthMeter,
    private val displayRefreshRate: () -> Float?
) : AnalyticsListener {
    private var startedAtMs = SystemClock.elapsedRealtime()
    private var firstFrameReported = false
    private var lastSampleMs = 0L
    private var loadErrors = 0
    private val frameSampleHandler = Handler(Looper.getMainLooper())
    private var frameSampleAtMs = 0L
    private var renderedAtSample = 0
    private var droppedAtSample = 0
    private var skippedAtSample = 0
    private val frameSampleRunnable = object : Runnable {
        override fun run() {
            sampleFrames()
            frameSampleHandler.postDelayed(this, FRAME_SAMPLE_INTERVAL_MS)
        }
    }

    fun reset() {
        startedAtMs = SystemClock.elapsedRealtime()
        firstFrameReported = false
        lastSampleMs = 0L
        loadErrors = 0
        frameSampleAtMs = 0L
    }

    fun release() {
        frameSampleHandler.removeCallbacksAndMessages(null)
    }

    override fun onIsPlayingChanged(eventTime: AnalyticsListener.EventTime, isPlaying: Boolean) {
        frameSampleHandler.removeCallbacksAndMessages(null)
        frameSampleAtMs = 0L
        if (isPlaying && Log.isLoggable(TAG, Log.DEBUG)) {
            frameSampleHandler.post(frameSampleRunnable)
        }
    }

    override fun onVideoInputFormatChanged(
        eventTime: AnalyticsListener.EventTime, format: Format, decoderReuseEvaluation: DecoderReuseEvaluation?
    ) {
        log("videoFormat=${format.width}x${format.height} contentFps=${format.frameRate} " +
            "codec=${format.sampleMimeType} displayHz=${displayRefreshRate()}")
    }

    /**
     * Frames the decoder handed to the output surface over the last interval.
     * With a Flutter texture this is the upper bound of what reaches the
     * screen: frames Flutter does not composite in time are dropped later and
     * are not counted here.
     */
    private fun sampleFrames() {
        val counters = player.videoDecoderCounters ?: return
        counters.ensureUpdated()
        val now = SystemClock.elapsedRealtime()
        val rendered = counters.renderedOutputBufferCount
        val dropped = counters.droppedBufferCount
        val skipped = counters.skippedOutputBufferCount
        // Counters restart with a new decoder; take a fresh baseline then.
        if (frameSampleAtMs != 0L && rendered >= renderedAtSample) {
            val seconds = (now - frameSampleAtMs) / 1000f
            val renderedFps = (rendered - renderedAtSample) / seconds
            log("renderedFps=${String.format(Locale.US, "%.1f", renderedFps)} contentFps=${player.videoFormat?.frameRate} " +
                "displayHz=${displayRefreshRate()} dropped=${dropped - droppedAtSample} " +
                "skipped=${skipped - skippedAtSample} speed=${player.playbackParameters.speed}")
        }
        frameSampleAtMs = now
        renderedAtSample = rendered
        droppedAtSample = dropped
        skippedAtSample = skipped
    }

    override fun onRenderedFirstFrame(eventTime: AnalyticsListener.EventTime, output: Any, renderTimeMs: Long) {
        if (firstFrameReported) return
        firstFrameReported = true
        log("firstFrameMs=${SystemClock.elapsedRealtime() - startedAtMs}")
    }

    override fun onPlaybackStateChanged(eventTime: AnalyticsListener.EventTime, state: Int) {
        if (state == Player.STATE_BUFFERING || state == Player.STATE_READY) {
            // State transitions intentionally include startup and seeks. Do not
            // mistake their count for rebuffer count when comparing captures.
            log("state=$state bufferMs=${player.totalBufferedDuration}")
        }
    }

    override fun onLoadCompleted(
        eventTime: AnalyticsListener.EventTime, loadEventInfo: LoadEventInfo, mediaLoadData: MediaLoadData
    ) {
        val now = SystemClock.elapsedRealtime()
        if (mediaLoadData.dataType != C.DATA_TYPE_MEDIA || now - lastSampleMs < 5000 ||
            !Log.isLoggable(TAG, Log.DEBUG)) return
        lastSampleMs = now
        val mediaDurationMs = if (mediaLoadData.mediaStartTimeMs != C.TIME_UNSET &&
            mediaLoadData.mediaEndTimeMs != C.TIME_UNSET) {
            mediaLoadData.mediaEndTimeMs - mediaLoadData.mediaStartTimeMs
        } else C.TIME_UNSET
        log("bufferMs=${player.totalBufferedDuration} bandwidthBps=${bandwidthMeter.bitrateEstimate} " +
            "trackType=${mediaLoadData.trackType} selectedBps=${mediaLoadData.trackFormat?.bitrate} " +
            "loadMs=${loadEventInfo.loadDurationMs} mediaMs=$mediaDurationMs " +
            "loadedBytes=${loadEventInfo.bytesLoaded} loadErrors=$loadErrors")
    }

    override fun onLoadError(
        eventTime: AnalyticsListener.EventTime, loadEventInfo: LoadEventInfo,
        mediaLoadData: MediaLoadData, error: IOException, wasCanceled: Boolean
    ) {
        if (!wasCanceled) loadErrors++
    }

    override fun onPlayerError(eventTime: AnalyticsListener.EventTime, error: PlaybackException) {
        log("errorCode=${error.errorCode} recoverable=${StreamingLoadErrorPolicy.canRecover(error)}")
    }

    private fun log(message: String) {
        if (Log.isLoggable(TAG, Log.DEBUG)) Log.d(TAG, message)
    }

    companion object {
        private const val TAG = "BetterPlayerStreaming"
        private const val FRAME_SAMPLE_INTERVAL_MS = 5000L
    }
}
