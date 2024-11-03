import 'dart:math';
import 'dart:typed_data';

import '../utils/bytes.dart';

/// The *length encoding* describes the length of an arbitrary sized data,
/// typically prepending their bytes with a length field or setting a
/// const-length key.
///
/// The specification of the length encoding may take multiple bytes, initialized by
/// 3 bits on a header byte.
///
/// The code values can be the following:
/// - `0`: length is prefixed with a 1-byte `uint8`
/// - `1`: length is prefixed with a 2-bytes `uint16`
/// - `2`: length is prefixed with a 4-bytes `uint32`
/// - `3`: length is prefixed with a 8-bytes `uint64`
/// - `4`: length is prefixed with a `varint` value
/// - `5`-`6`: reserved for future use
/// - `7`: length is const, specified with a follow-up `varint` value
class LengthEncoding3bitV1 {
  final LengthReaderFn readLength;

  LengthEncoding3bitV1._(this.readLength);

  factory LengthEncoding3bitV1.fromCodeAndReader(int code, BytesReader reader) {
    switch (code) {
      case 0:
        return LengthEncoding3bitV1._(_dynamicUint8Reader);
      case 1:
        return LengthEncoding3bitV1._(_dynamicUint16Reader);
      case 2:
        return LengthEncoding3bitV1._(_dynamicUint32Reader);
      case 3:
        return LengthEncoding3bitV1._(_dynamicUint64Reader);
      case 4:
        return LengthEncoding3bitV1._(_dynamicVarintReader);
      case 7:
        final length = reader.readVarint();
        return LengthEncoding3bitV1._((_) => length);
      default:
        throw UnimplementedError();
    }
  }
}

typedef LengthReaderFn = int Function(BytesReader reader);
typedef LengthWriterFn = void Function(BytesWriter writer, int value);

int _dynamicUint8Reader(BytesReader reader) => reader.readUint8();
int _dynamicUint16Reader(BytesReader reader) => reader.readUint16();
int _dynamicUint32Reader(BytesReader reader) => reader.readUint32();
int _dynamicUint64Reader(BytesReader reader) => reader.readUint64();
int _dynamicVarintReader(BytesReader reader) => reader.readVarint();

class LengthEncoding3bitV1Builder {
  final int code;
  final Uint8List bytes;
  final LengthWriterFn writeLength;

  LengthEncoding3bitV1Builder._(this.code, this.bytes, this.writeLength);

  factory LengthEncoding3bitV1Builder.fromValues(Iterable<int> values) {
    int minLength = 0, maxLength = 0;
    for (final v in values) {
      minLength = minLength == 0 ? v : min(v, minLength);
      maxLength = max(v, maxLength);
    }
    if (minLength == maxLength) {
      // TODO: const value may be an option
    }

    // TODO: detect if/when varint would be better
    final uintSize = UintSize.select(maxLength);
    switch (uintSize) {
      case UintSize.uint8:
        return LengthEncoding3bitV1Builder._(
            0, emptyBytes, _dynamicUint8Writers);
      case UintSize.uint16:
        return LengthEncoding3bitV1Builder._(
            1, emptyBytes, _dynamicUint16Writers);
      case UintSize.uint32:
        return LengthEncoding3bitV1Builder._(
            2, emptyBytes, _dynamicUint32Writers);
      case UintSize.uint64:
        return LengthEncoding3bitV1Builder._(
            3, emptyBytes, _dynamicUint64Writers);
    }
  }

  void writeInto(BytesWriter writer) {
    writer.writeUint8(code);
  }
}

void _dynamicUint8Writers(BytesWriter writer, int value) {
  writer.writeUint8(value);
}

void _dynamicUint16Writers(BytesWriter writer, int value) {
  writer.writeUint16(value);
}

void _dynamicUint32Writers(BytesWriter writer, int value) {
  writer.writeUint32(value);
}

void _dynamicUint64Writers(BytesWriter writer, int value) {
  writer.writeUint64(value);
}
