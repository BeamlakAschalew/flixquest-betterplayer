package uz.shs.better_player_plus

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.exoplayer.analytics.PlayerId
import androidx.media3.exoplayer.source.SampleQueue
import androidx.media3.exoplayer.upstream.DefaultAllocator
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], manifest = Config.NONE)
class StreamingBackBufferTest {
    @Test fun rewindNearRetentionBoundaryKeepsDecodableSamplesAndForwardBuffer() {
        for ((requestedMs, lowMemory, expectedMs) in listOf(
            Triple(60_000, false, 60_000),
            Triple(15_000, false, 15_000),
            Triple(60_000, true, 15_000)
        )) {
            val configuration = configuration(requestedMs, true)
            val control = StreamingLoadControl.create(configuration, if (lowMemory) 128 else 256, lowMemory)
            val id = PlayerId.UNSET
            control.onPrepared(id)
            val queue = sampleQueue(control.allocator as DefaultAllocator)
            try {
                assertEquals(expectedMs * 1000L, control.getBackBufferDurationUs(id))
                assertTrue(control.retainBackBufferFromKeyframe(id))
                val positionUs = (expectedMs + 20_000) * 1000L
                assertTrue(queue.seekTo(positionUs, false))
                // Use the same discard/seek operations as HlsSampleStreamWrapper.
                // The cutoff is 20s; decoding a seek to 21s needs the 18s keyframe.
                queue.discardTo(positionUs - control.getBackBufferDurationUs(id),
                    control.retainBackBufferFromKeyframe(id), true)
                val bufferedEndUs = queue.largestQueuedTimestampUs
                val bytes = control.allocator.totalBytesAllocated
                assertTrue(queue.seekTo(21_000_000L, false))
                assertEquals(18, queue.readIndex)
                assertEquals(199_000_000L, bufferedEndUs)
                assertEquals(bufferedEndUs, queue.largestQueuedTimestampUs)
                assertEquals(bytes, control.allocator.totalBytesAllocated)
                // Older, already discarded samples still require a reload.
                assertFalse(queue.seekTo(12_000_000L, false))
            } finally {
                queue.release()
                control.onReleased(id)
            }
        }
    }

    @Test fun discardingWithoutKeyframeRetentionReproducesFailedInBufferSeek() {
        val queue = sampleQueue(DefaultAllocator(true, C.DEFAULT_BUFFER_SEGMENT_SIZE))
        try {
            assertTrue(queue.seekTo(35_000_000L, false))
            queue.discardTo(20_000_000L, false, true)
            assertFalse(queue.seekTo(21_000_000L, false))
        } finally {
            queue.release()
        }
    }

    @Test fun explicitZeroBackBufferStillDisablesRetention() {
        for (lowMemory in listOf(false, true)) {
            val control = StreamingLoadControl.create(configuration(0, true), 128, lowMemory)
            assertEquals(0L, control.getBackBufferDurationUs(PlayerId.UNSET))
            assertFalse(control.retainBackBufferFromKeyframe(PlayerId.UNSET))
        }
    }

    @Test fun nativeDefaultsAndLegacyNullArgumentsKeepTheSameRewindWindow() {
        for (configuration in listOf(CustomDefaultLoadControl(),
            CustomDefaultLoadControl(null, null, null, null, null, null, null))) {
            assertEquals(60_000, configuration.backBufferDurationMs)
            assertTrue(configuration.retainBackBufferFromKeyframe)
        }
    }

    private fun configuration(backBufferMs: Int, retainKeyframe: Boolean) =
        CustomDefaultLoadControl(null, null, null, null, backBufferMs, retainKeyframe, null)

    private fun sampleQueue(allocator: DefaultAllocator): SampleQueue =
        SampleQueue.createWithoutDrm(allocator).apply {
            format(Format.Builder().setSampleMimeType(MimeTypes.VIDEO_H264).build())
            for (second in 0 until 200) {
                sampleData(ParsableByteArray(byteArrayOf(0)), 1)
                sampleMetadata(second * 1_000_000L,
                    if (second % 6 == 0) C.BUFFER_FLAG_KEY_FRAME else 0, 1, 0, null)
            }
        }
}
