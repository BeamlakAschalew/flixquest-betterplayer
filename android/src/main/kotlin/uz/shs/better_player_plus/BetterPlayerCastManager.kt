package uz.shs.better_player_plus

import android.content.Context
import android.net.Uri
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.MediaStatus
import com.google.android.gms.cast.framework.CastContext
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import com.google.android.gms.cast.framework.SessionManagerListener
import com.google.android.gms.common.images.WebImage
import org.json.JSONObject

@OptIn(UnstableApi::class)
internal class BetterPlayerCastManager(
    context: Context,
    private val playerFor: (Long) -> BetterPlayer?,
    private val dataSourceFor: (Long) -> Map<String, Any?>?,
    private val configurationFor: (Long) -> Map<String, Any?>?
) : SessionManagerListener<CastSession>, RemoteMediaClient.Callback() {
    private val castContext = CastContext.getSharedInstance(context.applicationContext)
    private val sessionManager = castContext.sessionManager
    private var targetTextureId: Long? = null
    private var remoteMediaClient: RemoteMediaClient? = null
    private var lastRemotePositionMs = 0L
    private var resumeLocalPlayback = false

    init {
        sessionManager.addSessionManagerListener(this, CastSession::class.java)
        sessionManager.currentCastSession?.takeIf { it.isConnected }?.let(::attachSession)
    }

    fun setTarget(textureId: Long) {
        targetTextureId = textureId
        sessionManager.currentCastSession?.takeIf { it.isConnected }?.let {
            attachSession(it)
            loadTarget()
        }
    }

    fun onDataSourceChanged(textureId: Long) {
        if (isCasting(textureId)) loadTarget()
    }

    fun isCasting(textureId: Long): Boolean =
        targetTextureId == textureId && sessionManager.currentCastSession?.isConnected == true

    fun play(textureId: Long): Boolean {
        if (!isCasting(textureId)) return false
        remoteMediaClient?.play()
        return true
    }

    fun pause(textureId: Long): Boolean {
        if (!isCasting(textureId)) return false
        remoteMediaClient?.pause()
        return true
    }

    fun seekTo(textureId: Long, positionMs: Long): Boolean {
        if (!isCasting(textureId)) return false
        remoteMediaClient?.seek(positionMs)
        return true
    }

    fun setVolume(textureId: Long, volume: Double): Boolean {
        if (!isCasting(textureId)) return false
        remoteMediaClient?.setStreamVolume(volume.coerceIn(0.0, 1.0))
        return true
    }

    fun setSpeed(textureId: Long, speed: Double): Boolean {
        if (!isCasting(textureId)) return false
        remoteMediaClient?.setPlaybackRate(speed)
        return true
    }

    fun position(textureId: Long): Long? {
        if (!isCasting(textureId)) return null
        return remoteMediaClient?.approximateStreamPosition?.also {
            lastRemotePositionMs = it
        }
    }

    fun disposePlayer(textureId: Long) {
        if (targetTextureId == textureId) targetTextureId = null
    }

    fun dispose() {
        remoteMediaClient?.unregisterCallback(this)
        sessionManager.removeSessionManagerListener(this, CastSession::class.java)
        remoteMediaClient = null
        targetTextureId = null
    }

    override fun onSessionStarted(session: CastSession, sessionId: String) {
        attachSession(session)
        loadTarget()
    }

    override fun onSessionResumed(session: CastSession, wasSuspended: Boolean) {
        attachSession(session)
        loadTarget()
    }

    override fun onSessionEnded(session: CastSession, error: Int) = finishSession()
    override fun onSessionSuspended(session: CastSession, reason: Int) = Unit
    override fun onSessionStarting(session: CastSession) = Unit
    override fun onSessionStartFailed(session: CastSession, error: Int) = Unit
    override fun onSessionEnding(session: CastSession) {
        snapshotRemoteState()
    }
    override fun onSessionResuming(session: CastSession, sessionId: String) = Unit
    override fun onSessionResumeFailed(session: CastSession, error: Int) = finishSession()

    override fun onStatusUpdated() {
        snapshotRemoteState()
    }

    private fun attachSession(session: CastSession) {
        val client = session.remoteMediaClient ?: return
        if (remoteMediaClient === client) return
        remoteMediaClient?.unregisterCallback(this)
        remoteMediaClient = client
        client.registerCallback(this)
    }

    private fun loadTarget() {
        val textureId = targetTextureId ?: return
        val player = playerFor(textureId) ?: return
        val dataSource = dataSourceFor(textureId) ?: return
        val configuration = configurationFor(textureId) ?: return
        if (configuration["enabled"] != true) return
        val uri = dataSource["uri"] as? String ?: return
        if (!uri.startsWith("http://") && !uri.startsWith("https://")) return
        val client = remoteMediaClient ?: return

        val wasPlaying = player.isPlaying()
        val startPosition = player.position.coerceAtLeast(0L)
        resumeLocalPlayback = wasPlaying
        lastRemotePositionMs = startPosition
        player.pause()

        val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MOVIE)
        (configuration["title"] as? String)?.takeIf { it.isNotBlank() }?.let {
            metadata.putString(MediaMetadata.KEY_TITLE, it)
        }
        (configuration["subtitle"] as? String)?.takeIf { it.isNotBlank() }?.let {
            metadata.putString(MediaMetadata.KEY_SUBTITLE, it)
        }
        (configuration["imageUrl"] as? String)?.takeIf { it.isNotBlank() }?.let {
            runCatching { metadata.addImage(WebImage(Uri.parse(it))) }
        }

        val customData = JSONObject()
        val custom = configuration["customData"] as? Map<*, *>
        custom?.forEach { (key, value) -> if (key is String) customData.put(key, value) }
        val headers = configuration["requestHeaders"] as? Map<*, *>
            ?: dataSource["headers"] as? Map<*, *>
        if (!headers.isNullOrEmpty()) {
            customData.put("headers", JSONObject(headers))
        }

        val contentType = (configuration["contentType"] as? String)
            ?.takeIf { it.isNotBlank() }
            ?: inferContentType(uri, dataSource["formatHint"] as? String)
        val live = configuration["isLive"] == true
        val mediaInfo = MediaInfo.Builder(uri)
            .setContentType(contentType)
            .setStreamType(if (live) MediaInfo.STREAM_TYPE_LIVE else MediaInfo.STREAM_TYPE_BUFFERED)
            .setMetadata(metadata)
            .setCustomData(customData)
            .build()
        val request = MediaLoadRequestData.Builder()
            .setMediaInfo(mediaInfo)
            .setAutoplay(wasPlaying)
            .setCurrentTime(startPosition)
            .setCustomData(customData)
            .build()
        client.load(request)
    }

    private fun snapshotRemoteState() {
        val client = remoteMediaClient ?: return
        lastRemotePositionMs = client.approximateStreamPosition.coerceAtLeast(0L)
        resumeLocalPlayback = when (client.mediaStatus?.playerState) {
            MediaStatus.PLAYER_STATE_PLAYING,
            MediaStatus.PLAYER_STATE_BUFFERING -> true
            MediaStatus.PLAYER_STATE_PAUSED -> false
            else -> resumeLocalPlayback
        }
    }

    private fun finishSession() {
        snapshotRemoteState()
        remoteMediaClient?.unregisterCallback(this)
        remoteMediaClient = null
        val textureId = targetTextureId ?: return
        playerFor(textureId)?.let { player ->
            player.seekTo(lastRemotePositionMs.coerceAtMost(Int.MAX_VALUE.toLong()).toInt())
            if (resumeLocalPlayback) player.play() else player.pause()
        }
    }

    private fun inferContentType(uri: String, formatHint: String?): String = when {
        formatHint == "hls" || uri.contains(".m3u8", ignoreCase = true) -> "application/x-mpegURL"
        formatHint == "dash" || uri.contains(".mpd", ignoreCase = true) -> "application/dash+xml"
        else -> "video/mp4"
    }

    companion object {
        private const val TAG = "BetterPlayerCast"
    }
}
