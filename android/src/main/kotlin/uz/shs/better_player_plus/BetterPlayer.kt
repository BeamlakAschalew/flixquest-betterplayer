package uz.shs.better_player_plus

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.support.v4.media.MediaMetadataCompat
import android.support.v4.media.session.MediaSessionCompat
import android.support.v4.media.session.PlaybackStateCompat
import uz.shs.better_player_plus.DataSourceUtils.getUserAgent
import uz.shs.better_player_plus.DataSourceUtils.isHTTP
import uz.shs.better_player_plus.DataSourceUtils.getDataSourceFactory
import io.flutter.plugin.common.EventChannel
import io.flutter.view.TextureRegistry.SurfaceTextureEntry
import io.flutter.plugin.common.MethodChannel
import androidx.media3.ui.PlayerNotificationManager
import androidx.work.WorkManager
import androidx.work.WorkInfo
import androidx.media3.ui.PlayerNotificationManager.MediaDescriptionAdapter
import androidx.media3.ui.PlayerNotificationManager.BitmapCallback
import androidx.work.OneTimeWorkRequest
import android.util.Log
import android.view.Surface
import androidx.annotation.OptIn
import androidx.lifecycle.Observer
import androidx.media3.extractor.DefaultExtractorsFactory
import io.flutter.plugin.common.EventChannel.EventSink
import androidx.work.Data
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.LoadControl
import androidx.media3.exoplayer.dash.DashMediaSource
import androidx.media3.exoplayer.dash.DefaultDashChunkSource
import androidx.media3.exoplayer.drm.DefaultDrmSessionManager
import androidx.media3.exoplayer.drm.DrmSessionManager
import androidx.media3.exoplayer.drm.DrmSessionManagerProvider
import androidx.media3.exoplayer.drm.DummyExoMediaDrm
import androidx.media3.exoplayer.drm.FrameworkMediaDrm
import androidx.media3.exoplayer.drm.HttpMediaDrmCallback
import androidx.media3.exoplayer.drm.LocalMediaDrmCallback
import androidx.media3.exoplayer.drm.UnsupportedDrmException
import androidx.media3.exoplayer.hls.HlsMediaSource
import androidx.media3.exoplayer.offline.Download
import androidx.media3.exoplayer.offline.DownloadHelper
import androidx.media3.exoplayer.smoothstreaming.DefaultSsChunkSource
import androidx.media3.exoplayer.smoothstreaming.SsMediaSource
import androidx.media3.exoplayer.source.ClippingMediaSource
import androidx.media3.exoplayer.source.MediaSource
import androidx.media3.exoplayer.source.ProgressiveMediaSource
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.exoplayer.upstream.DefaultLoadErrorHandlingPolicy
import androidx.media3.exoplayer.upstream.LoadErrorHandlingPolicy
import java.io.File
import java.lang.Exception
import java.lang.IllegalStateException
import java.util.*
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.max
import kotlin.math.min
import androidx.core.net.toUri

private const val MAX_SKIPPABLE_SEGMENT_DURATION_MS = 30_000L
private const val SHORT_SEGMENT_RETRY_COUNT = 3
private const val FLIXQUEST_OFFLINE_CACHE_KEY_PREFIX = "flixquest-offline:"
private const val LIVE_TARGET_OFFSET_MS = 30_000L
private const val LIVE_MIN_OFFSET_MS = 15_000L
private const val LIVE_MAX_OFFSET_MS = 60_000L
private const val LIVE_MIN_PLAYBACK_SPEED = 0.97f
private const val LIVE_MAX_PLAYBACK_SPEED = 1.03f

/**
 * Retries ordinary loads persistently, but exposes a short adaptive media
 * segment after repeated failures so the player can seek past that exact
 * segment. Manifest and initialization loads keep the normal resilient
 * behavior. The thirty-second ceiling covers common HLS/DASH segment sizes
 * without treating unusually long media chunks as safe to skip.
 */
private class ShortSegmentLoadErrorHandlingPolicy(
    private val onShortSegmentExhausted: (startMs: Long, endMs: Long) -> Boolean
) : DefaultLoadErrorHandlingPolicy(Int.MAX_VALUE) {
    override fun getRetryDelayMsFor(
        loadErrorInfo: LoadErrorHandlingPolicy.LoadErrorInfo
    ): Long {
        val mediaLoadData = loadErrorInfo.mediaLoadData
        val startMs = mediaLoadData.mediaStartTimeMs
        val endMs = mediaLoadData.mediaEndTimeMs
        val durationMs = endMs - startMs
        val isShortMediaSegment =
            mediaLoadData.dataType == C.DATA_TYPE_MEDIA &&
                startMs != C.TIME_UNSET &&
                endMs != C.TIME_UNSET &&
                durationMs in 1..MAX_SKIPPABLE_SEGMENT_DURATION_MS

        if (isShortMediaSegment) {
            if (loadErrorInfo.errorCount >= SHORT_SEGMENT_RETRY_COUNT &&
                onShortSegmentExhausted(startMs, endMs)
            ) {
                return C.TIME_UNSET
            }
            return min(loadErrorInfo.errorCount * 1_000L, 5_000L)
        }
        return super.getRetryDelayMsFor(loadErrorInfo)
    }
}

@UnstableApi
internal class BetterPlayer(
    context: Context,
    private val eventChannel: EventChannel,
    private val textureEntry: SurfaceTextureEntry,
    customDefaultLoadControl: CustomDefaultLoadControl?,
    result: MethodChannel.Result
) {
    private val exoPlayer: ExoPlayer?
    private val eventSink = QueuingEventSink()
    private val trackSelector: DefaultTrackSelector = DefaultTrackSelector(context)
    private val loadControl: LoadControl
    private var isInitialized = false
    private var surface: Surface? = null
    private var key: String? = null
    private var playerNotificationManager: PlayerNotificationManager? = null
    private var refreshHandler: Handler? = null
    private var refreshRunnable: Runnable? = null
    private var positionSnapshotHandler: Handler? = null
    private var positionSnapshotRunnable: Runnable? = null
    private var exoPlayerEventListener: Player.Listener? = null
    private var bitmap: Bitmap? = null
    private var mediaSession: MediaSessionCompat? = null
    private var drmSessionManager: DrmSessionManager? = null
    private val workManager: WorkManager
    private val workerObserverMap: HashMap<UUID, Observer<WorkInfo?>>
    private val customDefaultLoadControl: CustomDefaultLoadControl =
        customDefaultLoadControl ?: CustomDefaultLoadControl()
    private var lastSendBufferedPosition = 0L
    private val resilientLoadErrorHandlingPolicy =
        DefaultLoadErrorHandlingPolicy(Int.MAX_VALUE)
    /**
     * LoadErrorHandlingPolicy callbacks run on ExoPlayer's playback thread,
     * while player APIs (including currentPosition) must run on the player
     * application looper. Keep only cross-thread state in the callback and
     * read the player again from onPlayerError on the main thread.
     */
    @Volatile
    private var pendingBrokenSegmentStartMs: Long? = null
    @Volatile
    private var pendingBrokenSegmentEndMs: Long? = null
    private val skippedBrokenSegmentEnds = ConcurrentHashMap.newKeySet<Long>()
    @Volatile
    private var lastKnownPositionMs = 0L
    private var hasPreRollSequence = false
    private var preRollEndedSent = false
    private var contentStartPositionMs = 0L
    private val shortSegmentLoadErrorHandlingPolicy =
        ShortSegmentLoadErrorHandlingPolicy(::markShortSegmentForSkipping)

    init {
        val loadBuilder = DefaultLoadControl.Builder()
        loadBuilder.setBufferDurationsMs(
            this.customDefaultLoadControl.minBufferMs,
            this.customDefaultLoadControl.maxBufferMs,
            this.customDefaultLoadControl.bufferForPlaybackMs,
            this.customDefaultLoadControl.bufferForPlaybackAfterRebufferMs
        )
        loadBuilder.setBackBuffer(
            this.customDefaultLoadControl.backBufferDurationMs,
            this.customDefaultLoadControl.retainBackBufferFromKeyframe
        )
        loadBuilder.setPrioritizeTimeOverSizeThresholds(
            this.customDefaultLoadControl.prioritizeTimeOverSizeThresholds
        )
        loadControl = loadBuilder.build()
        exoPlayer = ExoPlayer.Builder(context)
            .setTrackSelector(trackSelector)
            .setLoadControl(loadControl)
            .build()
        workManager = WorkManager.getInstance(context)
        workerObserverMap = HashMap()
        setupVideoPlayer(eventChannel, textureEntry, result)
    }

    @OptIn(UnstableApi::class)
    fun setDataSource(
        context: Context,
        key: String?,
        dataSource: String?,
        formatHint: String?,
        result: MethodChannel.Result,
        headers: Map<String, String>?,
        useCache: Boolean,
        maxCacheSize: Long,
        maxCacheFileSize: Long,
        overriddenDuration: Long,
        licenseUrl: String?,
        drmHeaders: Map<String, String>?,
        cacheKey: String?,
        clearKey: String?,
        isLive: Boolean = false,
        preRollDataSource: Map<String, Any?>? = null,
        contentStartPositionMs: Long = 0L
    ) {
        this.key = key
        isInitialized = false
        lastKnownPositionMs = 0L
        pendingBrokenSegmentStartMs = null
        pendingBrokenSegmentEndMs = null
        skippedBrokenSegmentEnds.clear()
        val uri = dataSource?.toUri()
        var dataSourceFactory: DataSource.Factory?
        val userAgent = getUserAgent(headers)
        if (!licenseUrl.isNullOrEmpty()) {
            val httpMediaDrmCallback =
                HttpMediaDrmCallback(licenseUrl, DefaultHttpDataSource.Factory())
            if (drmHeaders != null) {
                for ((drmKey, drmValue) in drmHeaders) {
                    httpMediaDrmCallback.setKeyRequestProperty(drmKey, drmValue)
                }
            }
            val drmSchemeUuid = Util.getDrmUuid("widevine")
            if (drmSchemeUuid != null) {
                drmSessionManager = DefaultDrmSessionManager.Builder()
                    .setUuidAndExoMediaDrmProvider(
                        drmSchemeUuid
                    ) { uuid: UUID? ->
                        try {
                            val mediaDrm = FrameworkMediaDrm.newInstance(uuid!!)
                            // Force L3.
                            mediaDrm.setPropertyString("securityLevel", "L3")
                            return@setUuidAndExoMediaDrmProvider mediaDrm
                        } catch (_: UnsupportedDrmException) {
                            return@setUuidAndExoMediaDrmProvider DummyExoMediaDrm()
                        }
                    }
                    .setMultiSession(false)
                    .build(httpMediaDrmCallback)
            }
        } else if (!clearKey.isNullOrEmpty()) {
            DefaultDrmSessionManager.Builder()
                .setUuidAndExoMediaDrmProvider(
                    C.CLEARKEY_UUID,
                    FrameworkMediaDrm.DEFAULT_PROVIDER
                ).build(LocalMediaDrmCallback(clearKey.toByteArray()))
        } else {
            drmSessionManager = null
        }
        if (isHTTP(uri)) {
            dataSourceFactory = getDataSourceFactory(userAgent, headers)
            if (useCache && maxCacheSize > 0 && maxCacheFileSize > 0) {
                dataSourceFactory = CacheDataSourceFactory(
                    context,
                    maxCacheSize,
                    maxCacheFileSize,
                    dataSourceFactory
                )
            }
        } else {
            dataSourceFactory = DefaultDataSource.Factory(context)
        }
        val mediaSource = cacheKey
            ?.removePrefix(FLIXQUEST_OFFLINE_CACHE_KEY_PREFIX)
            ?.takeIf { cacheKey.startsWith(FLIXQUEST_OFFLINE_CACHE_KEY_PREFIX) }
            ?.let { downloadId -> buildFlixQuestOfflineMediaSource(context, downloadId) }
            ?: buildMediaSource(uri, dataSourceFactory, formatHint, cacheKey, context, isLive)
        val contentMediaSource = if (overriddenDuration != 0L) {
            val clippingMediaSource = ClippingMediaSource(
                mediaSource,
                0,
                overriddenDuration * 1000
            )
            clippingMediaSource
        } else {
            mediaSource
        }
        hasPreRollSequence = preRollDataSource != null
        preRollEndedSent = false
        this.contentStartPositionMs = contentStartPositionMs.coerceAtLeast(0L)
        if (preRollDataSource != null) {
            val preRollMediaSource = buildPreRollMediaSource(
                context,
                preRollDataSource
            )
            exoPlayer?.setMediaSources(listOf(preRollMediaSource, contentMediaSource))
        } else {
            exoPlayer?.setMediaSource(contentMediaSource)
        }
        exoPlayer?.prepare()
        result.success(null)
    }

    private fun buildPreRollMediaSource(
        context: Context,
        dataSource: Map<String, Any?>
    ): MediaSource {
        val uri = (dataSource["uri"] as? String)?.toUri()
        val headers = (dataSource["headers"] as? Map<*, *>)
            ?.entries
            ?.mapNotNull { entry ->
                val name = entry.key as? String
                val value = entry.value as? String
                if (name != null && value != null) name to value else null
            }
            ?.toMap()
            ?: emptyMap()
        val userAgent = getUserAgent(headers)
        var factory: DataSource.Factory = if (isHTTP(uri)) {
            getDataSourceFactory(userAgent, headers)
        } else {
            DefaultDataSource.Factory(context)
        }
        val useCache = dataSource["useCache"] as? Boolean ?: false
        val maxCacheSize = (dataSource["maxCacheSize"] as? Number)?.toLong() ?: 0L
        val maxCacheFileSize =
            (dataSource["maxCacheFileSize"] as? Number)?.toLong() ?: 0L
        if (useCache && maxCacheSize > 0 && maxCacheFileSize > 0) {
            factory = CacheDataSourceFactory(
                context,
                maxCacheSize,
                maxCacheFileSize,
                factory
            )
        }

        val contentDrmSessionManager = drmSessionManager
        drmSessionManager = null
        return try {
            buildMediaSource(
                uri,
                factory,
                dataSource["formatHint"] as? String,
                dataSource["cacheKey"] as? String,
                context
            )
        } finally {
            drmSessionManager = contentDrmSessionManager
        }
    }

    fun setupPlayerNotification(
        context: Context, title: String, author: String?,
        imageUrl: String?, notificationChannelName: String?,
        activityName: String
    ) {
        val mediaDescriptionAdapter: MediaDescriptionAdapter = object : MediaDescriptionAdapter {
            override fun getCurrentContentTitle(player: Player): String {
                return title
            }

            @SuppressLint("UnspecifiedImmutableFlag")
            override fun createCurrentContentIntent(player: Player): PendingIntent? {
                val packageName = context.applicationContext.packageName
                val notificationIntent = Intent()
                notificationIntent.setClassName(
                    packageName,
                    "$packageName.$activityName"
                )
                notificationIntent.flags = (Intent.FLAG_ACTIVITY_CLEAR_TOP
                        or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                return PendingIntent.getActivity(
                    context, 0,
                    notificationIntent,
                    PendingIntent.FLAG_IMMUTABLE
                )
            }

            override fun getCurrentContentText(player: Player): String? {
                return author
            }

            override fun getCurrentLargeIcon(
                player: Player,
                callback: BitmapCallback
            ): Bitmap? {
                if (imageUrl == null) {
                    return null
                }
                if (bitmap != null) {
                    return bitmap
                }
                val imageWorkRequest = OneTimeWorkRequest.Builder(ImageWorker::class.java)
                    .addTag(imageUrl)
                    .setInputData(
                        Data.Builder()
                            .putString(BetterPlayerPlugin.URL_PARAMETER, imageUrl)
                            .build()
                    )
                    .build()
                workManager.enqueue(imageWorkRequest)
                val workInfoObserver = Observer { workInfo: WorkInfo? ->
                    try {
                        if (workInfo != null) {
                            val state = workInfo.state
                            if (state == WorkInfo.State.SUCCEEDED) {
                                val outputData = workInfo.outputData
                                val filePath =
                                    outputData.getString(BetterPlayerPlugin.FILE_PATH_PARAMETER)
                                //Bitmap here is already processed and it's very small, so it won't
                                //break anything.
                                bitmap = BitmapFactory.decodeFile(filePath)
                                bitmap?.let { bitmap ->
                                    callback.onBitmap(bitmap)
                                }
                            }
                            if (state == WorkInfo.State.SUCCEEDED || state == WorkInfo.State.CANCELLED || state == WorkInfo.State.FAILED) {
                                val uuid = imageWorkRequest.id
                                val observer = workerObserverMap.remove(uuid)
                                if (observer != null) {
                                    workManager.getWorkInfoByIdLiveData(uuid)
                                        .removeObserver(observer)
                                }
                            }
                        }
                    } catch (exception: Exception) {
                        Log.e(TAG, "Image select error: $exception")
                    }
                }
                val workerUuid = imageWorkRequest.id
                workManager.getWorkInfoByIdLiveData(workerUuid)
                    .observeForever(workInfoObserver)
                workerObserverMap[workerUuid] = workInfoObserver
                return null
            }
        }
        var playerNotificationChannelName = notificationChannelName
        if (notificationChannelName == null) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val importance = NotificationManager.IMPORTANCE_LOW
                val channel = NotificationChannel(
                    DEFAULT_NOTIFICATION_CHANNEL,
                    DEFAULT_NOTIFICATION_CHANNEL, importance
                )
                channel.description = DEFAULT_NOTIFICATION_CHANNEL
                val notificationManager = context.getSystemService(
                    NotificationManager::class.java
                )
                notificationManager.createNotificationChannel(channel)
                playerNotificationChannelName = DEFAULT_NOTIFICATION_CHANNEL
            }
        }

        playerNotificationManager = PlayerNotificationManager.Builder(
            context, NOTIFICATION_ID,
            playerNotificationChannelName!!
        ).setMediaDescriptionAdapter(mediaDescriptionAdapter).build()

        playerNotificationManager?.apply {

            exoPlayer?.let {
                setPlayer(ForwardingPlayer(exoPlayer))
                setUseNextAction(false)
                setUsePreviousAction(false)
                setUseStopAction(false)
            }
        }

        refreshHandler = Handler(Looper.getMainLooper())
        refreshRunnable = Runnable {
            // This runnable is posted to the player's application looper.
            // Keep a snapshot for the load-error callback, which runs on a
            // separate playback thread and must not access ExoPlayer directly.
            lastKnownPositionMs = exoPlayer?.currentPosition ?: 0L
            val playbackState: PlaybackStateCompat = if (exoPlayer?.isPlaying == true) {
                PlaybackStateCompat.Builder()
                    .setActions(PlaybackStateCompat.ACTION_SEEK_TO)
                    .setState(PlaybackStateCompat.STATE_PLAYING, position, 1.0f)
                    .build()
            } else {
                PlaybackStateCompat.Builder()
                    .setActions(PlaybackStateCompat.ACTION_SEEK_TO)
                    .setState(PlaybackStateCompat.STATE_PAUSED, position, 1.0f)
                    .build()
            }
            mediaSession?.setPlaybackState(playbackState)
            refreshHandler?.postDelayed(refreshRunnable!!, 1000)
        }
        refreshHandler?.postDelayed(refreshRunnable!!, 0)
        exoPlayerEventListener = object : Player.Listener {
            override fun onPlaybackStateChanged(playbackState: Int) {
                mediaSession?.setMetadata(
                    MediaMetadataCompat.Builder()
                        .putLong(MediaMetadataCompat.METADATA_KEY_DURATION, getDuration())
                        .build()
                )
            }
        }
        exoPlayerEventListener?.let { exoPlayerEventListener ->
            exoPlayer?.addListener(exoPlayerEventListener)
        }
        exoPlayer?.seekTo(0)
    }

    fun disposeRemoteNotifications() {
        exoPlayerEventListener?.let { exoPlayerEventListener ->
            exoPlayer?.removeListener(exoPlayerEventListener)
        }
        if (refreshHandler != null) {
            refreshHandler?.removeCallbacksAndMessages(null)
            refreshHandler = null
            refreshRunnable = null
        }
        if (playerNotificationManager != null) {
            playerNotificationManager?.setPlayer(null)
        }
        bitmap = null
    }

    private fun buildMediaSource(
        uri: Uri?,
        mediaDataSourceFactory: DataSource.Factory,
        formatHint: String?,
        cacheKey: String?,
        context: Context,
        isLive: Boolean = false
    ): MediaSource {
        val type = if (formatHint == null) {
            // Provider proxy URLs frequently have extensionless paths (for
            // example, `/proxy?token=...`). Splitting the last path segment and
            // blindly reading index 1 caused an IndexOutOfBoundsException
            // before ExoPlayer could report a normal playback failure.
            uri?.let(Util::inferContentType) ?: C.CONTENT_TYPE_OTHER
        } else {
            when (formatHint) {
                FORMAT_SS -> C.CONTENT_TYPE_SS
                FORMAT_DASH -> C.CONTENT_TYPE_DASH
                FORMAT_HLS -> C.CONTENT_TYPE_HLS
                FORMAT_OTHER -> C.CONTENT_TYPE_OTHER
                else -> -1
            }
        }
        val mediaItemBuilder = MediaItem.Builder()
        mediaItemBuilder.setUri(uri)
        if (!cacheKey.isNullOrEmpty()) {
            mediaItemBuilder.setCustomCacheKey(cacheKey)
        }
        if (isLive) {
            mediaItemBuilder.setLiveConfiguration(
                MediaItem.LiveConfiguration.Builder()
                    .setTargetOffsetMs(LIVE_TARGET_OFFSET_MS)
                    .setMinOffsetMs(LIVE_MIN_OFFSET_MS)
                    .setMaxOffsetMs(LIVE_MAX_OFFSET_MS)
                    .setMinPlaybackSpeed(LIVE_MIN_PLAYBACK_SPEED)
                    .setMaxPlaybackSpeed(LIVE_MAX_PLAYBACK_SPEED)
                    .build()
            )
        }
        val mediaItem = mediaItemBuilder.build()
        var drmSessionManagerProvider: DrmSessionManagerProvider? = null
        drmSessionManager?.let { drmSessionManager ->
            drmSessionManagerProvider = DrmSessionManagerProvider { drmSessionManager }
        }

        return when (type) {
            C.CONTENT_TYPE_SS -> SsMediaSource.Factory(
                DefaultSsChunkSource.Factory(mediaDataSourceFactory),
                DefaultDataSource.Factory(context, mediaDataSourceFactory)
            ).apply {
                setLoadErrorHandlingPolicy(resilientLoadErrorHandlingPolicy)
                if (drmSessionManagerProvider != null) {
                    setDrmSessionManagerProvider(drmSessionManagerProvider)
                }
            }.createMediaSource(mediaItem)

            C.CONTENT_TYPE_DASH -> DashMediaSource.Factory(
                DefaultDashChunkSource.Factory(mediaDataSourceFactory),
                DefaultDataSource.Factory(context, mediaDataSourceFactory)
            ).apply {
                setLoadErrorHandlingPolicy(shortSegmentLoadErrorHandlingPolicy)
                if (drmSessionManagerProvider != null) {
                    setDrmSessionManagerProvider(drmSessionManagerProvider)
                }
            }.createMediaSource(mediaItem)

            C.CONTENT_TYPE_HLS -> HlsMediaSource.Factory(mediaDataSourceFactory)
                .apply {
                    setAllowChunklessPreparation(true)
                    setLoadErrorHandlingPolicy(shortSegmentLoadErrorHandlingPolicy)
                    if (drmSessionManagerProvider != null) {
                        setDrmSessionManagerProvider(drmSessionManagerProvider)
                    }
                }.createMediaSource(mediaItem)

            C.CONTENT_TYPE_OTHER -> ProgressiveMediaSource.Factory(
                mediaDataSourceFactory,
                DefaultExtractorsFactory()
            ).apply {
                setLoadErrorHandlingPolicy(resilientLoadErrorHandlingPolicy)
                if (drmSessionManagerProvider != null) {
                    setDrmSessionManagerProvider(drmSessionManagerProvider)
                }
            }.createMediaSource(mediaItem)

            else -> {
                throw IllegalStateException("Unsupported type: $type")
            }
        }
    }

    /**
     * FlixQuest stores HLS/DASH downloads in Media3's cache rather than as a
     * single file. Its Better Player fork can open those downloads directly by
     * reusing the app's read-only cache factory. Reflection deliberately keeps
     * this plugin buildable outside the FlixQuest application.
     */
    @OptIn(UnstableApi::class)
    private fun buildFlixQuestOfflineMediaSource(
        context: Context,
        downloadId: String,
    ): MediaSource {
        try {
            val storeClass = Class.forName(
                "dev.beamlak.flixquest_v2.downloads.StreamDownloadStore",
            )
            val companion = storeClass.getField("Companion").get(null)
            val store = companion.javaClass
                .getMethod("get", Context::class.java)
                .invoke(companion, context.applicationContext)
            val download = store.javaClass
                .getMethod("getDownload", String::class.java)
                .invoke(store, downloadId) as? Download
                ?: throw IllegalArgumentException("Offline download not found: $downloadId")
            val cacheFactory = store.javaClass
                .getMethod("readOnlyCacheFactory")
                .invoke(store) as? CacheDataSource.Factory
                ?: throw IllegalStateException("Offline cache is unavailable.")
            return DownloadHelper.createMediaSource(download.request, cacheFactory)
        } catch (error: ReflectiveOperationException) {
            throw IllegalStateException("Could not access the FlixQuest offline cache.", error)
        }
    }

    private fun setupVideoPlayer(
        eventChannel: EventChannel, textureEntry: SurfaceTextureEntry, result: MethodChannel.Result
    ) {
        eventChannel.setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(o: Any?, sink: EventSink) {
                    eventSink.setDelegate(sink)
                }

                override fun onCancel(o: Any?) {
                    eventSink.setDelegate(null)
                }
            },
        )
        surface = Surface(textureEntry.surfaceTexture())
        exoPlayer?.setVideoSurface(surface)
        setAudioAttributes(exoPlayer, true)

        // Keep a main-thread position snapshot available to the load-error
        // policy. The policy itself runs on ExoPlayer's playback thread and
        // must never call player APIs directly.
        positionSnapshotHandler = Handler(Looper.getMainLooper())
        positionSnapshotRunnable = object : Runnable {
            override fun run() {
                lastKnownPositionMs = exoPlayer?.currentPosition ?: 0L
                positionSnapshotHandler?.postDelayed(this, 250L)
            }
        }
        positionSnapshotHandler?.post(positionSnapshotRunnable!!)
        exoPlayer?.addListener(object : Player.Listener {
            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                val player = exoPlayer ?: return
                if (!hasPreRollSequence || preRollEndedSent || player.currentMediaItemIndex != 1) {
                    return
                }
                if (contentStartPositionMs > 0L) {
                    player.seekTo(1, contentStartPositionMs)
                }
                isInitialized = true
                sendInitialized()
                preRollEndedSent = true
                val event: MutableMap<String, Any?> = HashMap()
                event["event"] = "preRollEnded"
                event["key"] = key
                eventSink.success(event)
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                when (playbackState) {
                    Player.STATE_BUFFERING -> {
                        sendBufferingUpdate(true)
                        val event: MutableMap<String, Any> = HashMap()
                        event["event"] = "bufferingStart"
                        eventSink.success(event)
                    }

                    Player.STATE_READY -> {
                        if (!isInitialized) {
                            isInitialized = true
                            sendInitialized()
                        }
                        val event: MutableMap<String, Any> = HashMap()
                        event["event"] = "bufferingEnd"
                        eventSink.success(event)
                    }

                    Player.STATE_ENDED -> {
                        val event: MutableMap<String, Any?> = HashMap()
                        event["event"] = "completed"
                        event["key"] = key
                        eventSink.success(event)
                    }

                    Player.STATE_IDLE -> {
                        //no-op
                    }
                }
            }

            override fun onPlayerError(error: PlaybackException) {
                val player = exoPlayer
                if (hasPreRollSequence &&
                    player?.currentMediaItemIndex == 0 &&
                    player.hasNextMediaItem()
                ) {
                    val resumePlayback = player.playWhenReady
                    player.seekToNextMediaItem()
                    player.prepare()
                    player.playWhenReady = resumePlayback
                    return
                }
                if (skipBrokenShortSegment()) {
                    return
                }
                eventSink.error("VideoError", "Video player had error $error", "")
            }
        })
        val reply: MutableMap<String, Any> = HashMap()
        reply["textureId"] = textureEntry.id()
        result.success(reply)
    }

    private fun markShortSegmentForSkipping(startMs: Long, endMs: Long): Boolean {
        if (skippedBrokenSegmentEnds.contains(endMs)) {
            return true
        }
        // Do not access ExoPlayer here. This policy callback is invoked on
        // ExoPlayer's playback thread; player APIs are main-thread-only.
        val currentPositionMs = lastKnownPositionMs
        val segmentIsBlockingPlayback =
            currentPositionMs + 1_000L >= startMs && currentPositionMs <= endMs
        if (!segmentIsBlockingPlayback) {
            return false
        }
        pendingBrokenSegmentStartMs = startMs
        pendingBrokenSegmentEndMs = endMs
        return true
    }

    private fun skipBrokenShortSegment(): Boolean {
        val segmentStartMs = pendingBrokenSegmentStartMs ?: return false
        val segmentEndMs = pendingBrokenSegmentEndMs ?: return false
        pendingBrokenSegmentStartMs = null
        pendingBrokenSegmentEndMs = null
        val player = exoPlayer ?: return false
        // onPlayerError is delivered on the player's application looper, so
        // this access is safe. Re-check against the live position because the
        // snapshot used by the playback-thread callback may be up to one
        // refresh interval old.
        val currentPositionMs = player.currentPosition
        val segmentIsBlockingPlayback =
            currentPositionMs + 1_000L >= segmentStartMs && currentPositionMs <= segmentEndMs
        if (!segmentIsBlockingPlayback || !skippedBrokenSegmentEnds.add(segmentEndMs)) {
            return false
        }
        val durationMs = player.duration
        val unboundedTargetMs = segmentEndMs + 1L
        val targetMs =
            if (durationMs == C.TIME_UNSET || durationMs <= 0L) {
                unboundedTargetMs
            } else {
                min(unboundedTargetMs, durationMs)
            }
        val resumePlayback = player.playWhenReady
        Log.w(
            TAG,
            "Skipping repeatedly broken adaptive segment to ${targetMs}ms"
        )
        player.seekTo(targetMs)
        player.prepare()
        player.playWhenReady = resumePlayback
        return true
    }

    fun sendBufferingUpdate(isFromBufferingStart: Boolean) {
        val bufferedPosition = exoPlayer?.bufferedPosition ?: 0L
        if (isFromBufferingStart || bufferedPosition != lastSendBufferedPosition) {
            val event: MutableMap<String, Any> = HashMap()
            event["event"] = "bufferingUpdate"
            val range: List<Number?> = listOf(0, bufferedPosition)
            // iOS supports a list of buffered ranges, so here is a list with a single range.
            event["values"] = listOf(range)
            eventSink.success(event)
            lastSendBufferedPosition = bufferedPosition
        }
    }

    @Suppress("DEPRECATION")
    private fun setAudioAttributes(exoPlayer: ExoPlayer?, mixWithOthers: Boolean) {
        exoPlayer?.setAudioAttributes(
            AudioAttributes.Builder()
                .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                .build(),
            !mixWithOthers
        )
    }

    fun play() {
        exoPlayer?.playWhenReady = true
    }

    fun pause() {
        exoPlayer?.playWhenReady = false
    }
    
    fun isPlaying(): Boolean {
        return exoPlayer?.isPlaying ?: false
    }

    fun setLooping(value: Boolean) {
        exoPlayer?.repeatMode = if (value) Player.REPEAT_MODE_ALL else Player.REPEAT_MODE_OFF
    }

    fun setVolume(value: Double) {
        val bracketedValue = max(0.0, min(1.0, value))
            .toFloat()
        exoPlayer?.volume = bracketedValue
    }

    fun setSpeed(value: Double) {
        val bracketedValue = value.toFloat()
        val playbackParameters = PlaybackParameters(bracketedValue)
        exoPlayer?.playbackParameters = playbackParameters
    }

    fun setTrackParameters(width: Int, height: Int, bitrate: Int) {
        val parametersBuilder = trackSelector.buildUponParameters()
        if (width != 0 && height != 0) {
            parametersBuilder.setMaxVideoSize(width, height)
        }
        if (bitrate != 0) {
            parametersBuilder.setMaxVideoBitrate(bitrate)
        }
        if (width == 0 && height == 0 && bitrate == 0) {
            parametersBuilder.clearVideoSizeConstraints()
            parametersBuilder.setMaxVideoBitrate(Int.MAX_VALUE)
        }
        trackSelector.setParameters(parametersBuilder)
    }

    fun seekTo(location: Int) {
        exoPlayer?.seekTo(location.toLong())
    }

    val position: Long
        get() = exoPlayer?.currentPosition ?: 0L

    val absolutePosition: Long
        get() {
            val timeline = exoPlayer?.currentTimeline
            timeline?.let {
                if (!timeline.isEmpty) {
                    val windowStartTimeMs =
                        timeline.getWindow(0, Timeline.Window()).windowStartTimeMs
                    val pos = exoPlayer.currentPosition
                    return windowStartTimeMs + pos
                }
            }
            return exoPlayer?.currentPosition ?: 0L
        }

    private fun sendInitialized() {
        if (isInitialized) {
            val event: MutableMap<String, Any?> = HashMap()
            event["event"] = "initialized"
            event["key"] = key
            event["duration"] = getDuration()
            if (exoPlayer?.videoFormat != null) {
                val videoFormat = exoPlayer.videoFormat
                var width = videoFormat?.width
                var height = videoFormat?.height
                val rotationDegrees = videoFormat?.rotationDegrees
                // Switch the width/height if video was taken in portrait mode
                if (rotationDegrees == 90 || rotationDegrees == 270) {
                    width = exoPlayer.videoFormat?.height
                    height = exoPlayer.videoFormat?.width
                }
                event["width"] = width
                event["height"] = height
            }
            eventSink.success(event)
        }
    }

    private fun getDuration(): Long = exoPlayer?.duration ?: 0L

    /**
     * Create media session which will be used in notifications, pip mode.
     *
     * @param context                - android context
     * @return - configured MediaSession instance
     */
    @SuppressLint("InlinedApi")
    fun setupMediaSession(context: Context?): MediaSessionCompat? {
        mediaSession?.release()
        context?.let {

            val mediaButtonIntent = Intent(Intent.ACTION_MEDIA_BUTTON)
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                0, mediaButtonIntent,
                PendingIntent.FLAG_IMMUTABLE
            )
            val mediaSession = MediaSessionCompat(context, TAG, null, pendingIntent)
            mediaSession.setCallback(object : MediaSessionCompat.Callback() {
                override fun onSeekTo(pos: Long) {
                    sendSeekToEvent(pos)
                    super.onSeekTo(pos)
                }
            })
            mediaSession.isActive = true
//            val mediaSessionConnector = MediaSessionConnector(mediaSession)
//            mediaSessionConnector.setPlayer(exoPlayer)
            this.mediaSession = mediaSession
            return mediaSession
        }
        return null

    }

    fun onPictureInPictureStatusChanged(inPip: Boolean) {
        val event: MutableMap<String, Any> = HashMap()
        event["event"] = if (inPip) "pipStart" else "pipStop"
        eventSink.success(event)
    }

    fun disposeMediaSession() {
        if (mediaSession != null) {
            mediaSession?.release()
        }
        mediaSession = null
    }

    fun setAudioTrack(name: String, index: Int) {
        try {
            val mappedTrackInfo = trackSelector.currentMappedTrackInfo
            if (mappedTrackInfo != null) {
                for (rendererIndex in 0 until mappedTrackInfo.rendererCount) {
                    if (mappedTrackInfo.getRendererType(rendererIndex) != C.TRACK_TYPE_AUDIO) {
                        continue
                    }
                    val trackGroupArray = mappedTrackInfo.getTrackGroups(rendererIndex)
                    var hasElementWithoutLabel = false
                    var hasStrangeAudioTrack = false
                    for (groupIndex in 0 until trackGroupArray.length) {
                        val group = trackGroupArray[groupIndex]
                        for (groupElementIndex in 0 until group.length) {
                            val format = group.getFormat(groupElementIndex)
                            if (format.label == null) {
                                hasElementWithoutLabel = true
                            }
                            if (format.id != null && format.id == "1/15") {
                                hasStrangeAudioTrack = true
                            }
                        }
                    }
                    val normalizedName = normalizeTrackName(name)
                    var fallbackMatch: Pair<Int, Int>? = null
                    var audioTrackOrder = 0
                    for (groupIndex in 0 until trackGroupArray.length) {
                        val group = trackGroupArray[groupIndex]
                        for (groupElementIndex in 0 until group.length) {
                            val format = group.getFormat(groupElementIndex)
                            val label = format.label
                            val normalizedLabel = normalizeTrackName(label)
                            val normalizedLanguage = normalizeTrackName(format.language)

                            if (index == audioTrackOrder) {
                                setAudioTrack(rendererIndex, groupIndex, groupElementIndex)
                                return
                            }

                            if (fallbackMatch == null &&
                                (normalizedName == normalizedLabel ||
                                    normalizedName == normalizedLanguage)
                            ) {
                                fallbackMatch = Pair(groupIndex, groupElementIndex)
                            }

                            ///Fallback option
                            if (!hasStrangeAudioTrack && hasElementWithoutLabel && index == groupIndex) {
                                // When labels are missing, default to the first track within the group
                                val safeTrackIndex = if (group.length > 0) 0 else groupElementIndex
                                setAudioTrack(rendererIndex, groupIndex, safeTrackIndex)
                                return
                            }
                            ///Fallback option
                            if (hasStrangeAudioTrack && name == label) {
                                setAudioTrack(rendererIndex, groupIndex, groupElementIndex)
                                return
                            }

                            audioTrackOrder++
                        }
                    }

                    fallbackMatch?.let {
                        setAudioTrack(rendererIndex, it.first, it.second)
                        return
                    }
                }
            }
        } catch (exception: Exception) {
            Log.e(TAG, "setAudioTrack failed$exception")
        }
    }

    private fun normalizeTrackName(value: String?): String? {
        if (value == null) {
            return null
        }

        return value.lowercase(Locale.ROOT).trim()
    }

    private fun setAudioTrack(rendererIndex: Int, groupIndex: Int, trackIndex: Int) {
        val mappedTrackInfo = trackSelector.currentMappedTrackInfo
        if (mappedTrackInfo != null) {
            val trackGroups = mappedTrackInfo.getTrackGroups(rendererIndex)
            if (groupIndex >= 0 && groupIndex < trackGroups.length) {
                val group = trackGroups.get(groupIndex)
                val safeTrackIndex = trackIndex.coerceIn(0, group.length - 1)

                val builder = trackSelector.parameters
                    .buildUpon()
                    .setRendererDisabled(rendererIndex, false)

                for (audioGroupIndex in 0 until trackGroups.length) {
                    builder.clearOverridesOfType(trackGroups[audioGroupIndex].type)
                }

                builder.addOverride(
                    TrackSelectionOverride(
                        group,
                        safeTrackIndex
                    )
                )

                trackSelector.setParameters(builder)
            } else {
                Log.e(TAG, "setAudioTrack: groupIndex out of bounds: $groupIndex")
            }
        }
    }

    private fun sendSeekToEvent(positionMs: Long) {
        exoPlayer?.seekTo(positionMs)
        val event: MutableMap<String, Any> = HashMap()
        event["event"] = "seek"
        event["position"] = positionMs
        eventSink.success(event)
    }

    fun setMixWithOthers(mixWithOthers: Boolean) {
        setAudioAttributes(exoPlayer, mixWithOthers)
    }

    fun dispose() {
        disposeMediaSession()
        disposeRemoteNotifications()
        positionSnapshotHandler?.removeCallbacksAndMessages(null)
        positionSnapshotHandler = null
        positionSnapshotRunnable = null
        if (isInitialized) {
            exoPlayer?.stop()
        }
        textureEntry.release()
        eventChannel.setStreamHandler(null)
        surface?.release()
        exoPlayer?.release()
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other == null || javaClass != other.javaClass) return false
        val that = other as BetterPlayer
        if (if (exoPlayer != null) exoPlayer != that.exoPlayer else that.exoPlayer != null) return false
        return if (surface != null) surface == that.surface else that.surface == null
    }

    override fun hashCode(): Int {
        var result = exoPlayer?.hashCode() ?: 0
        result = 31 * result + (surface?.hashCode() ?: 0)
        return result
    }

    companion object {
        private const val TAG = "BetterPlayer"
        private const val FORMAT_SS = "ss"
        private const val FORMAT_DASH = "dash"
        private const val FORMAT_HLS = "hls"
        private const val FORMAT_OTHER = "other"
        private const val DEFAULT_NOTIFICATION_CHANNEL = "BETTER_PLAYER_NOTIFICATION"
        private const val NOTIFICATION_ID = 20772077

        //Clear cache without accessing BetterPlayerCache.
        fun clearCache(context: Context?, result: MethodChannel.Result) {
            try {
                context?.let {
                    val file = File(it.cacheDir, "betterPlayerCache")
                    deleteDirectory(file)
                }
                result.success(null)
            } catch (exception: Exception) {
                Log.e(TAG, exception.toString())
                result.error("", "", "")
            }
        }

        private fun deleteDirectory(file: File) {
            if (file.isDirectory) {
                val entries = file.listFiles()
                if (entries != null) {
                    for (entry in entries) {
                        deleteDirectory(entry)
                    }
                }
            }
            if (!file.delete()) {
                Log.e(TAG, "Failed to delete cache dir.")
            }
        }

        //Start pre cache of video. Invoke work manager job and start caching in background.
        fun preCache(
            context: Context?, dataSource: String?, preCacheSize: Long,
            maxCacheSize: Long, maxCacheFileSize: Long, headers: Map<String, String?>,
            cacheKey: String?, result: MethodChannel.Result
        ) {
            val dataBuilder = Data.Builder()
                .putString(BetterPlayerPlugin.URL_PARAMETER, dataSource)
                .putLong(BetterPlayerPlugin.PRE_CACHE_SIZE_PARAMETER, preCacheSize)
                .putLong(BetterPlayerPlugin.MAX_CACHE_SIZE_PARAMETER, maxCacheSize)
                .putLong(BetterPlayerPlugin.MAX_CACHE_FILE_SIZE_PARAMETER, maxCacheFileSize)
            if (cacheKey != null) {
                dataBuilder.putString(BetterPlayerPlugin.CACHE_KEY_PARAMETER, cacheKey)
            }
            for (headerKey in headers.keys) {
                dataBuilder.putString(
                    BetterPlayerPlugin.HEADER_PARAMETER + headerKey,
                    headers[headerKey]
                )
            }
            if (dataSource != null && context != null) {
                val cacheWorkRequest = OneTimeWorkRequest.Builder(CacheWorker::class.java)
                    .addTag(dataSource)
                    .setInputData(dataBuilder.build()).build()
                WorkManager.getInstance(context).enqueue(cacheWorkRequest)
            }
            result.success(null)
        }

        //Stop pre cache of video with given url. If there's no work manager job for given url, then
        //it will be ignored.
        fun stopPreCache(context: Context?, url: String?, result: MethodChannel.Result) {
            if (url != null && context != null) {
                WorkManager.getInstance(context).cancelAllWorkByTag(url)
            }
            result.success(null)
        }
    }

}
