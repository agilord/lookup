import 'package:lookup/src/utils/uleb128.dart';
import 'package:test/test.dart';

void main() {
  group('ULEB128', () {
    final pairs = [
      (0, [0]),
      (127, [127]),
      (128, [128, 1]),
      (624485, [0xE5, 0x8E, 0x26]),
    ];
    test('encode and decode', () {
      for (final p in pairs) {
        final encoded = encodeUleb128(p.$1);
        expect(encoded.size, p.$2.length, reason: p.$1.toString());
        expect(encoded.bytes.toList(), p.$2, reason: p.$1.toString());

        final decoded = decodeUleb128(encoded.bytes);
        expect(decoded.size, encoded.size, reason: p.$1.toString());
        expect(decoded.value, p.$1, reason: p.$1.toString());
      }
    });
  });
}
