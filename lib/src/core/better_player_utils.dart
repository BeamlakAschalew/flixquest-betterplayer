// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class BetterPlayerUtils {
  static const Set<int> _commonVideoHeights = {144, 240, 360, 480, 540, 576, 720, 1080, 1440, 2160, 4320};

  ///Returns the resolution encoded in a provider label, if it has one.
  static int? resolutionHeightFromLabel(String? label) {
    if (label == null || label.trim().isEmpty) return null;

    final dimensions = RegExp(r'(?<!\d)(\d{2,5})\s*[x×]\s*(\d{3,4})(?!\d)', caseSensitive: false).firstMatch(label);
    if (dimensions != null) return int.tryParse(dimensions.group(2)!);

    final explicit = RegExp(r'(?<!\d)(\d{3,4})\s*p\b', caseSensitive: false).firstMatch(label);
    if (explicit != null) return int.tryParse(explicit.group(1)!);

    for (final match in RegExp(r'(?<!\d)(\d{3,4})(?!\d)').allMatches(label)) {
      final height = int.tryParse(match.group(1)!);
      if (height != null && _commonVideoHeights.contains(height)) return height;
    }
    return null;
  }

  ///Returns the runtime video height from its natural dimensions. The shorter
  ///side is used so rotated/portrait content is still described consistently,
  ///and codec-padded heights such as 1088 are normalized to 1080p.
  static int? detectedVideoHeight(Size? size) {
    if (size == null || size.isEmpty) return null;
    final shorterSide = size.shortestSide.round();
    var nearest = shorterSide;
    var nearestDistance = 17;
    for (final height in _commonVideoHeights) {
      final distance = (height - shorterSide).abs();
      if (distance < nearestDistance) {
        nearest = height;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  static String? detectedVideoDimensions(Size? size) {
    if (size == null || size.isEmpty) return null;
    return '${size.width.round()}×${size.height.round()}';
  }

  static String formatBitrate(int bitrate) {
    if (bitrate < 1000) {
      return '$bitrate bit/s';
    }
    if (bitrate < 1000000) {
      final kbit = (bitrate / 1000).floor();
      return '~$kbit KBit/s';
    }
    final mbit = (bitrate / 1000000).floor();
    return '~$mbit MBit/s';
  }

  static String formatDuration(Duration position) {
    final ms = position.inMilliseconds;

    int seconds = ms ~/ 1000;
    final int hours = seconds ~/ 3600;
    seconds = seconds % 3600;
    final minutes = seconds ~/ 60;
    seconds = seconds % 60;

    final hoursString = hours >= 10
        ? '$hours'
        : hours == 0
        ? '00'
        : '0$hours';

    final minutesString = minutes >= 10
        ? '$minutes'
        : minutes == 0
        ? '00'
        : '0$minutes';

    final secondsString = seconds >= 10
        ? '$seconds'
        : seconds == 0
        ? '00'
        : '0$seconds';

    final formattedTime = '${hoursString == '00' ? '' : '$hoursString:'}$minutesString:$secondsString';

    return formattedTime;
  }

  static double calculateAspectRatio(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final width = size.width;
    final height = size.height;

    return width > height ? width / height : height / width;
  }

  static void log(String logMessage) {
    if (!kReleaseMode) {
      // ignore: avoid_print
      print(logMessage);
    }
  }
}
