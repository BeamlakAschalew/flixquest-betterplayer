import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/core/better_player_utils.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

import 'better_player_mock_controller.dart';
import 'mock_method_channel.dart';
import 'mock_video_player_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mockMethodChannel = MockMethodChannel();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      mockMethodChannel.channel,
      mockMethodChannel.handle,
    );
  });

  test('named resolution selection preserves the active subtitle', () async {
    const masterUrl = 'https://example.com/master.mp4';
    final subtitle = BetterPlayerSubtitlesSource(
      type: BetterPlayerSubtitlesSourceType.memory,
      name: 'English',
      content: 'WEBVTT\n\n00:00.000 --> 00:01.000\nHello',
    );
    final controller = BetterPlayerMockController(const BetterPlayerConfiguration())
      ..videoPlayerController = MockVideoPlayerController();

    await controller.setupDataSource(
      BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        masterUrl,
        subtitles: [subtitle],
        resolutions: const {'480p AAC': masterUrl, '720p AAC': masterUrl, '1080p AAC': masterUrl},
        selectedResolution: '720p AAC',
      ),
    );
    expect(controller.betterPlayerResolutionName, '720p AAC');
    await controller.setupSubtitleSource(subtitle);

    await controller.setResolution(masterUrl, name: '480p AAC');
    expect(controller.betterPlayerResolutionName, '480p AAC');
    expect(controller.betterPlayerSubtitlesSource, same(subtitle));
    expect(controller.betterPlayerSubtitlesSourceList, contains(same(subtitle)));
  });

  test('resolution selection applies its format and request headers', () async {
    const hlsUrl = 'https://example.com/720.m3u8';
    const dashUrl = 'https://example.com/1080.mpd';
    final controller = BetterPlayerMockController(const BetterPlayerConfiguration())
      ..videoPlayerController = MockVideoPlayerController();

    await controller.setupDataSource(
      BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        hlsUrl,
        resolutions: const {'720p': hlsUrl, '1080p': dashUrl},
        selectedResolution: '720p',
        videoFormat: BetterPlayerVideoFormat.hls,
        headers: const {'Referer': 'https://hls.example/'},
        resolutionVideoFormats: const {'720p': BetterPlayerVideoFormat.hls, '1080p': BetterPlayerVideoFormat.dash},
        resolutionHeaders: const {
          '720p': {'Referer': 'https://hls.example/'},
          '1080p': {'Referer': 'https://dash.example/'},
        },
      ),
    );

    await controller.setResolution(dashUrl, name: '1080p');

    expect(controller.betterPlayerDataSource!.url, dashUrl);
    expect(controller.betterPlayerDataSource!.videoFormat, BetterPlayerVideoFormat.dash);
    expect(controller.betterPlayerDataSource!.headers, {'Referer': 'https://dash.example/'});
  });

  test('detects and normalizes runtime video dimensions', () {
    expect(BetterPlayerUtils.detectedVideoHeight(const Size(1920, 1080)), 1080);
    expect(BetterPlayerUtils.detectedVideoHeight(const Size(1920, 1088)), 1080);
    expect(BetterPlayerUtils.detectedVideoHeight(const Size(720, 1280)), 720);
    expect(BetterPlayerUtils.detectedVideoDimensions(const Size(1920, 1080)), '1920×1080');
  });

  test('distinguishes generic provider names from resolution labels', () {
    expect(BetterPlayerUtils.resolutionHeightFromLabel('Vimeo'), isNull);
    expect(BetterPlayerUtils.resolutionHeightFromLabel('480 AAC'), 480);
    expect(BetterPlayerUtils.resolutionHeightFromLabel('1080p Vimeo'), 1080);
  });
}
