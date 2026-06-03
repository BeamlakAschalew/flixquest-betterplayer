///Representation of HLS / DASH audio track
class BetterPlayerAsmsAudioTrack {
  BetterPlayerAsmsAudioTrack({
    this.id,
    this.segmentAlignment,
    this.label,
    this.language,
    this.url,
    this.mimeType,
    this.isDefault = false,
  });

  ///Audio index in DASH xml or Id of track inside HLS playlist
  final int? id;

  ///segmentAlignment
  final bool? segmentAlignment;

  ///Description of the audio
  final String? label;

  ///Language code
  final String? language;

  ///Url of audio track
  final String? url;

  ///mimeType of the audio track
  final String? mimeType;

  ///If this audio track is marked as default in the source manifest.
  final bool isDefault;
}
