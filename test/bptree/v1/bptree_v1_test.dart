import 'dart:convert';

import 'package:lookup/bptree/v1/bptree_v1.dart';
import 'package:test/test.dart';

void main() {
  group('bptree/v1', () {
    test('minimal page with custom data', () {
      final bytes = BPTreeV1.build([
        MapEntry([2], [3]),
      ], customData: [
        7
      ]);
      expect(bytes.toList(), [
        171, 244, 112, // magic bytes
        0, // endian + internal version
        11, // custom data + sorted + offset index
        1, // entries count
        1, // custom data length
        7, // custom data
        0, // positing index code
        0, // position(s)
        0, // key-value code
        4, // bytes length
        1, 2, 1, 3, // key-value entries
      ]);
      final page = BPTreeV1.parse(bytes);
      expect(page.getValue([1]), null);
      expect(page.getValue([2]), [3]);
      expect(page.getValue([2, 1]), null);
      expect(page.getValue([3]), null);
    });

    test('padded page', () {
      final bytes = BPTreeV1.build(
        [
          MapEntry([2], [3]),
        ],
        usePadding: true,
      );
      expect(bytes.toList(), [
        171, 244, 112, // magic bytes
        0, // endian + internal version
        10, // sorted + offset index
        1, // entries count
        8, // offset index code
        0, // padding
        0, // position(s)
        64, // key-value code
        4, // bytes length
        0, 0, 0, 0, 0, //padding
        1, 2, 1, 3, // key-value entries
      ]);
      final page = BPTreeV1.parse(bytes);
      expect(page.getValue([1]), null);
      expect(page.getValue([2]), [3]);
      expect(page.getValue([2, 1]), null);
      expect(page.getValue([3]), null);
    });

    test('two entries', () {
      final bytes = BPTreeV1.build(
        [
          MapEntry([2, 1], [4]),
          MapEntry([2, 3], [5]),
        ],
      );
      expect(bytes.toList(), [
        171, 244, 112, // magic bytes
        0, // endian + internal version
        10, // sorted + offset index
        2, // entries count
        0, // offset index code
        0, 5, // positions
        0, // key-value code
        10, // key-value byte count
        2, 2, 1, 1, 4, // first item
        2, 2, 3, 1, 5, // second item
      ]);
      final page = BPTreeV1.parse(bytes);
      expect(page.getValue([2]), null);
      expect(page.getValue([2, 0]), null);
      expect(page.getValue([2, 1]), [4]);
      expect(page.getValue([2, 2]), null);
      expect(page.getValue([2, 3]), [5]);
      expect(page.getValue([2, 4]), null);
      expect(page.getValue([3]), null);
    });

    test('large keys', () {
      for (final keySize in [300, 10000, 70000]) {
        final bytes = BPTreeV1.build([
          MapEntry(List.filled(keySize, 0), [1])
        ]);
        expect(bytes.length, greaterThan(keySize));
        expect(bytes.length, lessThan(keySize + 20));
        final page = BPTreeV1.parse(bytes);
        expect(page.getValue([0]), null);
        expect(page.getValue(List.filled(keySize, 0)), [1]);
      }
    });

    test('large values', () {
      for (final valueSize in [300, 10000, 70000]) {
        final bytes = BPTreeV1.build([
          MapEntry([1], List.filled(valueSize, 0))
        ]);
        expect(bytes.length, greaterThan(valueSize));
        expect(bytes.length, lessThan(valueSize + 20));
        final page = BPTreeV1.parse(bytes);
        expect(page.getValue([0]), null);
        expect(page.getValue([1])!.toList(), List.filled(valueSize, 0),
            reason: '$valueSize');
      }
    });

    test('lots of keys', () {
      for (final keyCount in [255, 10000, 70000]) {
        final entries = <MapEntry<List<int>, List<int>>>[];
        for (var i = 0; i < keyCount; i++) {
          final key = utf8.encode(i.toString());
          entries.add(MapEntry(key, [i & 0xff]));
        }
        final bytes = BPTreeV1.build(entries);
        final page = BPTreeV1.parse(bytes);
        expect(page.getValue(utf8.encode('35')), [35]);
      }
    });
  });
}
