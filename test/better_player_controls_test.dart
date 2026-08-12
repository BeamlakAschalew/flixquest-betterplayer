import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/controls/better_player_material_controls.dart';
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

  testWidgets('async selection tiles show progress until work completes', (WidgetTester tester) async {
    final completion = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: BetterPlayerSelectionTile(
            icon: Icons.closed_caption,
            title: 'English',
            onTap: () => completion.future,
          ),
        ),
      ),
    );

    await tester.tap(find.text('English'));
    await tester.pump();
    expect(find.byKey(const Key('better_player_selection_progress')), findsOneWidget);

    completion.complete();
    await tester.pump();
    expect(find.byKey(const Key('better_player_selection_progress')), findsNothing);
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
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
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
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets('initial loading exposes a functional play button', (WidgetTester tester) async {
    final videoController = MockVideoPlayerController();
    mockController.videoPlayerController = videoController;
    await mockController.setupDataSource(BetterPlayerDataSource.network('https://example.com/video.mp4'));
    videoController.value = VideoPlayerValue(duration: null);

    await tester.pumpWidget(_wrapWidget(BetterPlayer(controller: mockController)));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final playTapSurface = find.descendant(
      of: find.byKey(const Key('better_player_material_controls_play_pause_button')),
      matching: find.byType(InkResponse),
    );
    expect(playTapSurface.hitTestable(), findsOneWidget);

    await tester.tap(playTapSurface);
    await tester.pump(const Duration(milliseconds: 400));
    expect(videoController.value.isPlaying, isTrue);
  });

  testWidgets('fullscreen scrim fills unsafe area while controls remain safe', (WidgetTester tester) async {
    final videoController = MockVideoPlayerController();
    mockController.videoPlayerController = videoController;
    await mockController.setupDataSource(BetterPlayerDataSource.network('https://example.com/video.mp4'));
    videoController.value = VideoPlayerValue(duration: const Duration(minutes: 2));
    mockController.enterFullScreen();

    await tester.pumpWidget(
      _wrapWidget(
        BetterPlayerControllerProvider(
          controller: mockController,
          child: BetterPlayerMaterialControls(
            onControlsVisibilityChanged: (_) {},
            onFullScreenChanged: (_) {},
            controlsConfiguration: mockController.betterPlayerControlsConfiguration,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    final scrim = find.byWidgetPredicate(
      (widget) =>
          widget is DecoratedBox &&
          widget.decoration is BoxDecoration &&
          (widget.decoration as BoxDecoration).gradient is LinearGradient,
    );
    expect(scrim, findsOneWidget);
    expect(find.ancestor(of: scrim, matching: find.byType(SafeArea)), findsNothing);

    final playButton = find.byKey(const Key('better_player_material_controls_play_pause_button'));
    expect(playButton, findsOneWidget);
    expect(find.ancestor(of: playButton, matching: find.byType(SafeArea)), findsOneWidget);
  });

  testWidgets('promoted controls keep their requested order and crop without interrupting playback', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var subtitlesTapped = false;
    var downloadTapped = false;
    final videoController = MockVideoPlayerController();
    mockController = BetterPlayerMockController(
      BetterPlayerConfiguration(
        controlsConfiguration: BetterPlayerControlsConfiguration(
          enablePip: false,
          showQualitiesButton: true,
          showSubtitlesButton: true,
          onSubtitlesTap: () => subtitlesTapped = true,
          enableDownloadButton: true,
          onDownloadTap: () => downloadTapped = true,
          enableCrop: true,
          enableEpisodeSelection: true,
          onEpisodeListTap: () {},
        ),
      ),
    );
    mockController.videoPlayerController = videoController;
    await mockController.setupDataSource(BetterPlayerDataSource.network('https://example.com/video.mp4'));
    videoController.value = VideoPlayerValue(duration: const Duration(minutes: 2), isPlaying: true);

    await tester.pumpWidget(_wrapWidget(BetterPlayer(controller: mockController)));
    await tester.pump(const Duration(milliseconds: 250));

    const orderedKeys = <Key>[
      Key('better_player_quality_button'),
      Key('better_player_subtitles_button'),
      Key('better_player_download_button'),
      Key('better_player_crop_button'),
      Key('better_player_episode_button'),
      Key('better_player_fullscreen_button'),
    ];
    final horizontalPositions = orderedKeys.map((key) => tester.getCenter(find.byKey(key)).dx).toList();
    expect(horizontalPositions, orderedEquals(horizontalPositions.toList()..sort()));

    tester.widget<BetterPlayerControlButton>(find.byKey(const Key('better_player_subtitles_button'))).onPressed!();
    await tester.pump();
    expect(subtitlesTapped, isTrue);

    tester.widget<BetterPlayerControlButton>(find.byKey(const Key('better_player_download_button'))).onPressed!();
    await tester.pump();
    expect(downloadTapped, isTrue);

    tester.widget<BetterPlayerControlButton>(find.byKey(const Key('better_player_crop_button'))).onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Crop & fit'), findsOneWidget);
    await tester.tap(find.text('Crop to fill'));
    await tester.pumpAndSettle();
    expect(mockController.getFit(), BoxFit.cover);
    expect(videoController.value.isPlaying, isTrue);
  });
}

///Wrap widget with material app to handle all features like navigation and
///localization properly.
Widget _wrapWidget(Widget widget) => MaterialApp(home: widget);
