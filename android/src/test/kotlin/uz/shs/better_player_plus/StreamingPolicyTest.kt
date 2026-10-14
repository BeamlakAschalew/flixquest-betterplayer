package uz.shs.better_player_plus

import android.net.Uri
import android.os.Handler
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.ParserException
import androidx.media3.common.PlaybackException
import androidx.media3.common.Timeline
import androidx.media3.common.TrackGroup
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.ByteArrayDataSource
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
import androidx.media3.exoplayer.source.chunk.MediaChunk
import androidx.media3.exoplayer.upstream.BandwidthMeter
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import java.io.FileNotFoundException
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class StreamingPolicyTest {
    private val spec = DataSpec(Uri.parse("https://example.test/segment.ts"))

    @Test fun liveMissingSegmentsRefreshQuicklyAndNeverUseMovieSkipping() {
        var skips = 0
        val policy = StreamingLoadErrorPolicy(isLive = true) { _, _, _ -> skips++; SegmentSkip.SKIPPING }
        for (code in listOf(404, 410)) {
            assertTrue(policy.getRetryDelayMsFor(errorInfo(httpError(code), 1)) >= 0)
            assertEquals(C.TIME_UNSET, policy.getRetryDelayMsFor(errorInfo(httpError(code), 2)))
        }
        assertTrue(policy.getRetryDelayMsFor(errorInfo(SocketTimeoutException(), 2, task = 2)) >= 0)
        assertEquals(0, skips)
    }

    @Test fun droppedConnectionsWaitForTheNetworkInsteadOfFailing() {
        var online = false
        val policy = StreamingLoadErrorPolicy(isOnline = { online })
        assertEquals(Int.MAX_VALUE, policy.getMinimumLoadableRetryCount(C.DATA_TYPE_MEDIA))
        assertEquals(Int.MAX_VALUE, policy.getMinimumLoadableRetryCount(C.DATA_TYPE_MANIFEST))
        for (attempt in 1..500) {
            assertEquals(StreamingLoadErrorPolicy.OFFLINE_RETRY_MS,
                policy.getRetryDelayMsFor(errorInfo(SocketTimeoutException(), attempt)))
            assertEquals(StreamingLoadErrorPolicy.OFFLINE_RETRY_MS,
                policy.getRetryDelayMsFor(errorInfo(UnknownHostException(), attempt, C.DATA_TYPE_MANIFEST, task = 2)))
        }
        // An HTTP status proves the network works, so it is never waited out.
        assertEquals(C.TIME_UNSET, policy.getRetryDelayMsFor(errorInfo(httpError(403), 1, task = 3)))
        online = true
        assertTrue(policy.getRetryDelayMsFor(errorInfo(SocketTimeoutException(), 501)) >= 0)
    }

    @Test fun reconnectingStartsAFreshNetworkBudget() {
        var online = true
        var now = 0L
        var outageChecks = 0
        val policy = StreamingLoadErrorPolicy(
            isOnline = { online }, onSuspectedOutage = { outageChecks++ }, nowMs = { now })
        policy.getRetryDelayMsFor(errorInfo(SocketTimeoutException(), 1))
        now += 5_000
        policy.getRetryDelayMsFor(errorInfo(SocketTimeoutException(), 2))
        assertEquals(1, outageChecks)
        online = false
        now += 60_000
        assertEquals(StreamingLoadErrorPolicy.OFFLINE_RETRY_MS,
            policy.getRetryDelayMsFor(errorInfo(SocketTimeoutException(), 3)))
        online = true
        now += 1_000
        // Back online: the minute spent offline does not count against the stream.
        assertNotEquals(C.TIME_UNSET, policy.getRetryDelayMsFor(errorInfo(SocketTimeoutException(), 4)))
        now += 4_000
        assertNotEquals(C.TIME_UNSET, policy.getRetryDelayMsFor(errorInfo(SocketTimeoutException(), 5)))
        now += 6_000
        assertEquals(C.TIME_UNSET, policy.getRetryDelayMsFor(errorInfo(SocketTimeoutException(), 6)))
    }

    @Test fun unreachableHostsGiveUpWithinTheOnlineBudget() {
        var now = 0L
        val policy = StreamingLoadErrorPolicy(nowMs = { now })
        for (attempt in 1..3) {
            assertNotEquals(C.TIME_UNSET, policy.getRetryDelayMsFor(errorInfo(SocketTimeoutException(), attempt)))
            now += 3_500
        }
        assertEquals(C.TIME_UNSET, policy.getRetryDelayMsFor(errorInfo(SocketTimeoutException(), 4)))
        // Slow failures (hanging connects) still stop at the hard budget.
        val slow = StreamingLoadErrorPolicy(nowMs = { now })
        slow.getRetryDelayMsFor(errorInfo(SocketTimeoutException(), 1, task = 2))
        now += 26_000
        assertEquals(C.TIME_UNSET, slow.getRetryDelayMsFor(errorInfo(SocketTimeoutException(), 2, task = 2)))
    }

    @Test fun localFilesNeverWaitForTheNetwork() {
        val policy = StreamingLoadErrorPolicy(isOnline = { false })
        val local = DataSpec(Uri.parse("file:///data/movie.mp4"))
        assertEquals(C.TIME_UNSET, policy.getRetryDelayMsFor(errorInfo(FileNotFoundException(), 1, spec = local)))
    }

    @Test fun failuresAreClassifiedByWhatTheySayAboutTheStream() {
        assertEquals(LoadFailure.MISSING, StreamingLoadErrorPolicy.classify(httpError(404)))
        assertEquals(LoadFailure.SERVER, StreamingLoadErrorPolicy.classify(httpError(502)))
        assertEquals(LoadFailure.SERVER, StreamingLoadErrorPolicy.classify(httpError(429)))
        assertEquals(LoadFailure.REJECTED, StreamingLoadErrorPolicy.classify(httpError(403)))
        assertEquals(LoadFailure.CORRUPT,
            StreamingLoadErrorPolicy.classify(ParserException.createForMalformedContainer("bad", null)))
        assertEquals(LoadFailure.CONNECTIVITY, StreamingLoadErrorPolicy.classify(UnknownHostException()))
        assertEquals(LoadFailure.CONNECTIVITY, StreamingLoadErrorPolicy.classify(
            HttpDataSource.HttpDataSourceException(spec,
                PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED, HttpDataSource.HttpDataSourceException.TYPE_READ)))
        assertEquals(LoadFailure.CONNECTIVITY, StreamingLoadErrorPolicy.classify(IOException(SocketTimeoutException())))
        assertEquals(LoadFailure.OTHER, StreamingLoadErrorPolicy.classify(FileNotFoundException()))
    }

    @Test fun anotherRenditionIsTriedBeforeABrokenSegmentIsSkipped() {
        var online = true
        val policy = StreamingLoadErrorPolicy(isOnline = { online })
        val options = LoadErrorHandlingPolicy.FallbackOptions(1, 0, 3, 0)
        assertNull(policy.getFallbackSelectionFor(options, errorInfo(SocketTimeoutException(), 1)))
        assertEquals(LoadErrorHandlingPolicy.FALLBACK_TYPE_TRACK,
            policy.getFallbackSelectionFor(options, errorInfo(SocketTimeoutException(), 2))?.type)
        assertEquals(LoadErrorHandlingPolicy.FALLBACK_TYPE_TRACK,
            policy.getFallbackSelectionFor(options, errorInfo(httpError(503), 2))?.type)
        // Offline every rendition fails the same way; excluding them would only lower quality.
        online = false
        assertNull(policy.getFallbackSelectionFor(options, errorInfo(SocketTimeoutException(), 2)))
    }

    @Test fun expiredLivePositionsRecoverLocallyWithoutAnEndlessLoop() {
        val recovery = LiveWindowRecovery()
        val expired = PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW
        assertFalse(recovery.shouldRecover(false, expired, 0))
        assertFalse(recovery.shouldRecover(true, PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED, 0))
        assertTrue(recovery.shouldRecover(true, expired, 0))
        assertFalse(recovery.shouldRecover(true, expired, 1000))
        assertTrue(recovery.shouldRecover(true, expired, 30_000))
        recovery.reset()
        assertTrue(recovery.shouldRecover(true, expired, 30_001))
    }

    @Test fun shortLiveWindowsCanUpgradeWithoutWaitingForTwentySecondsOfBuffer() {
        val meter = MutableBandwidthMeter(700_000)
        val selection = selection(meter)
        selection.updateSelectedTrack(0, 1_000_000, 6_000_000, mutableListOf(),
            Array(3) { MediaChunkIterator.EMPTY })
        assertEquals(300_000, selection.selectedFormat.bitrate)
        meter.estimate = 8_000_000
        selection.updateSelectedTrack(0, 5_000_000, 6_000_000, mutableListOf(),
            Array(3) { MediaChunkIterator.EMPTY })
        assertEquals(2_000_000, selection.selectedFormat.bitrate)
    }

    @Test fun briefFailuresNeverSkipMovieContent() {
        var skips = 0
        val policy = StreamingLoadErrorPolicy { _, _, _ -> skips++; SegmentSkip.SKIPPING }
        for ((task, exception) in listOf(SocketTimeoutException(), httpError(503), httpError(429)).withIndex()) {
            for (attempt in 1..3) policy.getRetryDelayMsFor(errorInfo(exception, attempt, task = task.toLong()))
        }
        assertEquals(0, skips)
    }

    @Test fun verifiedBrokenShortSegmentsAreSkippedOncePlaybackReachesThem() {
        var answer = SegmentSkip.SKIPPING
        val skipped = mutableListOf<LoadFailure>()
        val policy = StreamingLoadErrorPolicy { _, _, failure -> skipped += failure; answer }
        // Missing: checked three times.
        assertTrue(policy.getRetryDelayMsFor(errorInfo(httpError(404), 1)) >= 0)
        assertTrue(policy.getRetryDelayMsFor(errorInfo(httpError(404), 2)) >= 0)
        assertEquals(listOf<LoadFailure>(), skipped)
        assertEquals(StreamingLoadErrorPolicy.SKIP_PENDING_RETRY_MS,
            policy.getRetryDelayMsFor(errorInfo(httpError(404), 3)))
        // Corrupt: downloaded once more to rule out a damaged transfer.
        val corrupt = ParserException.createForMalformedContainer("bad", null)
        assertEquals(StreamingLoadErrorPolicy.CORRUPT_RECHECK_MS,
            policy.getRetryDelayMsFor(errorInfo(corrupt, 1, task = 2)))
        assertEquals(StreamingLoadErrorPolicy.SKIP_PENDING_RETRY_MS,
            policy.getRetryDelayMsFor(errorInfo(corrupt, 2, task = 2)))
        // Server errors: four checks.
        for (attempt in 1..3) policy.getRetryDelayMsFor(errorInfo(httpError(502), attempt, task = 3))
        assertEquals(StreamingLoadErrorPolicy.SKIP_PENDING_RETRY_MS,
            policy.getRetryDelayMsFor(errorInfo(httpError(502), 4, task = 3)))
        assertEquals(listOf(LoadFailure.MISSING, LoadFailure.CORRUPT, LoadFailure.SERVER), skipped)
        // Ahead of playback it keeps loading; refused, it surfaces.
        answer = SegmentSkip.NOT_BLOCKING
        assertNotEquals(C.TIME_UNSET, fail(policy, httpError(404), 3, task = 4))
        answer = SegmentSkip.REFUSED
        assertEquals(C.TIME_UNSET, fail(policy, httpError(404), 3, task = 5))
    }

    @Test fun onlyShortMediaSegmentsMaySkip() {
        var skips = 0
        val policy = StreamingLoadErrorPolicy { _, _, _ -> skips++; SegmentSkip.SKIPPING }
        assertEquals(C.TIME_UNSET, fail(policy, httpError(404), 3, C.DATA_TYPE_MANIFEST))
        assertEquals(C.TIME_UNSET, fail(policy, httpError(404), 3, durationMs = 60_000, task = 2))
        assertEquals(C.TIME_UNSET, fail(policy, httpError(404), 3, C.DATA_TYPE_MEDIA_INITIALIZATION, task = 3))
        assertEquals(0, skips)
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
            PlaybackException("manifest", null, PlaybackException.ERROR_CODE_PARSING_MANIFEST_MALFORMED)))
        // A fresh prepare usually revives a failed or reclaimed decoder.
        assertTrue(StreamingLoadErrorPolicy.canRecover(
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

    @Test fun bandwidthChangesAfterRewindDoNotDiscardDownloadedChunks() {
        val meter = MutableBandwidthMeter(8_000_000)
        val selection = selection(meter)
        update(selection, 30_000_000)
        val queuedFormat = selection.selectedFormat
        val queue = (0..4).map { index ->
            object : MediaChunk(ByteArrayDataSource(byteArrayOf(0)), spec, queuedFormat,
                C.SELECTION_REASON_ADAPTIVE, null,
                index * 6_000_000L, (index + 1) * 6_000_000L, index.toLong()) {
                override fun isLoadCompleted() = true
                override fun cancelLoad() = Unit
                override fun load() = Unit
            }
        }.toMutableList()
        // Resume from an earlier buffered position with a collapsed estimate.
        meter.estimate = 700_000
        selection.updateSelectedTrack(0, 30_000_000, C.TIME_UNSET, queue,
            Array(3) { MediaChunkIterator.EMPTY })
        assertEquals(300_000, selection.selectedFormat.bitrate)
        assertEquals(queue.size, selection.evaluateQueueSize(0, queue))
        assertTrue(queue.all { it.trackFormat == queuedFormat })
        meter.estimate = 8_000_000
        selection.updateSelectedTrack(0, 30_000_000, C.TIME_UNSET, queue,
            Array(3) { MediaChunkIterator.EMPTY })
        assertEquals(2_000_000, selection.selectedFormat.bitrate)
        assertEquals(queue.size, selection.evaluateQueueSize(0, queue))
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

    /** Fails one load [times] times, as Media3 reports it, and returns the last decision. */
    private fun fail(
        policy: StreamingLoadErrorPolicy, exception: IOException, times: Int,
        type: Int = C.DATA_TYPE_MEDIA, durationMs: Long = 6000, task: Long = 1
    ): Long = (1..times).map {
        policy.getRetryDelayMsFor(errorInfo(exception, it, type, durationMs, task))
    }.last()

    private fun errorInfo(
        exception: IOException, count: Int, type: Int = C.DATA_TYPE_MEDIA, durationMs: Long = 6000,
        task: Long = 1, spec: DataSpec = this.spec
    ) = LoadErrorHandlingPolicy.LoadErrorInfo(
        LoadEventInfo(task, spec, 0),
        MediaLoadData(type, C.TRACK_TYPE_VIDEO, null, 0, null, 0, durationMs), exception, count)

    private class MutableBandwidthMeter(var estimate: Long) : BandwidthMeter {
        override fun getBitrateEstimate() = estimate
        override fun getTransferListener(): TransferListener? = null
        override fun addEventListener(handler: Handler, listener: BandwidthMeter.EventListener) = Unit
        override fun removeEventListener(listener: BandwidthMeter.EventListener) = Unit
    }
}
