import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// Structured result from parsing BP monitor display OCR.
class BpOcrResult {
  final int? systolic;
  final int? diastolic;
  final int? pulse;
  final String rawText;
  final List<int> detectedNumbers;
  final String methodUsed; // 'labeled', 'slash', 'spatial', 'heuristic'
  final bool isComplete; // systolic != null && diastolic != null

  const BpOcrResult({
    this.systolic,
    this.diastolic,
    this.pulse,
    required this.rawText,
    this.detectedNumbers = const [],
    this.methodUsed = 'none',
    this.isComplete = false,
  });

  @override
  String toString() =>
      'BpOcrResult(sys: $systolic, dia: $diastolic, pulse: $pulse, method: $methodUsed, numbers: $detectedNumbers)';
}

/// Advanced OCR extraction engine tailored for digital Blood Pressure Monitors.
///
/// Digital BP monitors (Omron, Beurer, Citizen, Rossmax, Dr Trust, etc.) present
/// readings in 7-segment LCD digits with various layout and labeling styles:
/// 1. Labeled: "SYS 120", "SYS: 120", "120 mmHg SYS", "SYS\n120"
/// 2. Combined / Slash: "120/80", "120 / 80 mmHg"
/// 3. Spatial / Vertical: Top number = SYS, Middle = DIA, Bottom = PULSE
/// 4. 7-segment digit OCR corrections: 'O'/'o' -> '0', 'l'/'I' -> '1', 'S'/'s' -> '5'
class BpOcrParser {
  // Physiological validity ranges for pregnant women and adults
  static const int minSystolic = 70;
  static const int maxSystolic = 260;
  static const int minDiastolic = 40;
  static const int maxDiastolic = 160;
  static const int minPulse = 40;
  static const int maxPulse = 200;

  /// Main entry point when full ML Kit [RecognizedText] with bounding boxes is available.
  static BpOcrResult parseRecognizedText(RecognizedText recognized) {
    final rawText = recognized.text;

    // 1. First attempt: Labeled regex extraction on raw and cleaned text
    final labeled = _parseWithLabels(rawText);
    if (labeled.isComplete) return labeled;

    // 2. Second attempt: Slash / combined pattern (e.g., 120/80)
    final slash = _parseSlashPattern(rawText);
    if (slash.isComplete) return slash;

    // 3. Third attempt: Spatial / Positional layout using bounding boxes
    final spatial = _parseSpatialLayout(recognized);
    if (spatial != null && spatial.isComplete) return spatial;

    // 4. Fourth attempt: Line-by-line adjacency with label indicators
    final adjacent = _parseLineAdjacency(rawText);
    if (adjacent.isComplete) return adjacent;

    // 5. Fifth attempt: Heuristic candidate number extraction from all detected numbers
    return _parseHeuristic(rawText, previousPartial: labeled);
  }

  /// Pure text entry point (useful for web, testing, or fallback).
  static BpOcrResult parseText(String text) {
    // 1. Labeled
    final labeled = _parseWithLabels(text);
    if (labeled.isComplete) return labeled;

    // 2. Slash
    final slash = _parseSlashPattern(text);
    if (slash.isComplete) return slash;

    // 3. Line adjacency
    final adjacent = _parseLineAdjacency(text);
    if (adjacent.isComplete) return adjacent;

    // 4. Heuristic
    return _parseHeuristic(text, previousPartial: labeled);
  }

  /// Clean 7-segment LCD misrecognized characters in potential numeric tokens
  static String rectify7SegmentOcr(String input) {
    return input.replaceAllMapped(
      RegExp(r'\b[0-9lIOSZBsbqdO\-\/]{2,7}\b'),
      (match) {
        final token = match.group(0)!;
        // Don't replace if it's purely letters that form words like "SYS" or "DIA"
        if (RegExp(r'^(SYS|DIA|PUL|MIN|MAX|mmHg)$', caseSensitive: false).hasMatch(token)) {
          return token;
        }
        var cleaned = token
            .replaceAll(RegExp(r'[lI|!]'), '1')
            .replaceAll(RegExp(r'[OoQD]'), '0')
            .replaceAll(RegExp(r'[Ss]'), '5')
            .replaceAll(RegExp(r'[Zz]'), '2')
            .replaceAll(RegExp(r'[B]'), '8')
            .replaceAll(RegExp(r'[b]'), '6');
        return cleaned;
      },
    );
  }

  /// Extracts all distinct 2-3 digit numbers found in text
  static List<int> extractAllNumbers(String text) {
    final rectified = rectify7SegmentOcr(text);
    final matches = RegExp(r'\b(\d{2,3})\b').allMatches('$text\n$rectified');
    final numbers = <int>[];
    for (final m in matches) {
      final val = int.tryParse(m.group(1)!);
      if (val != null && val >= 35 && val <= 260) {
        if (!numbers.contains(val)) {
          numbers.add(val);
        }
      }
    }
    return numbers;
  }

  /// Attempt 1: Labeled extraction
  static BpOcrResult _parseWithLabels(String text) {
    final rectified = rectify7SegmentOcr(text);
    final combined = '$text\n$rectified';

    int? extract(List<String> labelPatterns) {
      for (final pat in labelPatterns) {
        // Label followed by number (e.g., "SYS 120", "SYS: 120", "SYS = 120")
        final m1 = RegExp('(?:$pat)[^0-9\\n]{0,15}(\\d{2,3})', caseSensitive: false).firstMatch(combined);
        if (m1 != null) {
          final v = int.tryParse(m1.group(1)!);
          if (v != null) return v;
        }

        // Number followed by label (e.g., "120 SYS", "120 mmHg SYS")
        final m2 = RegExp('(\\d{2,3})[^0-9\\n]{0,15}(?:$pat)', caseSensitive: false).firstMatch(combined);
        if (m2 != null) {
          final v = int.tryParse(m2.group(1)!);
          if (v != null) return v;
        }
      }
      return null;
    }

    final sys = extract([r'SYS(?:TOLIC)?', r'SYS\.', r'MAX', r'S(?!\w)']);
    final dia = extract([r'DIA(?:STOLIC)?', r'DIA\.', r'MIN', r'D(?!\w)']);
    final pulse = extract([r'PUL(?:SE)?', r'PUL\.', r'PR', r'HR', r'BPM', r'HEART', r'/min']);

    final detected = extractAllNumbers(text);

    final isValidSys = sys != null && sys >= minSystolic && sys <= maxSystolic;
    final isValidDia = dia != null && dia >= minDiastolic && dia <= maxDiastolic;
    final isValidPulse = pulse != null && pulse >= minPulse && pulse <= maxPulse;

    final isComplete = isValidSys && isValidDia && (sys > dia);

    return BpOcrResult(
      systolic: isValidSys ? sys : null,
      diastolic: isValidDia ? dia : null,
      pulse: isValidPulse ? pulse : null,
      rawText: text,
      detectedNumbers: detected,
      methodUsed: isComplete ? 'labeled' : 'none',
      isComplete: isComplete,
    );
  }

  /// Attempt 2: Slash / combined pattern (e.g., "120/80" or "130/85/72")
  static BpOcrResult _parseSlashPattern(String text) {
    final rectified = rectify7SegmentOcr(text);
    final combined = '$text\n$rectified';
    final detected = extractAllNumbers(text);

    final m = RegExp(r'\b(\d{2,3})\s*[/\\-]\s*(\d{2,3})(?:\s*[/\\-]\s*(\d{2,3}))?\b').firstMatch(combined);
    if (m != null) {
      final s = int.tryParse(m.group(1)!);
      final d = int.tryParse(m.group(2)!);
      final p = m.group(3) != null ? int.tryParse(m.group(3)!) : null;

      if (s != null && d != null && s >= minSystolic && s <= maxSystolic && d >= minDiastolic && d <= maxDiastolic && s > d) {
        int? finalPulse = (p != null && p >= minPulse && p <= maxPulse) ? p : null;
        if (finalPulse == null) {
          // Look for pulse elsewhere in the detected numbers
          for (final n in detected) {
            if (n != s && n != d && n >= minPulse && n <= maxPulse) {
              finalPulse = n;
              break;
            }
          }
        }

        return BpOcrResult(
          systolic: s,
          diastolic: d,
          pulse: finalPulse,
          rawText: text,
          detectedNumbers: detected,
          methodUsed: 'slash',
          isComplete: true,
        );
      }
    }

    return BpOcrResult(rawText: text, detectedNumbers: detected);
  }

  /// Attempt 3: Spatial layout using ML Kit bounding boxes
  static BpOcrResult? _parseSpatialLayout(RecognizedText recognized) {
    // Collect all lines with numbers and their vertical positions
    final items = <_SpatialNumber>[];

    for (final block in recognized.blocks) {
      for (final line in block.lines) {
        final lineText = line.text;
        final rectifiedLine = rectify7SegmentOcr(lineText);
        final matches = RegExp(r'\b(\d{2,3})\b').allMatches('$lineText $rectifiedLine');

        for (final m in matches) {
          final val = int.tryParse(m.group(1)!);
          if (val != null && val >= 35 && val <= 260) {
            final top = line.boundingBox.top;
            items.add(_SpatialNumber(val, top));
          }
        }
      }
    }

    if (items.length < 2) return null;

    // Sort by vertical position (Y coordinate ascending = top to bottom)
    items.sort((a, b) => a.top.compareTo(b.top));

    // Deduplicate consecutive identical values at similar heights
    final uniqueItems = <_SpatialNumber>[];
    for (final item in items) {
      if (uniqueItems.isEmpty ||
          uniqueItems.last.value != item.value ||
          (item.top - uniqueItems.last.top).abs() > 15) {
        uniqueItems.add(item);
      }
    }

    if (uniqueItems.length >= 2) {
      // Find top item plausible for SYS
      for (int i = 0; i < uniqueItems.length - 1; i++) {
        final sCandidate = uniqueItems[i].value;
        if (sCandidate >= minSystolic && sCandidate <= maxSystolic) {
          // Look for subsequent item plausible for DIA
          for (int j = i + 1; j < uniqueItems.length; j++) {
            final dCandidate = uniqueItems[j].value;
            if (dCandidate >= minDiastolic && dCandidate <= maxDiastolic && sCandidate > dCandidate) {
              // Found SYS and DIA! Now look for pulse below DIA
              int? pCandidate;
              for (int k = j + 1; k < uniqueItems.length; k++) {
                final p = uniqueItems[k].value;
                if (p >= minPulse && p <= maxPulse && p != dCandidate) {
                  pCandidate = p;
                  break;
                }
              }

              return BpOcrResult(
                systolic: sCandidate,
                diastolic: dCandidate,
                pulse: pCandidate,
                rawText: recognized.text,
                detectedNumbers: uniqueItems.map((e) => e.value).toList(),
                methodUsed: 'spatial',
                isComplete: true,
              );
            }
          }
        }
      }
    }

    return null;
  }

  /// Attempt 4: Line-by-line adjacency
  static BpOcrResult _parseLineAdjacency(String text) {
    final lines = text.split(RegExp(r'[\r\n]+')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    final detected = extractAllNumbers(text);

    int? sys;
    int? dia;
    int? pulse;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];

      // Check for SYS indicator
      if (RegExp(r'\b(?:SYS|SYSTOLIC|MAX)\b', caseSensitive: false).hasMatch(line)) {
        // Check current line, next line, or previous line for number
        sys ??= _findNumberInWindow(lines, i, minSystolic, maxSystolic);
      }

      // Check for DIA indicator
      if (RegExp(r'\b(?:DIA|DIASTOLIC|MIN)\b', caseSensitive: false).hasMatch(line)) {
        dia ??= _findNumberInWindow(lines, i, minDiastolic, maxDiastolic);
      }

      // Check for Pulse indicator
      if (RegExp(r'\b(?:PULSE|PUL|HR|PR|BPM|/min)\b', caseSensitive: false).hasMatch(line)) {
        pulse ??= _findNumberInWindow(lines, i, minPulse, maxPulse);
      }
    }

    final isComplete = sys != null && dia != null && sys > dia;

    return BpOcrResult(
      systolic: sys,
      diastolic: dia,
      pulse: pulse,
      rawText: text,
      detectedNumbers: detected,
      methodUsed: isComplete ? 'adjacent' : 'none',
      isComplete: isComplete,
    );
  }

  static int? _findNumberInWindow(List<String> lines, int index, int minVal, int maxVal) {
    // Check current line
    final currentNums = extractAllNumbers(lines[index]).where((n) => n >= minVal && n <= maxVal);
    if (currentNums.isNotEmpty) return currentNums.first;

    // Check line below
    if (index + 1 < lines.length) {
      final nextNums = extractAllNumbers(lines[index + 1]).where((n) => n >= minVal && n <= maxVal);
      if (nextNums.isNotEmpty) return nextNums.first;
    }

    // Check line above
    if (index - 1 >= 0) {
      final prevNums = extractAllNumbers(lines[index - 1]).where((n) => n >= minVal && n <= maxVal);
      if (prevNums.isNotEmpty) return prevNums.first;
    }

    return null;
  }

  /// Attempt 5: Heuristic extraction when labels and spatial markers are absent
  static BpOcrResult _parseHeuristic(String text, {BpOcrResult? previousPartial}) {
    final numbers = extractAllNumbers(text);

    int? sys = previousPartial?.systolic;
    int? dia = previousPartial?.diastolic;
    int? pulse = previousPartial?.pulse;

    if (numbers.isNotEmpty) {
      // If we don't have systolic and diastolic yet:
      if (sys == null || dia == null) {
        // Look for any valid (s, d) pair where s > d
        for (int i = 0; i < numbers.length; i++) {
          final candidateS = numbers[i];
          if (candidateS >= minSystolic && candidateS <= maxSystolic) {
            for (int j = 0; j < numbers.length; j++) {
              if (i == j) continue;
              final candidateD = numbers[j];
              if (candidateD >= minDiastolic && candidateD <= maxDiastolic && candidateS > candidateD) {
                // If the numbers appeared in sequence (e.g. 120 followed by 80), this is our pair!
                sys = candidateS;
                dia = candidateD;
                break;
              }
            }
            if (sys != null && dia != null) break;
          }
        }
      }

      // If we found SYS and DIA, look for a 3rd number for Pulse
      if (sys != null && dia != null && pulse == null) {
        for (final n in numbers) {
          if (n != sys && n != dia && n >= minPulse && n <= maxPulse) {
            pulse = n;
            break;
          }
        }
      }
    }

    final isComplete = sys != null && dia != null && sys > dia;

    return BpOcrResult(
      systolic: sys,
      diastolic: dia,
      pulse: pulse,
      rawText: text,
      detectedNumbers: numbers,
      methodUsed: isComplete ? 'heuristic' : 'none',
      isComplete: isComplete,
    );
  }
}

class _SpatialNumber {
  final int value;
  final double top;
  _SpatialNumber(this.value, this.top);
}

