// Copyright 2017 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
package uz.shs.better_player_plus

import android.app.Activity
import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.graphics.drawable.Icon
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.util.LongSparseArray
import android.util.Rational
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import android.provider.Settings
import android.view.WindowManager
import uz.shs.better_player_plus.BetterPlayerCache.releaseCache
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.embedding.engine.plugins.FlutterPlugin.FlutterPluginBinding
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.view.TextureRegistry
import java.lang.Exception
import java.util.HashMap
import androidx.core.util.size

/**
 * Android platform implementation of the VideoPlayerPlugin.
 */
@OptIn(UnstableApi::class)
class BetterPlayerPlugin : FlutterPlugin, ActivityAware, MethodCallHandler {
    private val videoPlayers = LongSparseArray<BetterPlayer>()
    private val dataSources = LongSparseArray<Map<String, Any?>>()
    private val castConfigurations = LongSparseArray<Map<String, Any?>>()
    private var flutterState: FlutterState? = null
    private var currentNotificationTextureId: Long = -1
    private var currentNotificationDataSource: Map<String, Any?>? = null
    private var activity: Activity? = null
    private var pipHandler: Handler? = null
    private var pipRunnable: Runnable? = null
    private var pipBroadcastReceiver: BroadcastReceiver? = null
    private var currentPipPlayer: BetterPlayer? = null
    private var brightnessChannel: MethodChannel? = null
    private var volumeChannel: MethodChannel? = null
    private var castManager: BetterPlayerCastManager? = null
    
    override fun onAttachedToEngine(binding: FlutterPluginBinding) {
        DataSourceUtils.initialize(binding.applicationContext)
        val loader = FlutterLoader()
        flutterState = FlutterState(
            binding.applicationContext,
            binding.binaryMessenger, object : KeyForAssetFn {
                override fun get(asset: String?): String {
                    return loader.getLookupKeyForAsset(
                        asset!!
                    )
                }

            }, object : KeyForAssetAndPackageName {
                override fun get(asset: String?, packageName: String?): String {
                    return loader.getLookupKeyForAsset(
                        asset!!, packageName!!
                    )
                }
            },
            binding.textureRegistry
        )
        flutterState?.startListening(this)
        castManager = BetterPlayerCastManager(
            binding.applicationContext,
            playerFor = { textureId -> videoPlayers[textureId] },
            dataSourceFor = { textureId -> dataSources[textureId] },
            configurationFor = { textureId -> castConfigurations[textureId] }
        )
        binding.platformViewRegistry.registerViewFactory(
            "better_player_plus/chromecast_button",
            BetterPlayerCastButtonFactory(castManager!!)
        )
        
        // Setup brightness channel
        brightnessChannel = MethodChannel(binding.binaryMessenger, "better_player_plus/brightness")
        brightnessChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getBrightness" -> {
                    result.success(getBrightness())
                }
                "setBrightness" -> {
                    val brightness = call.argument<Double>("brightness")
                    if (brightness != null) {
                        setBrightness(brightness.toFloat())
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Brightness value is required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // Setup volume channel
        volumeChannel = MethodChannel(binding.binaryMessenger, "better_player_plus/volume")
        volumeChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getVolume" -> {
                    val volume = getDeviceVolume().toDouble()
                    Log.d(TAG, "Volume channel: getVolume returning $volume")
                    result.success(volume)
                }
                "setVolume" -> {
                    val volume = call.argument<Double>("volume")
                    Log.d(TAG, "Volume channel: setVolume called with $volume")
                    if (volume != null) {
                        setDeviceVolume(volume.toFloat())
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "Volume value is required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }


    @OptIn(UnstableApi::class)
    override fun onDetachedFromEngine(binding: FlutterPluginBinding) {
        if (flutterState == null) {
            Log.wtf(TAG, "Detached from the engine before registering to it.")
        }
        disposeAllPlayers()
        releaseCache()
        castManager?.dispose()
        castManager = null
        flutterState?.stopListening()
        flutterState = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
    }

    override fun onDetachedFromActivityForConfigChanges() {}

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}

    override fun onDetachedFromActivity() {}

    @UnstableApi
    private fun disposeAllPlayers() {
        for (i in 0 until videoPlayers.size) {
            videoPlayers.valueAt(i).dispose()
        }
        videoPlayers.clear()
        dataSources.clear()
        castConfigurations.clear()
    }

    @UnstableApi
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (flutterState == null || flutterState?.textureRegistry == null) {
            result.error("no_activity", "better_player plugin requires a foreground activity", null)
            return
        }
        when (call.method) {
            INIT_METHOD -> disposeAllPlayers()
            CREATE_METHOD -> {
                val handle = flutterState!!.textureRegistry!!.createSurfaceTexture()
                val eventChannel = EventChannel(
                    flutterState?.binaryMessenger, EVENTS_CHANNEL + handle.id()
                )
                var customDefaultLoadControl: CustomDefaultLoadControl? = null
                if (call.hasArgument(MIN_BUFFER_MS) && call.hasArgument(MAX_BUFFER_MS) &&
                    call.hasArgument(BUFFER_FOR_PLAYBACK_MS) &&
                    call.hasArgument(BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS)
                ) {
                    customDefaultLoadControl = CustomDefaultLoadControl(
                        call.argument(MIN_BUFFER_MS),
                        call.argument(MAX_BUFFER_MS),
                        call.argument(BUFFER_FOR_PLAYBACK_MS),
                        call.argument(BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS),
                        call.argument(BACK_BUFFER_DURATION_MS),
                        call.argument(RETAIN_BACK_BUFFER_FROM_KEYFRAME),
                        call.argument(PRIORITIZE_TIME_OVER_SIZE_THRESHOLDS)
                    )
                }
                val player = BetterPlayer(
                    flutterState?.applicationContext!!, eventChannel, handle,
                    customDefaultLoadControl, result
                )
                videoPlayers.put(handle.id(), player)
            }

            PRE_CACHE_METHOD -> preCache(call, result)
            STOP_PRE_CACHE_METHOD -> stopPreCache(call, result)
            CLEAR_CACHE_METHOD -> clearCache(result)
            else -> {
                if (call.argument<Any>(TEXTURE_ID_PARAMETER) == null) {
//                    result.error(
//                        "Unknown textureId",
//                        "No video player associated with texture id",
//                        null
//                    )
                    return
                }
                val textureId = ((call.argument<Any>(TEXTURE_ID_PARAMETER) as Int?) ?: 0).toLong()
                val player = videoPlayers[textureId]
                if (player == null) {
                    result.error(
                        "Unknown textureId",
                        "No video player associated with texture id $textureId",
                        null
                    )
                    return
                }
                onMethodCall(call, result, textureId, player)
            }
        }
    }

    @OptIn(UnstableApi::class)
    private fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
        textureId: Long,
        player: BetterPlayer
    ) {
        when (call.method) {
            SET_DATA_SOURCE_METHOD -> {
                setDataSource(call, result, player)
            }

            CONFIGURE_CAST_METHOD -> {
                val configuration = call.argument<Map<String, Any?>>(CAST_CONFIGURATION_PARAMETER)
                    ?: emptyMap()
                castConfigurations.put(textureId, configuration)
                castManager?.onDataSourceChanged(textureId)
                result.success(null)
            }

            SET_LOOPING_METHOD -> {
                player.setLooping(call.argument(LOOPING_PARAMETER)!!)
                result.success(null)
            }

            SET_VOLUME_METHOD -> {
                val volume = call.argument<Double>(VOLUME_PARAMETER)!!
                if (castManager?.setVolume(textureId, volume) != true) {
                    player.setVolume(volume)
                }
                result.success(null)
            }

            PLAY_METHOD -> {
                setupNotification(player)
                if (castManager?.play(textureId) != true) player.play()
                result.success(null)
            }

            PAUSE_METHOD -> {
                if (castManager?.pause(textureId) != true) player.pause()
                result.success(null)
            }

            SEEK_TO_METHOD -> {
                val location = (call.argument<Any>(LOCATION_PARAMETER) as Number?)!!.toInt()
                if (castManager?.seekTo(textureId, location.toLong()) != true) {
                    player.seekTo(location)
                }
                result.success(null)
            }

            POSITION_METHOD -> {
                result.success(castManager?.position(textureId) ?: player.position)
                player.sendBufferingUpdate(false)
            }

            ABSOLUTE_POSITION_METHOD -> result.success(player.absolutePosition)
            SET_SPEED_METHOD -> {
                val speed = call.argument<Double>(SPEED_PARAMETER)!!
                if (castManager?.setSpeed(textureId, speed) != true) {
                    player.setSpeed(speed)
                }
                result.success(null)
            }

            SET_TRACK_PARAMETERS_METHOD -> {
                player.setTrackParameters(
                    call.argument(WIDTH_PARAMETER)!!,
                    call.argument(HEIGHT_PARAMETER)!!,
                    call.argument(BITRATE_PARAMETER)!!
                )
                result.success(null)
            }

            ENABLE_PICTURE_IN_PICTURE_METHOD -> {
                enablePictureInPicture(player)
                result.success(null)
            }

            DISABLE_PICTURE_IN_PICTURE_METHOD -> {
                disablePictureInPicture(player)
                result.success(null)
            }

            IS_PICTURE_IN_PICTURE_SUPPORTED_METHOD -> result.success(
                isPictureInPictureSupported()
            )

            SET_AUDIO_TRACK_METHOD -> {
                val name = call.argument<String?>(NAME_PARAMETER)
                val index = call.argument<Int?>(INDEX_PARAMETER)
                if (name != null && index != null) {
                    player.setAudioTrack(name, index)
                }
                result.success(null)
            }

            SET_MIX_WITH_OTHERS_METHOD -> {
                val mixWitOthers = call.argument<Boolean?>(
                    MIX_WITH_OTHERS_PARAMETER
                )
                if (mixWitOthers != null) {
                    player.setMixWithOthers(mixWitOthers)
                }
            }

            DISPOSE_METHOD -> {
                dispose(player, textureId)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    @OptIn(UnstableApi::class)
    private fun setDataSource(
        call: MethodCall,
        result: MethodChannel.Result,
        player: BetterPlayer
    ) {
        val dataSource = call.argument<Map<String, Any?>>(DATA_SOURCE_PARAMETER)!!
        dataSources.put(getTextureId(player)!!, dataSource)
        val key = getParameter(dataSource, KEY_PARAMETER, "")
        val headers: Map<String, String> = getParameter(dataSource, HEADERS_PARAMETER, HashMap())
        val overriddenDuration: Number = getParameter(dataSource, OVERRIDDEN_DURATION_PARAMETER, 0)
        if (dataSource[ASSET_PARAMETER] != null) {
            val asset = getParameter(dataSource, ASSET_PARAMETER, "")
            val assetLookupKey: String = if (dataSource[PACKAGE_PARAMETER] != null) {
                val packageParameter = getParameter(
                    dataSource,
                    PACKAGE_PARAMETER,
                    ""
                )
                flutterState!!.keyForAssetAndPackageName[asset, packageParameter]
            } else {
                flutterState!!.keyForAsset[asset]
            }
            player.setDataSource(
                flutterState?.applicationContext!!,
                key,
                "asset:///$assetLookupKey",
                null,
                result,
                headers,
                false,
                0L,
                0L,
                overriddenDuration.toLong(),
                null,
                null, null, null,
                false
            )
        } else {
            val useCache = getParameter(dataSource, USE_CACHE_PARAMETER, false)
            val maxCacheSizeNumber: Number = getParameter(dataSource, MAX_CACHE_SIZE_PARAMETER, 0)
            val maxCacheFileSizeNumber: Number =
                getParameter(dataSource, MAX_CACHE_FILE_SIZE_PARAMETER, 0)
            val maxCacheSize = maxCacheSizeNumber.toLong()
            val maxCacheFileSize = maxCacheFileSizeNumber.toLong()
            val uri = getParameter(dataSource, URI_PARAMETER, "")
            val cacheKey = getParameter<String?>(dataSource, CACHE_KEY_PARAMETER, null)
            val formatHint = getParameter<String?>(dataSource, FORMAT_HINT_PARAMETER, null)
            val isLive = getParameter(dataSource, IS_LIVE_PARAMETER, false)
            val licenseUrl = getParameter<String?>(dataSource, LICENSE_URL_PARAMETER, null)
            val clearKey = getParameter<String?>(dataSource, DRM_CLEARKEY_PARAMETER, null)
            val drmHeaders: Map<String, String> =
                getParameter(dataSource, DRM_HEADERS_PARAMETER, HashMap())
            val preRollDataSource =
                getParameter<Map<String, Any?>?>(
                    dataSource,
                    PRE_ROLL_DATA_SOURCE_PARAMETER,
                    null
                )
            val contentStartPosition: Number =
                getParameter(dataSource, CONTENT_START_POSITION_PARAMETER, 0)
            player.setDataSource(
                flutterState!!.applicationContext,
                key,
                uri,
                formatHint,
                result,
                headers,
                useCache,
                maxCacheSize,
                maxCacheFileSize,
                overriddenDuration.toLong(),
                licenseUrl,
                drmHeaders,
                cacheKey,
                clearKey,
                isLive,
                preRollDataSource,
                contentStartPosition.toLong()
            )
        }
    }

    /**
     * Start pre cache of video.
     *
     * @param call   - invoked method data
     * @param result - result which should be updated
     */
    @OptIn(UnstableApi::class)
    private fun preCache(call: MethodCall, result: MethodChannel.Result) {
        val dataSource = call.argument<Map<String, Any?>>(DATA_SOURCE_PARAMETER)
        if (dataSource != null) {
            val maxCacheSizeNumber: Number =
                getParameter(dataSource, MAX_CACHE_SIZE_PARAMETER, 100 * 1024 * 1024)
            val maxCacheFileSizeNumber: Number =
                getParameter(dataSource, MAX_CACHE_FILE_SIZE_PARAMETER, 10 * 1024 * 1024)
            val maxCacheSize = maxCacheSizeNumber.toLong()
            val maxCacheFileSize = maxCacheFileSizeNumber.toLong()
            val preCacheSizeNumber: Number =
                getParameter(dataSource, PRE_CACHE_SIZE_PARAMETER, 3 * 1024 * 1024)
            val preCacheSize = preCacheSizeNumber.toLong()
            val uri = getParameter(dataSource, URI_PARAMETER, "")
            val cacheKey = getParameter<String?>(dataSource, CACHE_KEY_PARAMETER, null)
            val headers: Map<String, String> =
                getParameter(dataSource, HEADERS_PARAMETER, HashMap())
            BetterPlayer.preCache(
                flutterState?.applicationContext,
                uri,
                preCacheSize,
                maxCacheSize,
                maxCacheFileSize,
                headers,
                cacheKey,
                result
            )
        }
    }

    /**
     * Stop pre cache video process (if exists).
     *
     * @param call   - invoked method data
     * @param result - result which should be updated
     */
    @UnstableApi
    private fun stopPreCache(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>(URL_PARAMETER)
        BetterPlayer.stopPreCache(flutterState?.applicationContext, url, result)
    }

    @UnstableApi
    private fun clearCache(result: MethodChannel.Result) {
        BetterPlayer.clearCache(flutterState?.applicationContext, result)
    }

    @OptIn(UnstableApi::class)
    private fun getTextureId(betterPlayer: BetterPlayer): Long? {
        for (index in 0 until videoPlayers.size) {
            if (betterPlayer === videoPlayers.valueAt(index)) {
                return videoPlayers.keyAt(index)
            }
        }
        return null
    }

    @OptIn(UnstableApi::class)
    private fun setupNotification(betterPlayer: BetterPlayer) {
        try {
            val textureId = getTextureId(betterPlayer)
            if (textureId != null) {
                val dataSource = dataSources[textureId]
                //Don't setup notification for the same source.
                if (textureId == currentNotificationTextureId && currentNotificationDataSource != null && dataSource != null && currentNotificationDataSource === dataSource) {
                    return
                }
                currentNotificationDataSource = dataSource
                currentNotificationTextureId = textureId
                removeOtherNotificationListeners()
                val showNotification = getParameter(dataSource, SHOW_NOTIFICATION_PARAMETER, false)
                if (showNotification) {
                    val title = getParameter(dataSource, TITLE_PARAMETER, "")
                    val author = getParameter(dataSource, AUTHOR_PARAMETER, "")
                    val imageUrl = getParameter(dataSource, IMAGE_URL_PARAMETER, "")
                    val notificationChannelName =
                        getParameter<String?>(dataSource, NOTIFICATION_CHANNEL_NAME_PARAMETER, null)
                    val activityName =
                        getParameter(dataSource, ACTIVITY_NAME_PARAMETER, "MainActivity")
                    betterPlayer.setupPlayerNotification(
                        flutterState?.applicationContext!!,
                        title, author, imageUrl, notificationChannelName, activityName
                    )
                }
            }
        } catch (exception: Exception) {
            Log.e(TAG, "SetupNotification failed", exception)
        }
    }

    @OptIn(UnstableApi::class)
    private fun removeOtherNotificationListeners() {
        for (index in 0 until videoPlayers.size) {
            videoPlayers.valueAt(index).disposeRemoteNotifications()
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun <T> getParameter(parameters: Map<String, Any?>?, key: String, defaultValue: T): T {
        if (parameters?.containsKey(key) == true) {
            val value = parameters[key]
            if (value != null) {
                return value as T
            }
        }
        return defaultValue
    }


    private fun isPictureInPictureSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && activity != null && activity!!.packageManager
            .hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    private fun enablePictureInPicture(player: BetterPlayer) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            player.setupMediaSession(flutterState!!.applicationContext)
            currentPipPlayer = player
            
            // Register broadcast receiver for PIP controls
            registerPipBroadcastReceiver()
            
            // Create PIP actions
            val actions = createPipActions()
            
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                params.setActions(actions)
            }
            
            activity!!.enterPictureInPictureMode(params.build())
            startPictureInPictureListenerTimer(player)
            player.onPictureInPictureStatusChanged(true)
        }
    }
    
    private fun registerPipBroadcastReceiver() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && pipBroadcastReceiver == null) {
            pipBroadcastReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context?, intent: Intent?) {
                    when (intent?.action) {
                        ACTION_PLAY -> currentPipPlayer?.play()
                        ACTION_PAUSE -> currentPipPlayer?.pause()
                    }
                    // Update PIP actions after play/pause
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        updatePipActions()
                    }
                }
            }
            
            val filter = IntentFilter().apply {
                addAction(ACTION_PLAY)
                addAction(ACTION_PAUSE)
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                activity?.registerReceiver(pipBroadcastReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                activity?.registerReceiver(pipBroadcastReceiver, filter)
            }
        }
    }
    
    private fun unregisterPipBroadcastReceiver() {
        pipBroadcastReceiver?.let {
            try {
                activity?.unregisterReceiver(it)
            } catch (e: Exception) {
                Log.e(TAG, "Error unregistering PIP broadcast receiver: ${e.message}")
            }
            pipBroadcastReceiver = null
        }
    }
    
    private fun createPipActions(): ArrayList<RemoteAction> {
        val actions = ArrayList<RemoteAction>()
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val player = currentPipPlayer
            val isPlaying = player?.isPlaying() ?: false
            
            if (isPlaying) {
                // Add pause action
                val pauseIntent = PendingIntent.getBroadcast(
                    activity,
                    0,
                    Intent(ACTION_PAUSE),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                
                val pauseIcon = Icon.createWithResource(activity, android.R.drawable.ic_media_pause)
                val pauseAction = RemoteAction(
                    pauseIcon,
                    "Pause",
                    "Pause video",
                    pauseIntent
                )
                actions.add(pauseAction)
            } else {
                // Add play action
                val playIntent = PendingIntent.getBroadcast(
                    activity,
                    0,
                    Intent(ACTION_PLAY),
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                
                val playIcon = Icon.createWithResource(activity, android.R.drawable.ic_media_play)
                val playAction = RemoteAction(
                    playIcon,
                    "Play",
                    "Play video",
                    playIntent
                )
                actions.add(playAction)
            }
        }
        
        return actions
    }
    
    private fun updatePipActions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && activity?.isInPictureInPictureMode == true) {
            val actions = createPipActions()
            val params = PictureInPictureParams.Builder()
                .setAspectRatio(Rational(16, 9))
                .setActions(actions)
                .build()
            
            activity?.setPictureInPictureParams(params)
        }
    }

    private fun disablePictureInPicture(player: BetterPlayer) {
        stopPipHandler()
        unregisterPipBroadcastReceiver()
        currentPipPlayer = null
        activity!!.moveTaskToBack(false)
        player.onPictureInPictureStatusChanged(false)
        player.disposeMediaSession()
    }

    private fun startPictureInPictureListenerTimer(player: BetterPlayer) {
        pipHandler = Handler(Looper.getMainLooper())
        pipRunnable = Runnable {
            if (activity!!.isInPictureInPictureMode) {
                pipHandler!!.postDelayed(pipRunnable!!, 100)
            } else {
                player.onPictureInPictureStatusChanged(false)
                player.disposeMediaSession()
                unregisterPipBroadcastReceiver()
                currentPipPlayer = null
                stopPipHandler()
            }
        }
        pipHandler!!.post(pipRunnable!!)
    }

    private fun dispose(player: BetterPlayer, textureId: Long) {
        castManager?.disposePlayer(textureId)
        player.dispose()
        videoPlayers.remove(textureId)
        dataSources.remove(textureId)
        castConfigurations.remove(textureId)
        stopPipHandler()
    }

    private fun stopPipHandler() {
        if (pipHandler != null) {
            pipHandler!!.removeCallbacksAndMessages(null)
            pipHandler = null
        }
        pipRunnable = null
    }
    
    /**
     * Get current screen brightness (0.0 - 1.0)
     */
    private fun getBrightness(): Float {
        return try {
            if (activity?.window != null) {
                val layoutParams = activity!!.window.attributes
                if (layoutParams.screenBrightness >= 0) {
                    layoutParams.screenBrightness
                } else {
                    // Get system brightness
                    val systemBrightness = Settings.System.getInt(
                        activity!!.contentResolver,
                        Settings.System.SCREEN_BRIGHTNESS,
                        125
                    )
                    systemBrightness / 255.0f
                }
            } else {
                0.5f
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get brightness", e)
            0.5f
        }
    }
    
    /**
     * Set screen brightness (0.0 - 1.0)
     */
    private fun setBrightness(brightness: Float) {
        try {
            if (activity?.window != null) {
                val layoutParams = activity!!.window.attributes
                // Set to -1 to restore system brightness control, otherwise set specific brightness
                layoutParams.screenBrightness = if (brightness < 0) {
                    -1.0f // Use system brightness
                } else {
                    brightness.coerceIn(0.0f, 1.0f)
                }
                activity!!.window.attributes = layoutParams
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set brightness", e)
        }
    }
    
    /**
     * Get current device media volume (0.0 - 1.0)
     */
    private fun getDeviceVolume(): Float {
        return try {
            val context = activity ?: flutterState?.applicationContext
            val audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            if (audioManager != null) {
                val currentVolume = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                Log.d(TAG, "getDeviceVolume: current=$currentVolume, max=$maxVolume")
                currentVolume.toFloat() / maxVolume.toFloat()
            } else {
                Log.e(TAG, "getDeviceVolume: AudioManager is null")
                0.5f
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get device volume", e)
            0.5f
        }
    }
    
    /**
     * Set device media volume (0.0 - 1.0)
     */
    private fun setDeviceVolume(volume: Float) {
        try {
            val context = activity ?: flutterState?.applicationContext
            val audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
            if (audioManager != null) {
                val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                val targetVolume = (volume.coerceIn(0.0f, 1.0f) * maxVolume).toInt()
                Log.d(TAG, "setDeviceVolume: volume=$volume, target=$targetVolume, max=$maxVolume")
                // Don't show UI - let the app handle the visual feedback
                audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, targetVolume, 0)
            } else {
                Log.e(TAG, "setDeviceVolume: AudioManager is null")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set device volume", e)
        }
    }

    private interface KeyForAssetFn {
        operator fun get(asset: String?): String
    }

    private interface KeyForAssetAndPackageName {
        operator fun get(asset: String?, packageName: String?): String
    }

    private class FlutterState(
        val applicationContext: Context,
        val binaryMessenger: BinaryMessenger,
        val keyForAsset: KeyForAssetFn,
        val keyForAssetAndPackageName: KeyForAssetAndPackageName,
        val textureRegistry: TextureRegistry?
    ) {
        private val methodChannel: MethodChannel = MethodChannel(binaryMessenger, CHANNEL)

        fun startListening(methodCallHandler: BetterPlayerPlugin?) {
            methodChannel.setMethodCallHandler(methodCallHandler)
        }

        fun stopListening() {
            methodChannel.setMethodCallHandler(null)
        }

    }

    companion object {
        private const val TAG = "BetterPlayerPlugin"
        private const val ACTION_PLAY = "uz.shs.better_player_plus.PLAY"
        private const val ACTION_PAUSE = "uz.shs.better_player_plus.PAUSE"
        private const val CHANNEL = "better_player_channel"
        private const val EVENTS_CHANNEL = "better_player_channel/videoEvents"
        private const val DATA_SOURCE_PARAMETER = "dataSource"
        private const val CAST_CONFIGURATION_PARAMETER = "configuration"
        private const val KEY_PARAMETER = "key"
        private const val HEADERS_PARAMETER = "headers"
        private const val USE_CACHE_PARAMETER = "useCache"
        private const val ASSET_PARAMETER = "asset"
        private const val PACKAGE_PARAMETER = "package"
        private const val URI_PARAMETER = "uri"
        private const val FORMAT_HINT_PARAMETER = "formatHint"
        private const val IS_LIVE_PARAMETER = "isLive"
        private const val TEXTURE_ID_PARAMETER = "textureId"
        private const val LOOPING_PARAMETER = "looping"
        private const val VOLUME_PARAMETER = "volume"
        private const val LOCATION_PARAMETER = "location"
        private const val SPEED_PARAMETER = "speed"
        private const val WIDTH_PARAMETER = "width"
        private const val HEIGHT_PARAMETER = "height"
        private const val BITRATE_PARAMETER = "bitrate"
        private const val SHOW_NOTIFICATION_PARAMETER = "showNotification"
        private const val TITLE_PARAMETER = "title"
        private const val AUTHOR_PARAMETER = "author"
        private const val IMAGE_URL_PARAMETER = "imageUrl"
        private const val NOTIFICATION_CHANNEL_NAME_PARAMETER = "notificationChannelName"
        private const val OVERRIDDEN_DURATION_PARAMETER = "overriddenDuration"
        private const val NAME_PARAMETER = "name"
        private const val INDEX_PARAMETER = "index"
        private const val LICENSE_URL_PARAMETER = "licenseUrl"
        private const val DRM_HEADERS_PARAMETER = "drmHeaders"
        private const val DRM_CLEARKEY_PARAMETER = "clearKey"
        private const val MIX_WITH_OTHERS_PARAMETER = "mixWithOthers"
        const val URL_PARAMETER = "url"
        const val PRE_CACHE_SIZE_PARAMETER = "preCacheSize"
        const val MAX_CACHE_SIZE_PARAMETER = "maxCacheSize"
        const val MAX_CACHE_FILE_SIZE_PARAMETER = "maxCacheFileSize"
        const val HEADER_PARAMETER = "header_"
        const val FILE_PATH_PARAMETER = "filePath"
        const val ACTIVITY_NAME_PARAMETER = "activityName"
        const val MIN_BUFFER_MS = "minBufferMs"
        const val MAX_BUFFER_MS = "maxBufferMs"
        const val BUFFER_FOR_PLAYBACK_MS = "bufferForPlaybackMs"
        const val BUFFER_FOR_PLAYBACK_AFTER_REBUFFER_MS = "bufferForPlaybackAfterRebufferMs"
        const val BACK_BUFFER_DURATION_MS = "backBufferDurationMs"
        const val RETAIN_BACK_BUFFER_FROM_KEYFRAME = "retainBackBufferFromKeyframe"
        const val PRIORITIZE_TIME_OVER_SIZE_THRESHOLDS = "prioritizeTimeOverSizeThresholds"
        const val CACHE_KEY_PARAMETER = "cacheKey"
        private const val INIT_METHOD = "init"
        private const val CREATE_METHOD = "create"
        private const val SET_DATA_SOURCE_METHOD = "setDataSource"
        private const val PRE_ROLL_DATA_SOURCE_PARAMETER = "preRollDataSource"
        private const val CONTENT_START_POSITION_PARAMETER = "contentStartPosition"
        private const val CONFIGURE_CAST_METHOD = "configureCast"
        private const val SET_LOOPING_METHOD = "setLooping"
        private const val SET_VOLUME_METHOD = "setVolume"
        private const val PLAY_METHOD = "play"
        private const val PAUSE_METHOD = "pause"
        private const val SEEK_TO_METHOD = "seekTo"
        private const val POSITION_METHOD = "position"
        private const val ABSOLUTE_POSITION_METHOD = "absolutePosition"
        private const val SET_SPEED_METHOD = "setSpeed"
        private const val SET_TRACK_PARAMETERS_METHOD = "setTrackParameters"
        private const val SET_AUDIO_TRACK_METHOD = "setAudioTrack"
        private const val ENABLE_PICTURE_IN_PICTURE_METHOD = "enablePictureInPicture"
        private const val DISABLE_PICTURE_IN_PICTURE_METHOD = "disablePictureInPicture"
        private const val IS_PICTURE_IN_PICTURE_SUPPORTED_METHOD = "isPictureInPictureSupported"
        private const val SET_MIX_WITH_OTHERS_METHOD = "setMixWithOthers"
        private const val CLEAR_CACHE_METHOD = "clearCache"
        private const val DISPOSE_METHOD = "dispose"
        private const val PRE_CACHE_METHOD = "preCache"
        private const val STOP_PRE_CACHE_METHOD = "stopPreCache"
    }
}
