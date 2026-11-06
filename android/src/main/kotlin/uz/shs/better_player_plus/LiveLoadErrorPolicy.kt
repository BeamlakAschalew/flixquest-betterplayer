package uz.shs.better_player_plus

import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.HttpDataSource
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy

/**
 * Load-error handling for live streams: a few bounded local retries, then the
 * error reaches the app, whose live player switches mirrors or resolves the
 * channel again.
 *
 * Live streams deliberately keep this behavior rather than
 * [StreamingLoadErrorPolicy]'s. That policy waits indefinitely while Android
 * reports the device offline, and Android's validation can fail while the
 * internet works; a live stream then stalls without ever letting the app fail
 * over.
 */
@UnstableApi
internal class LiveLoadErrorPolicy : DefaultLoadErrorHandlingPolicy(6) {
    override fun getRetryDelayMsFor(info: LoadErrorHandlingPolicy.LoadErrorInfo): Long {
        val response = info.exception as? HttpDataSource.InvalidResponseCodeException
        // Retrying an expired token or an invalid request with the same URL is futile.
        if (response != null && response.responseCode in listOf(400, 401, 403, 405, 416)) {
            return C.TIME_UNSET
        }
        // A segment may not yet be published on the first 404, or may already
        // have left the moving window. Let the app refresh after a brief retry.
        if (response?.responseCode in listOf(404, 410) && info.errorCount >= 2) {
            return C.TIME_UNSET
        }
        if (info.errorCount >= 6) return C.TIME_UNSET
        // Preserve Media3's non-retryable parser/file/security error classification.
        return super.getRetryDelayMsFor(info)
    }
}
