/// The words the phone controls show, so an app can hand over its own
/// translations. Everything defaults to English.
class BetterPlayerControlsStrings {
  const BetterPlayerControlsStrings({
    this.back = 'Back',
    this.play = 'Play',
    this.pause = 'Pause',
    this.replay = 'Replay',
    this.seekBack = 'Back {seconds} seconds',
    this.seekForward = 'Forward {seconds} seconds',
    this.speed = 'Speed',
    this.playbackSpeed = 'Playback speed',
    this.normalSpeed = 'Normal',
    this.lock = 'Lock',
    this.unlock = 'Unlock',
    this.screenLocked = 'Screen locked',
    this.tapToUnlock = 'Tap to unlock',
    this.episodes = 'Episodes',
    this.moreLikeThis = 'More like this',
    this.nextEpisode = 'Next episode',
    this.audioAndSubtitles = 'Audio & Subtitles',
    this.audio = 'Audio',
    this.subtitles = 'Subtitles',
    this.off = 'Off',
    this.quality = 'Quality',
    this.qualityAutoNote = 'Adjusts to your connection',
    this.qualityResolution = 'Resolution',
    this.more = 'More',
    this.close = 'Close',
    this.download = 'Download',
    this.fullscreen = 'Full screen',
    this.exitFullscreen = 'Exit full screen',
    this.pictureInPicture = 'Picture in picture',
    this.cropAndFit = 'Crop & fit',
    this.fit = 'Fit',
    this.fitDescription = 'Show the entire picture',
    this.cropToFill = 'Crop to fill',
    this.cropToFillDescription = 'Fill the screen, trimming the edges',
    this.stretch = 'Stretch',
    this.stretchDescription = 'Fill the screen without cropping',
    this.live = 'LIVE',
    this.playbackFailed = 'Playback failed',
  });

  final String back;
  final String play;
  final String pause;
  final String replay;

  /// With a `{seconds}` placeholder.
  final String seekBack;

  /// With a `{seconds}` placeholder.
  final String seekForward;
  final String speed;
  final String playbackSpeed;
  final String normalSpeed;
  final String lock;
  final String unlock;
  final String screenLocked;
  final String tapToUnlock;
  final String episodes;
  final String moreLikeThis;
  final String nextEpisode;
  final String audioAndSubtitles;
  final String audio;
  final String subtitles;
  final String off;
  final String quality;

  /// Under Auto: it follows the network, so the resolution comes and goes.
  final String qualityAutoNote;

  /// Heads the stream's own resolutions when provider sources share the sheet.
  final String qualityResolution;
  final String more;
  final String close;
  final String download;
  final String fullscreen;
  final String exitFullscreen;
  final String pictureInPicture;
  final String cropAndFit;
  final String fit;
  final String fitDescription;
  final String cropToFill;
  final String cropToFillDescription;
  final String stretch;
  final String stretchDescription;
  final String live;
  final String playbackFailed;

  String seekBackBy(int seconds) => seekBack.replaceAll('{seconds}', '$seconds');

  String seekForwardBy(int seconds) => seekForward.replaceAll('{seconds}', '$seconds');
}
