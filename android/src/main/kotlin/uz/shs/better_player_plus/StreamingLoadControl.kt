package uz.shs.better_player_plus

import android.app.ActivityManager
import android.content.Context
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.LoadControl

/** Time-based refills with a byte ceiling, including retained back-buffer samples. */
@UnstableApi
internal class StreamingLoadControl(
    private val delegate: LoadControl,
    private val maxBytes: Int
) : LoadControl by delegate {
    override fun shouldContinueLoading(parameters: LoadControl.Parameters): Boolean {
        val shouldLoad = delegate.shouldContinueLoading(parameters)
        return delegate.allocator.totalBytesAllocated < maxBytes && shouldLoad
    }

    override fun shouldStartPlayback(parameters: LoadControl.Parameters): Boolean {
        // A high-bitrate segment can hit the byte limit before the time threshold.
        // Permit playback to drain it instead of deadlocking startup/rebuffering.
        return delegate.shouldStartPlayback(parameters) ||
            (delegate.allocator.totalBytesAllocated >= maxBytes && parameters.bufferedDurationUs > 0)
    }

    companion object {
        fun create(context: Context, configuration: CustomDefaultLoadControl): LoadControl {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val lowMemory = activityManager.isLowRamDevice || activityManager.memoryClass <= 128
            val maxBytes = memoryBudgetBytes(activityManager.memoryClass, lowMemory)
            val maxBufferMs = configuration.maxBufferMs.coerceIn(1_000, if (lowMemory) 60_000 else 180_000)
            val startupMs = configuration.bufferForPlaybackMs.coerceIn(0, maxBufferMs)
            val rebufferMs = configuration.bufferForPlaybackAfterRebufferMs.coerceIn(0, maxBufferMs)
            val minBufferMs = configuration.minBufferMs.coerceIn(maxOf(startupMs, rebufferMs), maxBufferMs)
            val delegate = DefaultLoadControl.Builder()
                .setBufferDurationsMs(minBufferMs, maxBufferMs, startupMs, rebufferMs)
                .setBackBuffer(
                    configuration.backBufferDurationMs.coerceIn(0, if (lowMemory) 0 else 15_000),
                    !lowMemory && configuration.retainBackBufferFromKeyframe
                )
                .setTargetBufferBytes(maxBytes)
                .setPrioritizeTimeOverSizeThresholds(configuration.prioritizeTimeOverSizeThresholds)
                .build()
            // Media3 checks between loads; an individual segment can overshoot this
            // budget. It is a sample-buffer budget, not a total-process heap limit.
            return StreamingLoadControl(delegate, maxBytes)
        }

        internal fun memoryBudgetBytes(memoryClassMb: Int, lowMemory: Boolean): Int =
            (memoryClassMb / 4).coerceIn(8, if (lowMemory) 24 else 64) * 1024 * 1024
    }
}
