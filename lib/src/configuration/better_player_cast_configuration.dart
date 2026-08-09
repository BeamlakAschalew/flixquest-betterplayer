/// Metadata and behavior used when a network data source is played remotely.
///
/// The receiver downloads the media directly. [requestHeaders] are forwarded
/// through Cast custom data for custom receivers that deliberately support
/// header-aware manifest and segment requests. Do not place credentials in
/// this map unless the receiver is trusted to receive them.
class BetterPlayerCastConfiguration {
  const BetterPlayerCastConfiguration({
    this.enabled = true,
    this.enableChromecast = true,
    this.title,
    this.subtitle,
    this.imageUrl,
    this.contentType,
    this.isLive = false,
    this.requestHeaders = const <String, String>{},
    this.customData = const <String, Object?>{},
  });

  final bool enabled;
  final bool enableChromecast;
  final String? title;
  final String? subtitle;
  final String? imageUrl;
  final String? contentType;
  final bool isLive;
  final Map<String, String> requestHeaders;
  final Map<String, Object?> customData;

  Map<String, Object?> toMap() => <String, Object?>{
    'enabled': enabled,
    'enableChromecast': enableChromecast,
    'title': title,
    'subtitle': subtitle,
    'imageUrl': imageUrl,
    'contentType': contentType,
    'isLive': isLive,
    'requestHeaders': requestHeaders,
    'customData': customData,
  };
}
