import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/configuration/better_player_controller_event.dart';
import 'package:better_player_plus/src/controls/better_player_cupertino_controls.dart';
import 'package:better_player_plus/src/controls/better_player_material_controls.dart';
import 'package:better_player_plus/src/core/better_player_utils.dart';
import 'package:better_player_plus/src/subtitles/better_player_subtitles_drawer.dart';
import 'package:better_player_plus/src/video_player/video_player.dart';
import 'package:flutter/material.dart';

class BetterPlayerWithControls extends StatefulWidget {
  const BetterPlayerWithControls({super.key, this.controller});
  final BetterPlayerController? controller;

  @override
  State<BetterPlayerWithControls> createState() => _BetterPlayerWithControlsState();
}

class _BetterPlayerWithControlsState extends State<BetterPlayerWithControls> {
  BetterPlayerSubtitlesConfiguration get subtitlesConfiguration =>
      widget.controller!.betterPlayerConfiguration.subtitlesConfiguration;

  BetterPlayerControlsConfiguration get controlsConfiguration => widget.controller!.betterPlayerControlsConfiguration;

  final StreamController<bool> playerVisibilityStreamController = StreamController();
  final StreamController<bool> playerOrientationStreamController = StreamController();

  bool _initialized = false;
  bool _isFull = false;

  StreamSubscription? _controllerEventSubscription;

  @override
  void initState() {
    playerVisibilityStreamController.add(true);
    _controllerEventSubscription = widget.controller!.controllerEventStream.listen(_onControllerChanged);
    super.initState();
  }

  @override
  void didUpdateWidget(BetterPlayerWithControls oldWidget) {
    if (oldWidget.controller != widget.controller) {
      _controllerEventSubscription?.cancel();
      _controllerEventSubscription = widget.controller!.controllerEventStream.listen(_onControllerChanged);
    }
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    playerVisibilityStreamController.close();
    _controllerEventSubscription?.cancel();
    super.dispose();
  }

  void _onControllerChanged(BetterPlayerControllerEvent event) {
    setState(() {
      if (!_initialized) {
        _initialized = true;
      }
    });
  }

  void _onFullScreenChanged(BetterPlayerControllerEvent event) {
    setState(() {
      if (!_isFull) {
        _isFull = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final BetterPlayerController betterPlayerController = BetterPlayerController.of(context);

    double? aspectRatio;
    if (betterPlayerController.isFullScreen) {
      if (betterPlayerController.betterPlayerConfiguration.autoDetectFullscreenDeviceOrientation ||
          betterPlayerController.betterPlayerConfiguration.autoDetectFullscreenAspectRatio) {
        aspectRatio = betterPlayerController.videoPlayerController?.value.aspectRatio ?? 1.0;
      } else {
        aspectRatio =
            betterPlayerController.betterPlayerConfiguration.fullScreenAspectRatio ??
            BetterPlayerUtils.calculateAspectRatio(context);
      }
    } else {
      aspectRatio = betterPlayerController.getAspectRatio();
    }

    aspectRatio ??= 16 / 9;
    if (aspectRatio.isNaN || aspectRatio.isInfinite || aspectRatio <= 0) {
      aspectRatio = 16 / 9;
    }
    final innerContainer = Container(
      width: double.infinity,
      color: betterPlayerController.betterPlayerConfiguration.controlsConfiguration.backgroundColor,
      child: AspectRatio(aspectRatio: aspectRatio, child: _buildPlayerWithControls(betterPlayerController, context)),
    );

    if (betterPlayerController.betterPlayerConfiguration.expandToFill) {
      return Center(child: innerContainer);
    } else {
      return innerContainer;
    }
  }

  Container _buildPlayerWithControls(BetterPlayerController betterPlayerController, BuildContext context) {
    final configuration = betterPlayerController.betterPlayerConfiguration;
    var rotation = configuration.rotation;

    if (!(rotation <= 360 && rotation % 90 == 0)) {
      BetterPlayerUtils.log('Invalid rotation provided. Using rotation = 0');
      rotation = 0;
    }
    if (betterPlayerController.betterPlayerDataSource == null) {
      return Container();
    }
    _initialized = true;

    final bool placeholderOnTop = betterPlayerController.betterPlayerConfiguration.placeholderOnTop;
    // ignore: avoid_unnecessary_containers
    return Container(
      child: Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          if (placeholderOnTop) _buildPlaceholder(betterPlayerController),
          Transform.rotate(
            angle: rotation * pi / 180,
            child: _BetterPlayerVideoFitWidget(betterPlayerController, betterPlayerController.getFit()),
          ),
          betterPlayerController.betterPlayerConfiguration.overlay ?? Container(),
          BetterPlayerSubtitlesDrawer(
            betterPlayerController: betterPlayerController,
            betterPlayerSubtitlesConfiguration: subtitlesConfiguration,
            subtitles: betterPlayerController.subtitlesLines,
            playerVisibilityStream: playerVisibilityStreamController.stream,
          ),
          if (!placeholderOnTop) _buildPlaceholder(betterPlayerController),
          _buildControls(context, betterPlayerController),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(BetterPlayerController betterPlayerController) =>
      betterPlayerController.betterPlayerDataSource!.placeholder ??
      betterPlayerController.betterPlayerConfiguration.placeholder ??
      Container();

  Widget _buildControls(BuildContext context, BetterPlayerController betterPlayerController) {
    if (controlsConfiguration.showControls) {
      BetterPlayerTheme? playerTheme = controlsConfiguration.playerTheme;
      if (playerTheme == null) {
        if (Platform.isAndroid) {
          playerTheme = BetterPlayerTheme.material;
        } else {
          playerTheme = BetterPlayerTheme.cupertino;
        }
      }

      if (controlsConfiguration.customControlsBuilder != null && playerTheme == BetterPlayerTheme.custom) {
        return controlsConfiguration.customControlsBuilder!(betterPlayerController, onControlsVisibilityChanged);
      } else if (playerTheme == BetterPlayerTheme.material) {
        return _buildMaterialControl();
      } else if (playerTheme == BetterPlayerTheme.cupertino) {
        return _buildCupertinoControl();
      }
    }

    return const SizedBox();
  }

  Widget _buildMaterialControl() => BetterPlayerMaterialControls(
    onControlsVisibilityChanged: onControlsVisibilityChanged,
    controlsConfiguration: controlsConfiguration,
    onFullScreenChanged: onFullScreenChanged,
  );

  Widget _buildCupertinoControl() => BetterPlayerCupertinoControls(
    onControlsVisibilityChanged: onControlsVisibilityChanged,
    controlsConfiguration: controlsConfiguration,
  );

  void onControlsVisibilityChanged(bool state) {
    playerVisibilityStreamController.add(state);
  }

  void onFullScreenChanged(bool state) {
    playerOrientationStreamController.add(state);
  }
}

///Widget used to set the proper box fit of the video. Default fit is 'fill'.
class _BetterPlayerVideoFitWidget extends StatefulWidget {
  const _BetterPlayerVideoFitWidget(this.betterPlayerController, this.boxFit);

  final BetterPlayerController betterPlayerController;
  final BoxFit boxFit;

  @override
  _BetterPlayerVideoFitWidgetState createState() => _BetterPlayerVideoFitWidgetState();
}

class _BetterPlayerVideoFitWidgetState extends State<_BetterPlayerVideoFitWidget> {
  VideoPlayerController? get controller => widget.betterPlayerController.videoPlayerController;

  bool _initialized = false;

  VoidCallback? _initializedListener;

  bool _started = false;

  StreamSubscription? _controllerEventSubscription;

  @override
  void initState() {
    super.initState();
    if (!widget.betterPlayerController.betterPlayerConfiguration.showPlaceholderUntilPlay) {
      _started = true;
    } else {
      _started = widget.betterPlayerController.hasCurrentDataSourceStarted;
    }

    _initialize();
  }

  @override
  void didUpdateWidget(_BetterPlayerVideoFitWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.betterPlayerController.videoPlayerController != controller) {
      if (_initializedListener != null) {
        oldWidget.betterPlayerController.videoPlayerController!.removeListener(_initializedListener!);
      }
      _initialized = false;
      _initialize();
    }
  }

  void _initialize() {
    if (controller?.value.initialized == false) {
      _initializedListener = () {
        if (!mounted) {
          return;
        }

        if (_initialized != controller!.value.initialized) {
          _initialized = controller!.value.initialized;
          setState(() {});
        }
      };
      controller!.addListener(_initializedListener!);
    } else {
      _initialized = true;
    }

    _controllerEventSubscription = widget.betterPlayerController.controllerEventStream.listen((event) {
      if (event == BetterPlayerControllerEvent.play) {
        if (!_started) {
          setState(() {
            _started = widget.betterPlayerController.hasCurrentDataSourceStarted;
          });
        }
      }
      if (event == BetterPlayerControllerEvent.setupDataSource) {
        setState(() {
          _started = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_initialized && _started) {
      // iOS platform views (UiKitView) don't play well with Clip/Transform/FittedBox.
      // Render the platform view directly to avoid black screen.
      if (Platform.isIOS) {
        return SizedBox.expand(child: VideoPlayer(controller));
      }
      return Center(
        child: ClipRect(
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: FittedBox(
              fit: widget.boxFit,
              child: SizedBox(
                width: max(1, controller!.value.size?.width ?? 1.0),
                height: max(1, controller!.value.size?.height ?? 1.0),
                child: VideoPlayer(controller),
              ),
            ),
          ),
        ),
      );
    } else {
      return const SizedBox();
    }
  }

  @override
  void dispose() {
    if (_initializedListener != null) {
      widget.betterPlayerController.videoPlayerController!.removeListener(_initializedListener!);
    }
    _controllerEventSubscription?.cancel();
    super.dispose();
  }
}
