package uz.shs.better_player_plus

import androidx.media3.common.PlaybackException

/** Recover an expired live position locally, but surface persistent bad manifests. */
internal class LiveWindowRecovery {
    private var lastRecoveryMs: Long? = null

    fun reset() { lastRecoveryMs = null }

    fun shouldRecover(isLive: Boolean, errorCode: Int, elapsedMs: Long): Boolean {
        if (!isLive || errorCode != PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) return false
        val previous = lastRecoveryMs
        if (previous != null && elapsedMs - previous < 30_000) return false
        lastRecoveryMs = elapsedMs
        return true
    }
}
