import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/controls/better_player_material_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'better_player_mock_controller.dart';
import 'mock_video_player_controller.dart';

const _timeLabel = Key('better_player_time_label');

void main() {
  Future<BetterPlayerMockController> pumpControls(
    WidgetTester tester, {
    int? mode,
    ValueChanged<int>? onChanged,
    bool live = false,
  }) async {
    final videoController = MockVideoPlayerController();
    final controller = BetterPlayerMockController(
      BetterPlayerConfiguration(
        controlsConfiguration: BetterPlayerControlsConfiguration(
          showControlsOnInitialize: true,
          controlsHideTime: const Duration(minutes: 1),
          playerTimeMode: mode,
          onPlayerTimeModeChanged: onChanged,
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
    );
    await pumpControlsWidget(tester, controller);
    return controller;
  }

  // The player's double-tap detector holds a single tap until its window closes.
  Future<void> tapTime(WidgetTester tester) async {
    await tester.tap(find.byKey(_timeLabel));
    await tester.pump(const Duration(milliseconds: 350));
  }

  String timeLabel(WidgetTester tester) => tester.widget<Text>(find.byKey(_timeLabel)).data!;

  testWidgets('elapsed sits before the bar with time left after it', (tester) async {
    await pumpControls(tester, mode: BetterPlayerControlsConfiguration.timeModeRemaining);

    expect(tester.getTopLeft(find.text('10:00')).dx, lessThan(tester.getTopLeft(find.byKey(_timeLabel)).dx));
    expect(timeLabel(tester), '-30:00');
  });

  testWidgets('elapsed sits before the bar with the full length after it', (tester) async {
    await pumpControls(tester, mode: BetterPlayerControlsConfiguration.timeModeTotal);

    expect(find.text('10:00'), findsOneWidget);
    expect(timeLabel(tester), '40:00');
  });

  testWidgets('with no mode set the full length shows and a tap moves to time left', (tester) async {
    await pumpControls(tester);
    expect(timeLabel(tester), '40:00');

    await tapTime(tester);
    expect(timeLabel(tester), '-30:00');
  });

  testWidgets('tapping the time switches it and reports each choice', (tester) async {
    final reported = <int>[];
    await pumpControls(
      tester,
      mode: BetterPlayerControlsConfiguration.timeModeRemaining,
      onChanged: reported.add,
    );

    await tapTime(tester);
    expect(timeLabel(tester), '40:00');

    await tapTime(tester);
    expect(timeLabel(tester), '-30:00');

    expect(reported, [
      BetterPlayerControlsConfiguration.timeModeTotal,
      BetterPlayerControlsConfiguration.timeModeRemaining,
    ]);
  });

  testWidgets('the choice survives the controls being rebuilt for fullscreen', (tester) async {
    final controller = await pumpControls(tester, mode: BetterPlayerControlsConfiguration.timeModeRemaining);
    await tapTime(tester);

    await tester.pumpWidget(const SizedBox());
    await pumpControlsWidget(tester, controller);

    expect(timeLabel(tester), '40:00');
  });

  testWidgets('a tap on the time keeps the controls showing', (tester) async {
    await pumpControls(tester, mode: BetterPlayerControlsConfiguration.timeModeRemaining);

    await tapTime(tester);

    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first).opacity, 1);
  });

  testWidgets('hidden controls ignore a tap where the time was', (tester) async {
    final reported = <int>[];
    final controller = await pumpControls(
      tester,
      mode: BetterPlayerControlsConfiguration.timeModeRemaining,
      onChanged: reported.add,
    );
    final spot = tester.getCenter(find.byKey(_timeLabel));

    controller.setControlsVisibility(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first).opacity, 0);

    await tester.tapAt(spot);
    await tester.pump(const Duration(milliseconds: 350));
    expect(reported, isEmpty);
  });

  testWidgets('a live stream shows no time at all', (tester) async {
    await pumpControls(tester, live: true);

    expect(find.byKey(_timeLabel), findsNothing);
    expect(find.text('10:00'), findsNothing);
  });
}

Future<void> pumpControlsWidget(WidgetTester tester, BetterPlayerMockController controller) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: BetterPlayerControllerProvider(
          controller: controller,
          child: BetterPlayerMaterialControls(
            onControlsVisibilityChanged: (_) {},
            onFullScreenChanged: (_) {},
            controlsConfiguration: controller.betterPlayerControlsConfiguration,
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 250));
}
