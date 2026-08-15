import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'better_player_mock_controller.dart';
import 'mock_video_player_controller.dart';

void main() {
  testWidgets('remote navigation keeps every TV control visible', (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final videoController = MockVideoPlayerController();
    final controller = BetterPlayerMockController(
      BetterPlayerConfiguration(
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControlsOnInitialize: true,
          controlsHideTime: const Duration(minutes: 1),
          enableSubtitles: true,
          enableAudioTracks: true,
          enableQualities: true,
          enableCrop: true,
          enableEpisodeSelection: true,
          onEpisodeListTap: () {},
          enableMovieRecommendations: true,
          onMovieRecommendationsTap: () {},
        ),
      ),
    );
    controller.videoPlayerController = videoController;
    final controlsController = BetterPlayerTvControlsController();
    await controller.setupDataSource(BetterPlayerDataSource.network('https://example.com/video.mp4'));
    videoController.value = VideoPlayerValue(duration: const Duration(minutes: 2), isPlaying: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BetterPlayerTvControls(
            controller: controller,
            controlsController: controlsController,
            onControlsVisibilityChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    controlsController.show();
    await tester.pump();
    for (var index = 0; index < 3; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(FocusManager.instance.primaryFocus, isNotNull);
    }
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'BetterPlayer TV audio');
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));

    for (var index = 0; index < 5; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(FocusManager.instance.primaryFocus, isNotNull);
    }

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'BetterPlayer TV settings');
    expect(scrollable.position.pixels, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'BetterPlayer TV settings');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Player settings'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Player settings'), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'BetterPlayer TV settings');
    expect(find.byType(BetterPlayerTvControls), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live TV controls reach settings and restore focus after channels', (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var channelsOpened = false;
    Future<void> openChannels() async {
      channelsOpened = true;
    }

    final videoController = MockVideoPlayerController();
    final controller = BetterPlayerMockController(
      BetterPlayerConfiguration(
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControlsOnInitialize: true,
          controlsHideTime: const Duration(minutes: 1),
          enableSubtitles: true,
          enableAudioTracks: true,
          enableQualities: true,
          enableCrop: true,
          overflowMenuCustomItems: <BetterPlayerOverflowMenuItem>[
            BetterPlayerOverflowMenuItem(Icons.live_tv, 'Channels', openChannels),
          ],
        ),
      ),
    );
    controller.videoPlayerController = videoController;
    final controlsController = BetterPlayerTvControlsController();
    await controller.setupDataSource(BetterPlayerDataSource.network('https://example.com/live.mp4'));
    videoController.value = VideoPlayerValue(duration: const Duration(hours: 1), isPlaying: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BetterPlayerTvControls(
            controller: controller,
            controlsController: controlsController,
            onControlsVisibilityChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    controlsController.show();
    await tester.pump();

    for (var index = 0; index < 6; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(FocusManager.instance.primaryFocus, isNotNull);
    }
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'BetterPlayer TV settings');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Player settings'), findsOneWidget);
    expect(find.text('Channels'), findsOneWidget);

    expect(controlsController.handleBack(), isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Player settings'), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'BetterPlayer TV settings');

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Player settings'), findsOneWidget);

    for (var index = 0; index < 4; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(channelsOpened, isTrue);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'BetterPlayer TV settings');
    expect(tester.takeException(), isNull);
  });
}
