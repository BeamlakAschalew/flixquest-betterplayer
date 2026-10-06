import 'dart:math';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/core/better_player_utils.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Shared behaviour for the phone controls, and the dark panels they open.
abstract class BetterPlayerControlsState<T extends StatefulWidget> extends State<T> {
  static const int _bufferingInterval = 20000;

  BetterPlayerController? get betterPlayerController;

  BetterPlayerControlsConfiguration get betterPlayerControlsConfiguration;

  VideoPlayerValue? get latestValue;

  bool controlsNotVisible = true;

  void cancelAndRestartTimer();

  BetterPlayerControlsStrings get strings => betterPlayerControlsConfiguration.strings;

  bool isVideoFinished(VideoPlayerValue? value) =>
      value?.position != null &&
      value?.duration != null &&
      value!.position.inMilliseconds != 0 &&
      value.duration!.inMilliseconds != 0 &&
      value.position >= value.duration!;

  void skipBack() {
    if (latestValue == null) return;
    cancelAndRestartTimer();
    final target = max(
      0,
      (latestValue!.position - Duration(milliseconds: betterPlayerControlsConfiguration.backwardSkipTimeInMilliseconds))
          .inMilliseconds,
    );
    betterPlayerController!.seekTo(Duration(milliseconds: target));
  }

  void skipForward() {
    if (latestValue?.duration == null) return;
    cancelAndRestartTimer();
    final target = min(
      latestValue!.duration!.inMilliseconds,
      (latestValue!.position + Duration(milliseconds: betterPlayerControlsConfiguration.forwardSkipTimeInMilliseconds))
          .inMilliseconds,
    );
    betterPlayerController!.seekTo(Duration(milliseconds: target));
  }

  /// The More panel. With [includeBarActions] it also carries what the
  /// narrow layout leaves off its own bar: speed, audio and subtitles,
  /// quality, episodes and the app's quick actions.
  void onShowMoreClicked({bool includeBarActions = false}) {
    final configuration = betterPlayerControlsConfiguration;
    final live = betterPlayerController!.isLiveStream();
    final items = <_PlayerMenuItem>[
      if (includeBarActions && configuration.enableEpisodeSelection && configuration.onEpisodeListTap != null)
        _PlayerMenuItem(
          icon: PhosphorIcons.cardsThree(),
          title: strings.episodes,
          onTap: () => configuration.onEpisodeListTap!(),
        ),
      if (includeBarActions &&
          configuration.enableMovieRecommendations &&
          configuration.onMovieRecommendationsTap != null)
        _PlayerMenuItem(
          icon: PhosphorIcons.squaresFour(),
          title: strings.moreLikeThis,
          onTap: () => configuration.onMovieRecommendationsTap!(),
        ),
      if (includeBarActions && configuration.onNextEpisodeTap != null)
        _PlayerMenuItem(
          icon: PhosphorIcons.skipForward(),
          title: strings.nextEpisode,
          onTap: configuration.onNextEpisodeTap!,
        ),
      if (includeBarActions)
        for (final action in configuration.quickActions)
          _PlayerMenuItem(icon: action.icon, title: action.title, onTap: () => action.onClicked()),
      if (configuration.enablePlaybackSpeed && !live)
        _PlayerMenuItem(
          icon: configuration.playbackSpeedIcon,
          title: strings.playbackSpeed,
          value: BetterPlayerSpeedSelector.format(betterPlayerController!.videoPlayerController?.value.speed ?? 1),
          onTap: showSpeedSelection,
        ),
      if (configuration.enableSubtitles && (includeBarActions || !configuration.showSubtitlesButton))
        _PlayerMenuItem(
          icon: configuration.subtitlesIcon,
          title: audioAndSubtitlesLabel,
          value: _selectedSubtitleLabel(),
          onTap: openAudioAndSubtitles,
        ),
      if (configuration.enableQualities && (includeBarActions || !configuration.showQualitiesButton))
        _PlayerMenuItem(
          icon: configuration.qualitiesIcon,
          title: strings.quality,
          value: _selectedQualityLabel(),
          onTap: _showQualitiesSelectionWidget,
        ),
      if (configuration.enableCrop)
        _PlayerMenuItem(
          icon: configuration.cropIcon,
          title: strings.cropAndFit,
          value: _cropLabel(betterPlayerController!.getFit()),
          onTap: showCropSelection,
        ),
      if (configuration.enableDownloadButton && configuration.onDownloadTap != null)
        _PlayerMenuItem(icon: configuration.downloadIcon, title: strings.download, onTap: configuration.onDownloadTap!),
      ...configuration.overflowMenuCustomItems.map(
        (item) => _PlayerMenuItem(icon: item.icon, title: item.title, onTap: () => item.onClicked()),
      ),
    ];
    showPanel(
      title: strings.more,
      subtitle: configuration.name.isEmpty ? null : configuration.name,
      child: _panelList([
        for (final item in items)
          BetterPlayerMenuRow(
            icon: item.icon,
            title: item.title,
            value: item.value,
            onTap: () {
              _closeSheet();
              item.onTap();
            },
          ),
      ]),
    );
  }

  /// What the audio-and-subtitles control is called: both only when there
  /// is more than one soundtrack to choose between.
  String get audioAndSubtitlesLabel => _hasAudioChoice ? strings.audioAndSubtitles : strings.subtitles;

  /// A track's language as the app wants it shown; the raw label when the app
  /// did not ask for anything.
  String _languageLabel(String? label) {
    final text = label?.trim() ?? '';
    if (text.isEmpty) return '';
    return betterPlayerControlsConfiguration.languageLabelBuilder?.call(text) ?? text;
  }

  String _audioTrackLabel(BetterPlayerAsmsAudioTrack track, int index) {
    final label = _languageLabel(track.label);
    if (label.isNotEmpty) return label;
    final language = _languageLabel(track.language);
    return language.isNotEmpty ? language : '${strings.audio} ${index + 1}';
  }

  bool get _hasAudioChoice =>
      betterPlayerControlsConfiguration.enableAudioTracks &&
      (betterPlayerController?.betterPlayerAsmsAudioTracks?.length ?? 0) > 1;

  /// The app's own subtitle chooser when it has one, the package's otherwise.
  void openAudioAndSubtitles() {
    final callback = betterPlayerControlsConfiguration.onSubtitlesTap;
    cancelAndRestartTimer();
    if (callback != null) {
      callback();
      return;
    }
    _showAudioAndSubtitlesPanel();
  }

  ///Shows the package subtitle selector from a dedicated player control.
  void showSubtitlesSelection() {
    cancelAndRestartTimer();
    _showAudioAndSubtitlesPanel();
  }

  ///Shows the package quality selector from a dedicated player control.
  void showQualitiesSelection() {
    cancelAndRestartTimer();
    _showQualitiesSelectionWidget();
  }

  /// Speeds as stops along a line.
  void showSpeedSelection() {
    cancelAndRestartTimer();
    final speeds =
        betterPlayerControlsConfiguration.playbackSpeeds.where((speed) => speed > 0 && speed <= 2).toSet().toList()
          ..sort();
    final current = betterPlayerController!.videoPlayerController?.value.speed ?? 1;
    showPanel(
      title: strings.playbackSpeed,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
        child: speeds.isEmpty
            ? BetterPlayerEmptyState(icon: PhosphorIcons.gauge(), title: strings.normalSpeed)
            : BetterPlayerSpeedSelector(
                speeds: speeds,
                selected: current,
                normalLabel: strings.normalSpeed,
                // The panel stays open while the stops are dragged through.
                onSelected: (speed) {
                  betterPlayerController!.setSpeed(speed);
                },
              ),
      ),
    );
  }

  ///Shows video layout choices without interrupting playback.
  void showCropSelection() {
    cancelAndRestartTimer();
    final controller = betterPlayerController!;
    final current = controller.getFit();
    final modes = <({BoxFit fit, String title, String subtitle})>[
      (fit: BoxFit.contain, title: strings.fit, subtitle: strings.fitDescription),
      (fit: BoxFit.cover, title: strings.cropToFill, subtitle: strings.cropToFillDescription),
      (fit: BoxFit.fill, title: strings.stretch, subtitle: strings.stretchDescription),
    ];
    showPanel(
      title: strings.cropAndFit,
      child: _panelList(
        modes
            .map(
              (mode) => BetterPlayerSelectionTile(
                title: mode.title,
                subtitle: mode.subtitle,
                selected: mode.fit == current,
                onTap: () {
                  _closeSheet();
                  controller.setOverriddenFit(mode.fit);
                },
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  String _cropLabel(BoxFit fit) => switch (fit) {
    BoxFit.cover => strings.cropToFill,
    BoxFit.fill => strings.stretch,
    _ => strings.fit,
  };

  bool isLoading(VideoPlayerValue? value) {
    if (value == null) return false;
    if (value.duration == null && (!value.isPlaying || value.isBuffering)) return true;
    final bufferedEnd = value.buffered.isNotEmpty ? value.buffered.last.end : null;
    return bufferedEnd != null &&
        value.isPlaying &&
        value.isBuffering &&
        (bufferedEnd - value.position).inMilliseconds < _bufferingInterval;
  }

  /// Audio on one side and subtitles on the other, as two columns when there
  /// is room and one list when there isn't. Audio is left out when there is
  /// only one soundtrack.
  void _showAudioAndSubtitlesPanel() {
    final controller = betterPlayerController!;
    final subtitles = <BetterPlayerSubtitlesSource>[
      BetterPlayerSubtitlesSource(type: BetterPlayerSubtitlesSourceType.none),
      ...controller.betterPlayerSubtitlesSourceList.where(
        (source) => source.type != BetterPlayerSubtitlesSourceType.none,
      ),
    ];
    final selectedSubtitle = controller.betterPlayerSubtitlesSource;
    bool isSelectedSubtitle(BetterPlayerSubtitlesSource source) => source.type == BetterPlayerSubtitlesSourceType.none
        ? selectedSubtitle == null || selectedSubtitle.type == BetterPlayerSubtitlesSourceType.none
        : identical(source, selectedSubtitle) || source == selectedSubtitle;
    final subtitleTiles = <Widget>[
      for (final (index, source) in subtitles.indexed)
        BetterPlayerSelectionTile(
          title: source.type == BetterPlayerSubtitlesSourceType.none
              ? strings.off
              : source.name?.trim().isNotEmpty == true
              ? _languageLabel(source.name)
              : '${strings.subtitles} $index',
          selected: isSelectedSubtitle(source),
          onTap: () async {
            await controller.selectSubtitlesSource(source);
            if (mounted) _closeSheet();
          },
        ),
    ];
    final tracks = controller.betterPlayerAsmsAudioTracks ?? const <BetterPlayerAsmsAudioTrack>[];
    final selectedTrack = controller.betterPlayerAsmsAudioTrack;
    final audioTiles = <Widget>[
      for (final (index, track) in tracks.indexed)
        BetterPlayerSelectionTile(
          title: _audioTrackLabel(track, index),
          subtitle: track.language?.trim().isNotEmpty == true && track.label?.trim().isNotEmpty == true
              ? _languageLabel(track.language)
              : null,
          selected: selectedTrack == track || (selectedTrack == null && track.isDefault),
          onTap: () {
            _closeSheet();
            controller.setAudioTrack(track);
          },
        ),
    ];
    final withAudio = _hasAudioChoice && audioTiles.isNotEmpty;
    showPanel(
      title: withAudio ? strings.audioAndSubtitles : strings.subtitles,
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (!withAudio) return _panelList(subtitleTiles);
          if (constraints.maxWidth >= 520) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _panelColumn(strings.audio, audioTiles)),
                  const SizedBox(width: 12),
                  Expanded(child: _panelColumn(strings.subtitles, subtitleTiles)),
                ],
              ),
            );
          }
          return _panelList([
            BetterPlayerPanelSectionTitle(strings.audio),
            ...audioTiles,
            const SizedBox(height: 16),
            BetterPlayerPanelSectionTitle(strings.subtitles),
            ...subtitleTiles,
          ]);
        },
      ),
    );
  }

  Widget _panelColumn(String title, List<Widget> tiles) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      BetterPlayerPanelSectionTitle(title),
      Flexible(
        child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: tiles),
      ),
    ],
  );

  void _showQualitiesSelectionWidget() {
    final controller = betterPlayerController!;
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: controller.betterPlayerConfiguration.useRootNavigator,
      useSafeArea: true,
      showDragHandle: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetContext) => Theme(
        data: betterPlayerPanelTheme(Theme.of(context)),
        child: ListenableBuilder(
          // The decoded size changes as the stream adapts to the network.
          listenable: controller.videoPlayerController ?? ValueNotifier<int>(0),
          builder: (_, _) {
            final items = _qualityItems();
            return BetterPlayerModalSheet(
              title: strings.quality,
              subtitle: _selectedQualityLabel(),
              closeLabel: strings.close,
              child: items.isEmpty
                  ? BetterPlayerEmptyState(icon: PhosphorIcons.monitorPlay(), title: _selectedQualityLabel())
                  : _panelList(items),
            );
          },
        ),
      ),
    );
  }

  bool _isAutomaticTrack(BetterPlayerAsmsTrack track) => track.height == 0 && track.width == 0 && track.bitrate == 0;

  static final RegExp _autoSourceName = RegExp(r'^\s*auto(?:matic)?\b', caseSensitive: false);

  /// A provider source that is itself an adaptive playlist ("Auto ...").
  bool get _providerAutoActive {
    final controller = betterPlayerController!;
    final name = controller.betterPlayerResolutionName;
    if (name == null || name.trim().isEmpty) return false;
    final displayName = controller.betterPlayerDataSource?.resolutionDisplayNames?[name] ?? name;
    return _autoSourceName.hasMatch(displayName);
  }

  bool get _autoQualityActive {
    final controller = betterPlayerController!;
    if (_providerAutoActive) return true;
    if (controller.betterPlayerResolutionName?.trim().isNotEmpty == true) return false;
    final track = controller.betterPlayerAsmsTrack;
    return track == null || _isAutomaticTrack(track);
  }

  List<Widget> _qualityItems() {
    final controller = betterPlayerController!;
    final names = controller.betterPlayerDataSource?.asmsTrackNames ?? const <String>[];
    final tracks = controller.betterPlayerAsmsTracks;
    final sourceSelected = controller.betterPlayerResolutionName?.trim().isNotEmpty == true;
    final autoActive = _autoQualityActive;
    final hasAutoTrack = tracks.any(_isAutomaticTrack);

    final streamItems = <Widget>[];
    for (var index = 0; index < tracks.length; index++) {
      final track = tracks[index];
      final automatic = _isAutomaticTrack(track);
      // A provider "Auto" source already stands for adaptive playback, so the
      // stream's own Auto row would be a second, identical choice.
      if (automatic && _providerAutoActive) continue;
      if (!automatic && autoActive && hasAutoTrack) continue;
      final detectedHeight = BetterPlayerUtils.detectedVideoHeight(controller.videoPlayerController?.value.size);
      final label = automatic
          ? controller.translations.qualityAuto
          : index < names.length && names[index].trim().isNotEmpty
          ? names[index]
          : _qualityLabel(track);
      final selected = !sourceSelected && (automatic ? autoActive : controller.betterPlayerAsmsTrack == track);
      streamItems.add(
        BetterPlayerSelectionTile(
          title: label,
          subtitle: automatic
              ? [if (detectedHeight != null) '${detectedHeight}p', strings.qualityAutoNote].join(' • ')
              : _qualityDetails(track),
          selected: selected,
          onTap: () {
            _closeSheet();
            controller.setTrack(track);
          },
        ),
      );
    }
    final sourceItems = <Widget>[];
    controller.betterPlayerDataSource?.resolutions?.forEach((name, url) {
      final selected = name == controller.betterPlayerResolutionName;
      final detectedDetails = selected ? _detectedQualityDetails() : null;
      final displayName = controller.betterPlayerDataSource?.resolutionDisplayNames?[name] ?? name;
      final description = controller.betterPlayerDataSource?.resolutionDescriptions?[name];
      final subtitleParts = <String>[
        if (description?.trim().isNotEmpty == true) description!.trim(),
        if (BetterPlayerUtils.resolutionHeightFromLabel(displayName) == null && detectedDetails != null)
          detectedDetails,
      ];
      sourceItems.add(
        BetterPlayerSelectionTile(
          title: displayName,
          subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(' • '),
          selected: selected,
          onTap: () {
            _closeSheet();
            controller.setResolution(url, name: name);
          },
        ),
      );
    });

    if (streamItems.isNotEmpty && sourceItems.isNotEmpty) {
      return [
        BetterPlayerPanelSectionTitle(strings.qualityResolution),
        ...streamItems,
        const SizedBox(height: 12),
        BetterPlayerPanelSectionTitle('Sources'),
        ...sourceItems,
      ];
    }
    return [...streamItems, ...sourceItems];
  }

  String? _selectedSubtitleLabel() {
    final source = betterPlayerController!.betterPlayerSubtitlesSource;
    if (source == null || source.type == BetterPlayerSubtitlesSourceType.none) {
      return strings.off;
    }
    final name = _languageLabel(source.name);
    return name.isNotEmpty ? name : betterPlayerController!.translations.generalDefault;
  }

  String _selectedQualityLabel() {
    final detectedHeight = BetterPlayerUtils.detectedVideoHeight(
      betterPlayerController!.videoPlayerController?.value.size,
    );
    final resolutionName = betterPlayerController!.betterPlayerResolutionName;
    if (resolutionName?.trim().isNotEmpty == true) {
      final displayName =
          betterPlayerController!.betterPlayerDataSource?.resolutionDisplayNames?[resolutionName] ?? resolutionName!;
      if (detectedHeight != null && BetterPlayerUtils.resolutionHeightFromLabel(displayName) == null) {
        return '${displayName.trim()} • ${detectedHeight}p';
      }
      return displayName.trim();
    }
    final track = betterPlayerController!.betterPlayerAsmsTrack;
    if (track == null || (track.height == 0 && track.width == 0 && track.bitrate == 0)) {
      final auto = betterPlayerController!.translations.qualityAuto;
      return detectedHeight == null ? auto : '$auto • ${detectedHeight}p';
    }
    return _qualityLabel(track);
  }

  String? _detectedQualityDetails() {
    final size = betterPlayerController!.videoPlayerController?.value.size;
    final height = BetterPlayerUtils.detectedVideoHeight(size);
    final dimensions = BetterPlayerUtils.detectedVideoDimensions(size);
    if (height == null || dimensions == null) return null;
    return 'Detected ${height}p • $dimensions';
  }

  String _qualityLabel(BetterPlayerAsmsTrack track) {
    if ((track.height ?? 0) > 0) return '${track.height}p';
    if ((track.width ?? 0) > 0) return '${track.width}px';
    return betterPlayerController!.translations.qualityAuto;
  }

  String? _qualityDetails(BetterPlayerAsmsTrack track) {
    final details = <String>[
      if ((track.width ?? 0) > 0 && (track.height ?? 0) > 0) '${track.width}×${track.height}',
      if ((track.bitrate ?? 0) > 0) BetterPlayerUtils.formatBitrate(track.bitrate!),
      if (track.codecs?.trim().isNotEmpty == true) track.codecs!.trim(),
      if (track.mimeType?.trim().isNotEmpty == true) track.mimeType!.replaceFirst('video/', ''),
    ];
    return details.isEmpty ? null : details.join(' • ');
  }

  Widget _panelList(List<Widget> children) => ListView.separated(
    shrinkWrap: true,
    padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
    itemCount: children.length,
    separatorBuilder: (_, _) => const SizedBox(height: 2),
    itemBuilder: (_, index) => children[index],
  );

  void _closeSheet() {
    Navigator.of(
      context,
      rootNavigator: betterPlayerController?.betterPlayerConfiguration.useRootNavigator ?? false,
    ).pop();
  }

  /// A dark panel over the picture, whatever the app's theme.
  void showPanel({required String title, required Widget child, String? subtitle}) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: betterPlayerController?.betterPlayerConfiguration.useRootNavigator ?? false,
      useSafeArea: true,
      showDragHandle: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetContext) => Theme(
        data: betterPlayerPanelTheme(Theme.of(context)),
        child: BetterPlayerModalSheet(title: title, subtitle: subtitle, closeLabel: strings.close, child: child),
      ),
    );
  }

  ///Preserves ambient directionality so selectors and labels support RTL.
  Widget buildLTRDirectionality(Widget child) => child;

  void changePlayerControlsNotVisible(bool notVisible) {
    setState(() {
      if (notVisible) {
        betterPlayerController?.postEvent(BetterPlayerEvent(BetterPlayerEventType.controlsHiddenStart));
      }
      controlsNotVisible = notVisible;
    });
  }
}

class _PlayerMenuItem {
  const _PlayerMenuItem({required this.icon, required this.title, required this.onTap, this.value});

  final IconData icon;
  final String title;
  final String? value;
  final VoidCallback onTap;
}
