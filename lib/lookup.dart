import 'dart:typed_data';

/// A data structure that maps binary keys to binary values.
abstract class LookupMap {
  /// Returns the corresponding value of [key].
  ///
  /// Returns `null` when [key] is not part of the data structure.
  Uint8List? getValue(List<int> key);

  /// List keys that are part of the data structure.
  Iterable<Uint8List> listKeys();
}
