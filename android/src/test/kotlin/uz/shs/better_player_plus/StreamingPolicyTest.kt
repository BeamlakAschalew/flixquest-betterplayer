package uz.shs.better_player_plus

import android.net.Uri
import android.os.Handler
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Timeline
import androidx.media3.common.TrackGroup
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.HttpDataSource
import androidx.media3.datasource.TransferListener
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.LoadControl
import androidx.media3.exoplayer.analytics.PlayerId
import androidx.media3.exoplayer.source.LoadEventInfo
import androidx.media3.exoplayer.source.MediaLoadData
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.TrackGroupArray
import androidx.media3.exoplayer.source.chunk.MediaChunkIterator
import androidx.media3.exoplayer.upstream.BandwidthMeter
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import java.io.IOException
import java.net.SocketTimeoutException
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class StreamingPolicyTest {
    private val spec = DataSpec(Uri.parse("https://example.test/segment.ts"))

    @Test fun temporaryFailuresNeverSkipMovieContent() {
        var skips = 0
        val policy = StreamingLoadErrorPolicy { _, _ -> skips++; true }
        for (exception in listOf(SocketTimeoutException(), httpError(503), httpError(429))) {
            for (attempt in 1..6) policy.getRetryDelayMsFor(errorInfo(exception, attempt))
        }
        assertEquals(0, skips)
        assertEquals(C.TIME_UNSET, policy.getRetryDelayMsFor(errorInfo(SocketTimeoutException(), 6)))
    }

    @Test fun onlyMissingShortMediaMayUseTheExistingSkipFallback() {
        var skips = 0
        val policy = StreamingLoadErrorPolicy { _, _ -> skips++; true }
        assertTrue(policy.getRetryDelayMsFor(errorInfo(httpError(404), 2)) >= 0)
        assertEquals(C.TIME_UNSET, policy.getRetryDelayMsFor(errorInfo(httpError(404), 3)))
        assertEquals(1, skips)
        policy.getRetryDelayMsFor(errorInfo(httpError(404), 3, C.DATA_TYPE_MANIFEST))
        policy.getRetryDelayMsFor(errorInfo(httpError(404), 3, durationMs = 60_000))
        assertEquals(1, skips)
    }

    @Test fun authenticationErrorsSurfaceWithoutRepeatedReloads() {
        val policy = StreamingLoadErrorPolicy()
        for (code in listOf(401, 403)) {
            assertEquals(C.TIME_UNSET, policy.getRetryDelayMsFor(errorInfo(httpError(code), 1)))
            assertFalse(StreamingLoadErrorPolicy.canRecover(
                PlaybackException("HTTP", httpError(code), PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS)))
        }
        assertTrue(StreamingLoadErrorPolicy.canRecover(
            PlaybackException("HTTP", httpError(503), PlaybackException.ERROR_CODE_IO_BAD_HTTP_STATUS)))
        assertFalse(StreamingLoadErrorPolicy.canRecover(
            PlaybackException("decoder", null, PlaybackException.ERROR_CODE_DECODING_FAILED)))
    }

    @Test fun qualityDropsAcrossMultipleRenditionsWhenBandwidthCollapses() {
        val meter = MutableBandwidthMeter(8_000_000)
        val selection = selection(meter)
        update(selection, 30_000_000)
        assertEquals(2_000_000, selection.selectedFormat.bitrate)
        meter.estimate = 700_000
        update(selection, 5_000_000)
        assertEquals(300_000, selection.selectedFormat.bitrate)
        meter.estimate = 8_000_000
        update(selection, 5_000_000)
        assertEquals(300_000, selection.selectedFormat.bitrate)
        update(selection, 30_000_000)
        assertEquals(2_000_000, selection.selectedFormat.bitrate)
    }

    @Test fun rebufferingLeavesMoreBandwidthHeadroom() {
        val meter = MutableBandwidthMeter(1_000_000)
        val selection = selection(meter)
        update(selection, 30_000_000)
        assertEquals(600_000, selection.selectedFormat.bitrate)
        selection.onRebuffer()
        update(selection, 30_000_000)
        assertEquals(300_000, selection.selectedFormat.bitrate)
    }

    @Test fun byteCeilingStopsTimePrioritizedLoadingWithoutDeadlockingStartup() {
        val byteLimit = 1024 * 1024
        val delegate = DefaultLoadControl.Builder()
            .setBufferDurationsMs(45_000, 120_000, 1500, 5000)
            .setTargetBufferBytes(byteLimit)
            .setPrioritizeTimeOverSizeThresholds(true).build()
        val control = StreamingLoadControl(delegate, byteLimit)
        val id = PlayerId.UNSET
        control.onPrepared(id)
        val parameters = LoadControl.Parameters(
            id, Timeline.EMPTY, MediaSource.MediaPeriodId(Any()),
            0, 1_000_000, 1f, true, false, C.TIME_UNSET, C.TIME_UNSET
        )
        control.onTracksSelected(parameters, TrackGroupArray.EMPTY, emptyArray())
        assertEquals(0L, control.getBackBufferDurationUs(id))
        assertFalse(control.retainBackBufferFromKeyframe(id))
        assertTrue(control.shouldContinueLoading(parameters))
        assertFalse(control.shouldStartPlayback(parameters))
        val allocations = (1..16).map { control.allocator.allocate() }
        assertFalse(control.shouldContinueLoading(parameters))
        assertTrue(control.shouldStartPlayback(parameters))
        allocations.forEach { control.allocator.release(it) }
        assertTrue(control.shouldContinueLoading(parameters))
        control.onStopped(id)
        control.onReleased(id)
    }

    @Test fun weakDevicesGetSmallerMemoryBudgets() {
        assertEquals(16 * 1024 * 1024, StreamingLoadControl.memoryBudgetBytes(64, true))
        assertEquals(24 * 1024 * 1024, StreamingLoadControl.memoryBudgetBytes(128, true))
        assertEquals(64 * 1024 * 1024, StreamingLoadControl.memoryBudgetBytes(512, false))
    }

    private fun selection(meter: BandwidthMeter): StreamingTrackSelection {
        val group = TrackGroup(*intArrayOf(300_000, 600_000, 2_000_000).map { bitrate ->
            Format.Builder().setSampleMimeType(MimeTypes.VIDEO_H264).setAverageBitrate(bitrate).build()
        }.toTypedArray())
        return StreamingTrackSelection(group, intArrayOf(0, 1, 2), 0, meter, emptyList(), 20_000)
    }

    private fun update(selection: StreamingTrackSelection, bufferUs: Long) =
        selection.updateSelectedTrack(0, bufferUs, C.TIME_UNSET, mutableListOf(),
            Array(3) { MediaChunkIterator.EMPTY })

    private fun httpError(code: Int) = HttpDataSource.InvalidResponseCodeException(
        code, null, null, emptyMap(), spec, byteArrayOf())

    private fun errorInfo(
        exception: IOException, count: Int, type: Int = C.DATA_TYPE_MEDIA, durationMs: Long = 6000
    ) = LoadErrorHandlingPolicy.LoadErrorInfo(
        LoadEventInfo(1, spec, 0),
        MediaLoadData(type, C.TRACK_TYPE_VIDEO, null, 0, null, 0, durationMs), exception, count)

    private class MutableBandwidthMeter(var estimate: Long) : BandwidthMeter {
        override fun getBitrateEstimate() = estimate
        override fun getTransferListener(): TransferListener? = null
        override fun addEventListener(handler: Handler, listener: BandwidthMeter.EventListener) = Unit
        override fun removeEventListener(listener: BandwidthMeter.EventListener) = Unit
    }
}
