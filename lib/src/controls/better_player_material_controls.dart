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

/// The phone controls, laid out the way Netflix's are: the title at the top,
/// back, play and forward in the middle, and the timeline at the bottom with
/// the time left, over a row of labelled actions (speed, lock, episodes,
/// audio and subtitles, next episode). A live stream drops the timeline and
/// the seeking for a LIVE badge. Narrow players (portrait, inline) keep only
/// the essentials and move the rest into the More panel.
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

  bool get _locked => _betterPlayerController?.controlsEnabled != true;

  bool get _live => _betterPlayerController?.isLiveStream() == true;

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
        !_locked;

    Widget content = LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560 || constraints.maxHeight < 300;
        return Stack(
          fit: StackFit.expand,
          children: [
            _buildTapArea(),
            if (_locked) _buildLockedControls(compact) else _buildVisibleControls(compact),
            _buildNextVideoWidget(),
          ],
        );
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
        child: content,
      );
    }
    return content;
  }

  // ---------------------------------------------------------------------------
  // Type

  TextStyle _emphasis(double size, {Color color = Colors.white}) => TextStyle(
    color: color,
    fontSize: size,
    fontFamily: _configuration.emphasisFontFamily,
    fontWeight: _configuration.emphasisFontFamily == null ? FontWeight.w700 : null,
    height: 1.2,
  );

  static const _textShadow = [Shadow(color: Colors.black54, blurRadius: 8)];

  TextStyle get _timeStyle => _emphasis(13).copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
    shadows: _textShadow,
  );

  // ---------------------------------------------------------------------------
  // Layout

  Widget _buildVisibleControls(bool compact) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Scrims top and bottom only, reaching into the unsafe area, so the
        // middle of the picture stays the picture.
        _hideWithControls(
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xB3000000), Color(0x00000000), Color(0x00000000), Color(0xCC000000)],
                stops: [0, .32, .52, 1],
              ),
            ),
          ),
          notifyOnEnd: true,
        ),
        _withFullscreenSafeArea(
          Stack(
            fit: StackFit.expand,
            children: [
              Align(alignment: Alignment.topCenter, child: _hideWithControls(_topBar(compact))),
              Center(child: _centerArea(compact)),
              // The bottom bar gates itself: the skip button inside it has to
              // outlive the overlay.
              Align(alignment: Alignment.bottomCenter, child: _bottomBar(compact)),
            ],
          ),
        ),
      ],
    );
  }

  /// Fades a piece of the control surface out with the overlay. Everything the
  /// overlay owns goes through here; the IntroDB skip button deliberately does
  /// not, because its window closes on its own and would otherwise become
  /// unreachable as soon as the controls auto-hide.
  ///
  /// [notifyOnEnd] marks the one instance that reports the finished transition,
  /// so the controller still sees a single visibility change.
  Widget _hideWithControls(Widget child, {bool notifyOnEnd = false}) => AnimatedOpacity(
    opacity: controlsNotVisible ? 0 : 1,
    duration: betterPlayerMotionDuration,
    curve: Curves.easeOut,
    onEnd: notifyOnEnd ? _onPlayerHide : null,
    child: IgnorePointer(ignoring: controlsNotVisible, child: child),
  );

  Widget _withFullscreenSafeArea(Widget child) =>
      _betterPlayerController?.isFullScreen == true ? SafeArea(child: child) : child;

  Widget _topBar(bool compact) {
    final size = compact ? 40.0 : 44.0;
    final name = _configuration.name;
    final subtitle = _configuration.subtitle;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(compact ? 8 : 16, compact ? 6 : 10, compact ? 8 : 16, 0),
      child: Row(
        children: [
          BetterPlayerControlButton(
            key: const Key('better_player_back_button'),
            icon: PhosphorIcons.arrowLeft(),
            label: strings.back,
            size: size,
            onPressed: _exitPlayer,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _emphasis(compact ? 14 : 17).copyWith(shadows: _textShadow),
                      ),
                    ),
                    if (_live) ...[const SizedBox(width: 10), BetterPlayerLiveBadge(label: strings.live)],
                  ],
                ),
                if (subtitle?.isNotEmpty == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: BetterPlayerColors.secondary,
                        fontSize: compact ? 12 : 13,
                        shadows: _textShadow,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (compact && _configuration.enableSubtitles && _configuration.showSubtitlesButton)
            _iconButton(
              key: const Key('better_player_subtitles_button'),
              icon: _configuration.subtitlesIcon,
              label: audioAndSubtitlesLabel,
              size: size,
              onPressed: openAudioAndSubtitles,
            ),
          if (!compact && _configuration.enableMute) _muteButton(size),
          if (_configuration.enableCast && _betterPlayerController != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 6),
              child: BetterPlayerCastButton(controller: _betterPlayerController!, color: Colors.white, size: size),
            ),
          if (_configuration.enablePip) _pipButton(size),
          if (_configuration.enableOverflowMenu)
            _iconButton(
              key: const Key('better_player_more_button'),
              icon: PhosphorIcons.dotsThreeVertical(PhosphorIconsStyle.bold),
              label: strings.more,
              size: size,
              onPressed: () {
                cancelAndRestartTimer();
                onShowMoreClicked(includeBarActions: compact);
              },
            ),
        ],
      ),
    );
  }

  Widget _iconButton({
    Key? key,
    required IconData icon,
    required String label,
    required double size,
    required VoidCallback? onPressed,
    bool selected = false,
  }) => Padding(
    padding: const EdgeInsetsDirectional.only(start: 6),
    child: BetterPlayerControlButton(
      key: key,
      icon: icon,
      label: label,
      size: size,
      iconSize: size * .5,
      selected: selected,
      onPressed: onPressed,
    ),
  );

  Widget _centerArea(bool compact) {
    final loading = isLoading(_latestValue);
    return Stack(
      alignment: Alignment.center,
      children: [
        _hideWithControls(_transportControls(compact, loading: loading && !controlsNotVisible)),
        // Buffering still shows once the rest has gone.
        if (loading && controlsNotVisible) IgnorePointer(child: _loadingIndicator(compact ? 56 : 72)),
      ],
    );
  }

  Widget _loadingIndicator(double size) {
    final custom = _configuration.loadingWidget;
    return Semantics(
      label: 'Buffering',
      liveRegion: true,
      child:
          custom ??
          SizedBox.square(
            key: const Key('better_player_loading_indicator'),
            dimension: size,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: _configuration.loadingColor),
          ),
    );
  }

  Widget _transportControls(bool compact, {required bool loading}) {
    final finished = isVideoFinished(_latestValue);
    final playing = _controller?.value.isPlaying == true;
    final canSeek = _latestValue?.duration != null;
    final skipSize = compact ? 44.0 : 56.0;
    final playSize = compact ? 56.0 : 72.0;
    final gap = compact ? 28.0 : 52.0;
    final skips = _configuration.enableSkips && !_live;
    final backSeconds = _configuration.backwardSkipTimeInMilliseconds ~/ 1000;
    final forwardSeconds = _configuration.forwardSkipTimeInMilliseconds ~/ 1000;
    // Transport reads left to right in every language.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (skips) ...[
            BetterPlayerControlButton(
              key: const Key('better_player_material_controls_skip_back_button'),
              icon: _configuration.skipBackIcon,
              label: strings.seekBackBy(backSeconds),
              size: skipSize,
              onPressed: canSeek ? skipBack : null,
              glyphBuilder: (color) =>
                  BetterPlayerSkipGlyph(forward: false, seconds: backSeconds, color: color, size: skipSize * .54),
            ),
            SizedBox(width: gap),
          ],
          if (_configuration.enablePlayPause)
            Stack(
              alignment: Alignment.center,
              children: [
                BetterPlayerControlButton(
                  key: const Key('better_player_material_controls_play_pause_button'),
                  icon: finished
                      ? PhosphorIcons.arrowCounterClockwise(PhosphorIconsStyle.bold)
                      : playing
                      ? _configuration.pauseIcon
                      : _configuration.playIcon,
                  label: finished
                      ? strings.replay
                      : playing
                      ? strings.pause
                      : strings.play,
                  size: playSize,
                  iconSize: playSize * .46,
                  onPressed: _onPlayPause,
                ),
                if (loading) IgnorePointer(child: _loadingIndicator(playSize + 8)),
              ],
            ),
          if (skips) ...[
            SizedBox(width: gap),
            BetterPlayerControlButton(
              key: const Key('better_player_material_controls_skip_forward_button'),
              icon: _configuration.skipForwardIcon,
              label: strings.seekForwardBy(forwardSeconds),
              size: skipSize,
              onPressed: canSeek ? skipForward : null,
              glyphBuilder: (color) =>
                  BetterPlayerSkipGlyph(forward: true, seconds: forwardSeconds, color: color, size: skipSize * .54),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bottomBar(bool compact) {
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(compact ? 12 : 24, 4, compact ? 8 : 24, compact ? 4 : 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Left out of the fade, and kept above the rest of the bar so the
          // button holds the same spot whether or not the overlay is showing.
          if (!_live) _buildIntroDbSkipSlot(compact),
          _hideWithControls(_bottomBarBody(compact)),
        ],
      ),
    );
  }

  /// The app's IntroDB skip action. A skip window closes on its own, so the
  /// button stays outside the overlay fade and remains tappable once the
  /// controls auto-hide. The faded bar underneath still occupies its space,
  /// which is what keeps the button from moving between the two states.
  Widget _buildIntroDbSkipSlot(bool compact) {
    final builder = _configuration.introDbSkipButtonBuilder;
    if (builder == null || _configuration.introDbSkipAvailable?.call() == false) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Padding(
        padding: EdgeInsets.only(bottom: compact ? 4 : 10),
        child: builder(context),
      ),
    );
  }

  Widget _bottomBarBody(bool compact) {
    final live = _live;
    final fullscreenButton = _configuration.enableFullscreen ? _fullscreenButton(compact) : null;
    final timeline = !live && _configuration.enableProgressBar;
    final Widget firstRow;
    if (timeline) {
      firstRow = _timelineRow(trailing: fullscreenButton);
    } else if (compact || fullscreenButton != null) {
      firstRow = Row(
        children: [
          if (live && compact) BetterPlayerLiveBadge(label: strings.live),
          const Spacer(),
          ?fullscreenButton,
        ],
      );
    } else {
      firstRow = const SizedBox.shrink();
    }
    if (compact) return firstRow;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [firstRow, const SizedBox(height: 4), _actionRow()],
    );
  }

  Widget _timelineRow({Widget? trailing}) {
    final position = _latestValue?.position ?? Duration.zero;
    final mode = _configuration.playerTimeMode;
    final showPosition = mode != 1 && mode != 2;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Row(
        children: [
          if (_configuration.enableProgressText && showPosition) ...[
            Text(BetterPlayerUtils.formatDuration(position), style: _timeStyle),
            const SizedBox(width: 12),
          ],
          Expanded(child: SizedBox(height: 36, child: _progressBar())),
          if (_configuration.enableProgressText) ...[
            const SizedBox(width: 12),
            Text(_durationLabel(), key: const Key('better_player_time_label'), style: _timeStyle),
          ],
          if (trailing != null) ...[const SizedBox(width: 4), trailing],
        ],
      ),
    );
  }

  Widget _fullscreenButton(bool compact) {
    final fullscreen = _betterPlayerController!.isFullScreen;
    return BetterPlayerControlButton(
      key: const Key('better_player_fullscreen_button'),
      icon: fullscreen ? _configuration.fullscreenDisableIcon : _configuration.fullscreenEnableIcon,
      label: fullscreen ? strings.exitFullscreen : strings.fullscreen,
      size: compact ? 36 : 40,
      iconSize: compact ? 20 : 22,
      backgroundColor: Colors.transparent,
      onPressed: _onExpandCollapse,
    );
  }

  /// Speed, lock, episodes, audio and subtitles, quality and next episode:
  /// named when they all fit, icons alone when they don't.
  Widget _actionRow() {
    final configuration = _configuration;
    final live = _live;
    final speed = _controller?.value.speed ?? 1;
    final actions = <_BarAction>[
      if (configuration.enablePlaybackSpeed && !live)
        _BarAction(
          key: const Key('better_player_speed_button'),
          icon: configuration.playbackSpeedIcon,
          label: '${strings.speed} (${BetterPlayerSpeedSelector.format(speed)})',
          onPressed: showSpeedSelection,
        ),
      _BarAction(
        key: const Key('better_player_lock_button'),
        icon: PhosphorIcons.lockSimpleOpen(),
        label: strings.lock,
        onPressed: _lock,
      ),
      for (final action in configuration.quickActions)
        _BarAction(icon: action.icon, label: action.title, onPressed: () => action.onClicked()),
      if (configuration.enableEpisodeSelection && configuration.onEpisodeListTap != null)
        _BarAction(
          key: const Key('better_player_episode_button'),
          icon: PhosphorIcons.cardsThree(),
          label: strings.episodes,
          onPressed: () => configuration.onEpisodeListTap!(),
        ),
      if (configuration.enableMovieRecommendations && configuration.onMovieRecommendationsTap != null)
        _BarAction(
          key: const Key('better_player_recommendations_button'),
          icon: PhosphorIcons.squaresFour(),
          label: strings.moreLikeThis,
          onPressed: () => configuration.onMovieRecommendationsTap!(),
        ),
      if (configuration.enableSubtitles && configuration.showSubtitlesButton)
        _BarAction(
          key: const Key('better_player_subtitles_button'),
          icon: configuration.subtitlesIcon,
          label: audioAndSubtitlesLabel,
          onPressed: openAudioAndSubtitles,
        ),
      if (configuration.enableQualities && configuration.showQualitiesButton)
        _BarAction(
          key: const Key('better_player_quality_button'),
          icon: configuration.qualitiesIcon,
          label: strings.quality,
          onPressed: showQualitiesSelection,
        ),
      if (configuration.onNextEpisodeTap != null)
        _BarAction(
          key: const Key('better_player_next_episode_button'),
          icon: PhosphorIcons.skipForward(),
          label: strings.nextEpisode,
          onPressed: configuration.onNextEpisodeTap!,
        ),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    final labelStyle = _emphasis(14);
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaler = MediaQuery.textScalerOf(context);
        var needed = 0.0;
        for (final action in actions) {
          final painter = TextPainter(
            text: TextSpan(text: action.label, style: labelStyle),
            textDirection: Directionality.of(context),
            textScaler: textScaler,
            maxLines: 1,
          )..layout();
          needed += painter.width + 22 + 8 + 28 + 8;
          painter.dispose();
        }
        final labelled = needed <= constraints.maxWidth;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            for (final action in actions)
              BetterPlayerControlButton(
                key: action.key,
                icon: action.icon,
                label: action.label,
                showLabel: labelled,
                labelStyle: labelStyle,
                size: 44,
                backgroundColor: Colors.transparent,
                onPressed: () {
                  cancelAndRestartTimer();
                  action.onPressed();
                },
              ),
          ],
        );
      },
    );
  }

  String _durationLabel() {
    final duration = _latestValue?.duration ?? Duration.zero;
    final position = _latestValue?.position ?? Duration.zero;
    switch (_configuration.playerTimeMode) {
      case 1:
        final remaining = duration - position;
        return '-${BetterPlayerUtils.formatDuration(remaining.isNegative ? Duration.zero : remaining)}';
      case 2:
        return '${BetterPlayerUtils.formatDuration(position)} / ${BetterPlayerUtils.formatDuration(duration)}';
      default:
        return BetterPlayerUtils.formatDuration(duration);
    }
  }

  Widget _muteButton(double size) {
    final muted = (_latestValue?.volume ?? 1) == 0;
    return _iconButton(
      icon: muted ? _configuration.muteIcon : _configuration.unMuteIcon,
      label: muted ? 'Unmute' : 'Mute',
      size: size,
      onPressed: () {
        cancelAndRestartTimer();
        if (muted) {
          _controller?.setVolume(_latestPlayerVolume);
        } else {
          _latestPlayerVolume = _latestValue?.volume ?? .5;
          _controller?.setVolume(0);
        }
      },
    );
  }

  Widget _pipButton(double size) => FutureBuilder<bool>(
    future: _betterPlayerController!.isPictureInPictureSupported(),
    builder: (context, snapshot) {
      if (snapshot.data != true || _betterPlayerController!.betterPlayerGlobalKey == null) {
        return const SizedBox.shrink();
      }
      return _iconButton(
        icon: _configuration.pipMenuIcon,
        label: strings.pictureInPicture,
        size: size,
        onPressed: () =>
            _betterPlayerController!.enablePictureInPicture(_betterPlayerController!.betterPlayerGlobalKey!),
      );
    },
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
    timeStyle: _emphasis(14),
  );

  // ---------------------------------------------------------------------------
  // Lock

  void _lock() {
    _hideTimer?.cancel();
    _betterPlayerController?.setControlsEnabled(false);
    setState(() {});
  }

  void _unlock() {
    _betterPlayerController?.setControlsEnabled(true);
    cancelAndRestartTimer();
  }

  /// Locked, a tap shows only this: the lock, and how to open it.
  Widget _buildLockedControls(bool compact) {
    return _hideWithControls(
      _withFullscreenSafeArea(
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: compact ? 12 : 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BetterPlayerControlButton(
                  key: const Key('better_player_unlock_button'),
                  icon: PhosphorIcons.lockSimple(PhosphorIconsStyle.fill),
                  label: strings.unlock,
                  size: compact ? 48 : 56,
                  iconSize: compact ? 22 : 26,
                  onPressed: _unlock,
                ),
                const SizedBox(height: 10),
                Text(strings.screenLocked, style: _emphasis(compact ? 14 : 16).copyWith(shadows: _textShadow)),
                const SizedBox(height: 2),
                Text(
                  strings.tapToUnlock,
                  style: const TextStyle(color: BetterPlayerColors.secondary, fontSize: 13, shadows: _textShadow),
                ),
              ],
            ),
          ),
        ),
      ),
      notifyOnEnd: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Surfaces

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
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BetterPlayerIconSurface(icon: PhosphorIcons.warningCircle()),
            const SizedBox(height: 14),
            Text(strings.playbackFailed, textAlign: TextAlign.center, style: _emphasis(18)),
            if (_configuration.enableRetry) ...[
              const SizedBox(height: 18),
              BetterPlayerControlButton(
                icon: PhosphorIcons.arrowClockwise(),
                label: _betterPlayerController!.translations.generalRetry,
                showLabel: true,
                labelStyle: _emphasis(15),
                selected: true,
                onPressed: _betterPlayerController!.retryDataSource,
              ),
            ],
          ],
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
            padding: const EdgeInsets.fromLTRB(16, 16, 24, 96),
            child: BetterPlayerControlButton(
              icon: PhosphorIcons.skipForward(PhosphorIconsStyle.fill),
              label: '${_betterPlayerController!.translations.controlsNextVideoIn} $time',
              showLabel: true,
              labelStyle: _emphasis(15),
              selected: true,
              onPressed: _betterPlayerController!.playNextVideo,
            ),
          ),
        ),
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Actions

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

class _BarAction {
  const _BarAction({required this.icon, required this.label, required this.onPressed, this.key});

  final Key? key;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
}
