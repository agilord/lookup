Constant (read-only / immutable) data structures optimized for effiecient lookup
operations, indexing and search in memory and on disk.

## Features

**Implemented**:

- (partial) [B+tree](https://en.wikipedia.org/wiki/B%2B_tree) (`bptree/v1`)

**Planned**:

- [key/value hash table](https://en.wikipedia.org/wiki/Hash_table)
- [trie](https://en.wikipedia.org/wiki/Trie)
- [BK-tree](https://en.wikipedia.org/wiki/BK-tree)
- [Levenshtein automaton](https://en.wikipedia.org/wiki/Levenshtein_automaton)

## Goals and conventions

The goal of this package is to create low-level building blocks and composable
structures that could support efficient data lookup and search in read-only
index. Keys and values are arbitrary-length bytes without any restriction.

The formats are using binary encoding that can be read from file and be used
without further processing or (significant) memory allocation. By default
little-endian encoding is used, with an option to specify big-endian when
the target architecture is using that.

The implemented structures are placed in separate libraries that have their
own version number, in order to allow introducing changes (in a new version)
without breaking existing files. Each structure starts with 3 bytes that
identifies it (using the md5 hash of their `<name>/<version>`).

The implemented structures have an internal version value that allow some
features to be unimplemented later, while making it clear for the client
that they should be upgraded to read it.

The block size, content size and offset encodings are dynamic, to support both
small and large data sets, tuned efficiently for the specific use case. The
build process of the binary content should support both below 4 KiB and over
4 GiB block sizes.

## How to contribute?

Please open new issues to discuss features, structures and use cases, *before*
submitting any code.
