// ignore_for_file: prefer_collection_literals

library;

import 'dart:collection';
import 'package:archive/archive.dart' as archive;

import 'ext_file.dart';
import 'abstract_directory.dart';
import 'directory.dart'; // For AbstractInputStream/OutputStream types
import 'directory_exception.dart';
import 'path_not_exist.dart';
import 'fallback_zip_directory.dart';

// Read-Only Zip Directory
class ZipRODirectory extends AbstractDirectoryBase {
  final ExtFile _zipExtFile;
  archive.Archive? _archiveInstance;
  final String
  _zipPathPrefix; // Path prefix within the zip, e.g., "assets/" or ""

  // Fallback mechanism
  FallbackZipDirectory? _fallbackDirectory;
  bool _useFallback = false;

  // Lazy loading flags
  bool _filesLoaded = false;
  bool _dirsLoaded = false;
  final Set<String> _lazyFiles = LinkedHashSet<String>();
  final Map<String, AbstractDirectoryBase> _lazyDirs =
      <String, AbstractDirectoryBase>{};

  ZipRODirectory(this._zipExtFile, [this._zipPathPrefix = '']) {
    // _archiveInstance will be loaded lazily with improved error handling
  }

  Future<archive.Archive> _getArchiveInstance() async {
    if (_archiveInstance == null) {
      // Ensure file exists and is readable
      final file = _zipExtFile.ioFile;
      if (!await file.exists()) {
        throw DirectoryException(
          'ZIP file does not exist: ${_zipExtFile.path}',
        );
      }

      final fileSize = await file.length();
      if (fileSize < 22) {
        // Minimum ZIP file size (end of central directory record)
        throw DirectoryException(
          'File too small to be a valid ZIP: ${_zipExtFile.path}',
        );
      }

      // Read file completely into memory with validation
      final bytes = await file.readAsBytes();
      if (bytes.length != fileSize) {
        throw DirectoryException(
          'File read size mismatch: ${_zipExtFile.path}',
        );
      }

      // Validate ZIP signature (PK header)
      if (bytes.length >= 4 && (bytes[0] != 0x50 || bytes[1] != 0x4B)) {
        throw DirectoryException('Invalid ZIP signature: ${_zipExtFile.path}');
      }

      try {
        _archiveInstance = archive.ZipDecoder().decodeBytes(bytes);
      } catch (e) {
        // Archive package failed - use fallback mechanism
        print(
          '📋 Archive package failed for ${_zipExtFile.path}, using fallback: $e',
        );
        _useFallback = true;
        _fallbackDirectory = FallbackZipDirectory(_zipExtFile, _zipPathPrefix);
        throw DirectoryException(
          'ZipDecoder failed to parse file: ${_zipExtFile.path}',
          e,
        );
      }
    }
    return _archiveInstance!;
  }

  Future<FallbackZipDirectory> _getFallbackDirectory() async {
    _fallbackDirectory ??= FallbackZipDirectory(_zipExtFile, _zipPathPrefix);
    return _fallbackDirectory!;
  }

  // Load files on demand
  Future<void> _ensureFilesLoaded() async {
    if (!_filesLoaded) {
      if (_useFallback) {
        final fallback = await _getFallbackDirectory();
        await fallback.ensureFilesLoaded();
        _lazyFiles.addAll(fallback.lazyFiles);
      } else {
        try {
          final arch = await _getArchiveInstance();

          for (final file in arch.files) {
            if (file.isFile && file.name.startsWith(_zipPathPrefix)) {
              final relativeName = file.name.substring(_zipPathPrefix.length);
              if (!relativeName.contains('/')) {
                _lazyFiles.add(relativeName);
              }
            }
          }
        } catch (e) {
          // Switch to fallback on any error
          _useFallback = true;
          final fallback = await _getFallbackDirectory();
          await fallback.ensureFilesLoaded();
          _lazyFiles.addAll(fallback.lazyFiles);
        }
      }
      _filesLoaded = true;
    }
  }

  // Load directories on demand
  Future<void> _ensureDirsLoaded() async {
    if (!_dirsLoaded) {
      if (_useFallback) {
        final fallback = await _getFallbackDirectory();
        await fallback.ensureDirsLoaded();
        _lazyDirs.addAll(fallback.lazyDirs);
      } else {
        try {
          final arch = await _getArchiveInstance();

          final dirNames = <String>{};

          for (final file in arch.files) {
            if (file.name.startsWith(_zipPathPrefix)) {
              final relativeName = file.name.substring(_zipPathPrefix.length);
              final slashIndex = relativeName.indexOf('/');
              if (slashIndex > 0) {
                dirNames.add(relativeName.substring(0, slashIndex));
              }
            }
          }

          for (final dirName in dirNames) {
            _lazyDirs[dirName] = ZipRODirectory(
              _zipExtFile,
              '$_zipPathPrefix$dirName/',
            );
          }
        } catch (e) {
          // Switch to fallback on any error
          _useFallback = true;
          final fallback = await _getFallbackDirectory();
          await fallback.ensureDirsLoaded();
          _lazyDirs.addAll(fallback.lazyDirs);
        }
      }
      _dirsLoaded = true;
    }
  }

  @override
  Set<String> loadInitialFiles() {
    // Return empty set for sync initialization, files will be loaded lazily
    return LinkedHashSet<String>();
  }

  @override
  Map<String, AbstractDirectoryBase> loadInitialDirs() {
    // Return empty map for sync initialization, dirs will be loaded lazily
    return <String, AbstractDirectoryBase>{};
  }

  @override
  Future<AbstractInputStream> getFileInputLocal(String name) async {
    if (_useFallback) {
      final fallback = await _getFallbackDirectory();
      return fallback.getFileInputLocal(name);
    }

    try {
      await _ensureFilesLoaded();
      final arch = await _getArchiveInstance();

      final fullName = '$_zipPathPrefix$name';
      final file = arch.findFile(fullName);
      if (file == null || !file.isFile) {
        throw PathNotExist('File not found in zip: $fullName');
      }
      // file.content is List<int> (Uint8List usually)
      return MemoryInputStream(file.content); // Use helper from directory.dart
    } catch (e) {
      // Switch to fallback on any error
      _useFallback = true;
      final fallback = await _getFallbackDirectory();
      return fallback.getFileInputLocal(name);
    }
  }

  // Override getFileInput to handle lazy loading
  @override
  Future<AbstractInputStream> getFileInput(String path) async {
    if (_useFallback) {
      final fallback = await _getFallbackDirectory();
      return fallback.getFileInput(path);
    }

    try {
      // Try to load files and directories with improved error handling
      await _ensureFilesLoaded();
      await _ensureDirsLoaded();

      final parsed = _parsePath(path);
      if (parsed.dir != null) {
        // It's in a subdirectory
        if (_lazyDirs.containsKey(parsed.dir)) {
          return _lazyDirs[parsed.dir]!.getFileInput(parsed.subPath);
        }
        throw PathNotExist('Directory not found: ${parsed.dir}');
      }

      // It's in the current directory
      if (_lazyFiles.contains(path)) {
        return getFileInputLocal(path);
      }
      throw PathNotExist('File not found: $path');
    } catch (e) {
      // Switch to fallback on any error
      _useFallback = true;
      final fallback = await _getFallbackDirectory();
      return fallback.getFileInput(path);
    }
  }

  // Override containsFile to handle lazy loading
  @override
  bool containsFile(String path) {
    // This is tricky because it's synchronous but we need async loading
    // For now, return true and rely on getFileInput to do the actual check
    return true; // Optimistically return true, actual check happens in getFileInput
  }

  @override
  Future<AbstractOutputStream> getFileOutputLocal(String name) async {
    throw DirectoryException('ZipRODirectory is read-only');
  }

  @override
  Future<AbstractDirectoryBase> createDirLocal(String name) async {
    throw DirectoryException('ZipRODirectory is read-only');
  }

  @override
  Future<void> removeFileLocal(String name) async {
    throw DirectoryException('ZipRODirectory is read-only');
  }

  @override
  Future<int> getSize(String fileName) async {
    if (_useFallback) {
      final fallback = await _getFallbackDirectory();
      return fallback.getSize(fileName);
    }

    try {
      final arch = await _getArchiveInstance();

      final fullName = '$_zipPathPrefix$fileName';
      final file = arch.findFile(fullName);
      if (file != null && file.isFile) {
        return file.size;
      }
      throw PathNotExist('File not found in zip for getSize: $fullName');
    } catch (e) {
      // Switch to fallback on any error
      _useFallback = true;
      final fallback = await _getFallbackDirectory();
      return fallback.getSize(fileName);
    }
  }

  @override
  Future<int> getCompressedSize(String fileName) async {
    if (_useFallback) {
      final fallback = await _getFallbackDirectory();
      return fallback.getCompressedSize(fileName);
    }

    try {
      // The archive package doesn't provide compressed size information
      // Return the uncompressed size as a fallback
      return getSize(fileName);
    } catch (e) {
      // Switch to fallback on any error
      _useFallback = true;
      final fallback = await _getFallbackDirectory();
      return fallback.getCompressedSize(fileName);
    }
  }

  @override
  Future<int> getCompressionLevel(String fileName) async {
    if (_useFallback) {
      final fallback = await _getFallbackDirectory();
      return fallback.getCompressionLevel(fileName);
    }

    try {
      final arch = await _getArchiveInstance();

      final fullName = '$_zipPathPrefix$fileName';
      final file = arch.findFile(fullName);
      if (file != null && file.isFile) {
        // The compressionLevel property exists in ArchiveFile
        return file.compressionLevel ?? -1;
      }
      return -1;
    } catch (e) {
      // Switch to fallback on any error
      _useFallback = true;
      final fallback = await _getFallbackDirectory();
      return fallback.getCompressionLevel(fileName);
    }
  }

  @override
  Future<void> close() async {
    // The archive instance is in memory; nothing to close for it here unless we held a file handle.
    // _zipExtFile.close() might be relevant if ExtFile held a handle, but it doesn't currently.
    _archiveInstance = null; // Allow it to be garbage collected
    await _fallbackDirectory?.close();
    _fallbackDirectory = null;
    await super.close();
  }

  // Override getFiles to return all files in the archive
  @override
  Set<String> getFiles({bool recursive = false}) {
    if (_useFallback) {
      // Fallback doesn't support synchronous getFiles
      return LinkedHashSet<String>();
    }

    // We need to load the archive synchronously for this method
    // This is not ideal, but necessary for the sync interface
    if (_archiveInstance == null) {
      try {
        final bytes = _zipExtFile.ioFile.readAsBytesSync();
        _archiveInstance = archive.ZipDecoder().decodeBytes(bytes);
      } catch (e) {
        // Switch to fallback but can't provide sync data
        _useFallback = true;
        return LinkedHashSet<String>();
      }
    }

    final files = LinkedHashSet<String>();
    final arch = _archiveInstance!;

    for (final file in arch.files) {
      if (file.isFile) {
        // Remove the prefix if we're in a subdirectory
        if (_zipPathPrefix.isNotEmpty && file.name.startsWith(_zipPathPrefix)) {
          files.add(file.name.substring(_zipPathPrefix.length));
        } else if (_zipPathPrefix.isEmpty) {
          files.add(file.name);
        }
      }
    }

    return files;
  }

  _ParsedPath _parsePath(String path) {
    final pos = path.indexOf(Directory.separator);
    if (pos == -1) {
      return _ParsedPath(null, path);
    }
    return _ParsedPath(path.substring(0, pos), path.substring(pos + 1));
  }
}

class _ParsedPath {
  final String? dir;
  final String subPath;

  _ParsedPath(this.dir, this.subPath);
}
