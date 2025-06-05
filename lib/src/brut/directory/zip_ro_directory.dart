library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert'; // For utf8 decoding
import 'dart:io';
import 'dart:typed_data';

import 'abstract_directory.dart'; // Provides AbstractDirectoryBase
import 'directory.dart'; // Provides Directory, AbstractInputStream, AbstractOutputStream
// Assuming PathNotExistException and BytesInputStream are available/defined elsewhere
// For example:
// import 'package:apktool_dart/src/brut/directory/directory_exception.dart'; // For PathNotExistException
// import 'package:apktool_dart/src/brut/io/bytes_input_stream.dart'; // For BytesInputStream

// Placeholder for BytesInputStream - actual implementation should be in its own file.
// This is just to make the code below more concrete.
// Ensure this matches or is compatible with the actual AbstractInputStream definition.
class BytesInputStream extends AbstractInputStream {
  final Uint8List _data;
  int _position = 0;
  bool _closed = false;

  BytesInputStream(this._data);

  @override
  bool get isClosed => _closed;

  @override
  Stream<List<int>> asStream() {
    // This basic implementation reads the remainder of the data when the stream is listened to.
    // A more sophisticated stream would emit chunks.
    return Stream.fromFuture(
      Future(() async {
        if (_closed || _position >= _data.length) {
          return Uint8List(0); // Empty list if closed or no data left
        }
        final remainingData = _data.sublist(_position);
        _position = _data.length; // Mark as fully consumed
        return remainingData;
      }),
    ).where(
      (chunk) => chunk.isNotEmpty,
    ); // Filter out empty chunks if stream logic implies it
  }

  Future<int> readByte() async {
    if (_closed || _position >= _data.length) return -1; // EOF
    return _data[_position++];
  }

  @override
  Future<int> read(Uint8List buffer, int offset, int length) async {
    if (_closed) {
      return -1; // Or throw an exception if reading from a closed stream is an error
    }
    if (offset < 0 || length < 0 || offset + length > buffer.length) {
      throw ArgumentError('Invalid offset or length for read buffer');
    }
    if (_position >= _data.length) return -1; // EOF

    int bytesToRead = length;
    if (_position + bytesToRead > _data.length) {
      bytesToRead = _data.length - _position;
    }
    if (bytesToRead <= 0) return 0;

    buffer.setRange(offset, offset + bytesToRead, _data, _position);
    _position += bytesToRead;
    return bytesToRead;
  }

  Future<List<int>> readNBytes(int n) async {
    if (_closed) return Uint8List(0); // Or throw
    if (n < 0) {
      throw ArgumentError("Number of bytes to read cannot be negative.");
    }
    if (n == 0) return Uint8List(0);

    final bytesToEnd = _data.length - _position;
    final bytesToRead = (bytesToEnd < n) ? bytesToEnd : n;

    if (bytesToRead <= 0) return Uint8List(0);

    final result = _data.sublist(_position, _position + bytesToRead);
    _position += bytesToRead;
    return result;
  }

  Future<int> available() async {
    if (_closed) return 0;
    return _data.length - _position;
  }

  @override
  Future<void> close() async {
    _closed = true;
  }
}

// Placeholder for PathNotExistException
class PathNotExistException implements Exception {
  final String path;
  final String message;
  PathNotExistException(this.path, [String? msg])
    : message = msg ?? "Path does not exist: $path";
  @override
  String toString() => message;
}

class _ZipEntry {
  final String name;
  final int compressionMethod;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;
  final int crc32;
  final bool isDirectory;
  // final int lastModFileTime; // Not currently used
  // final int lastModFileDate; // Not currently used

  _ZipEntry({
    required this.name,
    required this.compressionMethod,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
    required this.crc32,
  }) : isDirectory = name.endsWith('/');
}

class ZipRODirectory extends AbstractDirectoryBase {
  final String? _zipFilePath;
  final String _pathInZip;

  Uint8List? _zipData;
  List<_ZipEntry>? _allEntries;

  // Instance members for ZipRODirectory to store its own files and directories
  // These will be returned by the overridden loadInitialContent method
  final Set<String> _files = {}; // Initialize to empty
  final Map<String, AbstractDirectoryBase> _dirs = {}; // Initialize to empty

  bool _isInitialized =
      false; // Tracks ZipRODirectory's own initialization status
  Future<void>? _initializationFuture;

  ZipRODirectory(String zipFilePath, [String pathInZip = ''])
    : _zipFilePath = zipFilePath,
      _pathInZip = _normalizePath(pathInZip),
      super();

  ZipRODirectory._fromSharedData(
    this._zipData,
    this._allEntries,
    String pathInZip,
  ) : _zipFilePath = null,
      _pathInZip = _normalizePath(pathInZip),
      super() {
    if (_zipData != null && _allEntries != null) {
      _populateFilesAndDirs();
      _isInitialized = true;
    }
  }

  static String _normalizePath(String path) {
    if (path.isEmpty) return '';
    var p = path.replaceAll('\\', '/');
    if (p.startsWith('/')) p = p.substring(1);
    if (p.isNotEmpty && !p.endsWith('/')) p += '/';
    return p;
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    // Use a shared future to prevent multiple initializations if called concurrently
    _initializationFuture ??= _doInitialize();
    return _initializationFuture;
  }

  Future<void> _doInitialize() async {
    try {
      if (_zipFilePath != null && _zipData == null) {
        final file = File(_zipFilePath);
        if (!await file.exists()) {
          throw PathNotExistException(
            _zipFilePath,
            "ZIP file not found at $_zipFilePath",
          );
        }
        _zipData = await file.readAsBytes();
      }

      if (_zipData == null) {
        throw StateError("ZipRODirectory has no data source.");
      }

      _allEntries ??= await _parseCentralDirectory(_zipData!);

      _populateFilesAndDirs();
      _isInitialized = true;
    } catch (e) {
      _isInitialized = false;
      rethrow;
    }
  }

  void _populateFilesAndDirs() {
    if (_allEntries == null || _zipData == null) return;
    _files.clear();
    _dirs.clear();

    final Set<String> addedSubDirNames = {};

    for (final entry in _allEntries!) {
      if (!entry.name.startsWith(_pathInZip)) {
        continue;
      }

      final relativeName = entry.name.substring(_pathInZip.length);
      if (relativeName.isEmpty || relativeName.contains('../')) {
        continue;
      }

      final separatorIndex = relativeName.indexOf('/');
      if (separatorIndex == -1) {
        // A file in the current directory level.
        if (!entry.isDirectory) {
          _files.add(relativeName);
        }
      } else {
        // An entry in a subdirectory.
        final dirName = relativeName.substring(0, separatorIndex);
        if (dirName.isNotEmpty && !addedSubDirNames.contains(dirName)) {
          final subDir = ZipRODirectory._fromSharedData(
            _zipData!,
            _allEntries!,
            '$_pathInZip$dirName/',
          );
          // This sub-directory will recursively populate its own files/dirs upon access.
          _dirs[dirName] = subDir as AbstractDirectoryBase;
          addedSubDirNames.add(dirName);
        }
      }
    }
  }

  // Override the loadInitialContent method required by AbstractDirectoryBase
  @override
  Future<DirectoryContent> loadInitialContent() async {
    if (!_isInitialized) await initialize();
    return DirectoryContent(Set.from(_files), Map.from(_dirs));
  }

  // Override getFiles to provide proper recursive functionality
  @override
  Future<Set<String>> getFiles({bool recursive = false}) async {
    if (!_isInitialized) await initialize();

    if (!recursive) {
      return UnmodifiableSetView(_files);
    }

    // For recursive, build the full list from the master _allEntries list
    final files = <String>{};
    for (final entry in _allEntries!) {
      if (entry.name.startsWith(_pathInZip) && !entry.isDirectory) {
        final relativePath = entry.name.substring(_pathInZip.length);
        if (relativePath.isNotEmpty) {
          files.add(relativePath);
        }
      }
    }
    return UnmodifiableSetView(files);
  }

  static Future<List<_ZipEntry>> _parseCentralDirectory(
    Uint8List zipData,
  ) async {
    int eocdOffset = -1;
    const eocdSignature = 0x06054b50;
    const minEocdSize = 22;
    // Max ZIP comment length is 65535. EOCD is at the end.
    // Search window: minEocdSize + maxCommentLength
    final searchLimit = (zipData.length < minEocdSize + 65535)
        ? 0
        : zipData.length - (minEocdSize + 65535);

    for (int i = zipData.length - minEocdSize; i >= searchLimit; i--) {
      if (zipData.length - i < 4) continue; // Bounds check for getUint32
      // Read potential signature directly as Uint32 for efficiency
      final ByteData sigView = ByteData.sublistView(zipData, i, i + 4);
      if (sigView.getUint32(0, Endian.little) == eocdSignature) {
        // Verify this is a valid EOCD (e.g. check comment length vs remaining bytes)
        if (zipData.length >= i + minEocdSize) {
          final ByteData eocdTestView = ByteData.sublistView(zipData, i);
          final int commentLength = eocdTestView.getUint16(20, Endian.little);
          if (i + minEocdSize + commentLength == zipData.length) {
            eocdOffset = i;
            break;
          }
        }
      }
    }

    if (eocdOffset == -1) {
      throw FormatException(
        "End of Central Directory record not found or invalid.",
      );
    }

    final eocdView = ByteData.sublistView(zipData, eocdOffset);
    final int totalEntries = eocdView.getUint16(10, Endian.little);
    final int cdSizeBytes = eocdView.getUint32(
      12,
      Endian.little,
    ); // Size of Central Directory
    final int cdStartOffset = eocdView.getUint32(16, Endian.little);

    if (cdStartOffset + cdSizeBytes > zipData.length) {
      throw FormatException("Central Directory offset/size out of bounds.");
    }

    final List<_ZipEntry> entries = [];
    ByteData cdView = ByteData.sublistView(
      zipData,
      cdStartOffset,
      cdStartOffset + cdSizeBytes,
    );
    int currentOffsetInCD = 0;
    const cdfhSignature = 0x02014b50;

    for (int i = 0; i < totalEntries; i++) {
      if (currentOffsetInCD + 46 > cdView.lengthInBytes) {
        // Min CDFH size
        throw FormatException("Central Directory too short for entry $i.");
      }
      if (cdView.getUint32(currentOffsetInCD, Endian.little) != cdfhSignature) {
        throw FormatException(
          "Invalid Central Directory File Header signature at entry $i.",
        );
      }

      final int compressionMethod = cdView.getUint16(
        currentOffsetInCD + 10,
        Endian.little,
      );
      final int crc32 = cdView.getUint32(currentOffsetInCD + 16, Endian.little);
      final int compressedSize = cdView.getUint32(
        currentOffsetInCD + 20,
        Endian.little,
      );
      final int uncompressedSize = cdView.getUint32(
        currentOffsetInCD + 24,
        Endian.little,
      );
      final int fileNameLength = cdView.getUint16(
        currentOffsetInCD + 28,
        Endian.little,
      );
      final int extraFieldLength = cdView.getUint16(
        currentOffsetInCD + 30,
        Endian.little,
      );
      final int fileCommentLength = cdView.getUint16(
        currentOffsetInCD + 32,
        Endian.little,
      );
      final int relativeOffsetLocalHeader = cdView.getUint32(
        currentOffsetInCD + 42,
        Endian.little,
      );

      final int fileNameStart = currentOffsetInCD + 46;
      if (fileNameStart + fileNameLength > cdView.lengthInBytes) {
        throw FormatException("File name length out of bounds for entry $i.");
      }
      String fileName = utf8.decode(
        Uint8List.sublistView(
          cdView,
          fileNameStart,
          fileNameStart + fileNameLength,
        ),
      );

      entries.add(
        _ZipEntry(
          name: fileName,
          compressionMethod: compressionMethod,
          compressedSize: compressedSize,
          uncompressedSize: uncompressedSize,
          localHeaderOffset: relativeOffsetLocalHeader,
          crc32: crc32,
        ),
      );

      currentOffsetInCD +=
          46 + fileNameLength + extraFieldLength + fileCommentLength;
    }
    return entries;
  }

  @override
  Future<AbstractDirectoryBase> createDirLocal(String name) {
    throw UnsupportedError("ZipRODirectory is read-only.");
  }

  @override
  Future<AbstractInputStream> getFileInputLocal(String name) async {
    if (!_isInitialized) await initialize(); // Auto-initialize if not done.

    final String fullPathInZip = _pathInZip + name;
    _ZipEntry? entry;
    try {
      entry = _allEntries!.firstWhere(
        (e) => e.name == fullPathInZip && !e.isDirectory,
      );
    } catch (e) {
      throw PathNotExistException(
        fullPathInZip,
        "File not found or is a directory: $fullPathInZip",
      );
    }

    if (_zipData == null) throw StateError("Zip data is not loaded.");
    final zipDataRef = _zipData!;

    if (entry.localHeaderOffset + 30 > zipDataRef.lengthInBytes) {
      // Min LFH size
      throw FormatException(
        "Local File Header offset out of bounds for $fullPathInZip.",
      );
    }
    final ByteData lfhView = ByteData.sublistView(
      zipDataRef,
      entry.localHeaderOffset,
    );
    const lfhSignature = 0x04034b50;
    if (lfhView.getUint32(0, Endian.little) != lfhSignature) {
      throw FormatException(
        "Invalid Local File Header signature for $fullPathInZip.",
      );
    }

    final int lfhFileNameLength = lfhView.getUint16(26, Endian.little);
    final int lfhExtraFieldLength = lfhView.getUint16(28, Endian.little);
    final int lfhHeaderFixedSize = 30;

    final int dataStartOffset =
        entry.localHeaderOffset +
        lfhHeaderFixedSize +
        lfhFileNameLength +
        lfhExtraFieldLength;
    if (dataStartOffset + entry.compressedSize > zipDataRef.lengthInBytes) {
      throw FormatException("File data out of bounds for $fullPathInZip.");
    }
    final Uint8List compressedData = Uint8List.sublistView(
      zipDataRef,
      dataStartOffset,
      dataStartOffset + entry.compressedSize,
    );

    Uint8List uncompressedData;
    if (entry.compressionMethod == 0) {
      // Store
      uncompressedData = compressedData;
    } else if (entry.compressionMethod == 8) {
      // Deflate
      final decoder = ZLibDecoder(raw: true);
      try {
        uncompressedData = Uint8List.fromList(decoder.convert(compressedData));
      } catch (e) {
        throw FormatException(
          "Failed to decompress $fullPathInZip (DEFLATE): $e",
        );
      }
    } else {
      throw UnimplementedError(
        "Unsupported compression method: ${entry.compressionMethod} for $fullPathInZip",
      );
    }

    if (uncompressedData.length != entry.uncompressedSize) {
      // Some tools might write incorrect uncompressed size for 0-byte files if compressed
      // or if using data descriptors that aren't being read here.
      // For now, strict check.
      throw FormatException(
        "Decompressed size mismatch for $fullPathInZip. Expected ${entry.uncompressedSize}, got ${uncompressedData.length}",
      );
    }

    // TODO: Optionally verify CRC32: Crc32().convert(uncompressedData) == entry.crc32

    return BytesInputStream(uncompressedData);
  }

  @override
  Future<AbstractOutputStream> getFileOutputLocal(String name) {
    throw UnsupportedError("ZipRODirectory is read-only.");
  }

  // These methods are no longer needed since AbstractDirectoryBase handles initialization
  Set<String> loadInitialFiles() {
    // This method is obsolete - AbstractDirectoryBase uses loadInitialContent instead
    return Set.unmodifiable(_files);
  }

  Map<String, AbstractDirectoryBase> loadInitialDirs() {
    // This method is obsolete - AbstractDirectoryBase uses loadInitialContent instead
    return Map.unmodifiable(_dirs);
  }

  @override
  Future<void> removeFileLocal(String name) {
    throw UnsupportedError("ZipRODirectory is read-only.");
  }

  // These methods now properly match the AbstractDirectoryBase signatures
  @override
  Future<bool> containsFile(String path) async {
    if (!_isInitialized) await initialize();
    return _files.contains(path);
  }

  @override
  Future<bool> containsDir(String path) async {
    if (!_isInitialized) await initialize();
    return _dirs.containsKey(path);
  }

  Future<int> getUncompressedFileSize(String fileName) async {
    if (!_isInitialized) await initialize(); // Auto-initialize
    final String fullPathInZip = _pathInZip + fileName;
    _ZipEntry? entry;
    try {
      entry = _allEntries!.firstWhere(
        (e) => e.name == fullPathInZip && !e.isDirectory,
      );
    } catch (e) {
      throw PathNotExistException(
        fileName,
        "File not found for size: $fullPathInZip",
      );
    }
    return entry.uncompressedSize;
  }

  Future<int> getCompressedFileSize(String fileName) async {
    if (!_isInitialized) await initialize(); // Auto-initialize
    final String fullPathInZip = _pathInZip + fileName;
    _ZipEntry? entry;
    try {
      entry = _allEntries!.firstWhere(
        (e) => e.name == fullPathInZip && !e.isDirectory,
      );
    } catch (e) {
      throw PathNotExistException(
        fileName,
        "File not found for compressed size: $fullPathInZip",
      );
    }
    return entry.compressedSize;
  }

  Future<int> getFileCompressionMethod(String fileName) async {
    if (!_isInitialized) await initialize(); // Auto-initialize
    final String fullPathInZip = _pathInZip + fileName;
    _ZipEntry? entry;
    try {
      entry = _allEntries!.firstWhere(
        (e) => e.name == fullPathInZip && !e.isDirectory,
      );
    } catch (e) {
      throw PathNotExistException(
        fileName,
        "File not found for compression method: $fullPathInZip",
      );
    }
    return entry.compressionMethod;
  }
}
