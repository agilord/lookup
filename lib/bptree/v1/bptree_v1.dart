/// Implements a B+tree.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:lookup/src/parts/key_value_entries_v1.dart';
import 'package:lookup/src/parts/length_encoding_3bit_v1.dart';
import 'package:lookup/src/parts/offset_index_v1.dart';

import '../../lookup.dart';
import '../../src/utils/bytes.dart';

const _magicBytes = [0xab, 0xf4, 0x70];
const _internalVersion = 0;

/// Represents a B+-tree node with sorted, arbitrary length key-value pairs,
/// key compression and offset index.
///
/// The structure starts with the following:
///
/// *Node identification* (always present):
/// - `uint8[3]`: [`0xab`, `0xf4`, `0x70`] - first 3 bytes of the md5 hash of `bptree/v1`.
/// - `uint8` byte - internal version and endian-ness
///   - `bits 0-6` - the minimum internal version required to parse the bytes
///   - `bit 7`: the endian-ness of the multi-byte encodings
///     (`0`: little-endian, `1`: big-endian).
///
/// *Node options* (always present):
/// - `uint8` byte
///   - `bit 0`: whether custom data is present
///   - `bit 1`: whether entries are sorted
///   - `bit 2`: whether key compression is present
///   - `bit 3`: whether offset index is present
///   - `bits 4-7`: reserved for future use.
/// - `varint` for the number of entries
///
/// *Custom data* (when flag is set):
/// - `varint` for bytes length
/// - `uint8[]` containing the custom data
///
/// *Key compression* (when flag is set):
/// - `varint` for prefix bytes length
/// - `uint8[]` containing the prefix bytes
/// - `varint` for postfix bytes length
/// - `uint8[]` containing the postfix bytes
///
/// NOTE: The keys inside this node will be stored without the given prefix or postfix.
///
/// *Offset index* (when flag is set):
/// - `uint8` byte
///   - `bit 0-1`: size code
///     - `0`: `uint8` 1-byte index
///     - `1`: `uint16` 2-bytes index
///     - `2`: `uint32` 4-bytes index
///     - `3`: `uint64` 8-bytes index
///   - `bit 2`: whether there is an item count for this index (or it will use a previously defined count if there is any)
///   - `bit 3`: whether start offset is padded to offset dividible by 8.
///   - `bits 4-7`: reserved for future use (sparse index specification)
/// - (optional) `varint` - the number of entries in the position index (if the flag above is set)
/// - (optional) `uint8[]` padding `0x00` (zero) bytes so that index starts at offset divisible by 8
/// - `uint8[]` position index bytes
///
/// *Key-value entries* (always present):
/// - `uint8`: key and value length specification
///   - `bits 0-2`: the length encoding of keys:
///     - `0`: length is prefixed with a 1-byte `uint8`
///     - `1`: length is prefixed with a 2-bytes `uint16`
///     - `2`: length is prefixed with a 4-bytes `uint32`
///     - `3`: length is prefixed with a 8-bytes `uint64`
///     - `4`: length is prefixed with a `varint` value
///     - `5`-`6`: reserved for future use
///     - `7`: length is const, specified with a follow-up `varint` value
///   - `bits 3-5`: the length encoding of values (see values for keys).
///   - `bit 6`: whether start offset is padded to offset dividible by 8.
///   - `bit 7`: reserved for future use
/// - (optional) `varint` for const key length (if key encoding code is `7`)
/// - (optional) `varint` for const value length (if value encoding code is `7`)
/// - `varint` total bytes length of the entries
/// - (optional) padding `0x00` (zero) bytes so that the entries start at an offset dividible by 8.
/// - entries encoded as
///   - key length prefix (or absent for const key length) depending on the key length encoding
///   - key bytes
///   - value length prefix (or absent for const value length) depending on the value length encoding
///   - value bytes
///
/// NOTE: there is no end marker for key-value entries, the last entry ends at the last byte.
abstract class BPTreeV1 implements LookupMap {
  static BPTreeV1 parse(Uint8List bytes) {
    if (bytes.length < 7) {
      throw FormatException('Insufficient bytes.');
    }
    for (var i = 0; i < _magicBytes.length; i++) {
      if (bytes[i] != _magicBytes[i]) {
        throw FormatException('Magic bytes mismatch.');
      }
    }
    final versionByte = bytes[3];
    final endian = (versionByte & 0x80) == 0 ? Endian.little : Endian.big;
    final internalVersion = versionByte & 0x7f;
    if (internalVersion > _internalVersion) {
      throw FormatException(
          'Internal version is not supported: $internalVersion');
    }

    final reader = BytesReader(bytes, endian: endian, offset: 4);
    final optionsBytes = reader.readUint8();
    final isCustomDataPresent = (optionsBytes & 0x01) != 0;
    final isSorted = (optionsBytes & 0x02) != 0;
    final isCompressionPresent = (optionsBytes & 0x04) != 0;
    final isOffsetPresent = (optionsBytes & 0x08) != 0;
    if ((optionsBytes >> 4) > 0) {
      throw FormatException('Unknown option bytes settings ($optionsBytes).');
    }
    final entriesCount = reader.readVarint();

    Uint8List? customData;
    if (isCustomDataPresent) {
      final length = reader.readVarint();
      customData = reader.subview(length);
    }

    Uint8List? prefixBytes;
    Uint8List? postfixBytes;
    if (isCompressionPresent) {
      final prefixLength = reader.readVarint();
      if (prefixLength > 0) {
        prefixBytes = reader.subview(prefixLength);
      }
      final postfixLength = reader.readVarint();
      if (postfixLength > 0) {
        postfixBytes = reader.subview(postfixLength);
      }
    }

    OffsetIndexV1? offsetIndex;
    if (isOffsetPresent) {
      offsetIndex = OffsetIndexV1.fromReader(
        reader,
        entriesCount: entriesCount,
      );
    }
    final entries = KeyValueEntriesV1.fromReader(reader);

    return _BPTreeV1._(
      endian,
      customData,
      isSorted,
      prefixBytes,
      postfixBytes,
      offsetIndex,
      entries,
    );
  }

  static Uint8List build(
    Iterable<MapEntry<List<int>, List<int>>> entries, {
    Endian? endian,
    List<int>? customData,
    bool? keepEntryOrder,
    bool? skipOffsetIndex,
    bool? usePadding,
  }) {
    assert(_internalVersion < 0x80);
    endian ??= Endian.host;
    keepEntryOrder ??= false;
    skipOffsetIndex ??= keepEntryOrder;
    usePadding ??= false;

    final writer = BytesWriter(endian);
    writer.write(_magicBytes);
    writer.writeUint8((endian == Endian.little ? 0 : 0x80) | _internalVersion);

    final entriesList = entries
        .map((e) => MapEntry(e.key.toUint8List(), e.value.toUint8List()))
        .toList();
    if (!keepEntryOrder) {
      entriesList.sort((a, b) => a.key.compareTo(b.key));
    }

    // TODO: implement compression
    final prefixBytes = emptyBytes;
    final postfixBytes = emptyBytes;

    final hasCompression = prefixBytes.isNotEmpty | postfixBytes.isNotEmpty;
    final hasCustomData = customData != null && customData.isNotEmpty;
    final firstByte = (hasCustomData ? 0x01 : 0) |
        (keepEntryOrder ? 0 : 0x02) |
        (hasCompression ? 0x04 : 0) |
        (skipOffsetIndex ? 0 : 0x08);
    writer.writeUint8(firstByte);

    writer.writeVarint(entriesList.length);
    if (hasCustomData) {
      writer.writeVarint(customData.length);
      writer.write(customData);
    }

    if (hasCompression) {
      writer.writeVarint(prefixBytes.length);
      writer.write(prefixBytes);
      writer.writeVarint(postfixBytes.length);
      writer.write(postfixBytes);
    }

    final keyLengthPrefixBuilder = LengthEncoding3bitV1Builder.fromValues(
        entriesList.map((e) => e.key.length));
    final valueLengthPrefixBuilder = LengthEncoding3bitV1Builder.fromValues(
        entriesList.map((e) => e.value.length));

    final kvWriter = BytesWriter(endian);
    final offsets = skipOffsetIndex ? null : <int>[];
    for (final e in entriesList) {
      offsets?.add(kvWriter.length);
      keyLengthPrefixBuilder.writeLength(kvWriter, e.key.length);
      kvWriter.write(e.key);
      valueLengthPrefixBuilder.writeLength(kvWriter, e.value.length);
      kvWriter.write(e.value);
    }
    final kvBytes = kvWriter.toBytes();

    if (!skipOffsetIndex) {
      writeOffsetIndex(
        writer,
        offsets!,
        entriesCount: entriesList.length,
        isPadded: usePadding,
      );
    }

    final kvCode = keyLengthPrefixBuilder.code |
        (valueLengthPrefixBuilder.code << 3) |
        (usePadding ? 0x40 : 0);
    writer.writeUint8(kvCode);
    writer.write(keyLengthPrefixBuilder.bytes);
    writer.write(valueLengthPrefixBuilder.bytes);
    writer.writeVarint(kvBytes.length);
    if (usePadding) {
      writer.writePadding8();
    }
    writer.write(kvBytes);
    return writer.toBytes();
  }

  bool append(List<int> key, List<int> value) {
    // TODO: If there’s extra space available and the entry can fit, append it.
    return false;
  }
}

class _BPTreeV1 implements BPTreeV1 {
  final Endian _endian;
  final Uint8List? customData;
  final bool _isSorted;
  final Uint8List? _prefixBytes;
  final Uint8List? _postfixBytes;
  final OffsetIndexV1? _offsetIndex;
  final KeyValueEntriesV1 _entries;

  _BPTreeV1._(
    this._endian,
    this.customData,
    this._isSorted,
    this._prefixBytes,
    this._postfixBytes,
    this._offsetIndex,
    this._entries,
  );

  late final _compressedByteCount =
      (_prefixBytes?.length ?? 0) + (_postfixBytes?.length ?? 0);

  @override
  Uint8List? getValue(List<int> input) {
    final key = input.toUint8List();
    if (key.length < _compressedByteCount) {
      return null;
    }
    if (_prefixBytes != null && _prefixBytes.isNotEmpty) {
      for (var i = 0; i < _prefixBytes.length; i++) {
        if (key[i] != _prefixBytes[i]) {
          return null;
        }
      }
    }
    if (_postfixBytes != null && _postfixBytes.isNotEmpty) {
      for (var i = _postfixBytes.length - 1; i >= 0; i--) {
        if (key[key.length - _postfixBytes.length + i] != _postfixBytes[i]) {
          return null;
        }
      }
    }
    final subkey = _compressedByteCount == 0
        ? key
        : key.sublist(_prefixBytes?.length ?? 0,
            key.length - (_postfixBytes?.length ?? 0));

    if (!_isSorted || _offsetIndex?.getOffset == null) {
      throw UnimplementedError('linear scan not implemented');
    }
    int start = 0;
    int end = _offsetIndex!.itemCount! - 1;

    final reader = BytesReader(_entries.entriesBytes, endian: _endian);
    while (start <= end) {
      final mid = (start + end) ~/ 2;
      final offset = _offsetIndex.getOffset!(mid);
      reader.goto(offset);
      final keyLength = _entries.keyLength.readLength(reader);
      // TODO: rewrite without subview
      final currentKey = reader.subview(keyLength);
      final c = subkey.compareTo(currentKey);

      if (c == 0) {
        final valueLength = _entries.valueLength.readLength(reader);
        return reader.subview(valueLength);
      }
      if (c < 0) {
        end = mid - 1;
        if (end < 0) {
          break;
        }
      } else {
        start = mid + 1;
        if (start >= _offsetIndex.itemCount!) {
          break;
        }
      }
    }
    return null;
  }

  @override
  Iterable<Uint8List> listKeys() {
    // TODO: implement listKeys (Should return [Uint8List] or a decoded `List<int>`?)
    throw UnimplementedError();
  }

  @override
  Iterable<MapEntry<Uint8List, Uint8List>> listEntries() {
    // TODO: Implement listEntries (should have a fast implementation without multiple accesses to [getValue]).
    throw UnimplementedError();
  }

  @override
  // TODO: Implement length (should be able to easily read the length from serialized bytes).
  int get length => throw UnimplementedError();

  @override
  bool append(List<int> key, List<int> value) {
    // TODO: Implement append (should write the new entry to the optionally allocated extra bytes).
    throw UnimplementedError();
  }

  @override
  Uint8List? delete(List<int> key) {
    // TODO: Implement delete (should mark an entry as deleted without actually removing it from serialization to avoid a full rewrite).
    throw UnimplementedError();
  }
}

class BPTreeV1Mutable implements MutableLookupMap {
  _BPTreeV1 _clean;
  _BPTreeV1? _dirty;
  int _maxDirtyLength;

  BPTreeV1Mutable._(this._clean, this._dirty, {int maxDirtyLength = 100})
      : _maxDirtyLength = math.max(maxDirtyLength, 10);

  factory BPTreeV1Mutable.parse(Uint8List cleanBytes,
          [Uint8List? dirtyBytes]) =>
      BPTreeV1Mutable._(
        BPTreeV1.parse(cleanBytes) as _BPTreeV1,
        dirtyBytes != null ? BPTreeV1.parse(dirtyBytes) as _BPTreeV1 : null,
      );

  int get maxDirtyLength => _maxDirtyLength;

  set maxDirtyLength(int value) {
    _maxDirtyLength = math.max(value, 10);
  }

  @override
  int get length {
    final dirty = _dirty;
    return dirty != null ? _clean.length + dirty.length : _clean.length;
  }

  @override
  Uint8List? getValue(List<int> key) =>
      _clean.getValue(key) ?? _dirty?.getValue(key);

  @override
  Uint8List? delete(List<int> key) => _clean.delete(key) ?? _dirty?.delete(key);

  @override
  Uint8List? putValue(List<int> key, List<int> value) {
    final prev = delete(key);

    final dirty = _dirty;

    if (dirty != null) {
      if (dirty.length > _maxDirtyLength) {
        _dirty = null;

        final allEntries = [
          ..._clean.listEntries(),
          ...dirty.listEntries(),
          MapEntry(key, value),
        ];

        _clean = _buildClean(allEntries);
        return prev;
      } else if (dirty.append(key, value)) {
        return prev;
      }
    }

    final dirtyEntries = [
      ...?dirty?.listEntries(),
      MapEntry(key, value),
    ];

    _dirty = _buildDirty(dirtyEntries);
    return prev;
  }

  _BPTreeV1 _buildClean(Iterable<MapEntry<List<int>, List<int>>> entries) {
    return BPTreeV1.parse(BPTreeV1.build(
      entries,
      endian: _clean._endian,
      keepEntryOrder: true,
      skipOffsetIndex: false,
      usePadding: false, // _clean.padded
    )) as _BPTreeV1;
  }

  _BPTreeV1 _buildDirty(Iterable<MapEntry<List<int>, List<int>>> entries) {
    return BPTreeV1.parse(BPTreeV1.build(
      entries,
      endian: _clean._endian,
      keepEntryOrder: false,
      skipOffsetIndex: true,
      usePadding: false, // _clean.padded
    )) as _BPTreeV1;
  }

  @override
  Iterable<Uint8List> listKeys() {
    final dirty = _dirty;
    return dirty != null
        ? [
            ..._clean.listKeys(),
            ...dirty.listKeys()
          ] // TODO: use  `CombinedIterableView` from `collection`
        : _clean.listKeys();
  }

  @override
  Iterable<MapEntry<Uint8List, Uint8List>> listEntries() {
    final dirty = _dirty;
    return dirty != null
        ? [
            ..._clean.listEntries(),
            ...dirty.listEntries()
          ] // TODO: use  `CombinedIterableView` from `collection`
        : _clean.listEntries();
  }
}
