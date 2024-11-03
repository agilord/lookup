import 'dart:math';
import 'dart:typed_data';

import 'uleb128.dart';

final emptyBytes = Uint8List(0).asUnmodifiableView();

enum UintSize {
  uint8,
  uint16,
  uint32,
  uint64;

  static UintSize select(int value) {
    if (value <= 0xff) {
      return uint8;
    } else if (value <= 0xffff) {
      return uint16;
    } else if (value <= 0xffffffff) {
      return uint32;
    } else {
      return uint64;
    }
  }
}

class BytesReader {
  final Uint8List _bytes;
  int _offset;
  late final _bd = ByteData.view(_bytes.buffer, _bytes.offsetInBytes);
  final Endian endian;

  BytesReader(
    this._bytes, {
    int offset = 0,
    Endian? endian,
  })  : _offset = offset,
        endian = endian ?? Endian.little;

  int get offset => _offset;

  void goto(int offset) {
    _offset = offset;
  }

  int readUint8() {
    return _bytes[_offset++];
  }

  int readUint16() {
    final offset_ = _offset;
    _offset += 2;
    return _bd.getUint16(offset_, endian);
  }

  int readUint32() {
    final offset_ = _offset;
    _offset += 4;
    return _bd.getUint32(offset_, endian);
  }

  int readUint64() {
    final offset_ = _offset;
    _offset += 8;
    return _bd.getUint64(offset_, endian);
  }

  int readVarint() {
    if (endian == Endian.little) {
      return _readUleb128();
    } else {
      throw UnimplementedError();
    }
  }

  int _readUleb128() {
    final r = decodeUleb128(_bytes, _offset);
    _offset += r.size;
    return r.value;
  }

  void skip(int length) {
    _offset += length;
  }

  void skipPaddingFor8() {
    final remainder = _offset & 0x07;
    if (remainder == 0) return;
    _offset += 8 - remainder;
  }

  Uint8List subviewRemaining() {
    return subview(_bytes.length - _offset);
  }

  Uint8List subview(int length) {
    final offset_ = _offset;
    _offset += length;
    return Uint8List.sublistView(_bytes, offset_, offset_ + length);
  }

  Uint16List subviewUint16(int length) {
    final offset_ = _offset;
    _offset += length;
    if (endian == Endian.host) {
      return Uint16List.sublistView(_bytes, offset_, offset_ + length);
    } else {
      throw UnimplementedError();
    }
  }

  Uint32List subviewUint32(int length) {
    final offset_ = _offset;
    _offset += length;
    if (endian == Endian.host) {
      return Uint32List.sublistView(_bytes, offset_, offset_ + length);
    } else {
      throw UnimplementedError();
    }
  }

  Uint64List subviewUint64(int length) {
    final offset_ = _offset;
    _offset += length;
    if (endian == Endian.host) {
      return Uint64List.sublistView(_bytes, offset_, offset_ + length);
    } else {
      throw UnimplementedError();
    }
  }
}

extension Uint8ListExt on Uint8List {
  int compareTo(Uint8List other) {
    final minLength = min(length, other.length);
    for (var i = 0; i < minLength; i++) {
      final c = this[i].compareTo(other[i]);
      if (c != 0) return c;
    }
    return length.compareTo(other.length);
  }
}

extension ListIntExt on List<int> {
  Uint8List toUint8List() =>
      this is Uint8List ? this as Uint8List : Uint8List.fromList(this);
}

class BytesWriter {
  final builder = BytesBuilder(copy: false);
  final Endian endian;

  BytesWriter(this.endian);

  int get length => builder.length;

  void write(List<int> bytes) => builder.add(bytes);

  void writeUint8(int value) {
    if (value < 0 || value > 255) {
      throw ArgumentError();
    }
    builder.addByte(value);
  }

  void writeUint16(int value) {
    final data = ByteData(2)..setUint16(0, value, endian);
    builder.add(data.buffer.asUint8List());
  }

  void writeUint32(int value) {
    final data = ByteData(4)..setUint32(0, value, endian);
    builder.add(data.buffer.asUint8List());
  }

  void writeUint64(int value) {
    final data = ByteData(8)..setUint64(0, value, endian);
    builder.add(data.buffer.asUint8List());
  }

  void writeVarint(int value) {
    if (endian == Endian.little) {
      _writeUleb128(value);
    } else {
      throw UnimplementedError();
    }
  }

  void _writeUleb128(int value) {
    builder.add(encodeUleb128(value).bytes);
  }

  void writePadding8() {
    final remainder = length & 0x07;
    if (remainder == 0) return;
    final count = 8 - remainder;
    write(Uint8List(count));
  }

  Uint8List toBytes() => builder.toBytes();
}
