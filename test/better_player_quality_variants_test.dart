import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'better_player_mock_controller.dart';
import 'mock_video_player_controller.dart';

const _master = 'https://example.com/master.m3u8';

const _variants = <BetterPlayerAsmsTrack>[
  BetterPlayerAsmsTrack('', 0, 0, 0, 0, '', ''),
  BetterPlayerAsmsTrack('', 854, 480, 1200000, 0, '', ''),
  BetterPlayerAsmsTrack('', 1280, 720, 2150000, 0, '', ''),
  BetterPlayerAsmsTrack('', 1920, 1080, 4500000, 0, '', ''),
];

void main() {
  late BetterPlayerMockController controller;
  late MockVideoPlayerController video;

  setUpAll(() {
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  setUp(() {
    video = MockVideoPlayerController();
    controller = BetterPlayerMockController(
      const BetterPlayerConfiguration(
        controlsConfiguration: BetterPlayerControlsConfiguration(showQualitiesButton: true),
      ),
    );
    controller.videoPlayerController = video;
  });

  Future<void> setUpSource(
    String url, {
    Map<String, String>? resolutions,
    String? selected,
    List<BetterPlayerAsmsTrack> tracks = _variants,
  }) async {
    await controller.setupDataSource(
      BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        url,
        resolutions: resolutions,
        selectedResolution: selected,
      ),
    );
    // The test HTTP client cannot reach the playlist, so stand in for the
    // tracks it would have listed.
    controller.betterPlayerAsmsTracks.addAll(tracks);
  }

  Future<List<BetterPlayerSelectionTile>> openQualitySheet(WidgetTester tester) async {
    video.value = VideoPlayerValue(duration: const Duration(minutes: 2), isPlaying: true);
    await tester.pumpWidget(MaterialApp(home: BetterPlayer(controller: controller)));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byKey(const Key('better_player_quality_button')));
    // The surface's double-tap recognizer holds the tap for a beat.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    return tester.widgetList<BetterPlayerSelectionTile>(find.byType(BetterPlayerSelectionTile)).toList();
  }

  group('resolutions read from one master playlist', () {
    const resolutions = {'1080p': _master, '720p': _master, '480p': _master, 'Auto': _master};

    test('are recognised as variants of the current stream', () async {
      await setUpSource(_master, resolutions: resolutions, selected: 'Auto');
      expect(controller.hasResolutionVariantsForCurrentStream, isTrue);
      expect(controller.betterPlayerResolutionName, 'Auto');
    });

    test('switch variants in place instead of reloading the playlist', () async {
      await setUpSource(_master, resolutions: resolutions, selected: 'Auto');
      final loads = video.networkDataSources.length;
      final events = <BetterPlayerEventType>[];
      controller.addEventsListener((event) => events.add(event.betterPlayerEventType));

      await controller.setResolution(_master, name: '720p');

      expect(video.networkDataSources.length, loads, reason: 'no reload');
      expect(video.trackParameters.last, (1280, 720, 2150000));
      expect(controller.betterPlayerResolutionName, '720p');
      expect(controller.betterPlayerDataSource?.selectedResolution, '720p');
      expect(events, contains(BetterPlayerEventType.changedResolution));
      expect(events, isNot(contains(BetterPlayerEventType.changedTrack)));

      await controller.setResolution(_master, name: 'Auto');
      expect(video.trackParameters.last, (0, 0, 0));
      expect(controller.betterPlayerResolutionName, 'Auto');
    });

    test('a missing height falls back to the closest variant below it', () async {
      await setUpSource(_master, resolutions: {...resolutions, '900p': _master}, selected: 'Auto');
      await controller.setResolution(_master, name: '900p');
      expect(video.trackParameters.last, (1280, 720, 2150000));
    });

    testWidgets('list each resolution once, with a single Auto entry', (tester) async {
      await setUpSource(_master, resolutions: resolutions, selected: 'Auto');
      final tiles = await openQualitySheet(tester);

      expect(tiles.map((tile) => tile.title), ['1080p', '720p', '480p', 'Auto']);
      expect(tiles.where((tile) => tile.selected).map((tile) => tile.title), ['Auto']);
    });
  });

  testWidgets('a lone Auto source offers its variants and one Auto entry', (tester) async {
    await setUpSource(_master, selected: 'auto');
    final tiles = await openQualitySheet(tester);

    expect(tiles.map((tile) => tile.title), ['Auto', '480p', '720p', '1080p']);
    expect(tiles.where((tile) => tile.selected).map((tile) => tile.title), ['Auto']);
  });

  testWidgets('a listed Adaptive source stands in for the stream Auto row', (tester) async {
    await setUpSource(
      _master,
      resolutions: const {'1080p': 'https://example.com/1080.mp4', 'Adaptive': _master},
      selected: 'Adaptive',
      tracks: _variants.take(3).toList(),
    );
    final tiles = await openQualitySheet(tester);
    final titles = tiles.map((tile) => tile.title).toList();

    expect(titles, ['480p', '720p', '1080p', 'Adaptive']);
    expect(titles, isNot(contains('Auto')));
    expect(tiles.where((tile) => tile.selected).map((tile) => tile.title), ['Adaptive']);
  });
}
