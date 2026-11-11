import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/controls/better_player_material_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'better_player_mock_controller.dart';
import 'mock_video_player_controller.dart';

/// Records every request and handles it (or not) as [handles] says.
class _RecordingInterceptor implements BetterPlayerPlaybackInterceptor {
  _RecordingInterceptor({this.handles = true});

  bool handles;
  final List<String> requests = <String>[];

  @override
  bool onPlayRequested(BetterPlayerController controller) {
    requests.add('play');
    return handles;
  }

  @override
  bool onPauseRequested(BetterPlayerController controller) {
    requests.add('pause');
    return handles;
  }

  @override
  bool onSeekRequested(BetterPlayerController controller, Duration position) {
    requests.add('seek:${position.inSeconds}');
    return handles;
  }

  @override
  bool onSpeedRequested(BetterPlayerController controller, double speed) {
    requests.add('speed:$speed');
    return handles;
  }
}

Future<(BetterPlayerMockController, MockVideoPlayerController)> _controller({
  BetterPlayerConfiguration configuration = const BetterPlayerConfiguration(),
  Duration position = const Duration(seconds: 30),
  bool playing = true,
}) async {
  final video = MockVideoPlayerController();
  final controller = BetterPlayerMockController(configuration)..videoPlayerController = video;
  await controller.setupDataSource(BetterPlayerDataSource.network('https://example.com/video.mp4'));
  video.value = VideoPlayerValue(duration: const Duration(minutes: 2), position: position, isPlaying: playing);
  video.playbackOperations.clear();
  return (controller, video);
}

const _gestures = BetterPlayerConfiguration(
  controlsConfiguration: BetterPlayerControlsConfiguration(
    gestureConfiguration: BetterPlayerGestureConfiguration(
      enableVolumeSwipe: false,
      enableBrightnessSwipe: false,
      enableSeekSwipe: false,
      enableDoubleTapSeek: true,
      fastHoldSpeed: 2,
      slowHoldSpeed: .5,
    ),
  ),
);

Widget _wrap(Widget child) => MaterialApp(home: child);

Finder _tapSurface(String key) => find.descendant(of: find.byKey(Key(key)), matching: find.byType(InkResponse));

void main() {
  setUpAll(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  group('request methods', () {
    test('act directly when no interceptor is set', () async {
      final (controller, video) = await _controller(playing: false);
      await controller.requestPlay();
      await controller.requestPause();
      await controller.requestSeekTo(const Duration(seconds: 12));
      await controller.requestSetSpeed(1.5);
      expect(video.playbackOperations, ['play', 'pause', 'seek:12000']);
      expect(video.speed, 1.5);
    });

    test('defer to an interceptor that handles them', () async {
      final (controller, video) = await _controller(playing: false);
      final interceptor = _RecordingInterceptor();
      controller.playbackInterceptor = interceptor;
      await controller.requestPlay();
      await controller.requestPause();
      await controller.requestSeekTo(const Duration(seconds: 12));
      await controller.requestSetSpeed(1.5);
      expect(interceptor.requests, ['play', 'pause', 'seek:12', 'speed:1.5']);
      expect(video.playbackOperations, isEmpty);
      expect(video.speed, 1);
    });

    test('still act when the interceptor declines', () async {
      final (controller, video) = await _controller(playing: false);
      final interceptor = _RecordingInterceptor(handles: false);
      controller.playbackInterceptor = interceptor;
      await controller.requestPlay();
      await controller.requestSeekTo(const Duration(seconds: 3));
      expect(interceptor.requests, ['play', 'seek:3']);
      expect(video.playbackOperations, ['play', 'seek:3000']);
    });

    test('the plain methods are never intercepted', () async {
      final (controller, video) = await _controller(playing: false);
      final interceptor = _RecordingInterceptor();
      controller.playbackInterceptor = interceptor;
      await controller.play();
      await controller.pause();
      await controller.seekTo(const Duration(seconds: 5));
      await controller.setSpeed(1.04);
      expect(interceptor.requests, isEmpty);
      expect(video.playbackOperations, ['play', 'pause', 'seek:5000']);
      expect(video.speed, 1.04);
    });
  });

  group('material controls', () {
    testWidgets('play/pause and skip buttons go through the interceptor', (tester) async {
      final (controller, video) = await _controller();
      final interceptor = _RecordingInterceptor();
      controller.playbackInterceptor = interceptor;
      await tester.pumpWidget(_wrap(BetterPlayer(controller: controller)));
      await tester.pump(const Duration(milliseconds: 250));

      await tester.tap(_tapSurface('better_player_material_controls_play_pause_button'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(_tapSurface('better_player_material_controls_skip_forward_button'));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(_tapSurface('better_player_material_controls_skip_back_button'));
      await tester.pump(const Duration(milliseconds: 400));

      expect(interceptor.requests, ['pause', 'seek:40', 'seek:20']);
      expect(video.playbackOperations, isEmpty);
      expect(video.value.isPlaying, isTrue);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('double-tap seeks are intercepted', (tester) async {
      final (controller, video) = await _controller(configuration: _gestures);
      final interceptor = _RecordingInterceptor();
      controller.playbackInterceptor = interceptor;
      await tester.pumpWidget(_wrap(BetterPlayer(controller: controller)));
      await tester.pump(const Duration(milliseconds: 250));

      final rect = tester.getRect(find.byType(BetterPlayer));
      final right = Offset(rect.left + rect.width * .85, rect.center.dy);
      await tester.tapAt(right);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(right);
      await tester.pump(const Duration(milliseconds: 250));

      expect(interceptor.requests, ['seek:40']);
      expect(video.lastSeekPosition, isNull);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a refused hold-to-speed changes nothing and shows no pill', (tester) async {
      final (controller, video) = await _controller(configuration: _gestures);
      final interceptor = _RecordingInterceptor();
      controller.playbackInterceptor = interceptor;
      await tester.pumpWidget(_wrap(BetterPlayer(controller: controller)));
      await tester.pump(const Duration(milliseconds: 250));

      final rect = tester.getRect(find.byType(BetterPlayer));
      final gesture = await tester.startGesture(Offset(rect.left + rect.width * .85, rect.center.dy));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('2x'), findsNothing);
      await gesture.up();
      await tester.pump();

      expect(interceptor.requests, ['speed:2.0']);
      expect(video.speed, 1);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the timeline asks for one seek on release', (tester) async {
      tester.view.physicalSize = const Size(1200, 675);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (controller, video) = await _controller();
      final interceptor = _RecordingInterceptor();
      controller.playbackInterceptor = interceptor;
      await tester.pumpWidget(_wrap(BetterPlayer(controller: controller)));
      await tester.pump(const Duration(milliseconds: 250));

      final bar = tester.getRect(find.byType(BetterPlayerMaterialVideoProgressBar));
      final gesture = await tester.startGesture(Offset(bar.left + 4, bar.center.dy));
      await gesture.moveBy(const Offset(30, 0));
      await tester.pump();
      await gesture.moveTo(Offset(bar.left + bar.width / 2, bar.center.dy));
      await tester.pump();
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 100));

      expect(interceptor.requests, hasLength(1));
      expect(interceptor.requests.single, anyOf('seek:59', 'seek:60', 'seek:61'));
      expect(video.playbackOperations, isEmpty);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('the speed menu is intercepted', (tester) async {
      tester.view.physicalSize = const Size(1200, 675);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final (controller, video) = await _controller();
      final interceptor = _RecordingInterceptor();
      controller.playbackInterceptor = interceptor;
      await tester.pumpWidget(_wrap(BetterPlayer(controller: controller)));
      await tester.pump(const Duration(milliseconds: 250));

      tester.widget<BetterPlayerControlButton>(find.byKey(const Key('better_player_speed_button'))).onPressed!();
      await tester.pumpAndSettle();
      final selector = tester.getRect(find.byType(BetterPlayerSpeedSelector));
      final gesture = await tester.startGesture(Offset(selector.left + selector.width * .1, selector.center.dy));
      await gesture.moveTo(Offset(selector.left + selector.width * .9, selector.center.dy));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(interceptor.requests, isNotEmpty);
      expect(interceptor.requests.every((request) => request.startsWith('speed:')), isTrue);
      expect(video.speed, 1);
    });
  });

  group('TV controls', () {
    testWidgets('play/pause and skips are intercepted', (tester) async {
      final (controller, video) = await _controller(
        configuration: BetterPlayerConfiguration(
          controlsConfiguration: BetterPlayerControlsConfiguration(
            playerTheme: BetterPlayerTheme.custom,
            customControlsBuilder: (controller, onVisibilityChanged) =>
                BetterPlayerTvControls(controller: controller, onControlsVisibilityChanged: onVisibilityChanged),
          ),
        ),
      );
      final interceptor = _RecordingInterceptor();
      controller.playbackInterceptor = interceptor;
      await tester.pumpWidget(_wrap(BetterPlayer(controller: controller)));
      await tester.pump(const Duration(milliseconds: 250));

      await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
      await tester.pump(const Duration(milliseconds: 100));
      expect(interceptor.requests, ['pause']);
      expect(video.playbackOperations, isEmpty);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
