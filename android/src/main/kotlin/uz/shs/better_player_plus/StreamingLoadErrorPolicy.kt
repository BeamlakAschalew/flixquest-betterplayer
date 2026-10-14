package uz.shs.better_player_plus

import android.os.SystemClock
import androidx.media3.common.C
import androidx.media3.common.ParserException
import androidx.media3.common.PlaybackException
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSourceException
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.Loader
import java.io.IOException
import java.net.ConnectException
import java.net.NoRouteToHostException
import java.net.SocketException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.concurrent.ConcurrentHashMap
import javax.net.ssl.SSLException
import kotlin.math.min

/** What a failed load says about the stream, as opposed to the network. */
internal enum class LoadFailure(val hasResponse: Boolean = false) {
    /** No usable response: DNS, connect, reset or timeout. Says nothing about the stream. */
    CONNECTIVITY,
    /** 404/410: the server says this resource is gone. */
    MISSING(hasResponse = true),
    /** 408/429/5xx: the server answered but could not serve it right now. */
    SERVER(hasResponse = true),
    /** Other 4xx, e.g. an expired token. The same URL will not start working again. */
    REJECTED(hasResponse = true),
    /** The bytes arrived but cannot be parsed. */
    CORRUPT,
    OTHER,
}

/** Answer to "may playback skip this broken segment now?". */
internal enum class SegmentSkip {
    /** A seek past the segment has been posted; keep retrying until it lands. */
    SKIPPING,
    /** Playback has not reached the segment yet; decide again on the next failure. */
    NOT_BLOCKING,
    /** Skipping would not help (too many in a row, or the host itself looks down). */
    REFUSED,
}

/**
 * Decides, per failed load, between waiting, retrying, skipping a broken
 * segment and giving up.
 *
 * - While the device is offline a remote load retries every second for as
 *   long as it takes, so a dropped connection never ends in a playback error.
 * - Online, a failure is checked a few times quickly. A short VOD media
 *   segment that is verifiably broken (missing, corrupt, or refused by a host
 *   that has otherwise been serving) is skipped once playback reaches it.
 * - Anything else gives up after a short, bounded budget so the app can
 *   reload the source or choose another one.
 *
 * Only this policy ends a load: Media3's own error-count threshold is disabled
 * by [getMinimumLoadableRetryCount], because it would surface an error while
 * the loader is still waiting for the network.
 */
@UnstableApi
internal class StreamingLoadErrorPolicy(
    private val isLive: Boolean = false,
    private val isOnline: () -> Boolean = { true },
    private val onSuspectedOutage: () -> Unit = {},
    private val nowMs: () -> Long = SystemClock::elapsedRealtime,
    /** Called on the playback thread with the segment's start and end, in ms. */
    private val onBrokenSegment: ((Long, Long, LoadFailure) -> SegmentSkip)? = null
) : DefaultLoadErrorHandlingPolicy() {

    private class Attempts {
        var lastErrorCount = 0
        var online = 0
        var firstOnlineFailureMs = 0L
        var waitedOffline = false
    }

    private data class Attempt(val count: Int, val elapsedMs: Long)

    private val attempts = ConcurrentHashMap<Long, Attempts>()

    override fun getMinimumLoadableRetryCount(dataType: Int): Int = Int.MAX_VALUE

    override fun onLoadTaskConcluded(loadTaskId: Long) {
        attempts.remove(loadTaskId)
    }

    override fun getFallbackSelectionFor(
        fallbackOptions: LoadErrorHandlingPolicy.FallbackOptions,
        loadErrorInfo: LoadErrorHandlingPolicy.LoadErrorInfo
    ): LoadErrorHandlingPolicy.FallbackSelection? {
        val failure = classify(loadErrorInfo.exception)
        if (!failure.hasResponse && isRemote(loadErrorInfo) && !isOnline()) return null
        // Before skipping content, let HLS/DASH try the same segment in another
        // rendition: one variant's file may be broken or unreachable when the
        // others are fine. Media3 already does this for 403/404/410/416/500/503.
        val tryOtherRendition = loadErrorInfo.errorCount >= 2 &&
            (failure == LoadFailure.CONNECTIVITY || failure == LoadFailure.SERVER ||
                failure == LoadFailure.CORRUPT)
        if (tryOtherRendition &&
            fallbackOptions.isFallbackAvailable(LoadErrorHandlingPolicy.FALLBACK_TYPE_TRACK)
        ) {
            return LoadErrorHandlingPolicy.FallbackSelection(
                LoadErrorHandlingPolicy.FALLBACK_TYPE_TRACK, RENDITION_EXCLUSION_MS
            )
        }
        return super.getFallbackSelectionFor(fallbackOptions, loadErrorInfo)
    }

    override fun getRetryDelayMsFor(info: LoadErrorHandlingPolicy.LoadErrorInfo): Long {
        val failure = classify(info.exception)
        // Retrying an expired token or an invalid request with the same URL is futile.
        if (failure == LoadFailure.REJECTED) return C.TIME_UNSET
        // A status code proves the network works, whatever Android reports.
        val online = failure.hasResponse || !isRemote(info) || isOnline()
        val attempt = record(info, online)
        if (!online) return OFFLINE_RETRY_MS
        if (failure == LoadFailure.CONNECTIVITY && attempt.count == OUTAGE_CHECK_ATTEMPT) {
            onSuspectedOutage()
        }
        return if (isLive) liveRetryDelay(info, failure, attempt) else vodRetryDelay(info, failure, attempt)
    }

    private fun liveRetryDelay(
        info: LoadErrorHandlingPolicy.LoadErrorInfo, failure: LoadFailure, attempt: Attempt
    ): Long = when (failure) {
        // A segment may not yet be published on the first 404, or may already
        // have left the moving window. Let the app refresh after a brief retry.
        LoadFailure.MISSING -> if (attempt.count >= 2) C.TIME_UNSET else LIVE_MISSING_RECHECK_MS
        LoadFailure.CONNECTIVITY -> if (networkBudgetSpent(attempt)) C.TIME_UNSET else backoff(attempt, 500, 3_000)
        LoadFailure.CORRUPT -> if (attempt.count >= CORRUPT_CHECKS) C.TIME_UNSET else CORRUPT_RECHECK_MS
        else -> boundedRetry(info, failure, attempt)
    }

    private fun vodRetryDelay(
        info: LoadErrorHandlingPolicy.LoadErrorInfo, failure: LoadFailure, attempt: Attempt
    ): Long {
        val media = info.mediaLoadData
        val durationMs = media.mediaEndTimeMs - media.mediaStartTimeMs
        val skippableSegment = onBrokenSegment != null && media.dataType == C.DATA_TYPE_MEDIA &&
            media.mediaStartTimeMs != C.TIME_UNSET && media.mediaEndTimeMs != C.TIME_UNSET &&
            durationMs in 1..MAX_SKIPPABLE_SEGMENT_MS
        if (skippableSegment && isVerifiedBroken(failure, attempt)) {
            return when (onBrokenSegment?.invoke(media.mediaStartTimeMs, media.mediaEndTimeMs, failure)) {
                SegmentSkip.SKIPPING -> SKIP_PENDING_RETRY_MS
                // Keep checking: once playback reaches it, the next failure
                // skips it, so playback stalls on it for a second at most.
                SegmentSkip.NOT_BLOCKING -> AHEAD_OF_PLAYBACK_RETRY_MS
                SegmentSkip.REFUSED, null -> C.TIME_UNSET
            }
        }
        return when (failure) {
            LoadFailure.CONNECTIVITY -> if (networkBudgetSpent(attempt)) C.TIME_UNSET else backoff(attempt, 500, 3_000)
            LoadFailure.MISSING -> if (attempt.count >= MISSING_CHECKS) C.TIME_UNSET else backoff(attempt, 300, 700)
            LoadFailure.CORRUPT -> if (attempt.count >= CORRUPT_CHECKS) C.TIME_UNSET else CORRUPT_RECHECK_MS
            else -> boundedRetry(info, failure, attempt)
        }
    }

    /** Checked enough times that skipping the segment is a fix rather than a guess. */
    private fun isVerifiedBroken(failure: LoadFailure, attempt: Attempt): Boolean = when (failure) {
        LoadFailure.MISSING -> attempt.count >= MISSING_CHECKS
        LoadFailure.CORRUPT, LoadFailure.OTHER -> attempt.count >= CORRUPT_CHECKS
        LoadFailure.SERVER -> attempt.count >= SERVER_CHECKS
        LoadFailure.CONNECTIVITY -> networkBudgetSpent(attempt)
        LoadFailure.REJECTED -> false
    }

    private fun boundedRetry(
        info: LoadErrorHandlingPolicy.LoadErrorInfo, failure: LoadFailure, attempt: Attempt
    ): Long {
        if (attempt.count >= MAX_ONLINE_ATTEMPTS) return C.TIME_UNSET
        // Preserve Media3's non-retryable file/security error classification.
        if (failure == LoadFailure.OTHER && super.getRetryDelayMsFor(info) == C.TIME_UNSET) return C.TIME_UNSET
        return backoff(attempt, 500, 4_000)
    }

    private fun networkBudgetSpent(attempt: Attempt): Boolean =
        attempt.elapsedMs >= ONLINE_NETWORK_HARD_BUDGET_MS ||
            (attempt.count >= ONLINE_NETWORK_MIN_ATTEMPTS && attempt.elapsedMs >= ONLINE_NETWORK_BUDGET_MS)

    /** Counts failures while online only; reconnecting starts a fresh budget. */
    private fun record(info: LoadErrorHandlingPolicy.LoadErrorInfo, online: Boolean): Attempt {
        val state = attempts.getOrPut(info.loadEventInfo.loadTaskId) { Attempts() }
        synchronized(state) {
            // Media3 restarts errorCount when a progressive load made progress.
            if (info.errorCount <= state.lastErrorCount) resetOnline(state)
            state.lastErrorCount = info.errorCount
            if (!online) {
                state.waitedOffline = true
                return Attempt(state.online, 0)
            }
            if (state.waitedOffline) {
                state.waitedOffline = false
                resetOnline(state)
            }
            val now = nowMs()
            if (state.online == 0) state.firstOnlineFailureMs = now
            state.online++
            return Attempt(state.online, now - state.firstOnlineFailureMs)
        }
    }

    private fun resetOnline(state: Attempts) {
        state.online = 0
        state.firstOnlineFailureMs = 0L
    }

    private fun backoff(attempt: Attempt, baseMs: Long, maxMs: Long): Long {
        val exponent = (attempt.count - 1).coerceIn(0, 6)
        return min(baseMs shl exponent, maxMs)
    }

    private fun isRemote(info: LoadErrorHandlingPolicy.LoadErrorInfo): Boolean {
        val scheme = info.loadEventInfo.uri.scheme?.lowercase()
        return scheme == "http" || scheme == "https"
    }

    companion object {
        internal const val OFFLINE_RETRY_MS = 1_000L
        internal const val SKIP_PENDING_RETRY_MS = 1_000L
        internal const val AHEAD_OF_PLAYBACK_RETRY_MS = 1_000L
        internal const val CORRUPT_RECHECK_MS = 300L
        internal const val LIVE_MISSING_RECHECK_MS = 300L
        internal const val MAX_SKIPPABLE_SEGMENT_MS = 30_000L
        internal const val MISSING_CHECKS = 3
        internal const val CORRUPT_CHECKS = 2
        internal const val SERVER_CHECKS = 4
        internal const val MAX_ONLINE_ATTEMPTS = 6
        internal const val OUTAGE_CHECK_ATTEMPT = 2
        internal const val ONLINE_NETWORK_MIN_ATTEMPTS = 3
        internal const val ONLINE_NETWORK_BUDGET_MS = 10_000L
        internal const val ONLINE_NETWORK_HARD_BUDGET_MS = 25_000L
        private const val RENDITION_EXCLUSION_MS = 30_000L

        fun classify(error: IOException): LoadFailure {
            val causes = generateSequence<Throwable>(error) { it.cause }.take(20).toList()
            causes.filterIsInstance<HttpDataSource.InvalidResponseCodeException>().firstOrNull()?.let {
                return when (it.responseCode) {
                    404, 410 -> LoadFailure.MISSING
                    408, 429, in 500..599 -> LoadFailure.SERVER
                    in 400..499 -> LoadFailure.REJECTED
                    else -> LoadFailure.SERVER
                }
            }
            if (causes.any { it is ParserException || it is Loader.UnexpectedLoaderException }) {
                return LoadFailure.CORRUPT
            }
            if (causes.any(::isConnectivityCause)) return LoadFailure.CONNECTIVITY
            val reason = causes.filterIsInstance<DataSourceException>().firstOrNull()?.reason
            if (reason == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED ||
                reason == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT
            ) {
                return LoadFailure.CONNECTIVITY
            }
            return LoadFailure.OTHER
        }

        private fun isConnectivityCause(error: Throwable): Boolean =
            error is UnknownHostException || error is ConnectException || error is NoRouteToHostException ||
                error is SocketTimeoutException || error is SocketException || error is SSLException ||
                error is org.chromium.net.NetworkException

        fun canRecover(error: PlaybackException): Boolean {
            val response = generateSequence<Throwable>(error) { it.cause }.take(20)
                .filterIsInstance<HttpDataSource.InvalidResponseCodeException>().firstOrNull()
            if (response != null) {
                return response.responseCode == 408 || response.responseCode == 429 ||
                    response.responseCode in 500..599
            }
            return error.errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED ||
                error.errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT ||
                error.errorCode == PlaybackException.ERROR_CODE_IO_UNSPECIFIED ||
                error.errorCode == PlaybackException.ERROR_CODE_TIMEOUT ||
                // A decoder that failed or was reclaimed usually works again
                // once the source is prepared afresh.
                error.errorCode == PlaybackException.ERROR_CODE_DECODING_FAILED ||
                error.errorCode == PlaybackException.ERROR_CODE_DECODING_RESOURCES_RECLAIMED
        }
    }
}
