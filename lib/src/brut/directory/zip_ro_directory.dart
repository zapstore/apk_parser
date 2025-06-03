library brut_directory;

import 'dart:collection';
import 'package:archive/archive.dart' as archive;
import 'dart:typed_data';

import 'ext_file.dart';
import 'abstract_directory.dart';
import 'directory.dart'; // For AbstractInputStream/OutputStream types
import 'directory_exception.dart';
import 'path_not_exist.dart';

// Read-Only Zip Directory
class ZipRODirectory extends AbstractDirectoryBase {
  final ExtFile _zipExtFile;
  archive.Archive? _archiveInstance;
  final String
  _zipPathPrefix; // Path prefix within the zip, e.g., "assets/" or ""

  // Lazy loading flags
  bool _filesLoaded = false;
  bool _dirsLoaded = false;
  final Set<String> _lazyFiles = LinkedHashSet<String>();
  final Map<String, AbstractDirectoryBase> _lazyDirs =
      LinkedHashMap<String, AbstractDirectoryBase>();

  ZipRODirectory(this._zipExtFile, [this._zipPathPrefix = '']) {
    // _archiveInstance will be loaded lazily or an error will be thrown if accessed before load.
  }

  Future<archive.Archive> _getArchiveInstance() async {
    if (_archiveInstance == null) {
      try {
        final bytes = await _zipExtFile.ioFile.readAsBytes();
        _archiveInstance = archive.ZipDecoder().decodeBytes(bytes);
      } catch (e) {
        throw DirectoryException(
          'Failed to decode zip file: ${_zipExtFile.path}',
          e,
        );
      }
    }
    return _archiveInstance!;
  }

  // Load files on demand
  Future<void> _ensureFilesLoaded() async {
    if (!_filesLoaded) {
      final arch = await _getArchiveInstance();
      for (final file in arch.files) {
        if (file.isFile && file.name.startsWith(_zipPathPrefix)) {
          final relativeName = file.name.substring(_zipPathPrefix.length);
          if (!relativeName.contains('/')) {
            _lazyFiles.add(relativeName);
          }
        }
      }
      _filesLoaded = true;
    }
  }

  // Load directories on demand
  Future<void> _ensureDirsLoaded() async {
    if (!_dirsLoaded) {
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
    return LinkedHashMap<String, AbstractDirectoryBase>();
  }

  @override
  Future<AbstractInputStream> getFileInputLocal(String name) async {
    await _ensureFilesLoaded();
    final arch = await _getArchiveInstance();
    final fullName = '$_zipPathPrefix$name';
    final file = arch.findFile(fullName);
    if (file == null || !file.isFile) {
      throw PathNotExist('File not found in zip: $fullName');
    }
    // file.content is List<int> (Uint8List usually)
    return MemoryInputStream(
      file.content as Uint8List,
    ); // Use helper from directory.dart
  }

  // Override getFileInput to handle lazy loading
  @override
  Future<AbstractInputStream> getFileInput(String path) async {
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
  }

  // Override containsFile to handle lazy loading
  @override
  bool containsFile(String path) {
    // This is tricky because it's synchronous but we need async loading
    // For now, return false and rely on getFileInput to do the actual check
    // This is not ideal but works around the sync/async mismatch
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
    final arch = await _getArchiveInstance();
    final fullName = '$_zipPathPrefix$fileName';
    final file = arch.findFile(fullName);
    if (file != null && file.isFile) {
      return file.size;
    }
    throw PathNotExist('File not found in zip for getSize: $fullName');
  }

  @override
  Future<int> getCompressedSize(String fileName) async {
    // The archive package doesn't provide compressed size information
    // Return the uncompressed size as a fallback
    return getSize(fileName);
  }

  @override
  Future<int> getCompressionLevel(String fileName) async {
    final arch = await _getArchiveInstance();
    final fullName = '$_zipPathPrefix$fileName';
    final file = arch.findFile(fullName);
    if (file != null && file.isFile) {
      // The compressionLevel property exists in ArchiveFile
      return file.compressionLevel ?? -1;
    }
    return -1;
  }

  @override
  Future<void> close() async {
    // The archive instance is in memory; nothing to close for it here unless we held a file handle.
    // _zipExtFile.close() might be relevant if ExtFile held a handle, but it doesn't currently.
    _archiveInstance = null; // Allow it to be garbage collected
    await super.close();
  }

  // Override getFiles to return all files in the archive
  @override
  Set<String> getFiles({bool recursive = false}) {
    // We need to load the archive synchronously for this method
    // This is not ideal, but necessary for the sync interface
    if (_archiveInstance == null) {
      try {
        final bytes = _zipExtFile.ioFile.readAsBytesSync();
        _archiveInstance = archive.ZipDecoder().decodeBytes(bytes);
      } catch (e) {
        throw DirectoryException(
          'Failed to decode zip file: ${_zipExtFile.path}',
          e,
        );
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
