import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/controls/better_player_material_controls.dart';
import 'package:better_player_plus/src/controls/better_player_material_progress_bar.dart';
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

  testWidgets('quality menu keeps external resolutions when adaptive tracks exist', (WidgetTester tester) async {
    final videoController = MockVideoPlayerController();
    mockController = BetterPlayerMockController(
      const BetterPlayerConfiguration(
        controlsConfiguration: BetterPlayerControlsConfiguration(showQualitiesButton: true),
      ),
    );
    mockController.videoPlayerController = videoController;
    await mockController.setupDataSource(
      BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        'https://example.com/720.mp4',
        resolutions: const {
          '1080p · ShowBox 2': 'https://example.com/1080.m3u8',
          '720p · ShowBox 1': 'https://example.com/720.m3u8',
          '360p · ShowBox 1': 'https://example.com/360.m3u8',
        },
        selectedResolution: '720p · ShowBox 1',
        resolutionDisplayNames: const {
          '1080p · ShowBox 2': '1080p',
          '720p · ShowBox 1': '720p',
          '360p · ShowBox 1': '360p',
        },
        resolutionDescriptions: const {
          '1080p · ShowBox 2': 'ShowBox 2',
          '720p · ShowBox 1': 'ShowBox 1',
          '360p · ShowBox 1': 'ShowBox 1',
        },
      ),
    );
    mockController.betterPlayerAsmsTracks.add(const BetterPlayerAsmsTrack('', 1280, 720, 1500000, 30, '', ''));
    videoController.value = VideoPlayerValue(duration: const Duration(minutes: 2), isPlaying: true);

    await tester.pumpWidget(_wrapWidget(BetterPlayer(controller: mockController)));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byKey(const Key('better_player_quality_button')));
    // The surface's double-tap recognizer holds the tap for a beat.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('720p'), findsWidgets);
    expect(find.text('360p'), findsOneWidget);
    expect(find.text('ShowBox 2'), findsOneWidget);
    expect(find.text('1080p · ShowBox 2'), findsNothing);
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
    expect(find.byKey(const Key('better_player_loading_indicator')), findsOneWidget);
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
    expect(find.byKey(const Key('better_player_loading_indicator')), findsNothing);
  });

  testWidgets('double taps seek by the configured duration on player edges', (WidgetTester tester) async {
    final videoController = MockVideoPlayerController();
    mockController = BetterPlayerMockController(
      const BetterPlayerConfiguration(
        controlsConfiguration: BetterPlayerControlsConfiguration(
          backwardSkipTimeInMilliseconds: 7000,
          forwardSkipTimeInMilliseconds: 15000,
          gestureConfiguration: BetterPlayerGestureConfiguration(
            enableVolumeSwipe: false,
            enableBrightnessSwipe: false,
            enableSeekSwipe: false,
            enableDoubleTapSeek: true,
          ),
        ),
      ),
    );
    mockController.videoPlayerController = videoController;
    await mockController.setupDataSource(BetterPlayerDataSource.network('https://example.com/video.mp4'));
    videoController.value = VideoPlayerValue(
      duration: const Duration(minutes: 2),
      position: const Duration(seconds: 30),
      isPlaying: true,
    );

    await tester.pumpWidget(_wrapWidget(BetterPlayer(controller: mockController)));
    await tester.pump(const Duration(milliseconds: 250));

    final playerRect = tester.getRect(find.byType(BetterPlayer));
    Future<void> doubleTapAt(Offset position) async {
      await tester.tapAt(position);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(position);
      await tester.pump(const Duration(milliseconds: 250));
    }

    await doubleTapAt(playerRect.center);
    expect(videoController.lastSeekPosition, isNull);

    await doubleTapAt(Offset(playerRect.left + playerRect.width * .85, playerRect.center.dy));
    expect(videoController.lastSeekPosition, const Duration(seconds: 45));
    expect(find.text('+15s'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 250));
    await doubleTapAt(Offset(playerRect.left + playerRect.width * .15, playerRect.center.dy));
    expect(videoController.lastSeekPosition, const Duration(seconds: 38));
    expect(find.text('-7s'), findsOneWidget);

    mockController.setControlsVisibility(false);
    await tester.pump(const Duration(milliseconds: 300));
    final skipForwardSurface = find.descendant(
      of: find.byKey(const Key('better_player_material_controls_skip_forward_button')),
      matching: find.byType(InkResponse),
    );
    expect(skipForwardSurface.hitTestable(), findsNothing);

    await doubleTapAt(Offset(playerRect.left + playerRect.width * .85, playerRect.center.dy));
    expect(videoController.lastSeekPosition, const Duration(seconds: 53));
    expect(skipForwardSurface.hitTestable(), findsNothing);
  });

  testWidgets('initial loading exposes a functional play button', (WidgetTester tester) async {
    final videoController = MockVideoPlayerController();
    mockController.videoPlayerController = videoController;
    await mockController.setupDataSource(BetterPlayerDataSource.network('https://example.com/video.mp4'));
    videoController.value = VideoPlayerValue(duration: null);

    await tester.pumpWidget(_wrapWidget(BetterPlayer(controller: mockController)));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const Key('better_player_loading_indicator')), findsOneWidget);
    final playTapSurface = find.descendant(
      of: find.byKey(const Key('better_player_material_controls_play_pause_button')),
      matching: find.byType(InkResponse),
    );
    expect(playTapSurface.hitTestable(), findsOneWidget);

    await tester.tap(playTapSurface);
    await tester.pump(const Duration(milliseconds: 400));
    expect(videoController.value.isPlaying, isTrue);
  });

  testWidgets('top overlay blocks transport controls', (WidgetTester tester) async {
    var overlayTaps = 0;
    final videoController = MockVideoPlayerController();
    mockController = BetterPlayerMockController(
      BetterPlayerConfiguration(
        overlayOnTop: true,
        overlay: GestureDetector(
          key: const Key('modal_player_overlay'),
          behavior: HitTestBehavior.opaque,
          onTap: () => overlayTaps++,
        ),
        controlsConfiguration: const BetterPlayerControlsConfiguration(showControlsOnInitialize: true),
      ),
    );
    mockController.videoPlayerController = videoController;
    await mockController.setupDataSource(BetterPlayerDataSource.network('https://example.com/video.mp4'));
    videoController.value = VideoPlayerValue(duration: const Duration(minutes: 2), isPlaying: true);

    await tester.pumpWidget(_wrapWidget(BetterPlayer(controller: mockController)));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tapAt(tester.getCenter(find.byType(BetterPlayer)));
    await tester.pump();

    expect(overlayTaps, 1);
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

  testWidgets('the action row keeps its order and crop does not interrupt playback', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 675);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var subtitlesTapped = false;
    var nextTapped = false;
    final videoController = MockVideoPlayerController();
    mockController = BetterPlayerMockController(
      BetterPlayerConfiguration(
        controlsConfiguration: BetterPlayerControlsConfiguration(
          enablePip: false,
          showQualitiesButton: true,
          showSubtitlesButton: true,
          onSubtitlesTap: () => subtitlesTapped = true,
          enableCrop: true,
          enableEpisodeSelection: true,
          onEpisodeListTap: () {},
          onNextEpisodeTap: () => nextTapped = true,
        ),
      ),
    );
    mockController.videoPlayerController = videoController;
    await mockController.setupDataSource(BetterPlayerDataSource.network('https://example.com/video.mp4'));
    videoController.value = VideoPlayerValue(duration: const Duration(minutes: 2), isPlaying: true);

    await tester.pumpWidget(_wrapWidget(BetterPlayer(controller: mockController)));
    await tester.pump(const Duration(milliseconds: 250));

    const orderedKeys = <Key>[
      Key('better_player_speed_button'),
      Key('better_player_lock_button'),
      Key('better_player_episode_button'),
      Key('better_player_subtitles_button'),
      Key('better_player_quality_button'),
      Key('better_player_next_episode_button'),
    ];
    final horizontalPositions = orderedKeys.map((key) => tester.getCenter(find.byKey(key)).dx).toList();
    expect(horizontalPositions, orderedEquals(horizontalPositions.toList()..sort()));
    expect(find.text('Speed (1x)'), findsOneWidget, reason: 'wide players name their actions');

    tester.widget<BetterPlayerControlButton>(find.byKey(const Key('better_player_subtitles_button'))).onPressed!();
    await tester.pump();
    expect(subtitlesTapped, isTrue);

    tester.widget<BetterPlayerControlButton>(find.byKey(const Key('better_player_next_episode_button'))).onPressed!();
    await tester.pump();
    expect(nextTapped, isTrue);

    tester.widget<BetterPlayerControlButton>(find.byKey(const Key('better_player_more_button'))).onPressed!();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crop & fit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Crop to fill'));
    await tester.pumpAndSettle();
    expect(mockController.getFit(), BoxFit.cover);
    expect(videoController.value.isPlaying, isTrue);
  });

  testWidgets('narrow players keep the essentials and move the rest into More', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final videoController = MockVideoPlayerController();
    mockController = BetterPlayerMockController(
      BetterPlayerConfiguration(
        controlsConfiguration: BetterPlayerControlsConfiguration(
          enablePip: false,
          showSubtitlesButton: true,
          onSubtitlesTap: () {},
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

    expect(find.byKey(const Key('better_player_speed_button')), findsNothing);
    expect(find.byKey(const Key('better_player_episode_button')), findsNothing);
    expect(find.byKey(const Key('better_player_subtitles_button')), findsOneWidget);
    expect(find.byKey(const Key('better_player_fullscreen_button')), findsOneWidget);

    tester.widget<BetterPlayerControlButton>(find.byKey(const Key('better_player_more_button'))).onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('Episodes'), findsOneWidget);
    expect(find.text('Playback speed'), findsOneWidget);
  });

  testWidgets('lock hides the controls until it is undone', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 675);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final videoController = MockVideoPlayerController();
    mockController.videoPlayerController = videoController;
    await mockController.setupDataSource(BetterPlayerDataSource.network('https://example.com/video.mp4'));
    videoController.value = VideoPlayerValue(duration: const Duration(minutes: 2), isPlaying: true);

    await tester.pumpWidget(_wrapWidget(BetterPlayer(controller: mockController)));
    await tester.pump(const Duration(milliseconds: 250));

    tester.widget<BetterPlayerControlButton>(find.byKey(const Key('better_player_lock_button'))).onPressed!();
    await tester.pump(const Duration(milliseconds: 300));
    expect(mockController.controlsEnabled, isFalse);
    expect(find.byKey(const Key('better_player_material_controls_play_pause_button')), findsNothing);

    await tester.tapAt(tester.getCenter(find.byType(BetterPlayer)));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Screen locked'), findsOneWidget);

    tester.widget<BetterPlayerControlButton>(find.byKey(const Key('better_player_unlock_button'))).onPressed!();
    await tester.pump(const Duration(milliseconds: 300));
    expect(mockController.controlsEnabled, isTrue);
    expect(find.byKey(const Key('better_player_material_controls_play_pause_button')), findsOneWidget);
  });

  testWidgets('dragging the timeline seeks once, on release', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 675);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final videoController = MockVideoPlayerController();
    mockController.videoPlayerController = videoController;
    await mockController.setupDataSource(BetterPlayerDataSource.network('https://example.com/video.mp4'));
    videoController.value = VideoPlayerValue(duration: const Duration(minutes: 2), isPlaying: true);

    await tester.pumpWidget(_wrapWidget(BetterPlayer(controller: mockController)));
    await tester.pump(const Duration(milliseconds: 250));

    final bar = tester.getRect(find.byType(BetterPlayerMaterialVideoProgressBar));
    final gesture = await tester.startGesture(Offset(bar.left + 4, bar.center.dy));
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveTo(Offset(bar.left + bar.width / 2, bar.center.dy));
    await tester.pump();
    expect(find.text('01:00'), findsOneWidget, reason: 'the bubble names the time under the handle');
    expect(videoController.lastSeekPosition, isNot(const Duration(minutes: 1)));

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(videoController.lastSeekPosition?.inSeconds, closeTo(60, 1));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the speed selector follows a drag and keeps the panel open', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 675);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final videoController = MockVideoPlayerController();
    mockController.videoPlayerController = videoController;
    await mockController.setupDataSource(BetterPlayerDataSource.network('https://example.com/video.mp4'));
    videoController.value = VideoPlayerValue(duration: const Duration(minutes: 2), isPlaying: true);

    await tester.pumpWidget(_wrapWidget(BetterPlayer(controller: mockController)));
    await tester.pump(const Duration(milliseconds: 250));

    tester.widget<BetterPlayerControlButton>(find.byKey(const Key('better_player_speed_button'))).onPressed!();
    await tester.pumpAndSettle();

    final selector = tester.getRect(find.byType(BetterPlayerSpeedSelector));
    final gesture = await tester.startGesture(
      Offset(selector.left + selector.width * .1, selector.center.dy),
    );
    await gesture.moveTo(Offset(selector.left + selector.width * .9, selector.center.dy));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(videoController.speed, 2.0);
    expect(
      find.byType(BetterPlayerSpeedSelector),
      findsOneWidget,
      reason: 'the panel stays open so the range can be tried',
    );
  });
}

///Wrap widget with material app to handle all features like navigation and
///localization properly.
Widget _wrapWidget(Widget widget) => MaterialApp(home: widget);
