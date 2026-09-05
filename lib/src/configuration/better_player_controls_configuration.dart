import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

///UI configuration of Better Player. Allows to change colors/icons/behavior
///of controls. Used in BetterPlayerConfiguration. Configuration applies only
///for player displayed in app, not in notification or PiP mode.
class BetterPlayerControlsConfiguration {
  const BetterPlayerControlsConfiguration({
    this.controlBarColor = Colors.black87,
    this.textColor = Colors.white,
    this.iconsColor = Colors.white,
    this.playIcon = PhosphorIconsRegular.play,
    this.pauseIcon = PhosphorIconsRegular.pause,
    this.muteIcon = PhosphorIconsRegular.speakerHigh,
    this.unMuteIcon = PhosphorIconsRegular.speakerSlash,
    this.fullscreenEnableIcon = PhosphorIconsRegular.cornersOut,
    this.fullscreenDisableIcon = PhosphorIconsRegular.cornersIn,
    this.skipBackIcon = PhosphorIconsRegular.arrowCounterClockwise,
    this.skipForwardIcon = PhosphorIconsRegular.arrowClockwise,
    this.enableFullscreen = true,
    this.enableMute = true,
    this.enableProgressText = true,
    this.enableProgressBar = true,
    this.enableProgressBarDrag = true,
    this.enablePlayPause = true,
    this.enableSkips = true,
    this.enableAudioTracks = true,
    this.progressBarPlayedColor = Colors.white,
    this.progressBarHandleColor = Colors.white,
    this.progressBarBufferedColor = Colors.white70,
    this.progressBarBackgroundColor = Colors.white60,
    this.controlsHideTime = const Duration(milliseconds: 300),
    this.customControlsBuilder,
    this.playerTheme,
    this.showControls = true,
    this.showControlsOnInitialize = true,
    this.controlBarHeight = 48.0,
    this.liveTextColor = Colors.red,
    this.enableOverflowMenu = true,
    this.enablePlaybackSpeed = true,
    this.playbackSpeeds = const [0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2],
    this.enableSubtitles = true,
    this.showSubtitlesButton = false,
    this.onSubtitlesTap,
    this.enableQualities = true,
    this.showQualitiesButton = false,
    this.enableDownloadButton = false,
    this.onDownloadTap,
    this.enableCrop = false,
    this.enablePip = true,
    this.enableCast = false,
    this.enableRetry = true,
    this.overflowMenuCustomItems = const [],
    this.overflowMenuIcon = PhosphorIconsRegular.dotsThreeVertical,
    this.pipMenuIcon = PhosphorIconsRegular.pictureInpicture,
    this.playbackSpeedIcon = PhosphorIconsRegular.gauge,
    this.qualitiesIcon = PhosphorIconsRegular.monitorPlay,
    this.subtitlesIcon = PhosphorIconsRegular.closedCaptioning,
    this.downloadIcon = PhosphorIconsRegular.downloadSimple,
    this.cropIcon = PhosphorIconsRegular.crop,
    this.audioTracksIcon = PhosphorIconsRegular.waveform,
    this.overflowMenuIconsColor = Colors.black,
    this.forwardSkipTimeInMilliseconds = 10000,
    this.backwardSkipTimeInMilliseconds = 10000,
    this.loadingColor = Colors.white,
    this.loadingWidget,
    this.backgroundColor = Colors.black,
    this.overflowModalColor = Colors.white,
    this.overflowModalTextColor = Colors.black,
    this.name = "",
    this.onFullScreenChange,
    this.watchingText,
    this.playerTimeMode,
    this.enableThumbnailPreview = true,
    this.onEpisodeListTap,
    this.enableEpisodeSelection = false,
    this.onMovieRecommendationsTap,
    this.enableMovieRecommendations = false,
    this.enableNextEpisodeButton = true,
    this.introDbSkipButtonBuilder,
    this.introDbSkipAvailable,
    this.onIntroDbSkip,
    this.gestureConfiguration = const BetterPlayerGestureConfiguration(),
  });

  factory BetterPlayerControlsConfiguration.white() => const BetterPlayerControlsConfiguration(
    controlBarColor: Colors.white,
    textColor: Colors.black,
    iconsColor: Colors.black,
    progressBarPlayedColor: Colors.black,
    progressBarHandleColor: Colors.black,
    progressBarBufferedColor: Colors.black54,
    progressBarBackgroundColor: Colors.white70,
  );

  factory BetterPlayerControlsConfiguration.cupertino() => const BetterPlayerControlsConfiguration();

  ///Setup BetterPlayerControlsConfiguration based on Theme options.
  factory BetterPlayerControlsConfiguration.theme(ThemeData theme) => BetterPlayerControlsConfiguration(
    textColor: theme.textTheme.bodyMedium?.color ?? Colors.white,
    iconsColor: theme.textTheme.bodyMedium?.color ?? Colors.white,
  );

  ///Color of the control bars
  final Color controlBarColor;

  ///Color of texts
  final Color textColor;

  ///Color of icons
  final Color iconsColor;

  ///Icon of play
  final IconData playIcon;

  ///Icon of pause
  final IconData pauseIcon;

  ///Icon of mute
  final IconData muteIcon;

  ///Icon of unmute
  final IconData unMuteIcon;

  ///Icon of fullscreen mode enable
  final IconData fullscreenEnableIcon;

  ///Icon of fullscreen mode disable
  final IconData fullscreenDisableIcon;

  ///Cupertino only icon, icon of skip
  final IconData skipBackIcon;

  ///Cupertino only icon, icon of forward
  final IconData skipForwardIcon;

  ///Flag used to enable/disable fullscreen
  final bool enableFullscreen;

  ///Flag used to enable/disable mute
  final bool enableMute;

  ///Flag used to enable/disable progress texts
  final bool enableProgressText;

  ///Flag used to enable/disable progress bar
  final bool enableProgressBar;

  ///Flag used to enable/disable progress bar drag
  final bool enableProgressBarDrag;

  ///Flag used to enable/disable play-pause
  final bool enablePlayPause;

  ///Flag used to enable skip forward and skip back
  final bool enableSkips;

  ///Progress bar played color
  final Color progressBarPlayedColor;

  ///Progress bar circle color
  final Color progressBarHandleColor;

  ///Progress bar buffered video color
  final Color progressBarBufferedColor;

  ///Progress bar background color
  final Color progressBarBackgroundColor;

  ///Time to hide controls
  final Duration controlsHideTime;

  ///Parameter used to build custom controls
  final Widget Function(BetterPlayerController controller, Function(bool) onPlayerVisibilityChanged)?
  customControlsBuilder;

  ///Parameter used to change theme of the player
  final BetterPlayerTheme? playerTheme;

  ///Flag used to show/hide controls
  final bool showControls;

  ///Flag used to show controls on init
  final bool showControlsOnInitialize;

  ///Control bar height
  final double controlBarHeight;

  ///Live text color;
  final Color liveTextColor;

  ///Flag used to show/hide overflow menu which contains playback, subtitles,
  ///qualities options.
  final bool enableOverflowMenu;

  ///Flag used to show/hide playback speed
  final bool enablePlaybackSpeed;

  ///Playback speeds displayed by the speed selector.
  final List<double> playbackSpeeds;

  ///Flag used to show/hide subtitles
  final bool enableSubtitles;

  ///Shows subtitles as a dedicated control instead of an overflow menu item.
  final bool showSubtitlesButton;

  ///Optional callback for the dedicated subtitles control. When omitted, the
  ///built-in subtitle selector is shown.
  final VoidCallback? onSubtitlesTap;

  ///Flag used to show/hide qualities
  final bool enableQualities;

  ///Shows video quality as a dedicated control instead of an overflow item.
  final bool showQualitiesButton;

  ///Shows a dedicated download control.
  final bool enableDownloadButton;

  ///Callback invoked by the dedicated download control.
  final VoidCallback? onDownloadTap;

  ///Shows a dedicated video crop control with fit, crop, and stretch modes.
  final bool enableCrop;

  ///Flag used to show/hide PiP mode
  final bool enablePip;

  ///Flag used to show the native Chromecast route control.
  final bool enableCast;

  ///Flag used to enable/disable retry feature
  final bool enableRetry;

  ///Flag used to show/hide audio tracks
  final bool enableAudioTracks;

  ///Custom items of overflow menu
  final List<BetterPlayerOverflowMenuItem> overflowMenuCustomItems;

  ///Icon of the overflow menu
  final IconData overflowMenuIcon;

  ///Icon of the PiP menu
  final IconData pipMenuIcon;

  ///Icon of the playback speed menu item from overflow menu
  final IconData playbackSpeedIcon;

  ///Icon of the subtitles menu item from overflow menu
  final IconData subtitlesIcon;

  ///Icon of the dedicated download control.
  final IconData downloadIcon;

  ///Icon of the dedicated crop control.
  final IconData cropIcon;

  ///Icon of the qualities menu item from overflow menu
  final IconData qualitiesIcon;

  ///Icon of the audios menu item from overflow menu
  final IconData audioTracksIcon;

  ///Color of overflow menu icons
  final Color overflowMenuIconsColor;

  ///Time which will be used once user uses forward
  final int forwardSkipTimeInMilliseconds;

  ///Time which will be used once user uses backward
  final int backwardSkipTimeInMilliseconds;

  ///Color of default loading indicator
  final Color loadingColor;

  ///Widget which can be used instead of default progress
  final Widget? loadingWidget;

  ///Color of the background, when no frame is displayed.
  final Color backgroundColor;

  ///Color of the bottom modal sheet used for overflow menu items.
  final Color overflowModalColor;

  ///Color of text in bottom modal sheet used for overflow menu items.
  final Color overflowModalTextColor;

  ///Name of video source
  final String name;

  ///You're watching text
  final String? watchingText;

  ///Database function
  final Function? onFullScreenChange;

  /// Player timer mode
  final int? playerTimeMode;

  ///Flag used to enable/disable thumbnail preview when seeking
  final bool enableThumbnailPreview;

  ///Callback for episode selection (for TV shows)
  final Function()? onEpisodeListTap;

  ///Enable episode selection button
  final bool enableEpisodeSelection;

  ///Callback for movie recommendations selection
  final Function()? onMovieRecommendationsTap;

  ///Enable movie recommendations button
  final bool enableMovieRecommendations;

  ///Enable next episode button (floating button at 85% progress for TV shows)
  final bool enableNextEpisodeButton;

  /// App-provided skip action rendered inside the player controls layer.
  final Widget Function(BuildContext context)? introDbSkipButtonBuilder;

  /// Whether [introDbSkipButtonBuilder] currently has something to skip.
  /// Queried on every controls build: the skip button is kept outside the
  /// overlay fade, so the controls need to know when it is live before giving
  /// it screen space (and, on TV, the select key).
  final bool Function()? introDbSkipAvailable;

  /// Runs the app's skip action. Used by the TV controls to fire the persistent
  /// skip button from the select key while the overlay is hidden.
  final VoidCallback? onIntroDbSkip;

  ///Gesture-based controls configuration (volume/brightness swipe)
  final BetterPlayerGestureConfiguration gestureConfiguration;
}
