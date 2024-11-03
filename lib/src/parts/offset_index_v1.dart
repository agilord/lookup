import 'dart:math';
import 'dart:typed_data';

import '../utils/bytes.dart';

/// The offset index is a list of precomputed positions, which can be used
/// as entry points into the key-value bytes.
///
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
class OffsetIndexV1 {
  int? itemCount;
  PositionReaderFn? getOffset;

  OffsetIndexV1._(this.itemCount, this.getOffset);

  factory OffsetIndexV1.fromReader(
    BytesReader reader, {
    required int? entriesCount,
  }) {
    final codeByte = reader.readUint8();
    final typeCode = codeByte & 0x03;
    final isCountPresent = (codeByte & 0x04) != 0;
    final isPadded = (codeByte & 0x08) != 0;

    final sparseCode = (codeByte >> 4) & 0x0f;
    if (sparseCode > 0) {
      throw UnimplementedError();
    }

    late int itemCount;
    if (isCountPresent) {
      itemCount = reader.readVarint();
    } else if (entriesCount == null) {
      throw FormatException('Missing entries or item count.');
    } else {
      itemCount = entriesCount;
    }

    if (isPadded) {
      reader.skipPaddingFor8();
    }

    // TODO: explore Uint16List & co
    switch (typeCode) {
      case 0:
        final bytes = reader.subview(itemCount);
        return OffsetIndexV1._(itemCount, (index) => bytes[index]);
      case 1:
        final bytes = reader.subview(itemCount * 2);
        final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes);
        return OffsetIndexV1._(
            itemCount, (index) => bd.getUint16(index * 2, reader.endian));
      case 2:
        final bytes = reader.subview(itemCount * 4);
        final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes);
        return OffsetIndexV1._(
            itemCount, (index) => bd.getUint32(index * 4, reader.endian));
      case 3:
        final bytes = reader.subview(itemCount * 8);
        final bd = ByteData.view(bytes.buffer, bytes.offsetInBytes);
        return OffsetIndexV1._(
            itemCount, (index) => bd.getUint64(index * 8, reader.endian));
      default:
        throw UnimplementedError();
    }
  }
}

typedef PositionReaderFn = int Function(int index);

void writeOffsetIndex(
  BytesWriter writer,
  List<int> values, {
  required int? entriesCount,
  required bool isPadded,
}) {
  final uintSize =
      values.isEmpty ? UintSize.uint8 : UintSize.select(values.reduce(max));

  final includeCount = entriesCount != values.length;

  late int code;
  late Uint8List positionBytes;
  switch (uintSize) {
    case UintSize.uint8:
      code = 0;
      positionBytes = Uint8List.fromList(values);
      break;
    case UintSize.uint16:
      code = 1;
      positionBytes = Uint8List(values.length * 2);
      final bd = positionBytes.buffer.asByteData();
      for (var i = 0; i < values.length; i++) {
        bd.setUint16(i * 2, values[i], writer.endian);
      }
      break;
    case UintSize.uint32:
      code = 2;
      positionBytes = Uint8List(values.length * 4);
      final bd = positionBytes.buffer.asByteData();
      for (var i = 0; i < values.length; i++) {
        bd.setUint32(i * 4, values[i], writer.endian);
      }
      break;
    case UintSize.uint64:
      code = 3;
      positionBytes = Uint8List(values.length * 8);
      final bd = positionBytes.buffer.asByteData();
      for (var i = 0; i < values.length; i++) {
        bd.setUint64(i * 8, values[i], writer.endian);
      }
      break;
  }
  final firstByte = code | (includeCount ? 0x04 : 0) | (isPadded ? 0x08 : 0);
  writer.writeUint8(firstByte);
  if (includeCount) {
    writer.writeVarint(values.length);
  }
  if (isPadded) {
    writer.writePadding8();
  }
  writer.write(positionBytes);
}
