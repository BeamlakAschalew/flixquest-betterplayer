import 'dart:async';
import 'dart:io';
import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/configuration/better_player_controller_event.dart';
import 'package:better_player_plus/src/core/better_player_utils.dart';
import 'package:better_player_plus/src/subtitles/better_player_subtitle.dart';
import 'package:better_player_plus/src/subtitles/better_player_subtitles_factory.dart';
import 'package:better_player_plus/src/video_player/video_player.dart';
import 'package:better_player_plus/src/video_player/video_player_platform_interface.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

///Class used to control overall Better Player behavior. Main class to change
///state of Better Player.
class BetterPlayerController {
  BetterPlayerController(
    this.betterPlayerConfiguration, {
    this.betterPlayerPlaylistConfiguration,
    BetterPlayerDataSource? betterPlayerDataSource,
  }) {
    _ambientGlowEnabled = betterPlayerConfiguration.enableAmbientGlow;
    _betterPlayerControlsConfiguration = betterPlayerConfiguration.controlsConfiguration;
    _eventListeners.add(eventListener);
    if (betterPlayerDataSource != null) {
      setupDataSource(betterPlayerDataSource);
    }
  }

  static const String _durationParameter = 'duration';
  static const String _progressParameter = 'progress';
  static const String _bufferedParameter = 'buffered';
  static const String _volumeParameter = 'volume';
  static const String _speedParameter = 'speed';
  static const String _dataSourceParameter = 'dataSource';
  static const String _sourceKeyParameter = 'sourceKey';
  static const String _authorizationHeader = 'Authorization';

  ///General configuration used in controller instance.
  final BetterPlayerConfiguration betterPlayerConfiguration;

  ///Playlist configuration used in controller instance.
  final BetterPlayerPlaylistConfiguration? betterPlayerPlaylistConfiguration;

  ///List of event listeners, which listen to events.
  final List<Function(BetterPlayerEvent)?> _eventListeners = [];

  ///List of files to delete once player disposes.
  final List<File> _tempFiles = [];

  ///Stream controller which emits stream when control visibility changes.
  final StreamController<bool> _controlsVisibilityStreamController = StreamController.broadcast();

  ///Instance of video player controller which is adapter used to communicate
  ///between flutter high level code and lower level native code.
  VideoPlayerController? videoPlayerController;

  ///Controls configuration
  late BetterPlayerControlsConfiguration _betterPlayerControlsConfiguration;

  ///Controls configuration
  BetterPlayerControlsConfiguration get betterPlayerControlsConfiguration => _betterPlayerControlsConfiguration;

  ///Expose all active eventListeners
  List<Function(BetterPlayerEvent)?> get eventListeners => _eventListeners.sublist(1);

  /// Defines a event listener where video player events will be send.
  Function(BetterPlayerEvent)? get eventListener => betterPlayerConfiguration.eventListener;

  ///Flag used to store full screen mode state.
  bool _isFullScreen = false;

  ///Flag used to store full screen mode state.
  bool get isFullScreen => _isFullScreen;

  late bool _ambientGlowEnabled;

  ///Whether the Android ambient glow layer is currently enabled.
  bool get ambientGlowEnabled => _ambientGlowEnabled;

  ///Time when last progress event was sent
  int _lastPositionSelection = 0;

  ///Currently used data source in player.
  BetterPlayerDataSource? _betterPlayerDataSource;

  ///Currently used data source in player.
  BetterPlayerDataSource? get betterPlayerDataSource => _betterPlayerDataSource;

  ///List of BetterPlayerSubtitlesSources.
  final List<BetterPlayerSubtitlesSource> _betterPlayerSubtitlesSourceList = [];

  ///List of BetterPlayerSubtitlesSources.
  List<BetterPlayerSubtitlesSource> get betterPlayerSubtitlesSourceList => _betterPlayerSubtitlesSourceList;
  BetterPlayerSubtitlesSource? _betterPlayerSubtitlesSource;

  ///Currently used subtitles source.
  BetterPlayerSubtitlesSource? get betterPlayerSubtitlesSource => _betterPlayerSubtitlesSource;

  ///Subtitles lines for current data source.
  List<BetterPlayerSubtitle> subtitlesLines = [];

  ///The delay applied to subtitle cues.
  ///
  ///A positive value displays subtitles later; a negative value displays
  ///them earlier. The value is scoped to this controller so it survives track
  ///and provider changes during the same playback session.
  final ValueNotifier<Duration> _subtitleOffsetNotifier = ValueNotifier<Duration>(Duration.zero);

  Duration get subtitleOffset => _subtitleOffsetNotifier.value;

  ValueListenable<Duration> get subtitleOffsetListenable => _subtitleOffsetNotifier;

  ///Updates subtitle timing and notifies subtitle renderers immediately,
  ///including while playback is paused.
  void setSubtitleOffset(Duration offset) {
    const maximumOffset = Duration(minutes: 1);
    final clampedMilliseconds = offset.inMilliseconds.clamp(
      -maximumOffset.inMilliseconds,
      maximumOffset.inMilliseconds,
    );
    final nextOffset = Duration(milliseconds: clampedMilliseconds);
    if (_subtitleOffsetNotifier.value == nextOffset) return;
    _subtitleOffsetNotifier.value = nextOffset;
  }

  ///Invalidates an older network subtitle request when the user selects a
  ///different track or the player replaces its data source.
  int _subtitleLoadGeneration = 0;

  ///How many sources one selection tries before it gives up. Providers hand out
  ///plenty of duplicate tracks for the same language and every dead link costs a
  ///request, so a sweep is bounded instead of walking them all.
  static const int _maxSubtitleAttempts = 6;

  ///Sources that were asked for cues and came back with none, either because the
  ///host refused the request or because the body held nothing readable. Kept for
  ///the lifetime of the data source so neither automatic selection nor the user
  ///spends another wait on a track that is already known to be dead.
  final Set<BetterPlayerSubtitlesSource> _failedSubtitlesSources = {};

  ///Sources known to yield no cues. See [subtitlesSourceHasFailed].
  Set<BetterPlayerSubtitlesSource> get failedSubtitlesSources => Set.unmodifiable(_failedSubtitlesSources);

  ///True when [subtitlesSource] already failed to produce cues for the current
  ///data source. A caller can offer another track instead of repeating the wait.
  bool subtitlesSourceHasFailed(BetterPlayerSubtitlesSource subtitlesSource) =>
      _failedSubtitlesSources.contains(subtitlesSource);

  ///List of tracks available for current data source. Used only for HLS / DASH.
  List<BetterPlayerAsmsTrack> _betterPlayerAsmsTracks = [];

  ///List of tracks available for current data source. Used only for HLS / DASH.
  List<BetterPlayerAsmsTrack> get betterPlayerAsmsTracks => _betterPlayerAsmsTracks;

  ///Currently selected player track. Used only for HLS / DASH.
  BetterPlayerAsmsTrack? _betterPlayerAsmsTrack;

  ///Currently selected player track. Used only for HLS / DASH.
  BetterPlayerAsmsTrack? get betterPlayerAsmsTrack => _betterPlayerAsmsTrack;

  String? _betterPlayerResolutionName;

  ///Selected named resolution for non-adaptive sources.
  String? get betterPlayerResolutionName => _betterPlayerResolutionName;

  ///Timer for next video. Used in playlist.
  Timer? _nextVideoTimer;

  ///Time for next video.
  int? _nextVideoTime;

  ///Stream controller which emits next video time.
  final StreamController<int?> _nextVideoTimeStreamController = StreamController.broadcast();

  Stream<int?> get nextVideoTimeStream => _nextVideoTimeStreamController.stream;

  ///Has player been disposed.
  bool _disposed = false;

  ///Was player playing before automatic pause.
  bool? _wasPlayingBeforePause;

  ///Currently used translations
  BetterPlayerTranslations translations = BetterPlayerTranslations();

  ///Has current data source started
  bool _hasCurrentDataSourceStarted = false;

  ///Has current data source initialized
  bool _hasCurrentDataSourceInitialized = false;

  ///Stream which sends flag whenever visibility of controls changes
  Stream<bool> get controlsVisibilityStream => _controlsVisibilityStreamController.stream;

  ///Current app lifecycle state.
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;

  ///Flag which determines if controls (UI interface) is shown. When false,
  ///UI won't be shown (show only player surface).
  bool _controlsEnabled = true;

  ///Flag which determines if controls (UI interface) is shown. When false,
  ///UI won't be shown (show only player surface).
  bool get controlsEnabled => _controlsEnabled;

  ///Overridden aspect ratio which will be used instead of aspect ratio passed
  ///in configuration.
  double? _overriddenAspectRatio;

  ///Overridden fit which will be used instead of fit passed in configuration.
  BoxFit? _overriddenFit;

  ///Was Picture in Picture opened.
  bool _wasInPipMode = false;

  ///Was player in fullscreen before Picture in Picture opened.
  bool _wasInFullScreenBeforePiP = false;

  ///Was controls enabled before Picture in Picture opened.
  bool _wasControlsEnabledBeforePiP = false;

  ///GlobalKey of the BetterPlayer widget
  GlobalKey? _betterPlayerGlobalKey;

  ///Getter of the GlobalKey
  GlobalKey? get betterPlayerGlobalKey => _betterPlayerGlobalKey;

  ///StreamSubscription for VideoEvent listener
  StreamSubscription<VideoEvent>? _videoEventStreamSubscription;

  ///Are controls always visible
  bool _controlsAlwaysVisible = false;

  ///Are controls always visible
  bool get controlsAlwaysVisible => _controlsAlwaysVisible;

  ///List of all possible audio tracks returned from ASMS stream
  List<BetterPlayerAsmsAudioTrack>? _betterPlayerAsmsAudioTracks;

  ///List of all possible audio tracks returned from ASMS stream
  List<BetterPlayerAsmsAudioTrack>? get betterPlayerAsmsAudioTracks => _betterPlayerAsmsAudioTracks;

  ///Selected ASMS audio track
  BetterPlayerAsmsAudioTrack? _betterPlayerAsmsAudioTrack;

  ///Selected ASMS audio track
  BetterPlayerAsmsAudioTrack? get betterPlayerAsmsAudioTrack => _betterPlayerAsmsAudioTrack;

  ///Selected videoPlayerValue when error occurred.
  VideoPlayerValue? _videoPlayerValueOnError;

  ///Retries transient network failures without requiring a user action.
  Timer? _networkRecoveryTimer;
  bool _networkRecoveryInProgress = false;
  int _networkRecoveryAttempts = 0;
  int _dataSourceSetupGeneration = 0;
  static const List<Duration> _networkRecoveryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 3),
    Duration(seconds: 8),
  ];

  ///Flag which holds information about player visibility
  bool _isPlayerVisible = true;

  final StreamController<BetterPlayerControllerEvent> _controllerEventStreamController = StreamController.broadcast();

  ///Stream of internal controller events. Shouldn't be used inside app. For
  ///normal events, use eventListener.
  Stream<BetterPlayerControllerEvent> get controllerEventStream => _controllerEventStreamController.stream;

  ///Flag which determines whether are ASMS segments loading
  bool _asmsSegmentsLoading = false;

  ///List of loaded ASMS segments
  final List<String> _asmsSegmentsLoaded = [];

  ///Currently displayed [BetterPlayerSubtitle].
  BetterPlayerSubtitle? renderedSubtitle;

  ///Get BetterPlayerController from context. Used in InheritedWidget.
  static BetterPlayerController of(BuildContext context) {
    final betterPLayerControllerProvider = context
        .dependOnInheritedWidgetOfExactType<BetterPlayerControllerProvider>()!;

    return betterPLayerControllerProvider.controller;
  }

  ///Setup new data source in Better Player.
  Future setupDataSource(BetterPlayerDataSource betterPlayerDataSource, {Duration? initialPosition}) =>
      _setupDataSourceWithSubtitle(betterPlayerDataSource, initialPosition: initialPosition);

  /// Updates resolution and subtitle metadata without reloading the native
  /// media source. This is used for background server/size enrichment.
  void updateDataSourceMetadata({
    Map<String, String>? resolutions,
    String? selectedResolution,
    Map<String, BetterPlayerVideoFormat?>? resolutionVideoFormats,
    Map<String, Map<String, String>>? resolutionHeaders,
    Map<String, String>? resolutionDisplayNames,
    Map<String, String>? resolutionDescriptions,
    List<BetterPlayerSubtitlesSource>? subtitles,
  }) {
    final current = _betterPlayerDataSource;
    if (current == null) return;
    _betterPlayerDataSource = current.copyWith(
      resolutions: resolutions,
      selectedResolution: selectedResolution,
      resolutionVideoFormats: resolutionVideoFormats,
      resolutionHeaders: resolutionHeaders,
      resolutionDisplayNames: resolutionDisplayNames,
      resolutionDescriptions: resolutionDescriptions,
      subtitles: subtitles,
    );
    if (selectedResolution != null) {
      _betterPlayerResolutionName = selectedResolution;
    }
    if (subtitles != null) {
      final existingKeys = <String>{
        for (final source in _betterPlayerSubtitlesSourceList)
          '${source.urls?.first ?? ''}|${source.name ?? ''}|${source.type}',
      };
      for (final source in subtitles) {
        final key = '${source.urls?.first ?? ''}|${source.name ?? ''}|${source.type}';
        if (existingKeys.add(key)) _betterPlayerSubtitlesSourceList.add(source);
      }
    }
    _postControllerEvent(BetterPlayerControllerEvent.dataSourceMetadataChanged);
    _postEvent(BetterPlayerEvent(BetterPlayerEventType.changedResolution));
  }

  /// Plays [preRollDataSource] and [betterPlayerDataSource] as one native
  /// sequence while retaining the same surface, controls, and fullscreen
  /// route across the transition.
  Future setupDataSourceWithPreRoll({
    required BetterPlayerDataSource preRollDataSource,
    required BetterPlayerDataSource betterPlayerDataSource,
    Duration contentStartPosition = Duration.zero,
  }) {
    if (preRollDataSource.type != BetterPlayerDataSourceType.network ||
        betterPlayerDataSource.type != BetterPlayerDataSourceType.network) {
      throw ArgumentError('Pre-roll sequences currently require network data sources.');
    }
    return _setupDataSourceWithSubtitle(
      betterPlayerDataSource,
      preRollDataSource: preRollDataSource,
      contentStartPosition: contentStartPosition,
      // The content position is applied natively when the sequence advances.
      // Explicit zero prevents a configured startAt from seeking the pre-roll.
      initialPosition: Duration.zero,
    );
  }

  Future<void> _setupDataSourceWithSubtitle(
    BetterPlayerDataSource betterPlayerDataSource, {
    BetterPlayerSubtitlesSource? subtitlesSourceToRestore,
    BetterPlayerDataSource? preRollDataSource,
    Duration contentStartPosition = Duration.zero,
    Duration? initialPosition,
  }) async {
    final setupGeneration = ++_dataSourceSetupGeneration;
    _cancelNetworkRecovery(clearSavedPosition: true);
    postEvent(
      BetterPlayerEvent(
        BetterPlayerEventType.setupDataSource,
        parameters: <String, dynamic>{_dataSourceParameter: betterPlayerDataSource},
      ),
    );
    _postControllerEvent(BetterPlayerControllerEvent.setupDataSource);
    _hasCurrentDataSourceStarted = false;
    _hasCurrentDataSourceInitialized = false;
    _betterPlayerDataSource = betterPlayerDataSource;
    _betterPlayerResolutionName = betterPlayerDataSource.selectedResolution;
    _subtitleLoadGeneration++;
    _betterPlayerSubtitlesSourceList.clear();
    _failedSubtitlesSources.clear();
    _betterPlayerSubtitlesSource = subtitlesSourceToRestore;
    subtitlesLines.clear();

    ///Build videoPlayerController if null
    if (videoPlayerController == null) {
      videoPlayerController = VideoPlayerController(
        bufferingConfiguration: betterPlayerDataSource.bufferingConfiguration,
      );
      videoPlayerController?.addListener(_onVideoPlayerChanged);
    }

    ///Clear asms tracks
    betterPlayerAsmsTracks.clear();

    ///Setup subtitles
    final List<BetterPlayerSubtitlesSource>? betterPlayerSubtitlesSourceList = betterPlayerDataSource.subtitles;
    if (betterPlayerSubtitlesSourceList != null) {
      _betterPlayerSubtitlesSourceList.addAll(betterPlayerDataSource.subtitles!);
    }
    if (subtitlesSourceToRestore != null &&
        _betterPlayerSubtitlesSourceList.none((source) => identical(source, subtitlesSourceToRestore))) {
      _betterPlayerSubtitlesSourceList.add(subtitlesSourceToRestore);
    }

    final asmsSetup = _isDataSourceAsms(betterPlayerDataSource)
        ? _setupAsmsDataSource(betterPlayerDataSource, setupGeneration)
        : null;
    Future<void>? suppliedSubtitleSetup;
    if (asmsSetup == null) {
      suppliedSubtitleSetup = _setupSubtitles();
    }

    ///Process data source
    await _setupDataSource(
      betterPlayerDataSource,
      preRollDataSource: preRollDataSource,
      contentStartPosition: contentStartPosition,
      initialPosition: initialPosition,
      setupGeneration: setupGeneration,
    );
    if (setupGeneration != _dataSourceSetupGeneration) return;
    final castConfiguration = betterPlayerDataSource.castConfiguration;
    if (castConfiguration != null && Platform.isAndroid) {
      await videoPlayerController?.configureCast(castConfiguration.toMap());
    }
    if (asmsSetup != null) {
      await asmsSetup;
      if (setupGeneration != _dataSourceSetupGeneration) return;
      await _setupSubtitles();
    } else {
      await suppliedSubtitleSetup;
    }
    if (subtitlesSourceToRestore != null) {
      await _setupSubtitleSourceSafely(subtitlesSourceToRestore, sourceInitialize: false);
    }
    setTrack(BetterPlayerAsmsTrack.defaultTrack());
  }

  ///Configure subtitles based on subtitles source.
  Future<void> _setupSubtitles() async {
    if (_betterPlayerSubtitlesSourceList.none((source) => source.type == BetterPlayerSubtitlesSourceType.none)) {
      _betterPlayerSubtitlesSourceList.add(BetterPlayerSubtitlesSource(type: BetterPlayerSubtitlesSourceType.none));
    }

    // HLS/DASH subtitle discovery finishes asynchronously. A user can select
    // one of the supplied subtitle sources while that work is still in
    // progress; do not replace that choice with the default when discovery
    // completes.
    if (_betterPlayerSubtitlesSource != null) {
      return;
    }

    // The supplied list is ordered by the user's language preference, so the
    // sources flagged selectedByDefault are the preferred candidates in the
    // order they should be tried. A single dead link used to leave playback
    // with no subtitles at all, so walk them until one actually yields cues.
    final preferredSources = _betterPlayerSubtitlesSourceList
        .where(
          (element) =>
              (element.selectedByDefault ?? false) &&
              element.type != BetterPlayerSubtitlesSourceType.none &&
              !_failedSubtitlesSources.contains(element),
        )
        .toList();

    if (preferredSources.isEmpty) {
      // Every preferred source having failed already is not the same as none
      // being flagged: the first case means subtitles are off, the second keeps
      // the historical behaviour of applying the last entry in the list.
      final anyPreferred = _betterPlayerSubtitlesSourceList.any(
        (element) => (element.selectedByDefault ?? false) && element.type != BetterPlayerSubtitlesSourceType.none,
      );
      final chosen = anyPreferred ? _noneSubtitlesSource() : _betterPlayerSubtitlesSourceList.last;
      await _setupSubtitleSourceSafely(chosen);
      return;
    }

    final attempts = preferredSources.length < _maxSubtitleAttempts ? preferredSources.length : _maxSubtitleAttempts;

    for (var index = 0; index < attempts; index++) {
      final candidate = preferredSources[index];
      var failed = false;
      try {
        await setupSubtitleSource(
          candidate,
          sourceInitialize: true,
          // Only the last candidate is worth a second request: while others are
          // left, moving on finds cues sooner than retrying a dead url.
          allowRetry: index == attempts - 1,
        );
      } catch (_) {
        failed = true;
      }

      if (_disposed) return;
      if (!identical(_betterPlayerSubtitlesSource, candidate)) return;
      if (!failed) {
        // Segmented tracks fetch their cues just in time while playing, so an
        // empty cue list right after selection is expected rather than a failure.
        if (candidate.asmsIsSegmented ?? false) return;
        if (subtitlesLines.isNotEmpty) return;
      }
    }

    await _setupSubtitleSourceSafely(_noneSubtitlesSource());
  }

  ///Applies [subtitlesSource] on the user's behalf and, when it turns out to
  ///hold no cues, moves on to [fallbacks] - or, without them, to the other
  ///tracks offered for the same language - before turning subtitles off.
  ///Returns the source that ended up selected.
  ///
  ///Providers hand out several tracks per language and any of them can be a dead
  ///link. Leaving one selected shows an empty caption track that looks like it
  ///is working, so a failing pick moves on instead of reporting an error.
  ///
  ///A caller that groups the tracks itself passes [fallbacks] in the order it
  ///wants them tried; the default order is the one the source list came in.
  Future<BetterPlayerSubtitlesSource> selectSubtitlesSource(
    BetterPlayerSubtitlesSource subtitlesSource, {
    List<BetterPlayerSubtitlesSource>? fallbacks,
  }) async {
    final candidates = <BetterPlayerSubtitlesSource>[
      // A source already known to be dead is not worth another request; its
      // alternatives are all that is left to try.
      if (!_failedSubtitlesSources.contains(subtitlesSource)) subtitlesSource,
      ...(fallbacks ?? _sameLanguageAlternatives(subtitlesSource)).where(
        (element) => !_failedSubtitlesSources.contains(element),
      ),
    ];

    for (final candidate in candidates) {
      try {
        await setupSubtitleSource(candidate);
      } catch (exception) {
        BetterPlayerUtils.log(exception.toString());
      }
      if (_disposed) return candidate;
      // The user picked something else while this one was loading; their newer
      // choice wins.
      if (!identical(_betterPlayerSubtitlesSource, candidate)) {
        return _betterPlayerSubtitlesSource ?? candidate;
      }
      if (!_failedSubtitlesSources.contains(candidate)) return candidate;
    }

    final off = _noneSubtitlesSource();
    await _setupSubtitleSourceSafely(off, sourceInitialize: false);
    return off;
  }

  ///Other network tracks offered for the same language as [subtitlesSource],
  ///skipping the ones already known to be dead. Bounded because every attempt
  ///costs a request. A subtitle file the user added takes no part: substituting
  ///it, or standing in for it, would be a surprise.
  List<BetterPlayerSubtitlesSource> _sameLanguageAlternatives(BetterPlayerSubtitlesSource subtitlesSource) {
    if (subtitlesSource.type != BetterPlayerSubtitlesSourceType.network) {
      return const [];
    }
    final language = subtitlesSource.name?.trim().toLowerCase();
    final alternatives = <BetterPlayerSubtitlesSource>[];
    for (final element in _betterPlayerSubtitlesSourceList) {
      if (alternatives.length >= _maxSubtitleAttempts) break;
      if (identical(element, subtitlesSource)) continue;
      if (element.type != BetterPlayerSubtitlesSourceType.network) continue;
      if (element.name?.trim().toLowerCase() != language) continue;
      if (_failedSubtitlesSources.contains(element)) continue;
      alternatives.add(element);
    }
    return alternatives;
  }

  ///The entry that turns subtitles off. [_setupSubtitles] makes sure one is in
  ///the list, so the last entry is only reached if a caller emptied it.
  BetterPlayerSubtitlesSource _noneSubtitlesSource() =>
      _betterPlayerSubtitlesSourceList.firstWhereOrNull(
        (element) => element.type == BetterPlayerSubtitlesSourceType.none,
      ) ??
      _betterPlayerSubtitlesSourceList.last;

  ///Applies a subtitle source without letting a failing source take the
  ///surrounding data source setup - and with it playback - down.
  Future<void> _setupSubtitleSourceSafely(
    BetterPlayerSubtitlesSource subtitlesSource, {
    bool sourceInitialize = true,
  }) async {
    try {
      await setupSubtitleSource(subtitlesSource, sourceInitialize: sourceInitialize);
    } catch (exception) {
      BetterPlayerUtils.log(exception.toString());
    }
  }

  ///Check if given [betterPlayerDataSource] is HLS / DASH-type data source.
  bool _isDataSourceAsms(BetterPlayerDataSource betterPlayerDataSource) =>
      (BetterPlayerAsmsUtils.isDataSourceHls(betterPlayerDataSource.url) ||
          betterPlayerDataSource.videoFormat == BetterPlayerVideoFormat.hls) ||
      (BetterPlayerAsmsUtils.isDataSourceDash(betterPlayerDataSource.url) ||
          betterPlayerDataSource.videoFormat == BetterPlayerVideoFormat.dash);

  ///Configure HLS / DASH data source based on provided data source and configuration.
  ///This method configures tracks, subtitles and audio tracks from given
  ///master playlist.
  Future _setupAsmsDataSource(BetterPlayerDataSource source, int setupGeneration) async {
    final String? data = await BetterPlayerAsmsUtils.getDataFromUrl(source.url, _getHeaders(source));
    if (setupGeneration != _dataSourceSetupGeneration) return;
    if (data != null) {
      final BetterPlayerAsmsDataHolder response = await BetterPlayerAsmsUtils.parse(data, source.url);
      if (setupGeneration != _dataSourceSetupGeneration) return;

      /// Load tracks
      if (source.useAsmsTracks ?? false) {
        _betterPlayerAsmsTracks = response.tracks ?? [];
      }

      /// Load subtitles
      if (source.useAsmsSubtitles ?? false) {
        final List<BetterPlayerAsmsSubtitle> asmsSubtitles = response.subtitles ?? [];
        for (final asmsSubtitle in asmsSubtitles) {
          _betterPlayerSubtitlesSourceList.add(
            BetterPlayerSubtitlesSource(
              type: BetterPlayerSubtitlesSourceType.network,
              name: asmsSubtitle.name,
              urls: asmsSubtitle.realUrls,
              asmsIsSegmented: asmsSubtitle.isSegmented,
              asmsSegmentsTime: asmsSubtitle.segmentsTime,
              asmsSegments: asmsSubtitle.segments,
              selectedByDefault: asmsSubtitle.isDefault,
            ),
          );
        }
      }

      ///Load audio tracks
      if ((source.useAsmsAudioTracks ?? false) && _isDataSourceAsms(source)) {
        _betterPlayerAsmsAudioTracks = response.audios ?? [];
        _betterPlayerAsmsAudioTrack = _betterPlayerAsmsAudioTracks?.firstWhereOrNull(
          (audioTrack) => audioTrack.isDefault,
        );
      }
    }
  }

  ///Setup subtitles to be displayed from given subtitle source.
  ///If subtitles source is segmented then don't load videos at start. Videos
  ///will load with just in time policy.
  ///[allowRetry] retries a network source once when the first attempt comes back
  ///empty or failing. Automatic selection turns it off while it still has other
  ///candidates left, because trying a different track beats asking a dead url
  ///twice.
  Future<void> setupSubtitleSource(
    BetterPlayerSubtitlesSource subtitlesSource, {
    bool sourceInitialize = false,
    bool allowRetry = true,
  }) async {
    final loadGeneration = ++_subtitleLoadGeneration;
    _betterPlayerSubtitlesSource = subtitlesSource;
    subtitlesLines.clear();
    _asmsSegmentsLoaded.clear();
    _asmsSegmentsLoading = false;

    if (subtitlesSource.type != BetterPlayerSubtitlesSourceType.none) {
      if (subtitlesSource.asmsIsSegmented ?? false) {
        return;
      }

      var subtitlesParsed = <BetterPlayerSubtitle>[];
      Object? loadError;
      StackTrace? loadStackTrace;
      try {
        subtitlesParsed = await BetterPlayerSubtitlesFactory.parseSubtitles(subtitlesSource);
      } catch (exception, stackTrace) {
        loadError = exception;
        loadStackTrace = stackTrace;
      }
      if (_subtitleLoadAborted(loadGeneration, subtitlesSource)) return;

      // A subtitle host that is briefly unavailable is common enough to be worth
      // one immediate retry; only after that does the source count as dead.
      if (sourceInitialize &&
          allowRetry &&
          subtitlesSource.type == BetterPlayerSubtitlesSourceType.network &&
          (loadError != null || subtitlesParsed.isEmpty)) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (_subtitleLoadAborted(loadGeneration, subtitlesSource)) return;
        loadError = null;
        loadStackTrace = null;
        try {
          subtitlesParsed = await BetterPlayerSubtitlesFactory.parseSubtitles(subtitlesSource);
        } catch (exception, stackTrace) {
          loadError = exception;
          loadStackTrace = stackTrace;
        }
        if (_subtitleLoadAborted(loadGeneration, subtitlesSource)) return;
      }

      if (loadError != null) {
        // Report the now empty track before handing the failure to the caller,
        // which decides whether to try another source or surface an error.
        _failedSubtitlesSources.add(subtitlesSource);
        _notifySubtitlesChanged(sourceInitialize: sourceInitialize);
        Error.throwWithStackTrace(loadError, loadStackTrace ?? StackTrace.current);
      }
      // A readable response with no cues in it is just as useless to a viewer as
      // a refused one, so it counts as a failed source too.
      if (subtitlesParsed.isEmpty) {
        _failedSubtitlesSources.add(subtitlesSource);
      } else {
        _failedSubtitlesSources.remove(subtitlesSource);
      }
      subtitlesLines.addAll(subtitlesParsed);
    }

    _notifySubtitlesChanged(sourceInitialize: sourceInitialize);
  }

  ///True when the subtitle load that started at [loadGeneration] no longer owns
  ///the selection, so its result has to be dropped instead of applied.
  bool _subtitleLoadAborted(int loadGeneration, BetterPlayerSubtitlesSource subtitlesSource) =>
      _disposed ||
      loadGeneration != _subtitleLoadGeneration ||
      !identical(_betterPlayerSubtitlesSource, subtitlesSource);

  void _notifySubtitlesChanged({required bool sourceInitialize}) {
    _postEvent(BetterPlayerEvent(BetterPlayerEventType.changedSubtitles));
    if (!_disposed && !sourceInitialize) {
      _postControllerEvent(BetterPlayerControllerEvent.changeSubtitles);
    }
  }

  ///Load ASMS subtitles segments for given [position].
  ///Segments overlapping [current video position;endPosition) are loaded.
  ///where endPosition is based on time segment detected in HLS playlist. If
  ///time segment is not present then 5000 ms will be used. Also time segment
  ///is multiplied by 5 to increase window of duration.
  ///Segments are also cached, so same segment won't load twice. Only one
  ///pack of segments can be load at given time.
  Future _loadAsmsSubtitlesSegments(Duration position) async {
    try {
      if (_asmsSegmentsLoading) {
        return;
      }
      _asmsSegmentsLoading = true;
      final BetterPlayerSubtitlesSource? source = _betterPlayerSubtitlesSource;
      final Duration loadDurationEnd = Duration(
        milliseconds: position.inMilliseconds + 5 * (_betterPlayerSubtitlesSource?.asmsSegmentsTime ?? 5000),
      );

      final segmentsToLoad = _betterPlayerSubtitlesSource?.asmsSegments
          ?.where(
            (segment) =>
                segment.endTime > position &&
                segment.startTime < loadDurationEnd &&
                !_asmsSegmentsLoaded.contains(segment.realUrl),
          )
          .map((segment) => segment.realUrl)
          .toList();

      if (segmentsToLoad != null && segmentsToLoad.isNotEmpty) {
        final subtitlesParsed = await BetterPlayerSubtitlesFactory.parseSubtitles(
          BetterPlayerSubtitlesSource(
            type: _betterPlayerSubtitlesSource!.type,
            headers: _betterPlayerSubtitlesSource!.headers,
            urls: segmentsToLoad,
          ),
        );

        ///Additional check if current source of subtitles is same as source
        ///used to start loading subtitles. It can be different when user
        ///changes subtitles and there was already pending load.
        if (source == _betterPlayerSubtitlesSource) {
          subtitlesLines.addAll(subtitlesParsed);
          _asmsSegmentsLoaded.addAll(segmentsToLoad);
        }
      }
      _asmsSegmentsLoading = false;
    } on Exception catch (exception) {
      BetterPlayerUtils.log('Load ASMS subtitle segments failed: $exception');
      _asmsSegmentsLoading = false;
    }
  }

  ///Get VideoFormat from BetterPlayerVideoFormat (adapter method which translates
  ///to video_player supported format).
  VideoFormat? _getVideoFormat(BetterPlayerVideoFormat? betterPlayerVideoFormat) {
    if (betterPlayerVideoFormat == null) {
      return null;
    }
    switch (betterPlayerVideoFormat) {
      case BetterPlayerVideoFormat.dash:
        return VideoFormat.dash;
      case BetterPlayerVideoFormat.hls:
        return VideoFormat.hls;
      case BetterPlayerVideoFormat.ss:
        return VideoFormat.ss;
      case BetterPlayerVideoFormat.other:
        return VideoFormat.other;
    }
  }

  ///Internal method which invokes videoPlayerController source setup.
  Future _setupDataSource(
    BetterPlayerDataSource betterPlayerDataSource, {
    BetterPlayerDataSource? preRollDataSource,
    Duration contentStartPosition = Duration.zero,
    Duration? initialPosition,
    int? setupGeneration,
    bool? resumePlayback,
  }) async {
    final isLive = betterPlayerDataSource.liveStream == true;
    final notification = betterPlayerDataSource.notificationConfiguration;
    switch (betterPlayerDataSource.type) {
      case BetterPlayerDataSourceType.network:
        await videoPlayerController?.setNetworkDataSource(
          betterPlayerDataSource.url,
          headers: _getHeaders(betterPlayerDataSource),
          // Live manifests are mutable and must always be reloaded upstream.
          useCache: !isLive && (betterPlayerDataSource.cacheConfiguration?.useCache ?? false),
          maxCacheSize: betterPlayerDataSource.cacheConfiguration?.maxCacheSize ?? 0,
          maxCacheFileSize: betterPlayerDataSource.cacheConfiguration?.maxCacheFileSize ?? 0,
          // Android uses the FlixQuest offline cache key to select a local
          // Media3 source. Never let a live source accidentally select it.
          cacheKey: isLive ? null : betterPlayerDataSource.cacheConfiguration?.key,
          showNotification: notification?.showNotification,
          title: notification?.title,
          author: notification?.author,
          imageUrl: notification?.imageUrl,
          notificationChannelName: notification?.notificationChannelName,
          overriddenDuration: betterPlayerDataSource.overriddenDuration,
          formatHint: _getVideoFormat(betterPlayerDataSource.videoFormat),
          licenseUrl: betterPlayerDataSource.drmConfiguration?.licenseUrl,
          certificateUrl: betterPlayerDataSource.drmConfiguration?.certificateUrl,
          drmHeaders: betterPlayerDataSource.drmConfiguration?.headers,
          activityName: notification?.activityName,
          clearKey: betterPlayerDataSource.drmConfiguration?.clearKey,
          videoExtension: betterPlayerDataSource.videoExtension,
          isLive: isLive,
          preRollDataSource: preRollDataSource == null
              ? null
              : DataSource(
                  sourceType: DataSourceType.network,
                  uri: preRollDataSource.url,
                  formatHint: _getVideoFormat(preRollDataSource.videoFormat),
                  headers: preRollDataSource.headers,
                  useCache: preRollDataSource.cacheConfiguration?.useCache ?? false,
                  maxCacheSize: preRollDataSource.cacheConfiguration?.maxCacheSize,
                  maxCacheFileSize: preRollDataSource.cacheConfiguration?.maxCacheFileSize,
                  cacheKey: preRollDataSource.cacheConfiguration?.key,
                  videoExtension: preRollDataSource.videoExtension,
                ),
          contentStartPosition: contentStartPosition,
        );

      case BetterPlayerDataSourceType.file:
        final file = File(betterPlayerDataSource.url);
        if (!file.existsSync()) {
          BetterPlayerUtils.log(
            "File ${file.path} doesn't exists. This may be because "
            "you're acessing file from native path and Flutter doesn't "
            'recognize this path.',
          );
        }

        await videoPlayerController?.setFileDataSource(
          File(betterPlayerDataSource.url),
          showNotification: notification?.showNotification,
          title: notification?.title,
          author: notification?.author,
          imageUrl: notification?.imageUrl,
          notificationChannelName: notification?.notificationChannelName,
          overriddenDuration: betterPlayerDataSource.overriddenDuration,
          activityName: notification?.activityName,
          clearKey: betterPlayerDataSource.drmConfiguration?.clearKey,
        );
      case BetterPlayerDataSourceType.memory:
        final file = await _createFile(betterPlayerDataSource.bytes!, extension: betterPlayerDataSource.videoExtension);

        if (file.existsSync()) {
          await videoPlayerController?.setFileDataSource(
            file,
            showNotification: notification?.showNotification,
            title: notification?.title,
            author: notification?.author,
            imageUrl: notification?.imageUrl,
            notificationChannelName: notification?.notificationChannelName,
            overriddenDuration: betterPlayerDataSource.overriddenDuration,
            activityName: notification?.activityName,
            clearKey: betterPlayerDataSource.drmConfiguration?.clearKey,
          );
          _tempFiles.add(file);
        } else {
          throw ArgumentError("Couldn't create file from memory.");
        }
    }
    if (setupGeneration != null && setupGeneration != _dataSourceSetupGeneration) {
      return;
    }
    await _initializeVideo(initialPosition: initialPosition, resumePlayback: resumePlayback);
  }

  ///Create file from provided list of bytes. File will be created in temporary
  ///directory.
  Future<File> _createFile(List<int> bytes, {String? extension = 'temp'}) async {
    final String dir = (await getTemporaryDirectory()).path;
    final File temp = File('$dir/better_player_${DateTime.now().millisecondsSinceEpoch}.$extension');
    await temp.writeAsBytes(bytes);
    return temp;
  }

  ///Initializes video based on configuration. Invoke actions which need to be
  ///run on player start.
  Future _initializeVideo({Duration? initialPosition, bool? resumePlayback}) async {
    setLooping(betterPlayerConfiguration.looping);
    _videoEventStreamSubscription?.cancel();
    _videoEventStreamSubscription = null;

    _videoEventStreamSubscription = videoPlayerController?.videoEventStreamController.stream.listen(_handleVideoEvent);

    // Apply the requested position before autoplay. Seeking after play has
    // already started causes a visible jump back to zero (or forward to a
    // resume point) during the first seconds of playback.
    final startAt = initialPosition ?? betterPlayerConfiguration.startAt;
    if (startAt != null && startAt != Duration.zero) {
      await seekTo(startAt);
    }

    final fullScreenByDefault = betterPlayerConfiguration.fullScreenByDefault;
    if (resumePlayback ?? betterPlayerConfiguration.autoPlay) {
      if (fullScreenByDefault && !isFullScreen) {
        enterFullScreen();
      }
      if (_isAutomaticPlayPauseHandled()) {
        if (_appLifecycleState == AppLifecycleState.resumed && _isPlayerVisible) {
          await play();
        } else {
          _wasPlayingBeforePause = true;
        }
      } else {
        await play();
      }
    } else {
      if (fullScreenByDefault) {
        enterFullScreen();
      }
    }
  }

  ///Method which is invoked when full screen changes.
  Future<void> _onFullScreenStateChanged() async {
    if ((videoPlayerController?.value.isPlaying ?? false) && !_isFullScreen) {
      enterFullScreen();
      videoPlayerController?.removeListener(_onFullScreenStateChanged);
    }
  }

  ///Enables full screen mode in player. This will trigger route change.
  void enterFullScreen() {
    _isFullScreen = true;
    _postControllerEvent(BetterPlayerControllerEvent.openFullscreen);
  }

  ///Disables full screen mode in player. This will trigger route change.
  void exitFullScreen() {
    _isFullScreen = false;
    _postControllerEvent(BetterPlayerControllerEvent.hideFullscreen);
  }

  ///Enables/disables full screen mode based on current fullscreen state.
  void toggleFullScreen() {
    _isFullScreen = !_isFullScreen;
    if (_isFullScreen) {
      _postControllerEvent(BetterPlayerControllerEvent.openFullscreen);
    } else {
      _postControllerEvent(BetterPlayerControllerEvent.hideFullscreen);
    }
  }

  ///Start video playback. Play will be triggered only if current lifecycle state
  ///is resumed.
  Future<void> play() async {
    if (videoPlayerController == null) {
      throw StateError('The data source has not been initialized');
    }

    if (_appLifecycleState == AppLifecycleState.resumed) {
      await videoPlayerController!.play();
      _hasCurrentDataSourceStarted = true;
      _wasPlayingBeforePause = null;
      _postEvent(BetterPlayerEvent(BetterPlayerEventType.play));
      _postControllerEvent(BetterPlayerControllerEvent.play);
    }
  }

  ///Enables/disables looping (infinity playback) mode.
  Future<void> setLooping(bool looping) async {
    if (videoPlayerController == null) {
      throw StateError('The data source has not been initialized');
    }

    await videoPlayerController!.setLooping(looping);
  }

  ///Stop video playback.
  Future<void> pause() async {
    if (videoPlayerController == null) {
      throw StateError('The data source has not been initialized');
    }

    await videoPlayerController!.pause();
    _postEvent(BetterPlayerEvent(BetterPlayerEventType.pause));
  }

  ///Move player to specific position/moment of the video.
  Future<void> seekTo(Duration moment) async {
    if (videoPlayerController == null) {
      throw StateError('The data source has not been initialized');
    }
    if (videoPlayerController?.value.duration == null) {
      throw StateError('The video has not been initialized yet.');
    }

    await videoPlayerController!.seekTo(moment);

    _postEvent(
      BetterPlayerEvent(BetterPlayerEventType.seekTo, parameters: <String, dynamic>{_durationParameter: moment}),
    );

    final Duration? currentDuration = videoPlayerController!.value.duration;
    if (currentDuration == null) {
      return;
    }
    // Seeking to the exact end is also a completed playback. This commonly
    // happens when an app-provided "skip credits" action targets the media
    // duration, and the platform may not emit another native completion event
    // after that seek.
    if (moment >= currentDuration) {
      _postEvent(BetterPlayerEvent(BetterPlayerEventType.finished));
    } else {
      cancelNextVideoTimer();
    }
  }

  ///Set volume of player. Allows values from 0.0 to 1.0.
  Future<void> setVolume(double volume) async {
    if (volume < 0.0 || volume > 1.0) {
      BetterPlayerUtils.log('Volume must be between 0.0 and 1.0');
      throw ArgumentError('Volume must be between 0.0 and 1.0');
    }
    if (videoPlayerController == null) {
      BetterPlayerUtils.log('The data source has not been initialized');
      throw StateError('The data source has not been initialized');
    }
    await videoPlayerController!.setVolume(volume);
    _postEvent(
      BetterPlayerEvent(BetterPlayerEventType.setVolume, parameters: <String, dynamic>{_volumeParameter: volume}),
    );
  }

  ///Set playback speed of video. Allows to set speed value between 0 and 2.
  Future<void> setSpeed(double speed) async {
    if (speed <= 0 || speed > 2) {
      BetterPlayerUtils.log('Speed must be between 0 and 2');
      throw ArgumentError('Speed must be between 0 and 2');
    }
    if (videoPlayerController == null) {
      BetterPlayerUtils.log('The data source has not been initialized');
      throw StateError('The data source has not been initialized');
    }
    await videoPlayerController?.setSpeed(speed);
    _postEvent(
      BetterPlayerEvent(BetterPlayerEventType.setSpeed, parameters: <String, dynamic>{_speedParameter: speed}),
    );
  }

  ///Flag which determines whenever player is playing or not.
  bool? isPlaying() {
    if (videoPlayerController == null) {
      throw StateError('The data source has not been initialized');
    }
    return videoPlayerController!.value.isPlaying;
  }

  ///Flag which determines whenever player is loading video data or not.
  bool? isBuffering() {
    if (videoPlayerController == null) {
      throw StateError('The data source has not been initialized');
    }
    return videoPlayerController!.value.isBuffering;
  }

  ///Show or hide controls manually
  void setControlsVisibility(bool isVisible) {
    _controlsVisibilityStreamController.add(isVisible);
  }

  ///Enable/disable controls (when enabled = false, controls will be always hidden)
  void setControlsEnabled(bool enabled) {
    if (!enabled) {
      _controlsVisibilityStreamController.add(false);
    }
    _controlsEnabled = enabled;
  }

  ///Internal method, used to trigger CONTROLS_VISIBLE or CONTROLS_HIDDEN event
  ///once controls state changed.
  void toggleControlsVisibility(bool isVisible) {
    _postEvent(
      isVisible
          ? BetterPlayerEvent(BetterPlayerEventType.controlsVisible)
          : BetterPlayerEvent(BetterPlayerEventType.controlsHiddenEnd),
    );
  }

  ///Send player event. Shouldn't be used manually.
  void postEvent(BetterPlayerEvent betterPlayerEvent) {
    _postEvent(betterPlayerEvent);
  }

  ///Send player event to all listeners.
  void _postEvent(BetterPlayerEvent betterPlayerEvent) {
    for (final Function(BetterPlayerEvent)? eventListener in _eventListeners) {
      if (eventListener != null) {
        eventListener(betterPlayerEvent);
      }
    }
  }

  ///Listener used to handle video player changes.
  Future<void> _onVideoPlayerChanged() async {
    final VideoPlayerValue currentVideoPlayerValue =
        videoPlayerController?.value ?? VideoPlayerValue(duration: Duration.zero);

    if (currentVideoPlayerValue.hasError) {
      _videoPlayerValueOnError ??= currentVideoPlayerValue;
      if (_betterPlayerDataSource?.liveStream != true && currentVideoPlayerValue.isErrorRecoverable) {
        _scheduleNetworkRecovery();
      }
      _postEvent(
        BetterPlayerEvent(
          BetterPlayerEventType.exception,
          parameters: <String, dynamic>{
            'exception': currentVideoPlayerValue.errorDescription,
            'recoverable': currentVideoPlayerValue.isErrorRecoverable,
            _sourceKeyParameter: _betterPlayerDataSource?.url,
          },
        ),
      );
    }
    final recoveryPosition = _videoPlayerValueOnError?.position;
    final playbackRecovered =
        recoveryPosition != null &&
        currentVideoPlayerValue.isPlaying &&
        !currentVideoPlayerValue.isBuffering &&
        currentVideoPlayerValue.position > recoveryPosition + const Duration(seconds: 1);
    if (currentVideoPlayerValue.initialized &&
        !currentVideoPlayerValue.hasError &&
        !_networkRecoveryInProgress &&
        (recoveryPosition == null || playbackRecovered)) {
      _cancelNetworkRecovery(clearSavedPosition: true);
    }
    if (currentVideoPlayerValue.initialized && !_hasCurrentDataSourceInitialized) {
      _hasCurrentDataSourceInitialized = true;
      _postEvent(
        BetterPlayerEvent(
          BetterPlayerEventType.initialized,
          parameters: <String, dynamic>{_sourceKeyParameter: _betterPlayerDataSource?.url},
        ),
      );
    }
    if (currentVideoPlayerValue.isPip) {
      _wasInPipMode = true;
    } else if (_wasInPipMode) {
      _postEvent(BetterPlayerEvent(BetterPlayerEventType.pipStop));
      _wasInPipMode = false;
      if (!_wasInFullScreenBeforePiP) {
        exitFullScreen();
      }
      if (_wasControlsEnabledBeforePiP) {
        setControlsEnabled(true);
      }
      videoPlayerController?.refresh();
    }

    if (_betterPlayerSubtitlesSource?.asmsIsSegmented ?? false) {
      _loadAsmsSubtitlesSegments(currentVideoPlayerValue.position);
    }

    final int now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastPositionSelection > 500) {
      _lastPositionSelection = now;
      _postEvent(
        BetterPlayerEvent(
          BetterPlayerEventType.progress,
          parameters: <String, dynamic>{
            _progressParameter: currentVideoPlayerValue.position,
            _durationParameter: currentVideoPlayerValue.duration,
            _sourceKeyParameter: _betterPlayerDataSource?.url,
          },
        ),
      );
    }
  }

  ///Add event listener which listens to player events.
  void addEventsListener(Function(BetterPlayerEvent) eventListener) {
    _eventListeners.add(eventListener);
  }

  ///Remove event listener. This method should be called once you're disposing
  ///Better Player.
  void removeEventsListener(Function(BetterPlayerEvent) eventListener) {
    _eventListeners.remove(eventListener);
  }

  ///Flag which determines whenever player is playing live data source.
  bool isLiveStream() {
    if (_betterPlayerDataSource == null) {
      BetterPlayerUtils.log('The data source has not been initialized');
      throw StateError('The data source has not been initialized');
    }
    return _betterPlayerDataSource!.liveStream ?? false;
  }

  ///Flag which determines whenever player data source has been initialized.
  bool? isVideoInitialized() {
    if (videoPlayerController == null) {
      BetterPlayerUtils.log('The data source has not been initialized');
      throw StateError('The data source has not been initialized');
    }
    return videoPlayerController?.value.initialized;
  }

  ///Start timer which will trigger next video. Used in playlist. Do not use
  ///manually.
  void startNextVideoTimer() {
    if (_nextVideoTimer == null) {
      if (betterPlayerPlaylistConfiguration == null) {
        BetterPlayerUtils.log('BettterPlayerPlaylistConifugration has not been set!');
        throw StateError('BettterPlayerPlaylistConifugration has not been set!');
      }

      _nextVideoTime = betterPlayerPlaylistConfiguration!.nextVideoDelay.inSeconds;
      _nextVideoTimeStreamController.add(_nextVideoTime);
      if (_nextVideoTime == 0) {
        return;
      }

      _nextVideoTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) async {
        if (_nextVideoTime == 1) {
          timer.cancel();
          _nextVideoTimer = null;
        }
        if (_nextVideoTime != null) {
          _nextVideoTime = _nextVideoTime! - 1;
        }
        _nextVideoTimeStreamController.add(_nextVideoTime);
      });
    }
  }

  ///Cancel next video timer. Used in playlist. Do not use manually.
  void cancelNextVideoTimer() {
    _nextVideoTime = null;
    _nextVideoTimeStreamController.add(_nextVideoTime);
    _nextVideoTimer?.cancel();
    _nextVideoTimer = null;
  }

  ///Play next video form playlist. Do not use manually.
  void playNextVideo() {
    _nextVideoTime = 0;
    _nextVideoTimeStreamController.add(_nextVideoTime);
    _postEvent(BetterPlayerEvent(BetterPlayerEventType.changedPlaylistItem));
    cancelNextVideoTimer();
  }

  ///Setup track parameters for currently played video. Can be only used for HLS or DASH
  ///data source.
  void setTrack(BetterPlayerAsmsTrack track) {
    if (videoPlayerController == null) {
      throw StateError('The data source has not been initialized');
    }
    _postEvent(
      BetterPlayerEvent(
        BetterPlayerEventType.changedTrack,
        parameters: <String, dynamic>{
          'id': track.id,
          'width': track.width,
          'height': track.height,
          'bitrate': track.bitrate,
          'frameRate': track.frameRate,
          'codecs': track.codecs,
          'mimeType': track.mimeType,
        },
      ),
    );

    videoPlayerController!.setTrackParameters(track.width, track.height, track.bitrate);
    _betterPlayerAsmsTrack = track;
    if (_betterPlayerAsmsTracks.isNotEmpty) {
      _betterPlayerResolutionName = null;
    }
  }

  ///Check if player can be played/paused automatically
  bool _isAutomaticPlayPauseHandled() =>
      !(_betterPlayerDataSource?.notificationConfiguration?.showNotification ?? false) &&
      betterPlayerConfiguration.handleLifecycle;

  ///Listener which handles state of player visibility. If player visibility is
  ///below 0.0 then video will be paused. When value is greater than 0, video
  ///will play again. If there's different handler of visibility then it will be
  ///used. If showNotification is set in data source or handleLifecycle is false
  /// then this logic will be ignored.
  Future<void> onPlayerVisibilityChanged(double visibilityFraction) async {
    _isPlayerVisible = visibilityFraction > 0;
    if (_disposed) {
      return;
    }
    _postEvent(BetterPlayerEvent(BetterPlayerEventType.changedPlayerVisibility));

    if (_isAutomaticPlayPauseHandled()) {
      if (betterPlayerConfiguration.playerVisibilityChangedBehavior != null) {
        betterPlayerConfiguration.playerVisibilityChangedBehavior!(visibilityFraction);
      } else {
        if (visibilityFraction == 0) {
          _wasPlayingBeforePause ??= isPlaying();
          pause();
        } else {
          if ((_wasPlayingBeforePause ?? false) && !isPlaying()!) {
            play();
          }
        }
      }
    }
  }

  ///Set different resolution (quality) for video
  Future<void> setResolution(String url, {String? name}) async {
    if (videoPlayerController == null) {
      throw StateError('The data source has not been initialized');
    }
    final position = await videoPlayerController!.position;
    final wasPlayingBeforeChange = isPlaying()!;
    final subtitlesSourceToRestore = _betterPlayerSubtitlesSource;
    pause();
    final resolutionName =
        name ??
        betterPlayerDataSource!.resolutions?.entries
            .where((entry) => entry.value == url)
            .map((entry) => entry.key)
            .singleOrNull;
    final resolutionFormats = betterPlayerDataSource!.resolutionVideoFormats;
    final hasResolutionFormat = resolutionName != null && resolutionFormats?.containsKey(resolutionName) == true;
    final resolutionHeaders = betterPlayerDataSource!.resolutionHeaders;
    final hasResolutionHeaders = resolutionName != null && resolutionHeaders?.containsKey(resolutionName) == true;
    await _setupDataSourceWithSubtitle(
      betterPlayerDataSource!.copyWith(
        url: url,
        selectedResolution: resolutionName,
        videoFormat: hasResolutionFormat ? resolutionFormats![resolutionName] : null,
        clearVideoFormat: hasResolutionFormat && resolutionFormats![resolutionName] == null,
        headers: hasResolutionHeaders ? resolutionHeaders![resolutionName] : null,
      ),
      subtitlesSourceToRestore: subtitlesSourceToRestore,
      initialPosition: position,
    );
    _betterPlayerResolutionName = resolutionName;
    if (wasPlayingBeforeChange) {
      play();
    }
    _postEvent(
      BetterPlayerEvent(
        BetterPlayerEventType.changedResolution,
        parameters: <String, dynamic>{'url': url, 'name': resolutionName},
      ),
    );
  }

  ///Setup translations for given locale. In normal use cases it shouldn't be
  ///called manually.
  void setupTranslations(Locale locale) {
    final String languageCode = locale.languageCode;
    translations =
        betterPlayerConfiguration.translations?.firstWhereOrNull(
          (translations) => translations.languageCode == languageCode,
        ) ??
        _getDefaultTranslations(locale);
  }

  ///Setup default translations for selected user locale. These translations
  ///are pre-build in.
  BetterPlayerTranslations _getDefaultTranslations(Locale locale) {
    final String languageCode = locale.languageCode;
    switch (languageCode) {
      case 'pl':
        return BetterPlayerTranslations.polish();
      case 'zh':
        return BetterPlayerTranslations.chinese();
      case 'hi':
        return BetterPlayerTranslations.hindi();
      case 'tr':
        return BetterPlayerTranslations.turkish();
      case 'vi':
        return BetterPlayerTranslations.vietnamese();
      case 'es':
        return BetterPlayerTranslations.spanish();
      default:
        return BetterPlayerTranslations();
    }
  }

  ///Flag which determines whenever current data source has started.
  bool get hasCurrentDataSourceStarted => _hasCurrentDataSourceStarted;

  ///Set current lifecycle state. If state is [AppLifecycleState.resumed] then
  ///player starts playing again. if lifecycle is in [AppLifecycleState.paused]
  ///state, then video playback will stop. If showNotification is set in data
  ///source or handleLifecycle is false then this logic will be ignored.
  void setAppLifecycleState(AppLifecycleState appLifecycleState) {
    if (_isAutomaticPlayPauseHandled()) {
      _appLifecycleState = appLifecycleState;
      if (appLifecycleState == AppLifecycleState.resumed) {
        if ((_wasPlayingBeforePause ?? false) && _isPlayerVisible) {
          play();
        }
      }
      if (appLifecycleState == AppLifecycleState.paused) {
        _wasPlayingBeforePause ??= isPlaying();
        pause();
      }
    }
  }

  // ignore: use_setters_to_change_properties
  ///Setup overridden aspect ratio.
  void setOverriddenAspectRatio(double aspectRatio) {
    _overriddenAspectRatio = aspectRatio;
  }

  ///Get aspect ratio used in current video. If aspect ratio is null, then
  ///aspect ratio from BetterPlayerConfiguration will be used. Otherwise
  ///[_overriddenAspectRatio] will be used.
  double? getAspectRatio() => _overriddenAspectRatio ?? betterPlayerConfiguration.aspectRatio;

  // ignore: use_setters_to_change_properties
  ///Setup overridden fit.
  void setOverriddenFit(BoxFit fit) {
    _overriddenFit = fit;
    _postControllerEvent(BetterPlayerControllerEvent.setFit);
  }

  ///Get fit used in current video. If fit is null, then fit from
  ///BetterPlayerConfiguration will be used. Otherwise [_overriddenFit] will be
  ///used.
  BoxFit getFit() => _overriddenFit ?? betterPlayerConfiguration.fit;

  ///Enable or disable the Android ambient glow without rebuilding playback.
  void setAmbientGlowEnabled(bool enabled) {
    if (_ambientGlowEnabled == enabled) return;
    _ambientGlowEnabled = enabled;
    _postControllerEvent(BetterPlayerControllerEvent.ambientGlow);
  }

  ///Enable Picture in Picture (PiP) mode. [betterPlayerGlobalKey] is required
  ///to open PiP mode in iOS. When device is not supported, PiP mode won't be
  ///open.
  Future<void>? enablePictureInPicture(GlobalKey betterPlayerGlobalKey) async {
    if (videoPlayerController == null) {
      throw StateError('The data source has not been initialized');
    }

    final bool isPipSupported = (await videoPlayerController!.isPictureInPictureSupported()) ?? false;

    if (isPipSupported) {
      _wasInFullScreenBeforePiP = _isFullScreen;
      _wasControlsEnabledBeforePiP = _controlsEnabled;
      setControlsEnabled(false);
      if (Platform.isAndroid) {
        _wasInFullScreenBeforePiP = _isFullScreen;
        await videoPlayerController?.enablePictureInPicture(left: 0, top: 0, width: 0, height: 0);
        enterFullScreen();
        _postEvent(BetterPlayerEvent(BetterPlayerEventType.pipStart));
        return;
      }
      if (Platform.isIOS) {
        final RenderBox? renderBox = betterPlayerGlobalKey.currentContext!.findRenderObject() as RenderBox?;
        if (renderBox == null) {
          BetterPlayerUtils.log(
            "Can't show PiP. RenderBox is null. Did you provide valid global"
            ' key?',
          );
          return;
        }
        final Offset position = renderBox.localToGlobal(Offset.zero);
        return videoPlayerController?.enablePictureInPicture(
          left: position.dx,
          top: position.dy,
          width: renderBox.size.width,
          height: renderBox.size.height,
        );
      } else {
        BetterPlayerUtils.log('Unsupported PiP in current platform.');
      }
    } else {
      BetterPlayerUtils.log(
        "Picture in picture is not supported in this device. If you're "
        "using Android, please check if you're using activity v2 "
        'embedding.',
      );
    }
  }

  ///Disable Picture in Picture mode if it's enabled.
  Future<void>? disablePictureInPicture() {
    if (videoPlayerController == null) {
      throw StateError('The data source has not been initialized');
    }
    return videoPlayerController!.disablePictureInPicture();
  }

  // ignore: use_setters_to_change_properties
  ///Set GlobalKey of BetterPlayer. Used in PiP methods called from controls.
  void setBetterPlayerGlobalKey(GlobalKey betterPlayerGlobalKey) {
    _betterPlayerGlobalKey = betterPlayerGlobalKey;
  }

  ///Check if picture in picture mode is supported in this device.
  Future<bool> isPictureInPictureSupported() async {
    if (videoPlayerController == null) {
      throw StateError('The data source has not been initialized');
    }

    final bool isPipSupported = (await videoPlayerController!.isPictureInPictureSupported()) ?? false;

    return isPipSupported && !_isFullScreen;
  }

  ///Handle VideoEvent when remote controls notification / PiP is shown
  Future<void> _handleVideoEvent(VideoEvent event) async {
    final sourceParameters = <String, dynamic>{if (event.key != null) _sourceKeyParameter: event.key};
    switch (event.eventType) {
      case VideoEventType.play:
        _postEvent(BetterPlayerEvent(BetterPlayerEventType.play, parameters: sourceParameters));
      case VideoEventType.pause:
        _postEvent(BetterPlayerEvent(BetterPlayerEventType.pause, parameters: sourceParameters));
      case VideoEventType.seek:
        _postEvent(BetterPlayerEvent(BetterPlayerEventType.seekTo, parameters: sourceParameters));
      case VideoEventType.completed:
        final VideoPlayerValue? videoValue = videoPlayerController?.value;
        _postEvent(
          BetterPlayerEvent(
            BetterPlayerEventType.finished,
            parameters: <String, dynamic>{
              _progressParameter: videoValue?.position,
              _durationParameter: videoValue?.duration,
            },
          ),
        );
      case VideoEventType.preRollEnded:
        _postEvent(BetterPlayerEvent(BetterPlayerEventType.preRollEnded, parameters: sourceParameters));
      case VideoEventType.bufferingStart:
        _postEvent(BetterPlayerEvent(BetterPlayerEventType.bufferingStart, parameters: sourceParameters));
      case VideoEventType.bufferingUpdate:
        _postEvent(
          BetterPlayerEvent(
            BetterPlayerEventType.bufferingUpdate,
            parameters: <String, dynamic>{...sourceParameters, _bufferedParameter: event.buffered},
          ),
        );
      case VideoEventType.bufferingEnd:
        _postEvent(BetterPlayerEvent(BetterPlayerEventType.bufferingEnd, parameters: sourceParameters));
      default:

        ///TODO: Handle when needed
        break;
    }
  }

  ///Setup controls always visible mode
  void setControlsAlwaysVisible(bool controlsAlwaysVisible) {
    _controlsAlwaysVisible = controlsAlwaysVisible;
    _controlsVisibilityStreamController.add(controlsAlwaysVisible);
  }

  ///Retry data source if playback failed.
  Future retryDataSource() async {
    final generation = _dataSourceSetupGeneration;
    final savedValue = _videoPlayerValueOnError;
    final isLive = _betterPlayerDataSource?.liveStream == true;
    final position = !isLive ? savedValue?.position : null;
    final resume = savedValue == null || !savedValue.initialized
        ? betterPlayerConfiguration.autoPlay
        : savedValue.isPlaying;
    await _setupDataSource(
      _betterPlayerDataSource!,
      initialPosition: position,
      setupGeneration: generation,
      resumePlayback: resume,
    );
    if (_disposed || generation != _dataSourceSetupGeneration) return;
  }

  void _scheduleNetworkRecovery() {
    if (_disposed ||
        _betterPlayerDataSource?.type != BetterPlayerDataSourceType.network ||
        videoPlayerController?.value.isErrorRecoverable == false ||
        _networkRecoveryAttempts >= _networkRecoveryDelays.length ||
        _networkRecoveryInProgress ||
        _networkRecoveryTimer?.isActive == true) {
      return;
    }
    final delay = _networkRecoveryDelays[_networkRecoveryAttempts];
    _networkRecoveryTimer = Timer(delay, () {
      _networkRecoveryTimer = null;
      unawaited(_attemptNetworkRecovery());
    });
  }

  Future<void> _attemptNetworkRecovery() async {
    if (_disposed ||
        _networkRecoveryInProgress ||
        _betterPlayerDataSource?.type != BetterPlayerDataSourceType.network ||
        videoPlayerController?.value.isErrorRecoverable == false ||
        _networkRecoveryAttempts >= _networkRecoveryDelays.length ||
        _betterPlayerDataSource?.liveStream == true) {
      return;
    }
    _networkRecoveryInProgress = true;
    final generation = _dataSourceSetupGeneration;
    _networkRecoveryAttempts++;
    try {
      await retryDataSource();
    } catch (error) {
      BetterPlayerUtils.log('Network playback recovery failed: $error');
    } finally {
      _networkRecoveryInProgress = false;
      final value = videoPlayerController?.value;
      if (!_disposed &&
          generation == _dataSourceSetupGeneration &&
          (value == null || value.hasError || !value.initialized)) {
        _scheduleNetworkRecovery();
      }
    }
  }

  void _cancelNetworkRecovery({required bool clearSavedPosition}) {
    _networkRecoveryTimer?.cancel();
    _networkRecoveryTimer = null;
    if (clearSavedPosition) {
      _videoPlayerValueOnError = null;
      _networkRecoveryAttempts = 0;
    }
  }

  ///Set [audioTrack] in player. Works only for HLS or DASH streams.
  void setAudioTrack(BetterPlayerAsmsAudioTrack audioTrack) {
    if (videoPlayerController == null) {
      throw StateError('The data source has not been initialized');
    }

    if (audioTrack.language == null) {
      _betterPlayerAsmsAudioTrack = null;
      return;
    }

    _betterPlayerAsmsAudioTrack = audioTrack;
    videoPlayerController!.setAudioTrack(audioTrack.label, audioTrack.id);
  }

  ///Enable or disable audio mixing with other sound within device.
  void setMixWithOthers(bool mixWithOthers) {
    if (videoPlayerController == null) {
      throw StateError('The data source has not been initialized');
    }

    videoPlayerController!.setMixWithOthers(mixWithOthers);
  }

  ///Clear all cached data. Video player controller must be initialized to
  ///clear the cache.
  Future<void> clearCache() async => VideoPlayerController.clearCache();

  ///Build headers map that will be used to setup video player controller. Apply
  ///DRM headers if available.
  Map<String, String?> _getHeaders([BetterPlayerDataSource? source]) {
    final dataSource = source ?? _betterPlayerDataSource;
    if (dataSource == null) return <String, String?>{};
    final headers = <String, String?>{...?dataSource.headers};
    if (dataSource.drmConfiguration?.drmType == BetterPlayerDrmType.token &&
        dataSource.drmConfiguration?.token != null) {
      headers[_authorizationHeader] = dataSource.drmConfiguration!.token!;
    }
    return headers;
  }

  ///PreCache a video. On Android, the future succeeds when
  ///the requested size, specified in
  ///[BetterPlayerCacheConfiguration.preCacheSize], is downloaded or when the
  ///complete file is downloaded if the file is smaller than the requested size.
  ///On iOS, the whole file will be downloaded, since [maxCacheFileSize] is
  ///currently not supported on iOS. On iOS, the video format must be in this
  ///list: https://github.com/sendyhalim/Swime/blob/master/Sources/MimeType.swift
  Future<void> preCache(BetterPlayerDataSource betterPlayerDataSource) async {
    final cacheConfig =
        betterPlayerDataSource.cacheConfiguration ?? const BetterPlayerCacheConfiguration(useCache: true);

    final dataSource = DataSource(
      sourceType: DataSourceType.network,
      uri: betterPlayerDataSource.url,
      useCache: true,
      headers: betterPlayerDataSource.headers,
      maxCacheSize: cacheConfig.maxCacheSize,
      maxCacheFileSize: cacheConfig.maxCacheFileSize,
      cacheKey: cacheConfig.key,
      videoExtension: betterPlayerDataSource.videoExtension,
    );

    return VideoPlayerController.preCache(dataSource, cacheConfig.preCacheSize);
  }

  ///Stop pre cache for given [betterPlayerDataSource]. If there was no pre
  ///cache started for given [betterPlayerDataSource] then it will be ignored.
  Future<void> stopPreCache(BetterPlayerDataSource betterPlayerDataSource) async =>
      VideoPlayerController.stopPreCache(betterPlayerDataSource.url, betterPlayerDataSource.cacheConfiguration?.key);

  /// Sets the new [betterPlayerControlsConfiguration] instance in the
  /// controller.
  void setBetterPlayerControlsConfiguration(BetterPlayerControlsConfiguration betterPlayerControlsConfiguration) {
    _betterPlayerControlsConfiguration = betterPlayerControlsConfiguration;
  }

  /// Add controller internal event.
  void _postControllerEvent(BetterPlayerControllerEvent event) {
    if (!_controllerEventStreamController.isClosed) {
      _controllerEventStreamController.add(event);
    }
  }

  ///Dispose BetterPlayerController. When [forceDispose] parameter is true, then
  ///autoDispose parameter will be overridden and controller will be disposed
  ///(if it wasn't disposed before).
  void dispose({bool forceDispose = false}) {
    if (!betterPlayerConfiguration.autoDispose && !forceDispose) {
      return;
    }
    if (!_disposed) {
      _subtitleLoadGeneration++;
      if (videoPlayerController != null) {
        pause();
        videoPlayerController!.removeListener(_onFullScreenStateChanged);
        videoPlayerController!.removeListener(_onVideoPlayerChanged);
        videoPlayerController!.dispose();
      }
      _eventListeners.clear();
      _nextVideoTimer?.cancel();
      _cancelNetworkRecovery(clearSavedPosition: true);
      _nextVideoTimeStreamController.close();
      _controlsVisibilityStreamController.close();
      _subtitleOffsetNotifier.dispose();
      _videoEventStreamSubscription?.cancel();
      _disposed = true;
      _controllerEventStreamController.close();

      ///Delete files async
      for (final file in _tempFiles) {
        file.delete();
      }
    }
  }
}
