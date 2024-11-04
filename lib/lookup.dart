import 'dart:typed_data';

/// A data structure that maps binary keys to binary values.
abstract class LookupMap {
  /// The entries length. See [listEntries].
  int get length;

  /// Returns the corresponding value of [key].
  ///
  /// Returns `null` when [key] is not part of the data structure.
  Uint8List? getValue(List<int> key);

  /// List keys that are part of the data structure.
  Iterable<Uint8List> listKeys();

  /// List all entries. See [listKeys].
  Iterable<MapEntry<Uint8List, Uint8List>> listEntries() =>
      listKeys().map((key) => MapEntry(key, getValue(key)!));

  /// Mark a key as deleted and return it's value.
  Uint8List? delete(List<int> key);
}

/// A Mutable [LookupMap]
abstract class MutableLookupMap extends LookupMap {
  /// Puts an entry, overwriting the current key or appending it.
  Uint8List? putValue(List<int> key, List<int> value);
}
