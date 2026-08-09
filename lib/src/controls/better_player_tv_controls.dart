import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/core/better_player_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

class BetterPlayerTvControlsController {
  _BetterPlayerTvControlsState? _state;

  bool get controlsVisible => _state?._visible ?? false;

  bool handleBack() => _state?._handleExternalBack() ?? false;

  void show({bool restorePreviousFocus = false}) =>
      _state?._showFromController(restorePreviousFocus: restorePreviousFocus);

  void hide({bool preserveFocus = false}) => _state?._hideFromController(preserveFocus: preserveFocus);
}

class BetterPlayerTvControls extends StatefulWidget {
  const BetterPlayerTvControls({
    required this.controller,
    required this.onControlsVisibilityChanged,
    this.accentColor,
    this.controlsController,
    this.onExit,
    super.key,
  });

  final BetterPlayerController controller;
  final Function(bool) onControlsVisibilityChanged;
  final Color? accentColor;
  final BetterPlayerTvControlsController? controlsController;
  final VoidCallback? onExit;

  @override
  State<BetterPlayerTvControls> createState() => _BetterPlayerTvControlsState();
}

class _BetterPlayerTvControlsState extends State<BetterPlayerTvControls> {
  late final FocusNode _rootFocus;
  late final FocusNode _playFocus;
  Timer? _hideTimer;
  VideoPlayerValue _value = VideoPlayerValue.uninitialized();
  _TvMenuData? _menu;
  final List<_TvMenuData> _menuHistory = <_TvMenuData>[];
  ValueNotifier<VideoPlayerValue>? _attachedVideoController;
  FocusNode? _menuReturnFocus;
  FocusNode? _overlayReturnFocus;
  bool _visible = true;
  bool _timelineEditing = false;

  BetterPlayerControlsConfiguration get _configuration => widget.controller.betterPlayerControlsConfiguration;

  Color get _accent => widget.accentColor ?? _configuration.progressBarPlayedColor;

  @override
  void initState() {
    super.initState();
    _rootFocus = FocusNode(debugLabel: 'BetterPlayer TV controls root');
    _playFocus = FocusNode(debugLabel: 'BetterPlayer TV play pause');
    widget.controlsController?._state = this;
    _visible = _configuration.showControlsOnInitialize;
    widget.controller.addEventsListener(_onPlayerEvent);
    _attachVideoListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _setVisibility(_visible);
      if (_visible) _playFocus.requestFocus();
      _restartHideTimer();
    });
  }

  @override
  void didUpdateWidget(BetterPlayerTvControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controlsController, widget.controlsController)) {
      if (identical(oldWidget.controlsController?._state, this)) {
        oldWidget.controlsController?._state = null;
      }
      widget.controlsController?._state = this;
    }
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeEventsListener(_onPlayerEvent);
      _attachedVideoController?.removeListener(_onVideoValue);
      _attachedVideoController = null;
      widget.controller.addEventsListener(_onPlayerEvent);
      _attachVideoListener();
    }
  }

  void _attachVideoListener() {
    final controller = widget.controller.videoPlayerController;
    if (identical(_attachedVideoController, controller)) return;
    _attachedVideoController?.removeListener(_onVideoValue);
    _attachedVideoController = controller;
    controller?.addListener(_onVideoValue);
    _onVideoValue();
  }

  void _onPlayerEvent(BetterPlayerEvent event) {
    _attachVideoListener();
    if (mounted) _onVideoValue();
  }

  void _onVideoValue() {
    final value = _attachedVideoController?.value;
    if (value != null && mounted) setState(() => _value = value);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeEventsListener(_onPlayerEvent);
    _attachedVideoController?.removeListener(_onVideoValue);
    _rootFocus.dispose();
    _playFocus.dispose();
    if (identical(widget.controlsController?._state, this)) {
      widget.controlsController?._state = null;
    }
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_isBack(key)) {
      if (!_handleExternalBack()) {
        Navigator.of(context).maybePop();
      }
      return KeyEventResult.handled;
    }

    if (key == LogicalKeyboardKey.mediaPlayPause) {
      _setVisibility(true);
      _togglePlayback();
      _requestPlayFocus();
      return KeyEventResult.handled;
    }

    if (!_visible && _isActivate(key)) {
      _setVisibility(true);
      _togglePlayback();
      _requestPlayFocus();
      return KeyEventResult.handled;
    }
    if (!_visible && _isDirectional(key)) {
      _setVisibility(true);
      _requestPlayFocus();
      return KeyEventResult.handled;
    }
    if (_visible) _restartHideTimer();
    return KeyEventResult.ignored;
  }

  bool _isBack(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack || key == LogicalKeyboardKey.browserBack;

  bool _isActivate(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.select ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter ||
      key == LogicalKeyboardKey.gameButtonA ||
      key == LogicalKeyboardKey.mediaPlayPause;

  bool _isDirectional(LogicalKeyboardKey key) =>
      key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.arrowLeft ||
      key == LogicalKeyboardKey.arrowRight;

  bool _handleExternalBack() {
    if (_menu != null) {
      _handleMenuBack();
      return true;
    }
    if (_visible) {
      _setVisibility(false);
      return true;
    }
    return false;
  }

  void _showFromController({required bool restorePreviousFocus}) {
    _setVisibility(true);
    final target = restorePreviousFocus ? _overlayReturnFocus : null;
    _overlayReturnFocus = null;
    _requestControlFocus(target);
  }

  void _hideFromController({required bool preserveFocus}) {
    if (preserveFocus && _visible && _overlayReturnFocus == null) {
      final currentFocus = FocusManager.instance.primaryFocus;
      if (currentFocus != null && currentFocus != _rootFocus && currentFocus.context != null) {
        _overlayReturnFocus = currentFocus;
      }
    }
    _setVisibility(false);
  }

  void _requestPlayFocus() {
    _requestControlFocus(_playFocus);
  }

  void _requestControlFocus(FocusNode? preferred) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = preferred != null && preferred.context != null && preferred.canRequestFocus
          ? preferred
          : _playFocus;
      target.requestFocus();
    });
  }

  void _setVisibility(bool visible) {
    if (_visible != visible && mounted) setState(() => _visible = visible);
    widget.onControlsVisibilityChanged(visible);
    widget.controller.toggleControlsVisibility(visible);
    if (!visible) {
      _hideTimer?.cancel();
      _rootFocus.requestFocus();
    } else {
      _restartHideTimer();
    }
  }

  void _restartHideTimer() {
    _hideTimer?.cancel();
    if (!_visible || _menu != null || _timelineEditing) return;
    final configured = _configuration.controlsHideTime;
    final duration = configured < const Duration(seconds: 5) ? const Duration(seconds: 5) : configured;
    _hideTimer = Timer(duration, () {
      if (mounted && _menu == null && !_timelineEditing) {
        _setVisibility(false);
      }
    });
  }

  Future<void> _togglePlayback() async {
    if (_value.isPlaying) {
      await widget.controller.pause();
    } else {
      await widget.controller.play();
    }
    _restartHideTimer();
  }

  Future<void> _seekBy(Duration delta) async {
    final duration = _value.duration;
    if (duration == null) return;
    final targetMs = (_value.position + delta).inMilliseconds.clamp(0, duration.inMilliseconds);
    await widget.controller.seekTo(Duration(milliseconds: targetMs));
    _restartHideTimer();
  }

  void _openMenu(String title, List<BetterPlayerTvMenuItem> items, {bool nested = false}) {
    _hideTimer?.cancel();
    if (_menu == null) {
      _menuReturnFocus = FocusManager.instance.primaryFocus;
      _menuHistory.clear();
    } else if (nested) {
      _menuHistory.add(_menu!);
    } else {
      _menuHistory.clear();
    }
    setState(() => _menu = _TvMenuData(title, items));
  }

  void _handleMenuBack() {
    if (_menuHistory.isEmpty) {
      _closeMenu();
      return;
    }
    setState(() => _menu = _menuHistory.removeLast());
  }

  void _closeMenu({bool restoreFocus = true}) {
    final returnFocus = _menuReturnFocus;
    _menuReturnFocus = null;
    _menuHistory.clear();
    setState(() => _menu = null);
    if (restoreFocus) _requestControlFocus(returnFocus);
    _restartHideTimer();
  }

  void _openSettings() {
    final items = <BetterPlayerTvMenuItem>[
      if (_configuration.enablePlaybackSpeed)
        BetterPlayerTvMenuItem(
          label: 'Playback speed',
          subtitle: '${_value.speed}×',
          icon: PhosphorIcons.gauge(),
          showsNext: true,
          onSelected: () => _openSpeedMenu(nested: true),
        ),
      if (_configuration.enableSubtitles)
        BetterPlayerTvMenuItem(
          label: 'Subtitles',
          subtitle: _subtitleLabel(),
          icon: PhosphorIcons.closedCaptioning(),
          showsNext: true,
          onSelected: () => _openSubtitlesMenu(nested: true),
        ),
      if (_configuration.enableAudioTracks)
        BetterPlayerTvMenuItem(
          label: 'Audio track',
          subtitle: _audioLabel(),
          icon: PhosphorIcons.waveform(),
          showsNext: true,
          onSelected: () => _openAudioMenu(nested: true),
        ),
      if (_configuration.enableQualities)
        BetterPlayerTvMenuItem(
          label: 'Quality',
          subtitle: _qualityLabel(),
          icon: PhosphorIcons.highDefinition(),
          showsNext: true,
          onSelected: () => _openQualityMenu(nested: true),
        ),
      for (final item in _configuration.overflowMenuCustomItems)
        BetterPlayerTvMenuItem(
          label: item.title,
          icon: item.icon,
          showsNext: true,
          onSelected: () {
            final returnFocus = _menuReturnFocus;
            _closeMenu(restoreFocus: false);
            _overlayReturnFocus = returnFocus;
            item.onClicked();
          },
        ),
    ];
    _openMenu('Player settings', items);
  }

  void _openSpeedMenu({bool nested = false}) {
    final current = _value.speed;
    _openMenu(
      'Playback speed',
      _configuration.playbackSpeeds
          .where((speed) => speed > 0 && speed <= 2)
          .map(
            (speed) => BetterPlayerTvMenuItem(
              label: '${_number(speed)}×',
              icon: speed == 1 ? PhosphorIcons.play() : PhosphorIcons.gauge(),
              selected: speed == current,
              onSelected: () {
                widget.controller.setSpeed(speed);
                _closeMenu();
              },
            ),
          )
          .toList(growable: false),
      nested: nested,
    );
  }

  void _openSubtitlesMenu({bool nested = false}) {
    final selected = widget.controller.betterPlayerSubtitlesSource;
    final sources = <BetterPlayerSubtitlesSource>[
      BetterPlayerSubtitlesSource(type: BetterPlayerSubtitlesSourceType.none),
      ...widget.controller.betterPlayerSubtitlesSourceList.where(
        (source) => source.type != BetterPlayerSubtitlesSourceType.none,
      ),
    ];
    _openMenu(
      'Subtitles',
      sources
          .asMap()
          .entries
          .map((entry) {
            final source = entry.value;
            final off = source.type == BetterPlayerSubtitlesSourceType.none;
            final isSelected = off
                ? selected == null || selected.type == BetterPlayerSubtitlesSourceType.none
                : identical(source, selected) || source == selected;
            return BetterPlayerTvMenuItem(
              label: off
                  ? 'Off'
                  : source.name?.trim().isNotEmpty == true
                  ? source.name!.trim()
                  : 'Subtitle ${entry.key}',
              icon: off ? PhosphorIcons.subtitlesSlash() : PhosphorIcons.closedCaptioning(),
              selected: isSelected,
              onSelected: () async {
                await widget.controller.setupSubtitleSource(source);
                if (mounted) _closeMenu();
              },
            );
          })
          .toList(growable: false),
      nested: nested,
    );
  }

  void _openAudioMenu({bool nested = false}) {
    final tracks = widget.controller.betterPlayerAsmsAudioTracks ?? const [];
    final selected = widget.controller.betterPlayerAsmsAudioTrack;
    _openMenu(
      'Audio track',
      tracks.isEmpty
          ? <BetterPlayerTvMenuItem>[
              BetterPlayerTvMenuItem(
                label: 'Default audio',
                icon: PhosphorIcons.waveform(),
                selected: true,
                onSelected: _closeMenu,
              ),
            ]
          : tracks
                .map(
                  (track) => BetterPlayerTvMenuItem(
                    label: track.label?.trim().isNotEmpty == true
                        ? track.label!.trim()
                        : track.language?.toUpperCase() ?? 'Audio track',
                    subtitle: track.language,
                    icon: PhosphorIcons.waveform(),
                    selected:
                        identical(track, selected) ||
                        (track.id == selected?.id && track.language == selected?.language),
                    onSelected: () {
                      widget.controller.setAudioTrack(track);
                      _closeMenu();
                    },
                  ),
                )
                .toList(growable: false),
      nested: nested,
    );
  }

  void _openQualityMenu({bool nested = false}) {
    final items = <BetterPlayerTvMenuItem>[];
    final tracks = widget.controller.betterPlayerAsmsTracks;
    final selectedTrack = widget.controller.betterPlayerAsmsTrack;
    for (final track in tracks) {
      final automatic = (track.width ?? 0) == 0 && (track.height ?? 0) == 0 && (track.bitrate ?? 0) == 0;
      items.add(
        BetterPlayerTvMenuItem(
          label: automatic
              ? 'Auto'
              : (track.height ?? 0) > 0
              ? '${track.height}p'
              : '${((track.bitrate ?? 0) / 1000).round()} kbps',
          subtitle: automatic || (track.bitrate ?? 0) <= 0
              ? null
              : '${((track.bitrate ?? 0) / 1000000).toStringAsFixed(1)} Mbps',
          icon: automatic ? PhosphorIcons.magicWand() : PhosphorIcons.monitorPlay(),
          selected: track == selectedTrack,
          onSelected: () {
            widget.controller.setTrack(track);
            _closeMenu();
          },
        ),
      );
    }
    if (tracks.isEmpty) {
      widget.controller.betterPlayerDataSource?.resolutions?.forEach((name, url) {
        final selected = name == widget.controller.betterPlayerResolutionName;
        items.add(
          BetterPlayerTvMenuItem(
            label: name,
            subtitle: selected && BetterPlayerUtils.resolutionHeightFromLabel(name) == null
                ? _detectedQualityDetails()
                : null,
            icon: PhosphorIcons.monitorPlay(),
            selected: selected,
            onSelected: () async {
              await widget.controller.setResolution(url, name: name);
              if (mounted) _closeMenu();
            },
          ),
        );
      });
    }
    if (items.isEmpty) {
      items.add(
        BetterPlayerTvMenuItem(
          label: _qualityLabel(),
          icon: widget.controller.betterPlayerResolutionName == null
              ? PhosphorIcons.magicWand()
              : PhosphorIcons.monitorPlay(),
          selected: true,
          onSelected: _closeMenu,
        ),
      );
    }
    _openMenu('Video quality', items, nested: nested);
  }

  String _subtitleLabel() {
    final source = widget.controller.betterPlayerSubtitlesSource;
    if (source == null || source.type == BetterPlayerSubtitlesSourceType.none) {
      return 'Off';
    }
    return source.name?.trim().isNotEmpty == true ? source.name!.trim() : 'On';
  }

  String _audioLabel() {
    final track = widget.controller.betterPlayerAsmsAudioTrack;
    return track?.label?.trim().isNotEmpty == true ? track!.label!.trim() : track?.language?.toUpperCase() ?? 'Default';
  }

  String _qualityLabel() {
    final detectedHeight = BetterPlayerUtils.detectedVideoHeight(widget.controller.videoPlayerController?.value.size);
    final resolutionName = widget.controller.betterPlayerResolutionName;
    if (resolutionName?.trim().isNotEmpty == true) {
      if (detectedHeight != null && BetterPlayerUtils.resolutionHeightFromLabel(resolutionName) == null) {
        return '${detectedHeight}p • ${resolutionName!.trim()}';
      }
      return resolutionName!.trim();
    }
    final track = widget.controller.betterPlayerAsmsTrack;
    if (track == null || (track.height ?? 0) == 0) {
      return detectedHeight == null ? 'Auto' : 'Auto • ${detectedHeight}p';
    }
    return '${track.height}p';
  }

  String? _detectedQualityDetails() {
    final size = widget.controller.videoPlayerController?.value.size;
    final height = BetterPlayerUtils.detectedVideoHeight(size);
    final dimensions = BetterPlayerUtils.detectedVideoDimensions(size);
    if (height == null || dimensions == null) return null;
    return 'Detected ${height}p • $dimensions';
  }

  String _number(double value) => value % 1 == 0 ? value.toStringAsFixed(0) : value.toString();

  Duration get _bufferedEnd {
    if (_value.buffered.isEmpty) return Duration.zero;
    return _value.buffered.last.end;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _rootFocus,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          _setVisibility(true);
          _requestPlayFocus();
        },
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            IgnorePointer(
              ignoring: !_visible,
              child: ExcludeFocus(
                excluding: !_visible,
                child: AnimatedOpacity(
                  opacity: _visible ? 1 : 0,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOut,
                  child: _buildControls(),
                ),
              ),
            ),
            if (_value.isBuffering) Center(child: CircularProgressIndicator(color: _accent)),
            if (_value.hasError) _buildError(),
            if (_menu case final menu?)
              BetterPlayerTvMenu(
                title: menu.title,
                items: menu.items,
                onClose: _closeMenu,
                onBack: _handleMenuBack,
                accentColor: _accent,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0x8a000000), Color(0x08000000), Color(0xe8000000)],
          stops: <double>[0, 0.42, 1],
        ),
      ),
      child: SafeArea(
        minimum: const EdgeInsets.all(30),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              _configuration.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            BetterPlayerTvProgressBar(
              position: _value.position,
              duration: _value.duration ?? Duration.zero,
              buffered: _bufferedEnd,
              seekStep: Duration(milliseconds: _configuration.forwardSkipTimeInMilliseconds),
              playedColor: _accent,
              bufferedColor: _configuration.progressBarBufferedColor,
              backgroundColor: _configuration.progressBarBackgroundColor,
              onSeek: widget.controller.seekTo,
              onEditingChanged: (editing) {
                _timelineEditing = editing;
                if (editing) {
                  _hideTimer?.cancel();
                } else {
                  _restartHideTimer();
                }
              },
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _TvControlButton(
                  label: 'Back',
                  icon: PhosphorIcons.caretLeft(),
                  accentColor: _accent,
                  onPressed: widget.onExit ?? () => Navigator.of(context).maybePop(),
                ),
                _TvControlButton(
                  label: 'Rewind',
                  icon: PhosphorIcons.rewind(),
                  accentColor: _accent,
                  onPressed: () => _seekBy(Duration(milliseconds: -_configuration.backwardSkipTimeInMilliseconds)),
                ),
                _TvControlButton(
                  focusNode: _playFocus,
                  label: _value.isPlaying ? 'Pause' : 'Play',
                  icon: _value.isPlaying
                      ? PhosphorIcons.pause(PhosphorIconsStyle.fill)
                      : PhosphorIcons.play(PhosphorIconsStyle.fill),
                  accentColor: _accent,
                  primary: true,
                  onPressed: _togglePlayback,
                ),
                _TvControlButton(
                  label: 'Forward',
                  icon: PhosphorIcons.fastForward(),
                  accentColor: _accent,
                  onPressed: () => _seekBy(Duration(milliseconds: _configuration.forwardSkipTimeInMilliseconds)),
                ),
                if (_configuration.enableSubtitles)
                  _TvControlButton(
                    label: 'Subtitles',
                    icon: PhosphorIcons.closedCaptioning(),
                    accentColor: _accent,
                    onPressed: _openSubtitlesMenu,
                  ),
                if (_configuration.enableAudioTracks)
                  _TvControlButton(
                    label: 'Audio',
                    icon: PhosphorIcons.waveform(),
                    accentColor: _accent,
                    onPressed: _openAudioMenu,
                  ),
                if (_configuration.enableQualities)
                  _TvControlButton(
                    label: 'Quality',
                    icon: PhosphorIcons.highDefinition(),
                    accentColor: _accent,
                    onPressed: _openQualityMenu,
                  ),
                if (_configuration.enableEpisodeSelection && _configuration.onEpisodeListTap != null)
                  _TvControlButton(
                    label: 'Episodes',
                    icon: PhosphorIcons.listBullets(),
                    accentColor: _accent,
                    onPressed: _configuration.onEpisodeListTap!,
                  ),
                if (_configuration.enableMovieRecommendations && _configuration.onMovieRecommendationsTap != null)
                  _TvControlButton(
                    label: 'More like this',
                    icon: PhosphorIcons.sparkle(),
                    accentColor: _accent,
                    onPressed: _configuration.onMovieRecommendationsTap!,
                  ),
                _TvControlButton(
                  label: 'Settings',
                  icon: PhosphorIcons.gear(),
                  accentColor: _accent,
                  onPressed: _openSettings,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return ColoredBox(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(PhosphorIconsRegular.warningCircle, color: Colors.white, size: 52),
            const SizedBox(height: 14),
            const Text(
              'Playback failed',
              style: TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 18),
            _TvControlButton(
              label: 'Retry',
              icon: PhosphorIcons.arrowClockwise(),
              accentColor: _accent,
              primary: true,
              autofocus: true,
              onPressed: widget.controller.retryDataSource,
            ),
          ],
        ),
      ),
    );
  }
}

class _TvMenuData {
  const _TvMenuData(this.title, this.items);

  final String title;
  final List<BetterPlayerTvMenuItem> items;
}

class _TvControlButton extends StatefulWidget {
  const _TvControlButton({
    required this.label,
    required this.icon,
    required this.accentColor,
    required this.onPressed,
    this.focusNode,
    this.primary = false,
    this.autofocus = false,
  });

  final String label;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final bool primary;
  final bool autofocus;

  @override
  State<_TvControlButton> createState() => _TvControlButtonState();
}

class _TvControlButtonState extends State<_TvControlButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: Semantics(
        button: true,
        label: widget.label,
        child: FocusableActionDetector(
          focusNode: widget.focusNode,
          autofocus: widget.autofocus,
          onFocusChange: (focused) => setState(() => _focused = focused),
          shortcuts: const <ShortcutActivator, Intent>{
            SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
          },
          actions: <Type, Action<Intent>>{
            ActivateIntent: CallbackAction<ActivateIntent>(
              onInvoke: (_) {
                widget.onPressed();
                return null;
              },
            ),
          },
          child: GestureDetector(
            onTap: widget.onPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 130),
              constraints: const BoxConstraints(minWidth: 76),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                color: widget.primary
                    ? widget.accentColor
                    : _focused
                    ? const Color(0xff30312f)
                    : Colors.black45,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: _focused ? Colors.white : Colors.transparent, width: 3),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(widget.icon, color: Colors.white, size: 25),
                  const SizedBox(height: 4),
                  Text(
                    widget.label,
                    maxLines: 1,
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
