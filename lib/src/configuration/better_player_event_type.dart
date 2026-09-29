///Supported event types
enum BetterPlayerEventType {
  initialized,
  preRollEnded,
  play,
  pause,
  seekTo,
  openFullscreen,
  hideFullscreen,
  setVolume,
  progress,
  finished,
  exception,
  controlsVisible,
  controlsHiddenStart,
  controlsHiddenEnd,
  setSpeed,
  changedSubtitles,
  changedTrack,
  changedPlayerVisibility,
  changedResolution,
  pipStart,
  pipStop,
  setupDataSource,
  bufferingStart,
  bufferingUpdate,
  bufferingEnd,
  changedPlaylistItem,

  /// A batch of network bytes the player downloaded. Parameters: `bytes`, the
  /// batch, and `totalBytes`, everything counted so far.
  networkUsage,
}
