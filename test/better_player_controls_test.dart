import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/controls/better_player_ui.dart';
import 'package:better_player_plus/src/core/better_player_with_controls.dart';
import 'package:better_player_plus/src/video_player/video_player_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'better_player_mock_controller.dart';
import 'mock_video_player_controller.dart';

void main() {
  late BetterPlayerMockController mockController;

  setUpAll(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  setUp(() {
    mockController = BetterPlayerMockController(const BetterPlayerConfiguration());
  });

  testWidgets('One of children is BetterPlayerWithControls', (WidgetTester tester) async {
    await tester.pumpWidget(_wrapWidget(BetterPlayer(controller: mockController)));
    expect(find.byWidgetPredicate((widget) => widget is BetterPlayerWithControls), findsOneWidget);
  });

  testWidgets('buffering controls can seek and pause without tapping the overlay', (WidgetTester tester) async {
    final videoController = MockVideoPlayerController();
    mockController.videoPlayerController = videoController;
    await mockController.setupDataSource(BetterPlayerDataSource.network('https://example.com/video.mp4'));
    videoController.value = VideoPlayerValue(
      duration: const Duration(minutes: 2),
      isPlaying: true,
      isBuffering: true,
      buffered: [DurationRange(Duration.zero, Duration(seconds: 1))],
    );

    await tester.pumpWidget(_wrapWidget(BetterPlayer(controller: mockController)));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('better_player_material_controls_skip_back_button')), findsOneWidget);
    expect(find.byKey(const Key('better_player_material_controls_play_pause_button')), findsOneWidget);
    expect(find.byKey(const Key('better_player_material_controls_skip_forward_button')), findsOneWidget);
    expect(mockController.videoPlayerController, same(videoController));
    expect(mockController.videoPlayerController?.value.duration, const Duration(minutes: 2));
    final skipForwardButton = tester.widget<BetterPlayerControlButton>(
      find.byKey(const Key('better_player_material_controls_skip_forward_button')),
    );
    expect(skipForwardButton.onPressed, isNotNull);
    final skipForwardTapSurface = find.descendant(
      of: find.byKey(const Key('better_player_material_controls_skip_forward_button')),
      matching: find.byType(InkResponse),
    );
    expect(skipForwardTapSurface.hitTestable(), findsOneWidget);

    await tester.tap(skipForwardTapSurface);
    await tester.pump(const Duration(milliseconds: 400));
    expect(videoController.lastSeekPosition, const Duration(seconds: 10));

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('better_player_material_controls_play_pause_button')),
        matching: find.byType(InkResponse),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(videoController.value.isPlaying, isFalse);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('initial loading exposes a functional play button', (WidgetTester tester) async {
    final videoController = MockVideoPlayerController();
    mockController.videoPlayerController = videoController;
    await mockController.setupDataSource(BetterPlayerDataSource.network('https://example.com/video.mp4'));
    videoController.value = VideoPlayerValue(duration: null);

    await tester.pumpWidget(_wrapWidget(BetterPlayer(controller: mockController)));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final playTapSurface = find.descendant(
      of: find.byKey(const Key('better_player_material_controls_play_pause_button')),
      matching: find.byType(InkResponse),
    );
    expect(playTapSurface.hitTestable(), findsOneWidget);

    await tester.tap(playTapSurface);
    await tester.pump(const Duration(milliseconds: 400));
    expect(videoController.value.isPlaying, isTrue);
  });
}

///Wrap widget with material app to handle all features like navigation and
///localization properly.
Widget _wrapWidget(Widget widget) => MaterialApp(home: widget);
