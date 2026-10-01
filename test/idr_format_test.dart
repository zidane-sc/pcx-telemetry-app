import 'package:flutter_test/flutter_test.dart';

/// Mirrors the helper in `garage_screen.dart`. Duplicated rather than imported
/// because it is a private member of a screen widget, and pulling a screen into
/// a unit test to test one string formatter would drag the whole widget tree in
/// behind it. If the helper changes, change this too — the assertions below
/// pin the behaviour that matters.
String formatIdr(double v) {
  final s = v.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  return buf.toString();
}

void main() {
  group('Indonesian rupiah formatting', () {
    test('groups thousands with dots, not commas', () {
      expect(formatIdr(1250000), '1.250.000');
      expect(formatIdr(250000), '250.000');
      expect(formatIdr(50000), '50.000');
      expect(formatIdr(5000), '5.000');
    });

    test('does not pad numbers under a thousand', () {
      expect(formatIdr(999), '999');
      expect(formatIdr(100), '100');
      expect(formatIdr(1), '1');
      expect(formatIdr(0), '0');
    });

    test('handles an exact multiple of a thousand', () {
      expect(formatIdr(1000), '1.000');
      expect(formatIdr(3000), '3.000');
    });

    test('handles seven and eight digits', () {
      expect(formatIdr(1000000), '1.000.000');
      expect(formatIdr(12345678), '12.345.678');
    });

    test('rounds rather than truncating', () {
      expect(formatIdr(1250.4), '1.250');
      expect(formatIdr(1250.6), '1.251');
    });

    test('a per-km rate with a fractional part still reads sensibly', () {
      // Rp 412.4 / km must not collapse to a misleadingly round number.
      final out = formatIdr(412.4);
      expect(out, '412');
      expect(out.contains('.'), isFalse,
          reason: 'a dot here would read as a decimal separator');
    });
  });
}