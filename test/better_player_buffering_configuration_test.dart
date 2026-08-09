import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/video_player/method_channel_video_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses a mobile-friendly back buffer by default', () {
    const configuration = BetterPlayerBufferingConfiguration();

    expect(configuration.backBufferDurationMs, 120000);
    expect(configuration.retainBackBufferFromKeyframe, isTrue);
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
      ),
    );

    expect(capturedCall?.method, 'create');
    final arguments = capturedCall?.arguments as Map<Object?, Object?>;
    expect(arguments['backBufferDurationMs'], 30000);
    expect(arguments['retainBackBufferFromKeyframe'], isFalse);
  });
}
