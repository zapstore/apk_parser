library;

import 'dart:io';
import 'directory_exception.dart';

/// Manual ZIP reader implementation for fallback when archive package fails
/// Implements basic ZIP parsing to extract files from APK/ZIP archives
class ManualZipReader {
  final String _filePath;
  late final RandomAccessFile _file;
  late final List<ZipFileEntry> _entries;
  bool _isInitialized = false;

  ManualZipReader(this._filePath);

  Future<void> initialize() async {
    if (_isInitialized) return;

    final file = File(_filePath);
    if (!await file.exists()) {
      throw DirectoryException('ZIP file not found: $_filePath');
    }

    try {
      _file = await file.open(mode: FileMode.read);
      await _findCentralDirectory();
      _isInitialized = true;
    } catch (e) {
      // If initialization fails, try to close the file handle
      try {
        await _file.close();
      } catch (_) {
        // Ignore close errors during cleanup
      }
      throw DirectoryException(
        'Failed to initialize ZIP reader for $_filePath: $e',
      );
    }
  }

  Future<void> close() async {
    if (_isInitialized) {
      try {
        await _file.close();
      } catch (_) {
        // Ignore close errors
      }
      _isInitialized = false;
    }
  }

  List<ZipFileEntry> get entries {
    if (!_isInitialized) {
      throw DirectoryException('ManualZipReader not initialized');
    }
    return List.unmodifiable(_entries);
  }

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
  }

  Future<ZipFileEntry?> findFile(String fileName) async {
    await _ensureInitialized();

    for (final entry in _entries) {
      if (entry.fileName == fileName) {
        return entry;
      }
    }
    return null;
  }

  Future<List<int>> extractFile(ZipFileEntry entry) async {
    await _ensureInitialized();

    // Seek to local file header
    await _file.setPosition(entry.localHeaderOffset);

    // Read local file header
    final localHeader = await _readLocalFileHeader();

    // Calculate actual data offset (header + filename + extra field)
    final dataOffset =
        entry.localHeaderOffset +
        30 +
        localHeader.fileNameLength +
        localHeader.extraFieldLength;

    await _file.setPosition(dataOffset);

    // Read compressed data
    final compressedData = await _file.read(entry.compressedSize);

    if (entry.compressionMethod == 0) {
      // Stored (no compression)
      return compressedData;
    } else if (entry.compressionMethod == 8) {
      // Deflate compression
      return _inflateData(compressedData, entry.uncompressedSize);
    } else {
      throw DirectoryException(
        'Unsupported compression method: ${entry.compressionMethod}',
      );
    }
  }

  /// Find and parse the central directory
  Future<void> _findCentralDirectory() async {
    final fileSize = await _file.length();

    // Look for End of Central Directory Record (EOCD)
    // Start from end and search backwards for signature 0x06054b50
    final eocdPosition = await _findEndOfCentralDirectory(fileSize);

    // Read EOCD record
    await _file.setPosition(eocdPosition);
    final eocd = await _readEndOfCentralDirectoryRecord();

    // Check if ZIP64 format
    if (eocd.centralDirectoryOffset == 0xFFFFFFFF) {
      // ZIP64 format - find ZIP64 EOCD locator
      final zip64EocdPosition = await _findZip64EndOfCentralDirectory(
        eocdPosition,
      );
      await _file.setPosition(zip64EocdPosition);
      final zip64Eocd = await _readZip64EndOfCentralDirectoryRecord();
      await _readCentralDirectoryEntries(
        zip64Eocd.centralDirectoryOffset,
        zip64Eocd.totalEntries,
      );
    } else {
      // Regular ZIP format
      await _readCentralDirectoryEntries(
        eocd.centralDirectoryOffset,
        eocd.totalEntries,
      );
    }
  }

  /// Search for End of Central Directory signature
  Future<int> _findEndOfCentralDirectory(int fileSize) async {
    const signature = 0x06054b50;
    const maxCommentSize = 65535;
    const eocdMinSize = 22;

    // Start search from minimum EOCD size from end
    final searchStart = (fileSize - maxCommentSize - eocdMinSize).clamp(
      0,
      fileSize - eocdMinSize,
    );
    final searchEnd = fileSize - eocdMinSize;

    for (int pos = searchEnd; pos >= searchStart; pos--) {
      await _file.setPosition(pos);
      final bytes = await _file.read(4);
      final sig = _bytesToUint32(bytes);

      if (sig == signature) {
        return pos;
      }
    }

    throw DirectoryException('End of Central Directory signature not found');
  }

  /// Find ZIP64 End of Central Directory
  Future<int> _findZip64EndOfCentralDirectory(int eocdPosition) async {
    const zip64LocatorSignature = 0x07064b50;

    // ZIP64 EOCD locator is 20 bytes and comes before regular EOCD
    final locatorPosition = eocdPosition - 20;
    await _file.setPosition(locatorPosition);

    final signature = _bytesToUint32(await _file.read(4));
    if (signature != zip64LocatorSignature) {
      throw DirectoryException('ZIP64 EOCD locator not found');
    }

    // Skip disk number (4 bytes)
    await _file.read(4);

    // Read ZIP64 EOCD offset (8 bytes)
    final zip64EocdOffset = _bytesToUint64(await _file.read(8));

    return zip64EocdOffset;
  }

  /// Read End of Central Directory Record
  Future<EndOfCentralDirectory> _readEndOfCentralDirectoryRecord() async {
    // Skip signature (already verified)
    await _file.read(4);

    final diskNumber = _bytesToUint16(await _file.read(2));
    final diskWithCentralDir = _bytesToUint16(await _file.read(2));
    final entriesOnDisk = _bytesToUint16(await _file.read(2));
    final totalEntries = _bytesToUint16(await _file.read(2));
    final centralDirectorySize = _bytesToUint32(await _file.read(4));
    final centralDirectoryOffset = _bytesToUint32(await _file.read(4));
    final commentLength = _bytesToUint16(await _file.read(2));

    return EndOfCentralDirectory(
      diskNumber: diskNumber,
      diskWithCentralDir: diskWithCentralDir,
      entriesOnDisk: entriesOnDisk,
      totalEntries: totalEntries,
      centralDirectorySize: centralDirectorySize,
      centralDirectoryOffset: centralDirectoryOffset,
      commentLength: commentLength,
    );
  }

  /// Read ZIP64 End of Central Directory Record
  Future<Zip64EndOfCentralDirectory>
  _readZip64EndOfCentralDirectoryRecord() async {
    const zip64EocdSignature = 0x06064b50;

    final signature = _bytesToUint32(await _file.read(4));
    if (signature != zip64EocdSignature) {
      throw DirectoryException('Invalid ZIP64 EOCD signature');
    }

    final recordSize = _bytesToUint64(await _file.read(8));
    final versionMade = _bytesToUint16(await _file.read(2));
    final versionNeeded = _bytesToUint16(await _file.read(2));
    final diskNumber = _bytesToUint32(await _file.read(4));
    final diskWithCentralDir = _bytesToUint32(await _file.read(4));
    final entriesOnDisk = _bytesToUint64(await _file.read(8));
    final totalEntries = _bytesToUint64(await _file.read(8));
    final centralDirectorySize = _bytesToUint64(await _file.read(8));
    final centralDirectoryOffset = _bytesToUint64(await _file.read(8));

    return Zip64EndOfCentralDirectory(
      recordSize: recordSize,
      versionMade: versionMade,
      versionNeeded: versionNeeded,
      diskNumber: diskNumber,
      diskWithCentralDir: diskWithCentralDir,
      entriesOnDisk: entriesOnDisk,
      totalEntries: totalEntries,
      centralDirectorySize: centralDirectorySize,
      centralDirectoryOffset: centralDirectoryOffset,
    );
  }

  /// Read central directory entries
  Future<void> _readCentralDirectoryEntries(int offset, int entryCount) async {
    await _file.setPosition(offset);
    _entries = <ZipFileEntry>[];

    for (int i = 0; i < entryCount; i++) {
      final entry = await _readCentralDirectoryEntry();
      _entries.add(entry);
    }
  }

  /// Read a single central directory entry
  Future<ZipFileEntry> _readCentralDirectoryEntry() async {
    const centralFileHeaderSignature = 0x02014b50;

    final signature = _bytesToUint32(await _file.read(4));
    if (signature != centralFileHeaderSignature) {
      throw DirectoryException('Invalid central directory entry signature');
    }

    final compressionMethod = _bytesToUint16(await _file.read(2));
    final crc32 = _bytesToUint32(await _file.read(4));
    final compressedSize = _bytesToUint32(await _file.read(4));
    final uncompressedSize = _bytesToUint32(await _file.read(4));
    final fileNameLength = _bytesToUint16(await _file.read(2));
    final extraFieldLength = _bytesToUint16(await _file.read(2));
    final fileCommentLength = _bytesToUint16(await _file.read(2));
    final localHeaderOffset = _bytesToUint32(await _file.read(4));

    // Read filename
    final fileNameBytes = await _file.read(fileNameLength);
    final fileName = String.fromCharCodes(fileNameBytes);

    // Skip extra field and comment
    if (extraFieldLength > 0) {
      await _file.read(extraFieldLength);
    }
    if (fileCommentLength > 0) {
      await _file.read(fileCommentLength);
    }

    return ZipFileEntry(
      fileName: fileName,
      compressionMethod: compressionMethod,
      compressedSize: compressedSize,
      uncompressedSize: uncompressedSize,
      crc32: crc32,
      localHeaderOffset: localHeaderOffset,
      isDirectory: fileName.endsWith('/'),
    );
  }

  /// Read local file header to get actual data offset
  Future<LocalFileHeader> _readLocalFileHeader() async {
    const localFileHeaderSignature = 0x04034b50;

    final signature = _bytesToUint32(await _file.read(4));
    if (signature != localFileHeaderSignature) {
      throw DirectoryException('Invalid local file header signature');
    }

    // Skip version, flags, compression method, time, date, crc32, sizes
    await _file.read(22);

    final fileNameLength = _bytesToUint16(await _file.read(2));
    final extraFieldLength = _bytesToUint16(await _file.read(2));

    return LocalFileHeader(
      fileNameLength: fileNameLength,
      extraFieldLength: extraFieldLength,
    );
  }

  /// Inflate deflated data using dart:io
  List<int> _inflateData(List<int> compressedData, int expectedSize) {
    try {
      // Use dart:io's ZLibDecoder for decompression
      final codec = ZLibCodec(raw: true); // raw = true for deflate
      final decompressed = codec.decode(compressedData);

      if (decompressed.length != expectedSize) {
        throw DirectoryException(
          'Decompressed size mismatch: expected $expectedSize, got ${decompressed.length}',
        );
      }

      return decompressed;
    } catch (e) {
      throw DirectoryException('Failed to decompress data: $e');
    }
  }

  // Utility methods for byte conversion
  int _bytesToUint16(List<int> bytes) {
    return bytes[0] | (bytes[1] << 8);
  }

  int _bytesToUint32(List<int> bytes) {
    return bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);
  }

  int _bytesToUint64(List<int> bytes) {
    int result = 0;
    for (int i = 0; i < 8; i++) {
      result |= (bytes[i] << (i * 8));
    }
    return result;
  }
}

/// Represents a file entry in the ZIP archive
class ZipFileEntry {
  final String fileName;
  final int compressionMethod;
  final int compressedSize;
  final int uncompressedSize;
  final int crc32;
  final int localHeaderOffset;
  final bool isDirectory;

  ZipFileEntry({
    required this.fileName,
    required this.compressionMethod,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.crc32,
    required this.localHeaderOffset,
    required this.isDirectory,
  });

  bool get isFile => !isDirectory;
}

/// End of Central Directory Record
class EndOfCentralDirectory {
  final int diskNumber;
  final int diskWithCentralDir;
  final int entriesOnDisk;
  final int totalEntries;
  final int centralDirectorySize;
  final int centralDirectoryOffset;
  final int commentLength;

  EndOfCentralDirectory({
    required this.diskNumber,
    required this.diskWithCentralDir,
    required this.entriesOnDisk,
    required this.totalEntries,
    required this.centralDirectorySize,
    required this.centralDirectoryOffset,
    required this.commentLength,
  });
}

/// ZIP64 End of Central Directory Record
class Zip64EndOfCentralDirectory {
  final int recordSize;
  final int versionMade;
  final int versionNeeded;
  final int diskNumber;
  final int diskWithCentralDir;
  final int entriesOnDisk;
  final int totalEntries;
  final int centralDirectorySize;
  final int centralDirectoryOffset;

  Zip64EndOfCentralDirectory({
    required this.recordSize,
    required this.versionMade,
    required this.versionNeeded,
    required this.diskNumber,
    required this.diskWithCentralDir,
    required this.entriesOnDisk,
    required this.totalEntries,
    required this.centralDirectorySize,
    required this.centralDirectoryOffset,
  });
}

/// Local File Header info
class LocalFileHeader {
  final int fileNameLength;
  final int extraFieldLength;

  LocalFileHeader({
    required this.fileNameLength,
    required this.extraFieldLength,
  });
}
