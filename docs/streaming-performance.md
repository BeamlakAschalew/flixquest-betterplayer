# Streaming resilience

The Android backend uses conservative adaptive quality selection, a shared
per-player bandwidth estimate, and a memory-capped forward buffer. Quality
upgrades wait for headroom; rebuffering temporarily reduces the bandwidth budget.
Available manifest renditions still determine the lowest sustainable bitrate.

Cronet initializes asynchronously through Google Play Services. New sources use
it when available and otherwise use the default HTTP transport without delaying
startup. Neither transport guarantees HTTP/3 on every server.

Movie recovery retries eligible network failures with bounded source reloads,
preserving position and pause state. Permanent HTTP failures surface immediately.
Timeouts do not trigger missing-segment skipping.

## Backward seeks

Android retains up to 60 seconds of played samples by default, including the
keyframe preceding the retention boundary. FlixQuest requests 15 seconds on TV
and 60 seconds on phones; low-memory Android devices cap either request at 15
seconds. Forward and backward samples share the existing byte ceiling. Memory
pressure can shorten retention; these durations are not a guaranteed cache.

Media3 HLS seeks inside retained samples preserve the forward queue. Seeking
outside those samples resets the queues and reloads from the seek position.
Without the preceding keyframe, even a seek near the retention boundary can
require that reset. FlixQuest streaming has no persistent media cache, so older
played segments cannot be assumed to remain on disk. The previous configuration
retained only 15 seconds on phones and none on TVs or low-memory Android devices.

Adaptive bandwidth selection applies to future loads. The track selection policy
keeps queued chunks during both quality upgrades and downgrades. A lower quality
after an out-of-buffer seek can follow the reset and depleted buffer rather than
cause it. Verify on a device by buffering ahead, rewinding within the retained
window under reduced bandwidth, and checking that the buffered end is preserved.
Also check a seek beyond the window, where a reload is expected.

## Live streams

FlixQuest supplies a separate live configuration: 10-second minimum and
30-second maximum forward buffer, 1.5-second startup, 3-second rebuffer threshold,
and no retained back buffer. These are loading targets, not guaranteed latency;
the manifest controls the live offset and available media window.

Android seeks to the default live position after a behind-live-window error,
at most once per 30 seconds. Repeated missing live segments surface for source
refresh instead of using movie segment skipping. Catch-up speed is capped at
1.01x to limit additional bandwidth demand.

The app owns live source recovery. It refreshes source URLs with bounded backoff
within a five-minute recovery window. A watchdog detects no playback or buffer
progress for 25 seconds, or no playback for 60 seconds despite buffer growth.
Paused playback is excluded. Sustained playback clears recovery; abruptly ended
broadcasts also enter recovery. Source resolution has a 30-second timeout, which
does not cancel an underlying provider request already in flight.

## Measuring on a device

Enable local Android diagnostics before opening a source:

```sh
adb shell setprop log.tag.BetterPlayerStreaming DEBUG
adb logcat -s BetterPlayerStreaming
```

The log includes first-frame time, buffer duration, bandwidth estimate, selected
bitrate, sampled media-load durations and error counts. It excludes source URLs
and headers. Buffering state transitions include startup and seeks, so their
count is not a rebuffer count. Disable with:

```sh
adb shell setprop log.tag.BetterPlayerStreaming INFO
```

Compare the same HLS and DASH sources before and after changes under controlled
bandwidth, latency, packet loss and short outages. Include live window expiry,
404/410 segments, token refresh, pause, channel switching and low-memory devices.
Record startup time, actual stalls, quality, live latency and memory use.
Automated tests verify policy and recovery behavior; they do not establish
real-network performance or guarantee uninterrupted playback.
