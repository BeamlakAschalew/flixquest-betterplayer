import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/core/better_player_with_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'better_player_mock_controller.dart';
import 'mock_video_player_controller.dart';

const _controlsKey = Key('controls');
const _tabletLandscape = Size(2000, 1303);
const _phoneLandscape = Size(2400, 1080);
const _phonePortrait = Size(1080, 2400);

void main() {
  /// Lays the player out the way the fullscreen route does and returns the
  /// rectangle the controls were given.
  Future<Rect> controlsRect(
    WidgetTester tester, {
    required Size screen,
    required Size? videoSize,
    bool autoDetectOrientation = true,
    bool autoDetectAspectRatio = false,
    double? fullScreenAspectRatio,
    double? inlineAspectRatio,
    bool fullScreen = true,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final videoController = MockVideoPlayerController();
    final controller = BetterPlayerMockController(
      BetterPlayerConfiguration(
        autoDetectFullscreenDeviceOrientation: autoDetectOrientation,
        autoDetectFullscreenAspectRatio: autoDetectAspectRatio,
        fullScreenAspectRatio: fullScreenAspectRatio,
        aspectRatio: inlineAspectRatio,
        showPlaceholderUntilPlay: false,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          playerTheme: BetterPlayerTheme.custom,
          customControlsBuilder: (controller, onVisibilityChanged) => const SizedBox.expand(key: _controlsKey),
        ),
      ),
    );
    controller.videoPlayerController = videoController;
    await controller.setupDataSource(BetterPlayerDataSource.network('https://example.com/content.m3u8'));
    videoController.value = videoController.value.copyWith(size: videoSize);
    if (fullScreen) {
      controller.enterFullScreen();
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Container(
            alignment: Alignment.center,
            color: Colors.black,
            child: BetterPlayerControllerProvider(
              controller: controller,
              child: BetterPlayerWithControls(controller: controller),
            ),
          ),
        ),
      ),
    );
    return tester.getRect(find.byKey(_controlsKey));
  }

  group('fullscreen controls fill the screen whatever the video shape', () {
    const videoSizes = <String, Size?>{
      'not loaded yet': null,
      '4:3': Size(1440, 1080),
      '16:9': Size(1920, 1080),
      '2.39:1': Size(1920, 804),
      '2.76:1': Size(1920, 696),
    };

    for (final entry in videoSizes.entries) {
      testWidgets('${entry.key} on a tablet', (tester) async {
        final rect = await controlsRect(tester, screen: _tabletLandscape, videoSize: entry.value);
        expect(rect, Offset.zero & _tabletLandscape);
      });

      testWidgets('${entry.key} on a phone', (tester) async {
        final rect = await controlsRect(tester, screen: _phoneLandscape, videoSize: entry.value);
        expect(rect, Offset.zero & _phoneLandscape);
      });
    }

    testWidgets('a vertical video in portrait', (tester) async {
      final rect = await controlsRect(tester, screen: _phonePortrait, videoSize: const Size(1080, 1920));
      expect(rect, Offset.zero & _phonePortrait);
    });

    testWidgets('with no auto detection flags set', (tester) async {
      final rect = await controlsRect(
        tester,
        screen: _tabletLandscape,
        videoSize: const Size(1920, 804),
        autoDetectOrientation: false,
      );
      expect(rect, Offset.zero & _tabletLandscape);
    });
  });

  testWidgets('an explicit fullScreenAspectRatio is honoured', (tester) async {
    final rect = await controlsRect(
      tester,
      screen: _tabletLandscape,
      videoSize: const Size(1440, 1080),
      fullScreenAspectRatio: 2,
    );
    expect(rect.size, const Size(2000, 1000));
  });

  testWidgets('autoDetectFullscreenAspectRatio still sizes the box to the video', (tester) async {
    final rect = await controlsRect(
      tester,
      screen: _tabletLandscape,
      videoSize: const Size(1600, 800),
      autoDetectOrientation: false,
      autoDetectAspectRatio: true,
    );
    expect(rect.size, const Size(2000, 1000));
  });

  testWidgets('the inline player keeps its configured aspect ratio', (tester) async {
    final rect = await controlsRect(
      tester,
      screen: _tabletLandscape,
      videoSize: const Size(1920, 804),
      inlineAspectRatio: 2,
      fullScreen: false,
    );
    expect(rect.size, const Size(2000, 1000));
  });
}
