import 'package:better_player_plus/src/core/better_player_utils.dart';

class BetterPlayerSubtitle {
  factory BetterPlayerSubtitle(String value, bool isWebVTT) {
    try {
      final scanner = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim().split('\n');
      if (scanner.length == 2) {
        return _handle2LinesSubtitles(scanner);
      }
      if (scanner.length > 2) {
        return _handle3LinesAndMoreSubtitles(scanner, isWebVTT);
      }
      return BetterPlayerSubtitle._();
    } catch (_) {
      BetterPlayerUtils.log('Failed to parse subtitle line: $value');
      return BetterPlayerSubtitle._();
    }
  }

  BetterPlayerSubtitle._({this.index, this.start, this.end, this.texts});
  static const String timerSeparator = ' --> ';
  final int? index;
  final Duration? start;
  final Duration? end;
  final List<String>? texts;

  static BetterPlayerSubtitle _handle2LinesSubtitles(List<String> scanner) {
    try {
      final timeSplit = scanner[0].split(timerSeparator);
      if (timeSplit.length != 2) return BetterPlayerSubtitle._();
      final start = _stringToDuration(timeSplit[0]);
      final end = _stringToDuration(timeSplit[1]);
      final texts = scanner.sublist(1, scanner.length);

      return BetterPlayerSubtitle._(index: -1, start: start, end: end, texts: texts);
    } catch (_) {
      BetterPlayerUtils.log('Failed to parse subtitle line: $scanner');
      return BetterPlayerSubtitle._();
    }
  }

  static BetterPlayerSubtitle _handle3LinesAndMoreSubtitles(List<String> scanner, bool isWebVTT) {
    try {
      int? index = -1;
      List<String> timeSplit = [];
      int firstLineOfText = 0;
      if (scanner[0].contains(timerSeparator)) {
        timeSplit = scanner[0].split(timerSeparator);
        firstLineOfText = 1;
      } else {
        index = int.tryParse(scanner[0]);
        timeSplit = scanner[1].split(timerSeparator);
        firstLineOfText = 2;
      }

      if (timeSplit.length != 2) return BetterPlayerSubtitle._();
      final start = _stringToDuration(timeSplit[0]);
      final end = _stringToDuration(timeSplit[1]);
      final texts = scanner.sublist(firstLineOfText, scanner.length);
      return BetterPlayerSubtitle._(index: index, start: start, end: end, texts: texts);
    } catch (_) {
      BetterPlayerUtils.log('Failed to parse subtitle line: $scanner');
      return BetterPlayerSubtitle._();
    }
  }

  static Duration _stringToDuration(String value) {
    try {
      final trimmed = value.trim();
      final valueSplit = trimmed.split(' ');
      String componentValue = valueSplit.isNotEmpty ? valueSplit[0].trim() : trimmed;

      final component = componentValue.split(':');
      // Interpret a missing hour component to mean 00 hours
      if (component.length == 2) {
        component.insert(0, '00');
      } else if (component.length != 3) {
        return const Duration();
      }

      final secsAndMillisSplitChar = component[2].contains(',') ? ',' : '.';
      final secsAndMillsSplit = component[2].split(secsAndMillisSplitChar);
      if (secsAndMillsSplit.length != 2) {
        return const Duration();
      }

      final hours = int.tryParse(component[0].trim());
      final minutes = int.tryParse(component[1].trim());
      final seconds = int.tryParse(secsAndMillsSplit[0].trim());

      String millisStr = secsAndMillsSplit[1].trim();
      if (millisStr.length > 3) {
        millisStr = millisStr.substring(0, 3);
      } else if (millisStr.length < 3) {
        millisStr = millisStr.padRight(3, '0');
      }
      final milliseconds = int.tryParse(millisStr);
      if (hours == null ||
          minutes == null ||
          seconds == null ||
          milliseconds == null) {
        return const Duration();
      }

      return Duration(
        hours: hours,
        minutes: minutes,
        seconds: seconds,
        milliseconds: milliseconds,
      );
    } catch (_) {
      BetterPlayerUtils.log('Failed to process value: $value');
      return const Duration();
    }
  }

  @override
  String toString() => 'BetterPlayerSubtitle{index: $index, start: $start, end: $end, texts: $texts}';
}
