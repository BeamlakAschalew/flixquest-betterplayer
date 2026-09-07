import 'dart:io';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/hls/better_player_hls_utils.dart';
import 'package:flutter_test/flutter_test.dart';

import 'mock_method_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('HLS subtitle windows retain their starts and load across seeks', () async {
    final previousOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = previousOverrides);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requested = <String>[];
    server.listen((request) async {
      final path = request.uri.path;
      if (path == '/subtitles.m3u8') {
        request.response.write(
          '#EXTM3U\n#EXT-X-TARGETDURATION:6\n'
          '#EXTINF:6,\n0.vtt\n#EXTINF:6,\n1.vtt\n'
          '#EXTINF:4.5,\n2.vtt\n#EXT-X-ENDLIST\n',
        );
      } else {
        requested.add(path);
        request.response.write('WEBVTT\n\n00:00.000 --> 00:06.000\nHello\n\n');
      }
      await request.response.close();
    });
    final base = 'http://${server.address.address}:${server.port}';
    final channel = MockMethodChannel();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      channel.channel,
      channel.handle,
    );
    final controller = BetterPlayerController(const BetterPlayerConfiguration());
    try {
      final tracks = await BetterPlayerHlsUtils.parseSubtitles(
        '#EXTM3U\n#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID="subs",'
            'NAME="English",URI="subtitles.m3u8"\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=1000000,SUBTITLES="subs"\nvideo.m3u8\n',
        '$base/master.m3u8',
      );
      final segments = tracks.single.segments!;
      expect(segments.map((s) => s.startTime.inMilliseconds), [0, 6000, 12000]);
      expect(segments.map((s) => s.endTime.inMilliseconds), [6000, 12000, 16500]);

      await controller.setupDataSource(BetterPlayerDataSource.network('$base/video.mp4'));
      final source = BetterPlayerSubtitlesSource(
        type: BetterPlayerSubtitlesSourceType.network,
        asmsIsSegmented: true,
        asmsSegments: segments,
        // A five-second lookahead also exercises partially overlapping chunks.
        asmsSegmentsTime: 1000,
      );
      for (final entry in <int, List<String>>{
        0: ['/0.vtt'],
        3: ['/0.vtt', '/1.vtt'],
        6: ['/1.vtt'],
        12: ['/2.vtt'],
      }.entries) {
        await controller.setupSubtitleSource(source);
        requested.clear();
        final video = controller.videoPlayerController!;
        video.value = video.value.copyWith(position: Duration(seconds: entry.key));
        // Notify even when the requested position is already zero.
        video.refresh();
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (controller.subtitlesLines.length < entry.value.length && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        expect(requested, entry.value, reason: 'position ${entry.key}s');
        expect(controller.subtitlesLines.length, entry.value.length);
      }
    } finally {
      controller.dispose();
      await server.close(force: true);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel.channel, null);
    }
  });
}
