import 'dart:math';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/controls/better_player_material_controls.dart';
import 'package:better_player_plus/src/controls/better_player_material_progress_bar.dart';
import 'package:better_player_plus/src/controls/better_player_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'better_player_mock_controller.dart';
import 'mock_video_player_controller.dart';

/// The lowest opacity applied to [finder] by the control surface's fades. The
/// IntroDB skip button opts out of them, so it stays at 1 while the rest of the
/// overlay drops to 0.
double _fadeOpacity(WidgetTester tester, Finder finder) {
  final fades = tester
      .widgetList<AnimatedOpacity>(find.ancestor(of: finder, matching: find.byType(AnimatedOpacity)))
      .map((fade) => fade.opacity);
  return fades.isEmpty ? 1 : fades.reduce(min);
}

void main() {
  testWidgets('material controls keep the IntroDB skip button live after the overlay hides', (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var skips = 0;
    final videoController = MockVideoPlayerController();
    final controller = BetterPlayerMockController(
      BetterPlayerConfiguration(
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControlsOnInitialize: true,
          controlsHideTime: const Duration(minutes: 1),
          introDbSkipButtonBuilder: (context) => FilledButton(
            onPressed: () => skips++,
            child: const Text('Skip intro'),
          ),
          introDbSkipAvailable: () => true,
          onIntroDbSkip: () => skips++,
        ),
      ),
    );
    controller.videoPlayerController = videoController;
    await controller.setupDataSource(BetterPlayerDataSource.network('https://example.com/video.mp4'));
    videoController.value = VideoPlayerValue(duration: const Duration(minutes: 2), isPlaying: true);

    await tester.pumpWidget(
      MaterialApp(
        home: BetterPlayerControllerProvider(
          controller: controller,
          child: BetterPlayerMaterialControls(
            onControlsVisibilityChanged: (_) {},
            onFullScreenChanged: (_) {},
            controlsConfiguration: controller.betterPlayerControlsConfiguration,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    final skipButton = find.text('Skip intro');
    final visibleRect = tester.getRect(skipButton);
    expect(skipButton, findsOneWidget);

    controller.setControlsVisibility(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(skipButton, findsOneWidget, reason: 'the skip button outlives the overlay');
    expect(_fadeOpacity(tester, skipButton), 1, reason: 'the skip button is left out of the overlay fade');
    expect(
      _fadeOpacity(tester, find.byType(BetterPlayerMaterialVideoProgressBar)),
      0,
      reason: 'the rest of the bottom bar still fades out',
    );
    expect(tester.getRect(skipButton), visibleRect, reason: 'hiding the overlay must not move the button');

    await tester.tap(skipButton);
    // A double-tap recognizer spans the whole surface, so the tap resolves a
    // beat later, exactly as it does for the rest of the control buttons.
    await tester.pump(const Duration(milliseconds: 400));
    expect(skips, 1, reason: 'the hidden overlay must not swallow the tap');
  });

  testWidgets('TV controls hand the select key to the IntroDB skip button while hidden', (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var skips = 0;
    var available = true;
    final videoController = MockVideoPlayerController();
    final controller = BetterPlayerMockController(
      BetterPlayerConfiguration(
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControlsOnInitialize: true,
          controlsHideTime: const Duration(minutes: 1),
          introDbSkipButtonBuilder: (context) => FilledButton(
            onPressed: () => skips++,
            child: const Text('Skip intro'),
          ),
          introDbSkipAvailable: () => available,
          onIntroDbSkip: () => skips++,
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
    await tester.pump(const Duration(milliseconds: 200));

    final skipButton = find.text('Skip intro');
    expect(skipButton, findsOneWidget);
    final visibleRect = tester.getRect(skipButton);

    controlsController.hide();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(controlsController.controlsVisible, isFalse);
    expect(skipButton, findsOneWidget, reason: 'the skip button outlives the overlay');
    expect(_fadeOpacity(tester, skipButton), 1);
    expect(_fadeOpacity(tester, find.byType(BetterPlayerTvProgressBar)), 0);
    expect(tester.getRect(skipButton), visibleRect, reason: 'hiding the overlay must not move the button');

    videoController.playbackOperations.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(skips, 1, reason: 'select fires the skip while it is the only thing on screen');
    expect(videoController.playbackOperations, isEmpty, reason: 'select must not double as play/pause here');
    expect(controlsController.controlsVisible, isFalse, reason: 'skipping does not wake the overlay');

    // Once the skip window closes, select goes back to waking the controls.
    available = false;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(skips, 1);
    expect(controlsController.controlsVisible, isTrue);
    expect(videoController.playbackOperations, <String>['pause']);
  });

  testWidgets('TV media play/pause key keeps toggling playback while a skip is offered', (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var skips = 0;
    final videoController = MockVideoPlayerController();
    final controller = BetterPlayerMockController(
      BetterPlayerConfiguration(
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControlsOnInitialize: false,
          controlsHideTime: const Duration(minutes: 1),
          introDbSkipButtonBuilder: (context) => FilledButton(
            onPressed: () => skips++,
            child: const Text('Skip intro'),
          ),
          introDbSkipAvailable: () => true,
          onIntroDbSkip: () => skips++,
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
    await tester.pump(const Duration(milliseconds: 200));

    expect(controlsController.controlsVisible, isFalse);
    expect(find.text('Skip intro'), findsOneWidget);

    videoController.playbackOperations.clear();
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pump();

    expect(skips, 0);
    expect(videoController.playbackOperations, <String>['pause']);
  });

  testWidgets('swipe zones still take vertical drags over the skip button area', (tester) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var skips = 0;
    final videoController = MockVideoPlayerController();
    final controller = BetterPlayerMockController(
      BetterPlayerConfiguration(
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControlsOnInitialize: true,
          controlsHideTime: const Duration(minutes: 1),
          introDbSkipButtonBuilder: (context) => FilledButton(
            onPressed: () => skips++,
            child: const Text('Skip intro'),
          ),
          introDbSkipAvailable: () => true,
          onIntroDbSkip: () => skips++,
        ),
      ),
    );
    controller.videoPlayerController = videoController;
    await controller.setupDataSource(BetterPlayerDataSource.network('https://example.com/video.mp4'));
    videoController.value = VideoPlayerValue(duration: const Duration(minutes: 2), isPlaying: true);

    await tester.pumpWidget(
      MaterialApp(
        home: BetterPlayerControllerProvider(
          controller: controller,
          child: BetterPlayerMaterialControls(
            onControlsVisibilityChanged: (_) {},
            onFullScreenChanged: (_) {},
            controlsConfiguration: controller.betterPlayerControlsConfiguration,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    controller.setControlsVisibility(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // The volume zone covers the right fifth of the surface, which is where the
    // skip button sits. Letting taps through must not cost it its swipes.
    final gesture = await tester.startGesture(const Offset(940, 300));
    // The first move gets the drag recognized; the second one is the swipe.
    await gesture.moveBy(const Offset(0, -24));
    await tester.pump();
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();

    expect(find.byType(BetterPlayerGesturePill), findsOneWidget);
    expect(skips, 0);

    await gesture.up();
    // Drain the feedback pill's own hide timer before the tree goes away.
    await tester.pump(const Duration(milliseconds: 900));
  });
}
