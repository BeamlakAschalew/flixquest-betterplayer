import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/video_player/method_channel_video_player.dart';
import 'package:better_player_plus/src/video_player/video_player_platform_interface.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses a bounded streaming reserve with fast startup', () {
    const configuration = BetterPlayerBufferingConfiguration();

    expect(configuration.minBufferMs, 45000);
    expect(configuration.maxBufferMs, 120000);
    expect(configuration.bufferForPlaybackMs, 1500);
    expect(configuration.bufferForPlaybackAfterRebufferMs, 5000);
    expect(configuration.backBufferDurationMs, 15000);
    expect(configuration.retainBackBufferFromKeyframe, isFalse);
    expect(configuration.prioritizeTimeOverSizeThresholds, isTrue);
  });

  test('supports a memory-bounded TV back buffer', () {
    const configuration = BetterPlayerBufferingConfiguration(
      backBufferDurationMs: 30000,
      retainBackBufferFromKeyframe: false,
    );

    expect(configuration.backBufferDurationMs, 30000);
    expect(configuration.retainBackBufferFromKeyframe, isFalse);
  });

  test('passes the back buffer profile to the Android create call', () async {
    const channel = MethodChannel('better_player_channel');
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return <String, dynamic>{'textureId': 1};
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );

    await MethodChannelVideoPlayer().create(
      bufferingConfiguration: const BetterPlayerBufferingConfiguration(
        backBufferDurationMs: 30000,
        retainBackBufferFromKeyframe: false,
        prioritizeTimeOverSizeThresholds: true,
      ),
    );

    expect(capturedCall?.method, 'create');
    final arguments = capturedCall?.arguments as Map<Object?, Object?>;
    expect(arguments['backBufferDurationMs'], 30000);
    expect(arguments['retainBackBufferFromKeyframe'], isFalse);
    expect(arguments['prioritizeTimeOverSizeThresholds'], isTrue);
  });

  test('passes live source metadata to native playback', () async {
    const channel = MethodChannel('better_player_channel');
    MethodCall? capturedCall;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      capturedCall = call;
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
    );

    await MethodChannelVideoPlayer().setDataSource(
      7,
      DataSource(
        sourceType: DataSourceType.network,
        uri: 'https://example.test/live.m3u8',
        formatHint: VideoFormat.hls,
        isLive: true,
      ),
    );

    expect(capturedCall?.method, 'setDataSource');
    final arguments = capturedCall?.arguments as Map<Object?, Object?>;
    final dataSource = arguments['dataSource'] as Map<Object?, Object?>;
    expect(dataSource['isLive'], isTrue);
  });
}
