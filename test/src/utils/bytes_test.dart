import 'package:lookup/src/utils/bytes.dart';
import 'package:test/test.dart';

void main() {
  group('Uint8List.compareTo', () {
    test('== 0', () {
      expect([1].toUint8List().compareTo([1].toUint8List()), 0);
      expect([1, 2, 3].toUint8List().compareTo([1, 2, 3].toUint8List()), 0);
    });

    test('< 0', () {
      expect([0].toUint8List().compareTo([1].toUint8List()), -1);
      expect([0, 1].toUint8List().compareTo([1].toUint8List()), -1);
      expect([0, 2].toUint8List().compareTo([1].toUint8List()), -1);
      expect([0, 0].toUint8List().compareTo([0, 1].toUint8List()), -1);
    });

    test('> 0', () {
      expect([2].toUint8List().compareTo([1].toUint8List()), 1);
      expect([2, 1].toUint8List().compareTo([1, 3].toUint8List()), 1);
      expect([2, 2].toUint8List().compareTo([1].toUint8List()), 1);
      expect([2, 0].toUint8List().compareTo([0, 1].toUint8List()), 1);
    });
  });

  group('BytesReader', () {
    test('subviews', () {
      final bytes = [0, 1, 2, 3, 4, 5, 6, 7].toUint8List();
      final reader = BytesReader(bytes);
      final list8 = reader.subview(8);
      expect(list8.toList(), bytes.toList());
      reader.goto(0);

      final list16 = reader.subviewUint16(8);
      expect(list16, [0x0100, 0x0302, 0x0504, 0x0706]);
    });
  });
}
