import 'dart:math';
import 'dart:typed_data';

/// Converts a list of bytes that represent an ULEB128 value
/// into an unsigned integer. Returns the (value and the byte size).
({int value, int size}) decodeUleb128(Uint8List bytes, [int offset = 0]) {
  int result = 0;
  int shift = 0;
  int size = 0;
  int i = offset;
  while (true) {
    final byte = bytes[i++] & 0xff;
    result |= (byte & 0x7f) << shift;
    size++;
    if ((byte & 0x80) == 0) break;
    shift += 7;
  }
  return (value: result, size: size);
}

final _uintBitLengthSizes = List.generate(64, (i) => (max(1, i) / 7).ceil());

/// Converts an unsigned integer into a list of bytes that represents an
/// LEB128 value. Returns the (byte buffer (new if provided) and the byte size).
({Uint8List bytes, int size}) encodeUleb128(int value,
    [Uint8List? bytes, int offset = 0]) {
  final size = _uintBitLengthSizes[value.bitLength];
  bytes ??= Uint8List(size);
  int i = 0;
  while (i < size) {
    var part = value & 0x7f;
    value >>= 7;
    if (value > 0) {
      part = part | 0x80;
    }
    bytes[offset + i] = part;
    i++;
  }
  return (bytes: bytes, size: size);
}
