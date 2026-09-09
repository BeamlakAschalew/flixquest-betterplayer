package uz.shs.better_player_plus

import androidx.media3.common.Format
import androidx.media3.common.TrackGroup
import androidx.media3.common.util.Clock
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.source.chunk.MediaChunk
import androidx.media3.exoplayer.source.chunk.MediaChunkIterator
import androidx.media3.exoplayer.trackselection.AdaptiveTrackSelection
import androidx.media3.exoplayer.upstream.BandwidthMeter
import com.google.common.collect.ImmutableList

/** Keep Media3's track exclusions, live-edge handling and audio/video bandwidth allocation. */
@UnstableApi
internal class StreamingTrackSelection(
    group: TrackGroup,
    tracks: IntArray,
    type: Int,
    bandwidthMeter: BandwidthMeter,
    checkpoints: List<AdaptationCheckpoint>,
    upgradeBufferMs: Long,
    private val policyClock: Clock = Clock.DEFAULT
) : AdaptiveTrackSelection(
    group, tracks, type, bandwidthMeter,
    upgradeBufferMs, 60_000, upgradeBufferMs,
    0, 0, 0.65f, DEFAULT_BUFFERED_FRACTION_TO_LIVE_EDGE_FOR_QUALITY_INCREASE,
    checkpoints, policyClock
) {
    private var recoveringUntilMs = 0L
    private var bufferLow = false

    override fun onRebuffer() {
        recoveringUntilMs = policyClock.elapsedRealtime() + 45_000L
    }

    override fun updateSelectedTrack(
        playbackPositionUs: Long,
        bufferedDurationUs: Long,
        availableDurationUs: Long,
        queue: MutableList<out MediaChunk>,
        mediaChunkIterators: Array<out MediaChunkIterator>
    ) {
        bufferLow = bufferedDurationUs < 10_000_000L
        super.updateSelectedTrack(
            playbackPositionUs, bufferedDurationUs, availableDurationUs, queue, mediaChunkIterators
        )
    }

    override fun canSelectFormat(format: Format, trackBitrate: Int, effectiveBitrate: Long): Boolean {
        // Approximately 55% of estimated throughput during startup or recovery,
        // versus 65% normally. Let Media3 choose the lowest track if none fits.
        val budget = if (bufferLow || policyClock.elapsedRealtime() < recoveringUntilMs) {
            (effectiveBitrate * (0.55 / 0.65)).toLong()
        } else effectiveBitrate
        return super.canSelectFormat(format, trackBitrate, budget)
    }

    // Downloaded media is the outage reserve. Never discard it just to upgrade.
    override fun evaluateQueueSize(playbackPositionUs: Long, queue: MutableList<out MediaChunk>): Int =
        queue.size

    class Factory(private val maxBufferMs: Int) : AdaptiveTrackSelection.Factory() {
        override fun createAdaptiveTrackSelection(
            group: TrackGroup,
            tracks: IntArray,
            type: Int,
            bandwidthMeter: BandwidthMeter,
            adaptationCheckpoints: ImmutableList<AdaptationCheckpoint>
        ): AdaptiveTrackSelection = StreamingTrackSelection(
            group, tracks, type, bandwidthMeter, adaptationCheckpoints,
            // A user's small buffer setting must not make upgrades impossible.
            (maxBufferMs / 2).coerceIn(1_000, 20_000).toLong()
        )
    }
}
