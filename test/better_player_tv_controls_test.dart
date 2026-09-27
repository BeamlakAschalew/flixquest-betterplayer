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
    // Playback first, then what the title offers, then the settings.
    const order = <String>[
      'rewind',
      'forward',
      'episodes',
      'recommendations',
      'subtitles',
      'audio',
      'quality',
      'crop',
      'settings',
    ];
    for (final id in order) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'BetterPlayer TV $id');
      // Every control stays on screen; nothing scrolls out of reach.
      final rect = FocusManager.instance.primaryFocus!.rect;
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(960));
    }
    // Only the focused control names itself.
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Audio'), findsNothing);
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

    for (var index = 0; index < 7; index++) {
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

  Future<(BetterPlayerController, MockVideoPlayerController)> pumpControls(
    WidgetTester tester, {
    bool live = false,
  }) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final videoController = MockVideoPlayerController();
    final controller = BetterPlayerMockController(
      const BetterPlayerConfiguration(
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControlsOnInitialize: false,
          controlsHideTime: Duration(seconds: 4),
        ),
      ),
    );
    controller.videoPlayerController = videoController;
    await controller.setupDataSource(
      BetterPlayerDataSource.network('https://example.com/video.m3u8', liveStream: live),
    );
    videoController.value = VideoPlayerValue(
      duration: const Duration(minutes: 40),
      position: const Duration(minutes: 10),
      isPlaying: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BetterPlayerTvControls(controller: controller, onControlsVisibilityChanged: (_) {}),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    return (controller as BetterPlayerController, videoController);
  }

  testWidgets('Right on a bare picture scrubs, and seeks once the remote rests', (tester) async {
    final (_, video) = await pumpControls(tester);
    video.playbackOperations.clear();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'BetterPlayer TV timeline');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    // The landing time shows while scrubbing; nothing has seeked yet.
    expect(find.text('10:20'), findsOneWidget);
    expect(video.playbackOperations.where((op) => op.startsWith('seek')), isEmpty);

    await tester.pump(const Duration(seconds: 1));
    expect(video.lastSeekPosition, const Duration(minutes: 10, seconds: 20));
    // Time left is counted down.
    expect(find.text('-29:40'), findsOneWidget);
  });

  testWidgets('Back while scrubbing cancels without seeking', (tester) async {
    final (_, video) = await pumpControls(tester);
    video.playbackOperations.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(seconds: 2));
    expect(video.playbackOperations.where((op) => op.startsWith('seek')), isEmpty);
  });

  testWidgets('Up on a bare picture brings the controls back on Play', (tester) async {
    await pumpControls(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'BetterPlayer TV play pause');
    expect(find.text('Pause'), findsOneWidget);
  });

  testWidgets('a live stream has no timeline or seeking', (tester) async {
    await pumpControls(tester, live: true);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump();
    expect(find.byType(BetterPlayerTvProgressBar), findsNothing);
    expect(find.text('LIVE'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'BetterPlayer TV play pause');
  });
}
