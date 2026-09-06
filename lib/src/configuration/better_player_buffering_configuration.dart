///Configuration class used to setup better buffering experience or setup custom
///load settings. Currently used only in Android.
class BetterPlayerBufferingConfiguration {
  const BetterPlayerBufferingConfiguration({
    this.minBufferMs = defaultMinBufferMs,
    this.maxBufferMs = defaultMaxBufferMs,
    this.bufferForPlaybackMs = defaultBufferForPlaybackMs,
    this.bufferForPlaybackAfterRebufferMs = defaultBufferForPlaybackAfterRebufferMs,
    this.backBufferDurationMs = defaultBackBufferDurationMs,
    this.retainBackBufferFromKeyframe = defaultRetainBackBufferFromKeyframe,
    this.prioritizeTimeOverSizeThresholds = defaultPrioritizeTimeOverSizeThresholds,
  });

  /// Streaming defaults: quick startup, an early refill, and bounded retention.
  /// Android also applies device-dependent duration and sample-memory ceilings.
  static const defaultMinBufferMs = 45000;
  static const defaultMaxBufferMs = 120000;
  static const defaultBufferForPlaybackMs = 1500;
  static const defaultBufferForPlaybackAfterRebufferMs = 5000;
  static const defaultBackBufferDurationMs = 15000;
  static const defaultRetainBackBufferFromKeyframe = false;
  static const defaultPrioritizeTimeOverSizeThresholds = true;

  /// The default minimum duration of media that the player will attempt to
  /// ensure is buffered at all times, in milliseconds.
  final int minBufferMs;

  /// The default maximum duration of media that the player will attempt to
  /// buffer, in milliseconds.
  final int maxBufferMs;

  /// The default duration of media that must be buffered for playback to start
  /// or resume following a user action such as a seek, in milliseconds.
  final int bufferForPlaybackMs;

  /// The default duration of media that must be buffered for playback to resume
  /// after a rebuffer, in milliseconds. A rebuffer is defined to be caused by
  /// buffer depletion rather than a user action.
  final int bufferForPlaybackAfterRebufferMs;

  /// Duration of already-played media retained in memory for fast backward
  /// seeks. This is not a persistent disk cache.
  final int backBufferDurationMs;

  /// Whether the back buffer may extend to the keyframe preceding its nominal
  /// start. Disabling this gives memory-constrained devices a firmer bound.
  final bool retainBackBufferFromKeyframe;

  /// Whether loading should continue until the time-based buffer target is
  /// reached even when the allocator's byte target has already been met.
  final bool prioritizeTimeOverSizeThresholds;
}
