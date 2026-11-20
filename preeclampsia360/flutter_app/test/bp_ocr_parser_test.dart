import 'package:flutter_test/flutter_test.dart';
import 'package:preeclampsia360/core/bp_ocr_parser.dart';

void main() {
  group('BpOcrParser Unit Tests', () {
    test('1. Standard labeled format with line breaks', () {
      const text = '''
Omron M2
SYS mmHg
128
DIA mmHg
84
PULSE /min
72
OK
''';
      final res = BpOcrParser.parseText(text);
      expect(res.isComplete, isTrue);
      expect(res.systolic, equals(128));
      expect(res.diastolic, equals(84));
      expect(res.pulse, equals(72));
    });

    test('2. Colon/inline labeled format', () {
      const text = 'SYS: 135 DIA: 88 PULSE: 76';
      final res = BpOcrParser.parseText(text);
      expect(res.isComplete, isTrue);
      expect(res.systolic, equals(135));
      expect(res.diastolic, equals(88));
      expect(res.pulse, equals(76));
    });

    test('3. Suffix label format (number before SYS/DIA)', () {
      const text = '''
140 mmHg SYS
90 mmHg DIA
80 /min PULSE
''';
      final res = BpOcrParser.parseText(text);
      expect(res.isComplete, isTrue);
      expect(res.systolic, equals(140));
      expect(res.diastolic, equals(90));
      expect(res.pulse, equals(80));
    });

    test('4. Slash format (120/80)', () {
      const text = '''
READING: 120/80
PUL: 74
''';
      final res = BpOcrParser.parseText(text);
      expect(res.isComplete, isTrue);
      expect(res.systolic, equals(120));
      expect(res.diastolic, equals(80));
      expect(res.pulse, equals(74));
    });

    test('5. Slash with triple values (125/82/70)', () {
      const text = 'Result: 125/82/70';
      final res = BpOcrParser.parseText(text);
      expect(res.isComplete, isTrue);
      expect(res.systolic, equals(125));
      expect(res.diastolic, equals(82));
      expect(res.pulse, equals(70));
    });

    test('6. Unlabeled vertical numbers (Omron 7-segment display without labels read)', () {
      const text = '''
130
85
72
''';
      final res = BpOcrParser.parseText(text);
      expect(res.isComplete, isTrue);
      expect(res.systolic, equals(130));
      expect(res.diastolic, equals(85));
      expect(res.pulse, equals(72));
    });

    test('7. 7-segment character rectifications (l35 -> 135, 8O -> 80)', () {
      const text = '''
SYS l35
DIA 8O
PUL 7Z
''';
      final res = BpOcrParser.parseText(text);
      expect(res.isComplete, isTrue);
      expect(res.systolic, equals(135));
      expect(res.diastolic, equals(80));
    });

    test('8. High critical BP reading (168/114, 92)', () {
      const text = '''
SYSTOLIC
168
DIASTOLIC
114
PULSE
92
''';
      final res = BpOcrParser.parseText(text);
      expect(res.isComplete, isTrue);
      expect(res.systolic, equals(168));
      expect(res.diastolic, equals(114));
      expect(res.pulse, equals(92));
    });

    test('9. User uploaded screenshot scenario (partial reading 49, E, in, ok)', () {
      const text = '''
49
E
in
(oK)
''';
      final res = BpOcrParser.parseText(text);
      // Not complete because 49 alone is not a valid systolic + diastolic pair
      expect(res.isComplete, isFalse);
      // But 49 is captured in detectedNumbers
      expect(res.detectedNumbers, contains(49));
    });
  });
}

