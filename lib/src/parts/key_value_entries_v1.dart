import 'dart:typed_data';

import 'package:lookup/src/parts/length_encoding_3bit_v1.dart';
import 'package:lookup/src/utils/bytes.dart';

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
class KeyValueEntriesV1 {
  final LengthEncoding3bitV1 keyLength;
  final LengthEncoding3bitV1 valueLength;
  final Uint8List entriesBytes;

  KeyValueEntriesV1._(this.keyLength, this.valueLength, this.entriesBytes);

  factory KeyValueEntriesV1.fromReader(BytesReader reader) {
    final firstByte = reader.readUint8();
    final keyCode = firstByte & 0x07;
    final valueCode = (firstByte >> 3) & 0x07;
    final isPadded = (firstByte & 0x40) != 0;

    if ((firstByte >> 7) > 0) {
      throw UnimplementedError();
    }
    final keyLength = LengthEncoding3bitV1.fromCodeAndReader(keyCode, reader);
    final valueLength =
        LengthEncoding3bitV1.fromCodeAndReader(valueCode, reader);

    final totalBytes = reader.readVarint();
    if (isPadded) {
      reader.skipPaddingFor8();
    }
    final entries = reader.subview(totalBytes);
    return KeyValueEntriesV1._(keyLength, valueLength, entries);
  }
}
