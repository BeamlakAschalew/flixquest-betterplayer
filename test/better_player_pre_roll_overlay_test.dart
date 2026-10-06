import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/core/better_player_with_controls.dart';
import 'package:better_player_plus/src/subtitles/better_player_subtitles_drawer.dart';
import 'package:better_player_plus/src/video_player/video_player_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'better_player_mock_controller.dart';
import 'mock_video_player_controller.dart';

void main() {
  testWidgets('a pre-roll swaps the controls for the app overlay and hides subtitles', (tester) async {
    final videoController = MockVideoPlayerController();
    final controller = BetterPlayerMockController(
      BetterPlayerConfiguration(
        showPlaceholderUntilPlay: false,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          preRollOverlayBuilder: (context, controller) => const Text('Ad overlay'),
        ),
      ),
    );
    controller.videoPlayerController = videoController;
    final reasons = <Object?>[];
    controller.addEventsListener((event) {
      if (event.betterPlayerEventType == BetterPlayerEventType.preRollEnded) {
        reasons.add(event.parameters?[BetterPlayerController.preRollEndReasonParameter]);
      }
    });

    await controller.setupDataSourceWithPreRoll(
      preRollDataSource: BetterPlayerDataSource.network('https://ads.example/ad.mp4'),
      betterPlayerDataSource: BetterPlayerDataSource.network('https://example.com/content.m3u8'),
      contentStartPosition: const Duration(minutes: 12),
    );
    expect(controller.isPreRollActive, isTrue);
    expect(videoController.lastContentStartPosition, const Duration(minutes: 12));

    await tester.pumpWidget(
      MaterialApp(
        home: BetterPlayerControllerProvider(
          controller: controller,
          child: BetterPlayerWithControls(controller: controller),
        ),
      ),
    );
    expect(find.text('Ad overlay'), findsOneWidget);
    expect(find.byType(BetterPlayerSubtitlesDrawer), findsNothing);

    videoController.videoEventStreamController.add(
      VideoEvent(eventType: VideoEventType.preRollEnded, key: null, preRollEndReason: 'skipped'),
    );
    await tester.pump();
    expect(controller.isPreRollActive, isFalse);
    expect(reasons, ['skipped']);
    expect(find.text('Ad overlay'), findsNothing);
    expect(find.byType(BetterPlayerSubtitlesDrawer), findsOneWidget);
  });

  testWidgets('a builder returning null keeps the regular controls during a pre-roll', (tester) async {
    final videoController = MockVideoPlayerController();
    final controller = BetterPlayerMockController(
      BetterPlayerConfiguration(
        showPlaceholderUntilPlay: false,
        controlsConfiguration: BetterPlayerControlsConfiguration(
          preRollOverlayBuilder: (context, controller) => null,
          customControlsBuilder: (controller, onVisibilityChanged) => const Text('Regular controls'),
          playerTheme: BetterPlayerTheme.custom,
        ),
      ),
    );
    controller.videoPlayerController = videoController;
    await controller.setupDataSourceWithPreRoll(
      preRollDataSource: BetterPlayerDataSource.network('https://example.com/intro.mp4'),
      betterPlayerDataSource: BetterPlayerDataSource.network('https://example.com/content.m3u8'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: BetterPlayerControllerProvider(
          controller: controller,
          child: BetterPlayerWithControls(controller: controller),
        ),
      ),
    );
    expect(find.text('Regular controls'), findsOneWidget);
    // Content subtitles still wait for the content.
    expect(find.byType(BetterPlayerSubtitlesDrawer), findsNothing);
  });

  testWidgets('the content is uninitialized between the pre-roll and its own initialized event', (tester) async {
    final videoController = MockVideoPlayerController();
    final controller = BetterPlayerMockController(const BetterPlayerConfiguration());
    controller.videoPlayerController = videoController;
    final events = <BetterPlayerEventType>[];
    controller.addEventsListener((event) => events.add(event.betterPlayerEventType));
    await controller.setupDataSourceWithPreRoll(
      preRollDataSource: BetterPlayerDataSource.network('https://ads.example/ad.mp4'),
      betterPlayerDataSource: BetterPlayerDataSource.network('https://example.com/content.mp4'),
    );
    videoController.value = VideoPlayerValue(
      duration: const Duration(seconds: 30),
      position: const Duration(seconds: 6),
      isPlaying: true,
    );
    await tester.pump();
    events.clear();

    // Skipped at 6 s: the content has not been prepared yet.
    videoController.emit(VideoEvent(eventType: VideoEventType.preRollEnded, key: null, preRollEndReason: 'skipped'));
    await tester.pump();
    expect(videoController.value.initialized, isFalse);
    expect(videoController.value.position, Duration.zero);
    expect(videoController.value.isPlaying, isTrue);
    expect(events, [BetterPlayerEventType.preRollEnded]);

  });

  test('a plain data source is never a pre-roll', () async {
    final videoController = MockVideoPlayerController();
    final controller = BetterPlayerMockController(const BetterPlayerConfiguration());
    controller.videoPlayerController = videoController;
    await controller.setupDataSource(BetterPlayerDataSource.network('https://example.com/content.m3u8'));
    expect(controller.isPreRollActive, isFalse);
    await controller.skipPreRoll();
    expect(controller.isPreRollActive, isFalse);
  });
}
