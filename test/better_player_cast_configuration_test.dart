import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes receiver metadata and request headers', () {
    const configuration = BetterPlayerCastConfiguration(
      title: 'Example',
      subtitle: 'Episode 2',
      imageUrl: 'https://example.com/poster.jpg',
      contentType: 'application/x-mpegURL',
      requestHeaders: <String, String>{'Referer': 'https://example.com/'},
      customData: <String, Object?>{'mediaId': 42},
    );

    expect(configuration.toMap(), <String, Object?>{
      'enabled': true,
      'enableChromecast': true,
      'title': 'Example',
      'subtitle': 'Episode 2',
      'imageUrl': 'https://example.com/poster.jpg',
      'contentType': 'application/x-mpegURL',
      'isLive': false,
      'requestHeaders': <String, String>{'Referer': 'https://example.com/'},
      'customData': <String, Object?>{'mediaId': 42},
    });
  });
}
