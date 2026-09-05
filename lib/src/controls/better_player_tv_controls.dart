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
  final Map<String, FocusNode> _buttonFocusNodes = <String, FocusNode>{};
  final Map<String, GlobalKey> _buttonKeys = <String, GlobalKey>{};
  List<String> _buttonIds = const <String>[];
  List<FocusNode> _buttonOrder = const <FocusNode>[];
  final ScrollController _buttonScrollController = ScrollController();
  final GlobalKey _buttonViewportKey = GlobalKey();
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

  FocusNode _buttonNode(String id) =>
      _buttonFocusNodes.putIfAbsent(id, () => FocusNode(debugLabel: 'BetterPlayer TV $id'));

  GlobalKey _buttonKey(String id) => _buttonKeys.putIfAbsent(id, GlobalKey.new);

  KeyEventResult _handleButtonKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final direction = event.logicalKey == LogicalKeyboardKey.arrowRight
        ? 1
        : event.logicalKey == LogicalKeyboardKey.arrowLeft
        ? -1
        : 0;
    if (direction == 0) return KeyEventResult.ignored;
    _restartHideTimer();
    final focusedNode = FocusManager.instance.primaryFocus;
    final index = _buttonOrder.indexOf(focusedNode ?? node);
    final targetIndex = index + direction;
    if (index < 0 || targetIndex < 0 || targetIndex >= _buttonOrder.length) {
      return KeyEventResult.handled;
    }
    final target = _buttonOrder[targetIndex];
    target.requestFocus();
    _revealButton(_buttonIds[targetIndex]);
    return KeyEventResult.handled;
  }

  void _revealButton(String id) {
    if (!mounted || !_buttonScrollController.hasClients) return;
    final targetBox = _buttonKeys[id]?.currentContext?.findRenderObject() as RenderBox?;
    final viewportBox = _buttonViewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (targetBox == null || viewportBox == null) return;
    final targetCenter = targetBox.localToGlobal(targetBox.size.center(Offset.zero), ancestor: viewportBox).dx;
    final nextOffset = (_buttonScrollController.offset + targetCenter - viewportBox.size.width / 2).clamp(
      _buttonScrollController.position.minScrollExtent,
      _buttonScrollController.position.maxScrollExtent,
    );
    if ((nextOffset - _buttonScrollController.offset).abs() < 1) return;
    unawaited(
      _buttonScrollController.animateTo(
        nextOffset,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeEventsListener(_onPlayerEvent);
    _attachedVideoController?.removeListener(_onVideoValue);
    _rootFocus.dispose();
    _playFocus.dispose();
    _buttonScrollController.dispose();
    for (final node in _buttonFocusNodes.values) {
      if (!identical(node, _playFocus)) node.dispose();
    }
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

    if (!_visible && _isActivate(key) && _configuration.introDbSkipAvailable?.call() == true) {
      final onSkip = _configuration.onIntroDbSkip;
      if (onSkip != null) {
        onSkip();
        return KeyEventResult.handled;
      }
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
          onSelected: () async {
            final returnFocus = _menuReturnFocus;
            _closeMenu(restoreFocus: false);
            _overlayReturnFocus = returnFocus;
            final result = item.onClicked();
            if (result is Future<dynamic>) {
              _hideTimer?.cancel();
              try {
                await result;
              } finally {
                _restoreOverlayFocus();
              }
            }
          },
        ),
    ];
    _openMenu('Player settings', items);
  }

  void _restoreOverlayFocus() {
    if (!mounted || _menu != null) return;
    final target = _overlayReturnFocus;
    _overlayReturnFocus = null;
    _setVisibility(true);
    _requestControlFocus(target);
    if (target != null) {
      final index = _buttonOrder.indexOf(target);
      if (index >= 0) _revealButton(_buttonIds[index]);
    }
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
    widget.controller.betterPlayerDataSource?.resolutions?.forEach((name, url) {
      final selected = name == widget.controller.betterPlayerResolutionName;
      final displayName = widget.controller.betterPlayerDataSource?.resolutionDisplayNames?[name] ?? name;
      final description = widget.controller.betterPlayerDataSource?.resolutionDescriptions?[name];
      final detectedDetails = selected && BetterPlayerUtils.resolutionHeightFromLabel(displayName) == null
          ? _detectedQualityDetails()
          : null;
      final subtitleParts = <String>[
        if (description?.trim().isNotEmpty == true) description!.trim(),
        if (detectedDetails != null) detectedDetails,
      ];
      items.add(
        BetterPlayerTvMenuItem(
          label: displayName,
          subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' • '),
          icon: PhosphorIcons.monitorPlay(),
          selected: selected,
          onSelected: () async {
            await widget.controller.setResolution(url, name: name);
            if (mounted) _closeMenu();
          },
        ),
      );
    });
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

  void _openCropMenu({bool nested = false}) {
    final current = widget.controller.getFit();
    _openMenu('Crop & fit', <BetterPlayerTvMenuItem>[
      BetterPlayerTvMenuItem(
        label: 'Fit',
        subtitle: 'Show the entire video',
        icon: PhosphorIcons.arrowsIn(),
        selected: current == BoxFit.contain,
        onSelected: () => _selectCropMode(BoxFit.contain),
      ),
      BetterPlayerTvMenuItem(
        label: 'Crop to fill',
        subtitle: 'Fill the screen and trim overflowing edges',
        icon: PhosphorIcons.crop(),
        selected: current == BoxFit.cover,
        onSelected: () => _selectCropMode(BoxFit.cover),
      ),
      BetterPlayerTvMenuItem(
        label: 'Stretch',
        subtitle: 'Fill the screen without cropping',
        icon: PhosphorIcons.arrowsOut(),
        selected: current == BoxFit.fill,
        onSelected: () => _selectCropMode(BoxFit.fill),
      ),
    ], nested: nested);
  }

  void _selectCropMode(BoxFit fit) {
    widget.controller.setOverriddenFit(fit);
    _closeMenu();
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
      final displayName =
          widget.controller.betterPlayerDataSource?.resolutionDisplayNames?[resolutionName] ?? resolutionName!;
      if (detectedHeight != null && BetterPlayerUtils.resolutionHeightFromLabel(displayName) == null) {
        return '${displayName.trim()} • ${detectedHeight}p';
      }
      return displayName.trim();
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
            _buildControls(),
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
    final buttonIds = <String>[
      'back',
      'rewind',
      'play',
      'forward',
      if (_configuration.enableSubtitles) 'subtitles',
      if (_configuration.enableAudioTracks) 'audio',
      if (_configuration.enableQualities) 'quality',
      if (_configuration.enableCrop) 'crop',
      if (_configuration.enableEpisodeSelection && _configuration.onEpisodeListTap != null) 'episodes',
      if (_configuration.enableMovieRecommendations && _configuration.onMovieRecommendationsTap != null)
        'recommendations',
      'settings',
    ];
    _buttonIds = buttonIds;
    _buttonOrder = [for (final id in buttonIds) id == 'play' ? _playFocus : _buttonNode(id)];
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        _hideWithControls(
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0x8a000000), Color(0x08000000), Color(0xe8000000)],
                stops: <double>[0, 0.42, 1],
              ),
            ),
          ),
        ),
        SafeArea(
          minimum: const EdgeInsets.all(30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _hideWithControls(
                Text(
                  _configuration.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
                ),
              ),
              const Spacer(),
              // Outside the fade: the skip window closes on its own, so the
              // button has to survive the overlay's auto-hide. The faded
              // timeline below still holds its space, so the button stays put.
              if (_configuration.introDbSkipButtonBuilder case final builder?)
                _buildIntroDbSkipSlot(builder),
              _hideWithControls(
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
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
          LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              key: _buttonViewportKey,
              width: constraints.maxWidth,
              child: SingleChildScrollView(
                controller: _buttonScrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      _TvControlButton(
                        key: _buttonKey('back'),
                        focusNode: _buttonNode('back'),
                        onKeyEvent: _handleButtonKey,
                        label: 'Back',
                        icon: PhosphorIcons.caretLeft(),
                        accentColor: _accent,
                        onPressed: widget.onExit ?? () => Navigator.of(context).maybePop(),
                      ),
                      _TvControlButton(
                        key: _buttonKey('rewind'),
                        focusNode: _buttonNode('rewind'),
                        onKeyEvent: _handleButtonKey,
                        label: 'Rewind',
                        icon: PhosphorIcons.rewind(),
                        accentColor: _accent,
                        onPressed: () =>
                            _seekBy(Duration(milliseconds: -_configuration.backwardSkipTimeInMilliseconds)),
                      ),
                      _TvControlButton(
                        key: _buttonKey('play'),
                        focusNode: _playFocus,
                        onKeyEvent: _handleButtonKey,
                        label: _value.isPlaying ? 'Pause' : 'Play',
                        icon: _value.isPlaying
                            ? PhosphorIcons.pause(PhosphorIconsStyle.fill)
                            : PhosphorIcons.play(PhosphorIconsStyle.fill),
                        accentColor: _accent,
                        primary: true,
                        onPressed: _togglePlayback,
                      ),
                      _TvControlButton(
                        key: _buttonKey('forward'),
                        focusNode: _buttonNode('forward'),
                        onKeyEvent: _handleButtonKey,
                        label: 'Forward',
                        icon: PhosphorIcons.fastForward(),
                        accentColor: _accent,
                        onPressed: () =>
                            _seekBy(Duration(milliseconds: _configuration.forwardSkipTimeInMilliseconds)),
                      ),
                      if (_configuration.enableSubtitles)
                        _TvControlButton(
                          key: _buttonKey('subtitles'),
                          focusNode: _buttonNode('subtitles'),
                          onKeyEvent: _handleButtonKey,
                          label: 'Subtitles',
                          icon: PhosphorIcons.closedCaptioning(),
                          accentColor: _accent,
                          onPressed: _openSubtitlesMenu,
                        ),
                      if (_configuration.enableAudioTracks)
                        _TvControlButton(
                          key: _buttonKey('audio'),
                          focusNode: _buttonNode('audio'),
                          onKeyEvent: _handleButtonKey,
                          label: 'Audio',
                          icon: PhosphorIcons.waveform(),
                          accentColor: _accent,
                          onPressed: _openAudioMenu,
                        ),
                      if (_configuration.enableQualities)
                        _TvControlButton(
                          key: _buttonKey('quality'),
                          focusNode: _buttonNode('quality'),
                          onKeyEvent: _handleButtonKey,
                          label: 'Quality',
                          icon: PhosphorIcons.highDefinition(),
                          accentColor: _accent,
                          onPressed: _openQualityMenu,
                        ),
                      if (_configuration.enableCrop)
                        _TvControlButton(
                          key: _buttonKey('crop'),
                          focusNode: _buttonNode('crop'),
                          onKeyEvent: _handleButtonKey,
                          label: 'Crop & fit',
                          icon: _configuration.cropIcon,
                          accentColor: _accent,
                          onPressed: _openCropMenu,
                        ),
                      if (_configuration.enableEpisodeSelection && _configuration.onEpisodeListTap != null)
                        _TvControlButton(
                          key: _buttonKey('episodes'),
                          focusNode: _buttonNode('episodes'),
                          onKeyEvent: _handleButtonKey,
                          label: 'Episodes',
                          icon: PhosphorIcons.listBullets(),
                          accentColor: _accent,
                          onPressed: _configuration.onEpisodeListTap!,
                        ),
                      if (_configuration.enableMovieRecommendations &&
                          _configuration.onMovieRecommendationsTap != null)
                        _TvControlButton(
                          key: _buttonKey('recommendations'),
                          focusNode: _buttonNode('recommendations'),
                          onKeyEvent: _handleButtonKey,
                          label: 'More like this',
                          icon: PhosphorIcons.sparkle(),
                          accentColor: _accent,
                          onPressed: _configuration.onMovieRecommendationsTap!,
                        ),
                      _TvControlButton(
                        key: _buttonKey('settings'),
                        focusNode: _buttonNode('settings'),
                        onKeyEvent: _handleButtonKey,
                        label: 'Settings',
                        icon: PhosphorIcons.gear(),
                        accentColor: _accent,
                        onPressed: _openSettings,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Fades a piece of the control surface with the overlay, and takes it out of
  /// the focus tree while it is gone.
  Widget _hideWithControls(Widget child) => IgnorePointer(
    ignoring: !_visible,
    child: ExcludeFocus(
      excluding: !_visible,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: child,
      ),
    ),
  );

  /// The app's IntroDB skip action, kept on screen after the overlay hides.
  /// While it is the only thing showing, the select key fires it instead of
  /// waking the controls, which is what the focus-style ring signals.
  Widget _buildIntroDbSkipSlot(Widget Function(BuildContext context) builder) {
    if (_configuration.introDbSkipAvailable?.call() == false) {
      return const SizedBox.shrink();
    }
    final armed = !_visible && _configuration.onIntroDbSkip != null;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: armed ? Colors.white : Colors.transparent, width: 3),
          ),
          child: builder(context),
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
    this.onKeyEvent,
    this.primary = false,
    this.autofocus = false,
    super.key,
  });

  final String label;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final KeyEventResult Function(FocusNode node, KeyEvent event)? onKeyEvent;
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
        child: Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onKeyEvent: widget.onKeyEvent,
          child: FocusableActionDetector(
            focusNode: widget.focusNode,
            autofocus: widget.autofocus,
            onFocusChange: (focused) {
              setState(() => _focused = focused);
              if (focused) {
                Scrollable.ensureVisible(
                  context,
                  alignment: 0.5,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                );
              }
            },
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
      ),
    );
  }
}
