import 'dart:math';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:better_player_plus/src/controls/better_player_ui.dart';
import 'package:better_player_plus/src/core/better_player_utils.dart';
import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Shared behavior and modern modal presentation for player controls.
abstract class BetterPlayerControlsState<T extends StatefulWidget> extends State<T> {
  static const int _bufferingInterval = 20000;

  BetterPlayerController? get betterPlayerController;

  BetterPlayerControlsConfiguration get betterPlayerControlsConfiguration;

  VideoPlayerValue? get latestValue;

  bool controlsNotVisible = true;

  void cancelAndRestartTimer();

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

  void onShowMoreClicked() {
    final translations = betterPlayerController!.translations;
    final items = <_PlayerMenuItem>[
      if (betterPlayerControlsConfiguration.enablePlaybackSpeed)
        _PlayerMenuItem(
          icon: betterPlayerControlsConfiguration.playbackSpeedIcon,
          title: translations.overflowMenuPlaybackSpeed,
          subtitle: '${betterPlayerController!.videoPlayerController?.value.speed ?? 1}×',
          onTap: _showSpeedChooserWidget,
        ),
      if (betterPlayerControlsConfiguration.enableSubtitles)
        _PlayerMenuItem(
          icon: betterPlayerControlsConfiguration.subtitlesIcon,
          title: translations.overflowMenuSubtitles,
          subtitle: _selectedSubtitleLabel(),
          onTap: _showSubtitlesSelectionWidget,
        ),
      if (betterPlayerControlsConfiguration.enableQualities)
        _PlayerMenuItem(
          icon: betterPlayerControlsConfiguration.qualitiesIcon,
          title: translations.overflowMenuQuality,
          subtitle: _selectedQualityLabel(),
          onTap: _showQualitiesSelectionWidget,
        ),
      if (betterPlayerControlsConfiguration.enableAudioTracks)
        _PlayerMenuItem(
          icon: betterPlayerControlsConfiguration.audioTracksIcon,
          title: translations.overflowMenuAudioTracks,
          subtitle: _selectedAudioLabel(),
          onTap: _showAudioTracksSelectionWidget,
        ),
      ...betterPlayerControlsConfiguration.overflowMenuCustomItems.map(
        (item) => _PlayerMenuItem(icon: item.icon, title: item.title, onTap: item.onClicked),
      ),
    ];
    _showSheet(
      icon: PhosphorIcons.slidersHorizontal(),
      title: 'Player settings',
      subtitle: betterPlayerControlsConfiguration.name.isEmpty ? null : betterPlayerControlsConfiguration.name,
      child: _selectionList(
        items
            .map(
              (item) => BetterPlayerSelectionTile(
                icon: item.icon,
                title: item.title,
                subtitle: item.subtitle,
                onTap: () {
                  _closeSheet();
                  item.onTap();
                },
              ),
            )
            .toList(),
      ),
    );
  }

  void _showSpeedChooserWidget() {
    final speeds =
        betterPlayerControlsConfiguration.playbackSpeeds.where((speed) => speed > 0 && speed <= 2).toSet().toList()
          ..sort();
    final current = betterPlayerController!.videoPlayerController?.value.speed ?? 1;
    _showSheet(
      icon: betterPlayerControlsConfiguration.playbackSpeedIcon,
      title: betterPlayerController!.translations.overflowMenuPlaybackSpeed,
      subtitle: '${current.toStringAsFixed(current % 1 == 0 ? 0 : 2)}×',
      child: speeds.isEmpty
          ? BetterPlayerEmptyState(icon: PhosphorIcons.gauge(), title: betterPlayerController!.translations.generalNone)
          : _selectionList(
              speeds
                  .map(
                    (speed) => BetterPlayerSelectionTile(
                      icon: speed == 1 ? PhosphorIcons.play() : PhosphorIcons.gauge(),
                      title: '${speed.toStringAsFixed(speed % 1 == 0 ? 0 : 2)}×',
                      subtitle: speed == 1 ? betterPlayerController!.translations.generalDefault : null,
                      selected: current == speed,
                      onTap: () {
                        _closeSheet();
                        betterPlayerController!.setSpeed(speed);
                      },
                    ),
                  )
                  .toList(),
            ),
    );
  }

  bool isLoading(VideoPlayerValue? value) {
    if (value == null) return false;
    if (!value.isPlaying && value.duration == null) return true;
    final bufferedEnd = value.buffered.isNotEmpty ? value.buffered.last.end : null;
    return bufferedEnd != null &&
        value.isPlaying &&
        value.isBuffering &&
        (bufferedEnd - value.position).inMilliseconds < _bufferingInterval;
  }

  void _showSubtitlesSelectionWidget() {
    final subtitles = List<BetterPlayerSubtitlesSource>.of(betterPlayerController!.betterPlayerSubtitlesSourceList);
    if (subtitles.firstWhereOrNull((source) => source.type == BetterPlayerSubtitlesSourceType.none) == null) {
      subtitles.add(BetterPlayerSubtitlesSource(type: BetterPlayerSubtitlesSourceType.none));
    }
    final selected = betterPlayerController!.betterPlayerSubtitlesSource;
    _showSheet(
      icon: betterPlayerControlsConfiguration.subtitlesIcon,
      title: betterPlayerController!.translations.overflowMenuSubtitles,
      subtitle: _selectedSubtitleLabel(),
      child: _selectionList(
        subtitles.asMap().entries.map((entry) {
          final index = entry.key;
          final source = entry.value;
          final off = source.type == BetterPlayerSubtitlesSourceType.none;
          final isSelected =
              identical(source, selected) ||
              source == selected ||
              (off && selected?.type == BetterPlayerSubtitlesSourceType.none);
          final title = off
              ? betterPlayerController!.translations.generalNone
              : source.name?.trim().isNotEmpty == true
              ? source.name!.trim()
              : betterPlayerController!.translations.generalDefault;
          final typeLabel = off ? null : '${source.type?.name ?? 'subtitle'} • ${index + 1}';
          return BetterPlayerSelectionTile(
            icon: off
                ? PhosphorIcons.subtitlesSlash()
                : isSelected
                ? PhosphorIcons.closedCaptioning(PhosphorIconsStyle.fill)
                : PhosphorIcons.closedCaptioning(),
            title: title,
            subtitle: typeLabel,
            selected: isSelected,
            onTap: () async {
              await betterPlayerController!.setupSubtitleSource(source);
              if (mounted) _closeSheet();
            },
          );
        }).toList(),
      ),
    );
  }

  void _showQualitiesSelectionWidget() {
    final items = <Widget>[];
    final names = betterPlayerController!.betterPlayerDataSource?.asmsTrackNames ?? const <String>[];
    final tracks = betterPlayerController!.betterPlayerAsmsTracks;
    for (var index = 0; index < tracks.length; index++) {
      final track = tracks[index];
      final automatic = track.height == 0 && track.width == 0 && track.bitrate == 0;
      final currentSize = betterPlayerController?.videoPlayerController?.value.size;
      final currentHeight = currentSize?.height.toInt() ?? 0;
      final currentWidth = currentSize?.width.toInt() ?? 0;
      final label = automatic
          ? betterPlayerController!.translations.qualityAuto
          : index < names.length && names[index].trim().isNotEmpty
          ? names[index]
          : _qualityLabel(track);
      final selected = betterPlayerController!.betterPlayerAsmsTrack == track;
      items.add(
        BetterPlayerSelectionTile(
          icon: automatic
              ? PhosphorIcons.magicWand()
              : selected
              ? PhosphorIcons.monitorPlay(PhosphorIconsStyle.fill)
              : PhosphorIcons.monitorPlay(),
          title: label,
          subtitle: automatic ? (currentHeight > 0 ? '$currentWidth×$currentHeight' : null) : _qualityDetails(track),
          selected: selected,
          onTap: () {
            _closeSheet();
            betterPlayerController!.setTrack(track);
          },
        ),
      );
    }
    if (tracks.isEmpty) {
      betterPlayerController!.betterPlayerDataSource?.resolutions?.forEach((name, url) {
        final selected = name == betterPlayerController!.betterPlayerResolutionName;
        final detectedDetails = selected ? _detectedQualityDetails() : null;
        items.add(
          BetterPlayerSelectionTile(
            icon: selected ? PhosphorIcons.monitorPlay(PhosphorIconsStyle.fill) : PhosphorIcons.monitorPlay(),
            title: name,
            subtitle: BetterPlayerUtils.resolutionHeightFromLabel(name) == null ? detectedDetails : null,
            selected: selected,
            onTap: () {
              _closeSheet();
              betterPlayerController!.setResolution(url, name: name);
            },
          ),
        );
      });
    }
    _showSheet(
      icon: betterPlayerControlsConfiguration.qualitiesIcon,
      title: betterPlayerController!.translations.overflowMenuQuality,
      subtitle: _selectedQualityLabel(),
      child: items.isEmpty
          ? BetterPlayerEmptyState(icon: PhosphorIcons.monitorPlay(), title: _selectedQualityLabel())
          : _selectionList(items),
    );
  }

  void _showAudioTracksSelectionWidget() {
    final tracks = betterPlayerController!.betterPlayerAsmsAudioTracks ?? const <BetterPlayerAsmsAudioTrack>[];
    final selected = betterPlayerController!.betterPlayerAsmsAudioTrack;
    _showSheet(
      icon: betterPlayerControlsConfiguration.audioTracksIcon,
      title: betterPlayerController!.translations.overflowMenuAudioTracks,
      subtitle: _selectedAudioLabel(),
      child: tracks.isEmpty
          ? BetterPlayerEmptyState(
              icon: PhosphorIcons.waveform(),
              title: betterPlayerController!.translations.generalDefault,
            )
          : _selectionList(
              tracks.asMap().entries.map((entry) {
                final index = entry.key;
                final track = entry.value;
                final isSelected = selected == track || (selected == null && track.isDefault);
                final label = track.label?.trim().isNotEmpty == true
                    ? track.label!.trim()
                    : track.language?.trim().isNotEmpty == true
                    ? track.language!.trim()
                    : '${betterPlayerController!.translations.generalDefault} ${index + 1}';
                final details = <String>{
                  if (track.language?.trim().isNotEmpty == true) track.language!.trim(),
                  if (track.mimeType?.trim().isNotEmpty == true) track.mimeType!.replaceFirst('audio/', ''),
                  if (track.isDefault) betterPlayerController!.translations.generalDefault,
                }.join(' • ');
                return BetterPlayerSelectionTile(
                  icon: isSelected ? PhosphorIcons.waveform(PhosphorIconsStyle.fill) : PhosphorIcons.waveform(),
                  title: label,
                  subtitle: details,
                  selected: isSelected,
                  onTap: () {
                    _closeSheet();
                    betterPlayerController!.setAudioTrack(track);
                  },
                );
              }).toList(),
            ),
    );
  }

  String? _selectedSubtitleLabel() {
    final source = betterPlayerController!.betterPlayerSubtitlesSource;
    if (source == null || source.type == BetterPlayerSubtitlesSourceType.none) {
      return betterPlayerController!.translations.generalNone;
    }
    return source.name ?? betterPlayerController!.translations.generalDefault;
  }

  String _selectedQualityLabel() {
    final detectedHeight = BetterPlayerUtils.detectedVideoHeight(
      betterPlayerController!.videoPlayerController?.value.size,
    );
    final resolutionName = betterPlayerController!.betterPlayerResolutionName;
    if (resolutionName?.trim().isNotEmpty == true) {
      if (detectedHeight != null && BetterPlayerUtils.resolutionHeightFromLabel(resolutionName) == null) {
        return '${detectedHeight}p • ${resolutionName!.trim()}';
      }
      return resolutionName!.trim();
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

  String _selectedAudioLabel() {
    final track = betterPlayerController!.betterPlayerAsmsAudioTrack;
    return track?.label ?? track?.language ?? betterPlayerController!.translations.generalDefault;
  }

  Widget _selectionList(List<Widget> children) => ListView.separated(
    shrinkWrap: true,
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
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

  void _showSheet({required IconData icon, required String title, required Widget child, String? subtitle}) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: betterPlayerController?.betterPlayerConfiguration.useRootNavigator ?? false,
      useSafeArea: true,
      showDragHandle: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .58),
      builder: (sheetContext) {
        final inheritedTheme = Theme.of(context);
        final configured = betterPlayerControlsConfiguration;
        final modalSurface = configured.overflowModalColor;
        final modalText = configured.overflowModalTextColor;
        final useConfiguredSurface = modalSurface != Colors.white || modalText != Colors.black;
        final colors = inheritedTheme.colorScheme;
        final themed = inheritedTheme.copyWith(
          colorScheme: useConfiguredSurface
              ? colors.copyWith(
                  surface: modalSurface,
                  surfaceContainerHigh: modalSurface,
                  surfaceContainerLow: Color.alphaBlend(modalText.withValues(alpha: .05), modalSurface),
                  surfaceContainerHighest: Color.alphaBlend(modalText.withValues(alpha: .1), modalSurface),
                  onSurface: modalText,
                  onSurfaceVariant: modalText.withValues(alpha: .72),
                  outlineVariant: modalText.withValues(alpha: .24),
                  primary: betterPlayerReadableAccent(configured.overflowMenuIconsColor, modalSurface),
                )
              : colors,
        );
        return Theme(
          data: themed,
          child: BetterPlayerModalSheet(icon: icon, title: title, subtitle: subtitle, child: child),
        );
      },
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
  const _PlayerMenuItem({required this.icon, required this.title, required this.onTap, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
}
