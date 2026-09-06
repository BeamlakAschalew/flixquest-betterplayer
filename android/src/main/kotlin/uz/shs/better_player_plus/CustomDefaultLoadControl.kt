package uz.shs.better_player_plus

import androidx.media3.common.util.UnstableApi

@UnstableApi
internal class CustomDefaultLoadControl {
    /**
     * The default minimum duration of media that the player will attempt to ensure is buffered
     * at all times, in milliseconds.
     */
    @JvmField
    val minBufferMs: Int

    /**
     * The default maximum duration of media that the player will attempt to buffer, in milliseconds.
     */
    @JvmField
    val maxBufferMs: Int

    /**
     * The default duration of media that must be buffered for playback to start or resume following
     * a user action such as a seek, in milliseconds.
     */
    @JvmField
    val bufferForPlaybackMs: Int

    /**
     * he default duration of media that must be buffered for playback to resume after a rebuffer,
     * in milliseconds. A rebuffer is defined to be caused by buffer depletion rather than a user
     * action.
     */
    @JvmField
    val bufferForPlaybackAfterRebufferMs: Int

    /** Duration of already-played media retained for fast backward seeks. */
    @JvmField
    val backBufferDurationMs: Int

    /** Whether the back buffer extends to the keyframe before its nominal start. */
    @JvmField
    val retainBackBufferFromKeyframe: Boolean

    /** Continue loading to the time threshold even when the byte target is met. */
    @JvmField
    val prioritizeTimeOverSizeThresholds: Boolean

    constructor() {
        minBufferMs = 45_000
        maxBufferMs = 120_000
        bufferForPlaybackMs = 1_500
        bufferForPlaybackAfterRebufferMs =
            5_000
        backBufferDurationMs = 15_000
        retainBackBufferFromKeyframe = false
        prioritizeTimeOverSizeThresholds = true
    }

    constructor(
        minBufferMs: Int?,
        maxBufferMs: Int?,
        bufferForPlaybackMs: Int?,
        bufferForPlaybackAfterRebufferMs: Int?,
        backBufferDurationMs: Int?,
        retainBackBufferFromKeyframe: Boolean?,
        prioritizeTimeOverSizeThresholds: Boolean?
    ) {
        this.minBufferMs = minBufferMs ?: 45_000
        this.maxBufferMs = maxBufferMs ?: 120_000
        this.bufferForPlaybackMs =
            bufferForPlaybackMs ?: 1_500
        this.bufferForPlaybackAfterRebufferMs = bufferForPlaybackAfterRebufferMs
            ?: 5_000
        this.backBufferDurationMs = backBufferDurationMs ?: 15_000
        this.retainBackBufferFromKeyframe = retainBackBufferFromKeyframe ?: false
        this.prioritizeTimeOverSizeThresholds = prioritizeTimeOverSizeThresholds ?: true
    }
}
