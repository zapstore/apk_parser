library;

import 'dart:collection';
import 'dart:typed_data';

import 'ext_file.dart';
import 'abstract_directory.dart';
import 'directory.dart';
import 'directory_exception.dart';
import 'path_not_exist.dart';
import 'manual_zip_reader.dart';

/// Fallback ZIP directory that uses manual ZIP reading when archive package fails
class FallbackZipDirectory extends AbstractDirectoryBase {
  final ExtFile _zipExtFile;
  ManualZipReader? _manualReader;
  final String _zipPathPrefix;

  // Cache for loaded files and directories
  bool _filesLoaded = false;
  bool _dirsLoaded = false;
  final Set<String> _lazyFiles = LinkedHashSet<String>();
  final Map<String, AbstractDirectoryBase> _lazyDirs =
      <String, AbstractDirectoryBase>{};

  FallbackZipDirectory(this._zipExtFile, [this._zipPathPrefix = '']);

  Future<ManualZipReader> _getManualReader() async {
    if (_manualReader == null) {
      _manualReader = ManualZipReader(_zipExtFile.path);
      await _manualReader!.initialize();
    }
    return _manualReader!;
  }

  Future<void> _ensureFilesLoaded() async {
    if (!_filesLoaded) {
      final reader = await _getManualReader();

      for (final entry in reader.entries) {
        if (entry.isFile && entry.fileName.startsWith(_zipPathPrefix)) {
          final relativeName = entry.fileName.substring(_zipPathPrefix.length);
          if (!relativeName.contains('/')) {
            _lazyFiles.add(relativeName);
          }
        }
      }
      _filesLoaded = true;
    }
  }

  Future<void> _ensureDirsLoaded() async {
    if (!_dirsLoaded) {
      final reader = await _getManualReader();
      final dirNames = <String>{};

      for (final entry in reader.entries) {
        if (entry.fileName.startsWith(_zipPathPrefix)) {
          final relativeName = entry.fileName.substring(_zipPathPrefix.length);
          final slashIndex = relativeName.indexOf('/');
          if (slashIndex > 0) {
            dirNames.add(relativeName.substring(0, slashIndex));
          }
        }
      }

      for (final dirName in dirNames) {
        _lazyDirs[dirName] = FallbackZipDirectory(
          _zipExtFile,
          '$_zipPathPrefix$dirName/',
        );
      }
      _dirsLoaded = true;
    }
  }

  @override
  Set<String> loadInitialFiles() {
    return LinkedHashSet<String>();
  }

  @override
  Map<String, AbstractDirectoryBase> loadInitialDirs() {
    return <String, AbstractDirectoryBase>{};
  }

  @override
  Future<AbstractInputStream> getFileInputLocal(String name) async {
    final reader = await _getManualReader();
    final fullName = '$_zipPathPrefix$name';

    final entry = await reader.findFile(fullName);
    if (entry == null || !entry.isFile) {
      throw PathNotExist('File not found in fallback zip: $fullName');
    }

    // Extract file content using manual reader
    final content = await reader.extractFile(entry);
    return MemoryInputStream(Uint8List.fromList(content));
  }

  @override
  Future<AbstractInputStream> getFileInput(String path) async {
    await _ensureFilesLoaded();
    await _ensureDirsLoaded();

    final parsed = _parsePath(path);
    if (parsed.dir != null) {
      if (_lazyDirs.containsKey(parsed.dir)) {
        return _lazyDirs[parsed.dir]!.getFileInput(parsed.subPath);
      }
      throw PathNotExist('Directory not found: ${parsed.dir}');
    }

    if (_lazyFiles.contains(path)) {
      return getFileInputLocal(path);
    }
    throw PathNotExist('File not found: $path');
  }

  @override
  bool containsFile(String path) {
    return true; // Optimistically return true, actual check in getFileInput
  }

  @override
  Future<AbstractOutputStream> getFileOutputLocal(String name) async {
    throw DirectoryException('FallbackZipDirectory is read-only');
  }

  @override
  Future<AbstractDirectoryBase> createDirLocal(String name) async {
    throw DirectoryException('FallbackZipDirectory is read-only');
  }

  @override
  Future<void> removeFileLocal(String name) async {
    throw DirectoryException('FallbackZipDirectory is read-only');
  }

  @override
  Future<int> getSize(String fileName) async {
    final reader = await _getManualReader();
    final fullName = '$_zipPathPrefix$fileName';

    final entry = await reader.findFile(fullName);
    if (entry != null && entry.isFile) {
      return entry.uncompressedSize;
    }
    throw PathNotExist('File not found in fallback zip for getSize: $fullName');
  }

  @override
  Future<int> getCompressedSize(String fileName) async {
    final reader = await _getManualReader();
    final fullName = '$_zipPathPrefix$fileName';

    final entry = await reader.findFile(fullName);
    if (entry != null && entry.isFile) {
      return entry.compressedSize;
    }
    throw PathNotExist(
      'File not found in fallback zip for getCompressedSize: $fullName',
    );
  }

  @override
  Future<int> getCompressionLevel(String fileName) async {
    final reader = await _getManualReader();
    final fullName = '$_zipPathPrefix$fileName';

    final entry = await reader.findFile(fullName);
    if (entry != null && entry.isFile) {
      // Map compression method to level approximation
      switch (entry.compressionMethod) {
        case 0:
          return 0; // Stored (no compression)
        case 8:
          return 6; // Deflate (default level)
        default:
          return -1; // Unknown
      }
    }
    return -1;
  }

  @override
  Future<void> close() async {
    await _manualReader?.close();
    _manualReader = null;
    await super.close();
  }

  @override
  Set<String> getFiles({bool recursive = false}) {
    // Note: This method is synchronous but we need async initialization
    // This is a limitation - we can't provide synchronous access to async data
    throw DirectoryException(
      'getFiles() not supported for FallbackZipDirectory - use async methods',
    );
  }

  _ParsedPath _parsePath(String path) {
    final pos = path.indexOf(Directory.separator);
    if (pos == -1) {
      return _ParsedPath(null, path);
    }
    return _ParsedPath(path.substring(0, pos), path.substring(pos + 1));
  }

  Future<void> ensureFilesLoaded() async {
    await _ensureFilesLoaded();
  }

  Future<void> ensureDirsLoaded() async {
    await _ensureDirsLoaded();
  }

  Set<String> get lazyFiles => Set.unmodifiable(_lazyFiles);
  Map<String, AbstractDirectoryBase> get lazyDirs =>
      Map.unmodifiable(_lazyDirs);
}

class _ParsedPath {
  final String? dir;
  final String subPath;

  _ParsedPath(this.dir, this.subPath);
}
