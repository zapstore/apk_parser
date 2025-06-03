library;

import 'dart:io' as dart_io;
// For path operations if needed

import 'directory.dart';
import 'directory_exception.dart';
import 'file_directory.dart';
import 'zip_ro_directory.dart';

class ExtFile {
  final dart_io.File _file;
  Directory? _directory;
  final String _path;

  ExtFile(String path) : _path = path, _file = dart_io.File(path);

  ExtFile.fromFile(dart_io.File file) : _path = file.path, _file = file;

  String get path => _path;
  Future<bool> exists() => _file.exists();
  Future<dart_io.FileSystemEntity> delete() async {
    await close();
    return _file.delete();
  }

  bool existsSync() => _file.existsSync();
  void deleteSync() {
    // closeSync() is not directly available on Directory, but close is async.
    // For a sync delete, if we need to ensure resources are freed from _directory,
    // it implies _directory might need a sync close or a different pattern.
    // For now, if _directory exists, its resources might not be deterministically closed here.
    // Best effort: nullify it. Proper solution depends on Directory's close impl.
    _directory = null;
    _file.deleteSync();
  }

  Future<bool> isDirectory() async {
    return dart_io.FileSystemEntity.isDirectory(_path);
  }

  bool isDirectorySync() {
    return dart_io.FileSystemEntity.isDirectorySync(_path);
  }

  Future<bool> isFile() async {
    return dart_io.FileSystemEntity.isFile(_path);
  }

  bool isFileSync() {
    return dart_io.FileSystemEntity.isFileSync(_path);
  }

  Future<Directory> getDirectory() async {
    if (_directory != null) {
      return _directory!;
    }

    if (await isDirectory()) {
      _directory = FileDirectory(this);
    } else if (await isFile()) {
      // Check if it's a file, potentially a zip
      // Basic check, could be improved (e.g. by magic bytes for zip)
      if (path.toLowerCase().endsWith('.zip') ||
          path.toLowerCase().endsWith('.apk')) {
        _directory = ZipRODirectory(this);
      } else {
        throw DirectoryException(
          'File is not a directory and not a recognized archive (zip/apk): $path',
        );
      }
    } else {
      throw DirectoryException('Path is neither a file nor a directory: $path');
    }
    return _directory!;
  }

  // Synchronous version for cases where async is not possible (rare for getDirectory)
  // This is more challenging because ZipRODirectory uses package:archive which is async for reading.
  // For now, this will throw if it needs to create a ZipRODirectory.
  Directory getDirectorySync() {
    if (_directory != null) {
      return _directory!;
    }
    if (isDirectorySync()) {
      _directory = FileDirectory.sync(
        this,
      ); // Assuming FileDirectory can be constructed sync
    } else if (isFileSync()) {
      if (path.toLowerCase().endsWith('.zip') ||
          path.toLowerCase().endsWith('.apk')) {
        // ZipRODirectory inherently async due to reading zip contents.
        // A true sync version would require a sync zip library or pre-parsing.
        throw DirectoryException(
          'Cannot create ZipRODirectory synchronously: $path',
        );
      } else {
        throw DirectoryException(
          'File is not a directory and not a recognized archive (zip/apk): $path',
        );
      }
    } else {
      throw DirectoryException('Path is neither a file nor a directory: $path');
    }
    return _directory!;
  }

  Future<void> close() async {
    if (_directory != null) {
      await _directory!.close();
      _directory = null;
    }
  }

  // For convenience, to access the underlying dart:io.File if needed by other parts.
  dart_io.File get ioFile => _file;
}
