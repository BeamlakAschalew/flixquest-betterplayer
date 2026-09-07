package uz.shs.better_player_plus

import androidx.media3.common.C
import androidx.media3.common.PlaybackException
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy

/** Bounded local retries before the application can recover or choose another source. */
@UnstableApi
internal class StreamingLoadErrorPolicy(
    private val isLive: Boolean = false,
    private val onMissingSegment: ((Long, Long) -> Boolean)? = null
) : DefaultLoadErrorHandlingPolicy(6) {
    override fun getRetryDelayMsFor(info: LoadErrorHandlingPolicy.LoadErrorInfo): Long {
        val response = info.exception as? HttpDataSource.InvalidResponseCodeException
        // Retrying an expired token or an invalid request with the same URL is futile.
        if (response != null && response.responseCode in listOf(400, 401, 403, 405, 416)) {
            return C.TIME_UNSET
        }
        // A segment may not yet be published on the first 404, or may already
        // have left the moving window. Let the app refresh after a brief retry.
        if (isLive && response?.responseCode in listOf(404, 410) && info.errorCount >= 2) {
            return C.TIME_UNSET
        }
        val media = info.mediaLoadData
        val durationMs = media.mediaEndTimeMs - media.mediaStartTimeMs
        if (!isLive && response?.responseCode in listOf(404, 410) &&
            info.errorCount >= 3 && media.dataType == C.DATA_TYPE_MEDIA &&
            media.mediaStartTimeMs != C.TIME_UNSET && media.mediaEndTimeMs != C.TIME_UNSET &&
            durationMs in 1..30_000 &&
            onMissingSegment?.invoke(media.mediaStartTimeMs, media.mediaEndTimeMs) == true
        ) {
            return C.TIME_UNSET
        }
        if (info.errorCount >= 6) return C.TIME_UNSET
        // Preserve Media3's non-retryable parser/file/security error classification.
        return super.getRetryDelayMsFor(info)
    }

    companion object {
        fun canRecover(error: PlaybackException): Boolean {
            val response = generateSequence<Throwable>(error) { it.cause }.take(20)
                .filterIsInstance<HttpDataSource.InvalidResponseCodeException>().firstOrNull()
            if (response != null) {
                return response.responseCode == 408 || response.responseCode == 429 ||
                    response.responseCode in 500..599
            }
            return error.errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED ||
                error.errorCode == PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT ||
                error.errorCode == PlaybackException.ERROR_CODE_IO_UNSPECIFIED
        }
    }
}
