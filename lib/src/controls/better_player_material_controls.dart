import 'dart:async';

import 'package:better_player_plus/src/configuration/better_player_controls_configuration.dart';
import 'package:better_player_plus/src/controls/better_player_controls_state.dart';
import 'package:better_player_plus/src/controls/better_player_cast_button.dart';
import 'package:better_player_plus/src/controls/better_player_gesture_controls.dart';
import 'package:better_player_plus/src/controls/better_player_material_progress_bar.dart';
import 'package:better_player_plus/src/controls/better_player_multiple_gesture_detector.dart';
import 'package:better_player_plus/src/controls/better_player_progress_colors.dart';
import 'package:better_player_plus/src/controls/better_player_ui.dart';
import 'package:better_player_plus/src/core/better_player_brightness_manager.dart';
import 'package:better_player_plus/src/core/better_player_controller.dart';
import 'package:better_player_plus/src/core/better_player_utils.dart';
import 'package:better_player_plus/src/core/better_player_volume_manager.dart';
import 'package:better_player_plus/src/video_player/video_player.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class BetterPlayerMaterialControls extends StatefulWidget {
  const BetterPlayerMaterialControls({
    required this.onControlsVisibilityChanged,
    required this.onFullScreenChanged,
    required this.controlsConfiguration,
    super.key,
  });

  final Function(bool visibility) onControlsVisibilityChanged;
  final Function(bool isFullscreen) onFullScreenChanged;
  final BetterPlayerControlsConfiguration controlsConfiguration;

  @override
  State<BetterPlayerMaterialControls> createState() => _BetterPlayerMaterialControlsState();
}

class _BetterPlayerMaterialControlsState extends BetterPlayerControlsState<BetterPlayerMaterialControls> {
  VideoPlayerValue? _latestValue;
  Timer? _hideTimer;
  Timer? _initTimer;
  Timer? _expandTimer;
  VideoPlayerController? _controller;
  BetterPlayerController? _betterPlayerController;
  StreamSubscription? _visibilitySubscription;
  double _latestPlayerVolume = .5;
  double _deviceVolume = .5;
  double _brightness = .5;
  bool _brightnessInitialized = false;
  bool _volumeInitialized = false;

  BetterPlayerControlsConfiguration get _configuration => widget.controlsConfiguration;

  @override
  VideoPlayerValue? get latestValue => _latestValue;

  @override
  BetterPlayerController? get betterPlayerController => _betterPlayerController;

  @override
  BetterPlayerControlsConfiguration get betterPlayerControlsConfiguration => _configuration;

  @override
  Widget build(BuildContext context) => buildLTRDirectionality(_buildMainWidget());

  Widget _buildMainWidget() {
    if (_latestValue?.hasError == true) {
      return ColoredBox(color: Colors.black, child: _buildErrorWidget());
    }
    _initializeSystemLevels();
    final gestures = _configuration.gestureConfiguration;
    final gesturesEnabled =
        (gestures.enableVolumeSwipe ||
            gestures.enableBrightnessSwipe ||
            gestures.enableSeekSwipe ||
            gestures.enableDoubleTapSeek) &&
        _betterPlayerController?.controlsEnabled == true;

    Widget content = LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520 || constraints.maxHeight < 270;
        final overlay = Stack(
          fit: StackFit.expand,
          children: [
            _buildTapArea(),
            AnimatedOpacity(
              opacity: controlsNotVisible ? 0 : 1,
              duration: betterPlayerMotionDuration,
              curve: Curves.easeOutCubic,
              onEnd: _onPlayerHide,
              child: IgnorePointer(ignoring: controlsNotVisible, child: _buildVisibleControls(compact)),
            ),
            _buildNextVideoWidget(),
          ],
        );
        return overlay;
      },
    );

    content = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        BetterPlayerMultipleGestureDetector.of(context)?.onTap?.call();
        controlsNotVisible ? cancelAndRestartTimer() : changePlayerControlsNotVisible(true);
      },
      onDoubleTap: gestures.enableDoubleTapSeek
          ? null
          : () {
              BetterPlayerMultipleGestureDetector.of(context)?.onDoubleTap?.call();
              cancelAndRestartTimer();
            },
      onLongPress: () => BetterPlayerMultipleGestureDetector.of(context)?.onLongPress?.call(),
      child: content,
    );

    if (gesturesEnabled) {
      content = BetterPlayerGestureHandler(
        configuration: gestures,
        currentVolume: _deviceVolume,
        currentBrightness: _brightness,
        backwardDoubleTapSeek: Duration(milliseconds: _configuration.backwardSkipTimeInMilliseconds),
        forwardDoubleTapSeek: Duration(milliseconds: _configuration.forwardSkipTimeInMilliseconds),
        controlsVisible: !controlsNotVisible,
        isFullScreen: _betterPlayerController?.isFullScreen == true,
        onVolumeChanged: (value) {
          setState(() => _deviceVolume = value);
          BetterPlayerVolumeManager.setVolume(value);
        },
        onBrightnessChanged: (value) {
          setState(() => _brightness = value);
          BetterPlayerBrightnessManager.setBrightness(value);
        },
        onSeek: (offset) async {
          final position = await _controller?.position;
          final duration = _controller?.value.duration;
          if (position == null || duration == null) return;
          final target = position + offset;
          await _betterPlayerController?.seekTo(
            target < Duration.zero
                ? Duration.zero
                : target > duration
                ? duration
                : target,
          );
        },
        onTap: cancelAndRestartTimer,
        child: content,
      );
    }
    return content;
  }

  Widget _buildVisibleControls(bool compact) {
    if (_betterPlayerController?.controlsEnabled != true) {
      return _withFullscreenSafeArea(
        Align(
          alignment: Alignment.topRight,
          child: Padding(padding: const EdgeInsets.all(10), child: _lockButton()),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xB3000000), Color(0x26000000), Color(0x12000000), Color(0xC7000000)],
              stops: [0, .28, .55, 1],
            ),
          ),
        ),
        _withFullscreenSafeArea(
          Stack(
            fit: StackFit.expand,
            children: [
              Align(alignment: Alignment.topCenter, child: _topBar(compact)),
              Center(child: _transportControlsArea(compact)),
              Align(alignment: Alignment.bottomCenter, child: _bottomBar(compact)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _withFullscreenSafeArea(Widget child) =>
      _betterPlayerController?.isFullScreen == true ? SafeArea(child: child) : child;

  Widget _topBar(bool compact) {
    final iconColor = _configuration.iconsColor;
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 8 : 16, 8, compact ? 6 : 12, 4),
      child: Row(
        children: [
          BetterPlayerControlButton(
            icon: PhosphorIcons.arrowLeft(),
            label: MaterialLocalizations.of(context).backButtonTooltip,
            iconColor: iconColor,
            size: compact ? 42 : 48,
            onPressed: _exitPlayer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!compact && _configuration.watchingText?.isNotEmpty == true)
                  Text(
                    _configuration.watchingText!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: iconColor.withValues(alpha: .72),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .9,
                    ),
                  ),
                Text(
                  _configuration.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: iconColor,
                    fontSize: compact ? 13 : 16,
                    fontWeight: FontWeight.w700,
                    shadows: const [Shadow(color: Colors.black54, blurRadius: 6)],
                  ),
                ),
              ],
            ),
          ),
          if (!compact) _lockButton(),
          if (_configuration.enableCast && _betterPlayerController != null)
            BetterPlayerCastButton(controller: _betterPlayerController!, color: iconColor, size: compact ? 42 : 48),
          if (_configuration.enablePip) _pipButton(compact),
          if (_configuration.enableOverflowMenu)
            BetterPlayerControlButton(
              icon: _configuration.overflowMenuIcon,
              label: 'Player settings',
              iconColor: iconColor,
              size: compact ? 42 : 48,
              onPressed: onShowMoreClicked,
            ),
        ],
      ),
    );
  }

  Widget _transportControls(bool compact) {
    final finished = isVideoFinished(_latestValue);
    final iconColor = _configuration.iconsColor;
    final gap = compact ? 16.0 : 28.0;
    final canSeek = _latestValue?.duration != null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_configuration.enableSkips)
          BetterPlayerControlButton(
            key: const Key('better_player_material_controls_skip_back_button'),
            icon: _configuration.skipBackIcon,
            label: 'Seek back ${_configuration.backwardSkipTimeInMilliseconds ~/ 1000} seconds',
            iconColor: iconColor,
            backgroundColor: Colors.black.withValues(alpha: .14),
            size: compact ? 44 : 52,
            iconSize: compact ? 21 : 25,
            onPressed: canSeek ? skipBack : null,
          ),
        SizedBox(width: gap),
        if (_configuration.enablePlayPause)
          BetterPlayerControlButton(
            key: const Key('better_player_material_controls_play_pause_button'),
            icon: finished
                ? PhosphorIcons.arrowCounterClockwise(PhosphorIconsStyle.bold)
                : _controller?.value.isPlaying == true
                ? _configuration.pauseIcon
                : _configuration.playIcon,
            label: finished
                ? 'Replay'
                : _controller?.value.isPlaying == true
                ? 'Pause'
                : 'Play',
            iconColor: iconColor,
            backgroundColor: Colors.black.withValues(alpha: .18),
            size: compact ? 62 : 76,
            iconSize: compact ? 31 : 38,
            onPressed: _onPlayPause,
          ),
        SizedBox(width: gap),
        if (_configuration.enableSkips)
          BetterPlayerControlButton(
            key: const Key('better_player_material_controls_skip_forward_button'),
            icon: _configuration.skipForwardIcon,
            label: 'Seek forward ${_configuration.forwardSkipTimeInMilliseconds ~/ 1000} seconds',
            iconColor: iconColor,
            backgroundColor: Colors.black.withValues(alpha: .14),
            size: compact ? 44 : 52,
            iconSize: compact ? 21 : 25,
            onPressed: canSeek ? skipForward : null,
          ),
      ],
    );
  }

  Widget _bottomBar(bool compact) {
    final live = _betterPlayerController!.isLiveStream();
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 10 : 20, 4, compact ? 10 : 20, compact ? 8 : 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live)
            Align(alignment: AlignmentDirectional.centerStart, child: _live())
          else ...[
            if (_configuration.enableProgressText)
              Row(
                children: [
                  Text(BetterPlayerUtils.formatDuration(_latestValue?.position ?? Duration.zero), style: _timeStyle),
                  const Spacer(),
                  Text(_durationLabel(), style: _timeStyle),
                ],
              ),
            if (_configuration.enableProgressBar) SizedBox(height: compact ? 22 : 28, child: _progressBar()),
          ],
          Row(
            children: [
              if (_configuration.enableMute) _muteButton(compact),
              const Spacer(),
              if (_configuration.enableQualities && _configuration.showQualitiesButton)
                _featureButton(
                  key: const Key('better_player_quality_button'),
                  icon: _configuration.qualitiesIcon,
                  label: 'Quality',
                  compact: compact,
                  onPressed: showQualitiesSelection,
                ),
              if (_configuration.enableSubtitles && _configuration.showSubtitlesButton)
                _featureButton(
                  key: const Key('better_player_subtitles_button'),
                  icon: _configuration.subtitlesIcon,
                  label: 'Subtitles',
                  compact: compact,
                  onPressed: _onSubtitlesPressed,
                ),
              if (_configuration.enableDownloadButton)
                _featureButton(
                  key: const Key('better_player_download_button'),
                  icon: _configuration.downloadIcon,
                  label: 'Download',
                  compact: compact,
                  onPressed: _configuration.onDownloadTap == null ? null : _onDownloadPressed,
                ),
              if (_configuration.enableCrop)
                _featureButton(
                  key: const Key('better_player_crop_button'),
                  icon: _configuration.cropIcon,
                  label: 'Crop & fit',
                  compact: compact,
                  selected: _betterPlayerController!.getFit() != BoxFit.contain,
                  onPressed: showCropSelection,
                ),
              if (_configuration.enableEpisodeSelection)
                _featureButton(
                  key: const Key('better_player_episode_button'),
                  icon: PhosphorIcons.listBullets(),
                  label: 'Episodes',
                  compact: compact,
                  onPressed: _configuration.onEpisodeListTap,
                ),
              if (_configuration.enableMovieRecommendations)
                _featureButton(
                  key: const Key('better_player_recommendations_button'),
                  icon: PhosphorIcons.filmSlate(),
                  label: 'Recommendations',
                  compact: compact,
                  onPressed: _configuration.onMovieRecommendationsTap,
                ),
              if (_configuration.enableFullscreen)
                BetterPlayerControlButton(
                  key: const Key('better_player_fullscreen_button'),
                  icon: _betterPlayerController!.isFullScreen
                      ? _configuration.fullscreenDisableIcon
                      : _configuration.fullscreenEnableIcon,
                  label: _betterPlayerController!.isFullScreen ? 'Exit fullscreen' : 'Enter fullscreen',
                  iconColor: _configuration.iconsColor,
                  size: compact ? 42 : 48,
                  onPressed: _onExpandCollapse,
                ),
            ],
          ),
        ],
      ),
    );
  }

  TextStyle get _timeStyle => TextStyle(
    color: _configuration.textColor,
    fontSize: 12,
    fontFeatures: const [FontFeature.tabularFigures()],
    fontWeight: FontWeight.w600,
    shadows: const [Shadow(color: Colors.black, blurRadius: 5)],
  );

  String _durationLabel() {
    final duration = _latestValue?.duration ?? Duration.zero;
    final position = _latestValue?.position ?? Duration.zero;
    switch (_configuration.playerTimeMode) {
      case 1:
        return '-${BetterPlayerUtils.formatDuration(duration - position)}';
      case 2:
        return '${BetterPlayerUtils.formatDuration(position)} / ${BetterPlayerUtils.formatDuration(duration)}';
      default:
        return BetterPlayerUtils.formatDuration(duration);
    }
  }

  Widget _featureButton({
    Key? key,
    required IconData icon,
    required String label,
    required bool compact,
    required VoidCallback? onPressed,
    bool selected = false,
  }) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 6),
    child: BetterPlayerControlButton(
      key: key,
      icon: icon,
      label: label,
      iconColor: _configuration.iconsColor,
      size: compact ? 42 : 48,
      selected: selected,
      onPressed: onPressed,
    ),
  );

  void _onSubtitlesPressed() {
    final callback = _configuration.onSubtitlesTap;
    if (callback == null) {
      showSubtitlesSelection();
      return;
    }
    cancelAndRestartTimer();
    callback();
  }

  void _onDownloadPressed() {
    cancelAndRestartTimer();
    _configuration.onDownloadTap?.call();
  }

  Widget _muteButton(bool compact) => BetterPlayerControlButton(
    icon: (_latestValue?.volume ?? 0) > 0 ? _configuration.unMuteIcon : _configuration.muteIcon,
    label: (_latestValue?.volume ?? 0) > 0 ? 'Mute' : 'Unmute',
    iconColor: _configuration.iconsColor,
    size: compact ? 42 : 48,
    onPressed: () {
      cancelAndRestartTimer();
      if ((_latestValue?.volume ?? 0) == 0) {
        _controller?.setVolume(_latestPlayerVolume);
      } else {
        _latestPlayerVolume = _latestValue?.volume ?? .5;
        _controller?.setVolume(0);
      }
    },
  );

  Widget _lockButton() => BetterPlayerControlButton(
    icon: _betterPlayerController?.controlsEnabled == true
        ? PhosphorIcons.lockOpen()
        : PhosphorIcons.lock(PhosphorIconsStyle.fill),
    label: _betterPlayerController?.controlsEnabled == true ? 'Lock controls' : 'Unlock controls',
    iconColor: _configuration.iconsColor,
    selected: _betterPlayerController?.controlsEnabled != true,
    onPressed: () {
      _betterPlayerController?.setControlsEnabled(_betterPlayerController?.controlsEnabled != true);
      cancelAndRestartTimer();
    },
  );

  Widget _pipButton(bool compact) => FutureBuilder<bool>(
    future: _betterPlayerController!.isPictureInPictureSupported(),
    builder: (context, snapshot) {
      if (snapshot.data != true || _betterPlayerController!.betterPlayerGlobalKey == null) {
        return const SizedBox.shrink();
      }
      return BetterPlayerControlButton(
        icon: _configuration.pipMenuIcon,
        label: 'Picture in picture',
        iconColor: _configuration.iconsColor,
        size: compact ? 42 : 48,
        onPressed: () =>
            _betterPlayerController!.enablePictureInPicture(_betterPlayerController!.betterPlayerGlobalKey!),
      );
    },
  );

  Widget _live() => DecoratedBox(
    decoration: BoxDecoration(
      color: _configuration.liveTextColor.withValues(alpha: .18),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: _configuration.liveTextColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(
            _betterPlayerController!.translations.controlsLive,
            style: TextStyle(color: _configuration.textColor, fontSize: 12, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    ),
  );

  Widget _progressBar() => BetterPlayerMaterialVideoProgressBar(
    _controller,
    _betterPlayerController,
    onDragStart: () => _hideTimer?.cancel(),
    onDragEnd: _startHideTimer,
    onTapDown: cancelAndRestartTimer,
    colors: BetterPlayerProgressColors(
      playedColor: _configuration.progressBarPlayedColor,
      handleColor: _configuration.progressBarHandleColor,
      bufferedColor: _configuration.progressBarBufferedColor,
      backgroundColor: _configuration.progressBarBackgroundColor,
    ),
    showThumbnailPreview: _configuration.enableThumbnailPreview,
  );

  Widget _buildTapArea() => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onTap: () {
      if (controlsNotVisible) {
        cancelAndRestartTimer();
      } else {
        _hideTimer?.cancel();
        changePlayerControlsNotVisible(true);
      }
    },
    child: const ColoredBox(color: Colors.transparent),
  );

  Widget _buildErrorWidget() {
    final custom = _betterPlayerController?.betterPlayerConfiguration.errorBuilder;
    if (custom != null) {
      return custom(context, _betterPlayerController!.videoPlayerController!.value.errorDescription);
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BetterPlayerIconSurface(icon: PhosphorIcons.warningCircle(), color: _configuration.loadingColor),
                const SizedBox(height: 14),
                Text(
                  _betterPlayerController!.translations.generalDefaultError,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _configuration.textColor, fontSize: 17, fontWeight: FontWeight.w700),
                ),
                if (_configuration.enableRetry) ...[
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _betterPlayerController!.retryDataSource,
                    icon: Icon(PhosphorIcons.arrowClockwise()),
                    label: Text(_betterPlayerController!.translations.generalRetry),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _transportControlsArea(bool compact) {
    final loading = isLoading(_latestValue);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _transportControls(compact),
        const SizedBox(height: 10),
        SizedBox(height: 3, child: loading ? IgnorePointer(child: _buildLoadingWidget()) : const SizedBox.shrink()),
      ],
    );
  }

  Widget _buildLoadingWidget() {
    if (_configuration.loadingWidget != null) {
      return _configuration.loadingWidget!;
    }
    return Semantics(
      label: 'Buffering',
      liveRegion: true,
      child: SizedBox(
        width: 60,
        height: 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 3,
            color: _configuration.loadingColor,
            backgroundColor: _configuration.loadingColor.withValues(alpha: .24),
          ),
        ),
      ),
    );
  }

  Widget _buildNextVideoWidget() => StreamBuilder<int?>(
    stream: _betterPlayerController?.nextVideoTimeStream,
    builder: (context, snapshot) {
      final time = snapshot.data;
      if (time == null || time <= 0) return const SizedBox.shrink();
      return Align(
        alignment: AlignmentDirectional.bottomEnd,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 84),
            child: Material(
              color: Colors.black.withValues(alpha: .76),
              borderRadius: BorderRadius.circular(18),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _betterPlayerController!.playNextVideo,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(PhosphorIcons.skipForward(PhosphorIconsStyle.fill), color: _configuration.iconsColor),
                      const SizedBox(width: 10),
                      Text(
                        '${_betterPlayerController!.translations.controlsNextVideoIn} $time',
                        style: TextStyle(color: _configuration.textColor, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Future<void> _exitPlayer() async {
    if (_betterPlayerController!.isFullScreen) {
      _betterPlayerController!.exitFullScreen();
      widget.onFullScreenChanged(false);
      return;
    }
    final callback = _configuration.onFullScreenChange;
    Navigator.pop(context, callback ?? () {});
  }

  void _onExpandCollapse() {
    changePlayerControlsNotVisible(true);
    final entering = !_betterPlayerController!.isFullScreen;
    _betterPlayerController!.toggleFullScreen();
    widget.onFullScreenChanged(entering);
    _expandTimer?.cancel();
    _expandTimer = Timer(_configuration.controlsHideTime, cancelAndRestartTimer);
  }

  void _onPlayPause() {
    final finished = isVideoFinished(_latestValue);
    if (_controller?.value.isPlaying == true) {
      _hideTimer?.cancel();
      changePlayerControlsNotVisible(false);
      _betterPlayerController?.pause();
      return;
    }
    cancelAndRestartTimer();
    if (finished) _betterPlayerController?.seekTo(Duration.zero);
    _betterPlayerController?.play();
    _betterPlayerController?.cancelNextVideoTimer();
  }

  Future<void> _initializeSystemLevels() async {
    if (_brightnessInitialized && _volumeInitialized) return;
    var changed = false;
    if (!_brightnessInitialized) {
      _brightnessInitialized = true;
      try {
        _brightness = await BetterPlayerBrightnessManager.getBrightness();
        changed = true;
      } catch (error) {
        BetterPlayerUtils.log('Failed to read brightness: $error');
      }
    }
    if (!_volumeInitialized) {
      _volumeInitialized = true;
      try {
        _deviceVolume = await BetterPlayerVolumeManager.getVolume();
        changed = true;
      } catch (error) {
        BetterPlayerUtils.log('Failed to read device volume: $error');
      }
    }
    if (mounted && changed) setState(() {});
  }

  Future<void> _initialize() async {
    _controller?.addListener(_updateState);
    _updateState();
    if (_controller?.value.isPlaying == true || _betterPlayerController!.betterPlayerConfiguration.autoPlay) {
      _startHideTimer();
    }
    if (_configuration.showControlsOnInitialize) {
      _initTimer = Timer(const Duration(milliseconds: 200), () => changePlayerControlsNotVisible(false));
    }
    _visibilitySubscription = _betterPlayerController!.controlsVisibilityStream.listen((visible) {
      changePlayerControlsNotVisible(!visible);
      if (visible) cancelAndRestartTimer();
    });
  }

  void _updateState() {
    if (!mounted || _controller == null) return;
    final nextValue = _controller!.value;
    final loadingChanged = isLoading(_latestValue) != isLoading(nextValue);
    final shouldRebuild =
        !controlsNotVisible ||
        isVideoFinished(nextValue) ||
        isLoading(nextValue) ||
        loadingChanged ||
        _latestValue?.hasError != nextValue.hasError;
    _latestValue = nextValue;
    if (shouldRebuild) {
      setState(() {
        if (isVideoFinished(_latestValue)) {
          changePlayerControlsNotVisible(false);
        }
      });
    }
  }

  @override
  void cancelAndRestartTimer() {
    _hideTimer?.cancel();
    changePlayerControlsNotVisible(false);
    _startHideTimer();
  }

  void _startHideTimer() {
    if (_betterPlayerController?.controlsAlwaysVisible == true) return;
    _hideTimer = Timer(const Duration(seconds: 3), () => changePlayerControlsNotVisible(true));
  }

  void _onPlayerHide() {
    _betterPlayerController?.toggleControlsVisibility(!controlsNotVisible);
    widget.onControlsVisibilityChanged(!controlsNotVisible);
  }

  void _disposeController() {
    _controller?.removeListener(_updateState);
    _hideTimer?.cancel();
    _initTimer?.cancel();
    _expandTimer?.cancel();
    _visibilitySubscription?.cancel();
  }

  @override
  void didChangeDependencies() {
    final nextController = BetterPlayerController.of(context);
    if (_betterPlayerController != nextController) {
      _disposeController();
      _betterPlayerController = nextController;
      _controller = nextController.videoPlayerController;
      _latestValue = _controller?.value;
      _initialize();
    }
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _disposeController();
    BetterPlayerBrightnessManager.restoreOriginalBrightness();
    super.dispose();
  }
}
