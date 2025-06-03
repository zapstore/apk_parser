library brut_directory;

import 'dart:async';
import 'dart:collection'; // For LinkedHashMap, LinkedHashSet
import 'dart:io' as dart_io;

import 'directory.dart';
import 'directory_exception.dart';
import 'path_not_exist.dart';
import 'path_already_exists.dart';
// import 'dir_utils.dart'; // TODO: Port DirUtils

abstract class AbstractDirectoryBase implements Directory {
  // These are now initialized by calling abstract methods implemented by subclasses.
  late final Set<String> _files;
  late Set<String>? _filesRecursive; // Cache for recursive file list
  late final Map<String, AbstractDirectoryBase> _dirs;

  bool _initialized = false;

  AbstractDirectoryBase();

  // Ensures that _files and _dirs are loaded. Call this at the beginning of public methods.
  void _ensureInitialized() {
    if (!_initialized) {
      _files = loadInitialFiles();
      _dirs = loadInitialDirs();
      _initialized = true;
    }
  }

  @override
  Set<String> getFiles({bool recursive = false}) {
    _ensureInitialized();
    if (!recursive) {
      return UnmodifiableSetView(_files);
    }
    _filesRecursive ??= _calculateRecursiveFiles();
    return UnmodifiableSetView(_filesRecursive!);
  }

  Set<String> _calculateRecursiveFiles() {
    _ensureInitialized(); // _files and _dirs are available
    final recursive = LinkedHashSet<String>.from(_files);
    for (final entry in _dirs.entries) {
      for (final path in entry.value.getFiles(recursive: true)) {
        recursive.add('${entry.key}${Directory.separator}$path');
      }
    }
    return recursive;
  }

  @override
  bool containsFile(String path) {
    _ensureInitialized();
    _SubPath subPath;
    try {
      subPath = _getSubPath(path);
    } on PathNotExist {
      return false;
    }

    if (subPath.dir != null) {
      return subPath.dir!.containsFile(subPath.path);
    }
    return _files.contains(subPath.path);
  }

  @override
  bool containsDir(String path) {
    _ensureInitialized();
    _SubPath subPath;
    try {
      subPath = _getSubPath(path);
    } on PathNotExist {
      return false;
    }

    if (subPath.dir != null) {
      return subPath.dir!.containsDir(subPath.path);
    }
    return _dirs.containsKey(subPath.path);
  }

  @override
  Map<String, Directory> getDirs({bool recursive = false}) {
    _ensureInitialized();
    if (!recursive) {
      return UnmodifiableMapView(_dirs);
    }
    final recursiveDirs = LinkedHashMap<String, AbstractDirectoryBase>.from(
      _dirs,
    );
    for (final entry in _dirs.entries) {
      final subDirs = entry.value.getDirs(recursive: true);
      for (final subEntry in subDirs.entries) {
        recursiveDirs['${entry.key}${Directory.separator}${subEntry.key}'] =
            subEntry.value as AbstractDirectoryBase;
      }
    }
    return UnmodifiableMapView(recursiveDirs);
  }

  @override
  Future<AbstractInputStream> getFileInput(String path) async {
    _ensureInitialized();
    final subPath = _getSubPath(path);
    if (subPath.dir != null) {
      return subPath.dir!.getFileInput(subPath.path);
    }
    if (!_files.contains(subPath.path)) {
      throw PathNotExist(path);
    }
    return getFileInputLocal(subPath.path);
  }

  @override
  Future<AbstractOutputStream> getFileOutput(String path) async {
    _ensureInitialized();
    final parsed = _parsePath(path);
    if (parsed.dir == null) {
      // File is in the current directory. Add to _files set if not present.
      // Note: _files is final after _ensureInitialized. This implies direct modification
      // of the set instance, which is okay for LinkedHashSet.
      if (_files.add(parsed.subPath)) {
        _filesRecursive = null; // Invalidate cache if structure changed
      }
      return getFileOutputLocal(parsed.subPath);
    }

    final String parentDirName = parsed.dir!;
    AbstractDirectoryBase dir;
    if (_dirs.containsKey(parentDirName)) {
      dir = _dirs[parentDirName]!;
    } else {
      dir = await createDirLocal(parentDirName);
      _dirs[parentDirName] = dir;
      // _filesRecursive might need invalidation if dirs affect recursive file list, but less direct.
    }
    return dir.getFileOutput(parsed.subPath);
  }

  @override
  Future<Directory> getDir(String path) async {
    _ensureInitialized();
    final subPath = _getSubPath(path);
    if (subPath.dir != null) {
      return subPath.dir!.getDir(subPath.path);
    }
    if (!_dirs.containsKey(subPath.path)) {
      throw PathNotExist(path);
    }
    return _dirs[subPath.path]!;
  }

  @override
  Future<Directory> createDir(String path) async {
    _ensureInitialized();
    final parsed = _parsePath(path);
    if (parsed.dir == null) {
      if (_dirs.containsKey(parsed.subPath)) {
        throw PathAlreadyExists('$path (already exists as a directory)');
      }
      final newDir = await createDirLocal(parsed.subPath);
      _dirs[parsed.subPath] = newDir;
      return newDir;
    }

    final String parentDirName = parsed.dir!;
    AbstractDirectoryBase parentDir;
    if (_dirs.containsKey(parentDirName)) {
      parentDir = _dirs[parentDirName]!;
    } else {
      parentDir = await createDirLocal(parentDirName);
      _dirs[parentDirName] = parentDir;
    }
    return parentDir.createDir(parsed.subPath);
  }

  @override
  Future<bool> removeFile(String path) async {
    _ensureInitialized();
    _SubPath subPath;
    try {
      subPath = _getSubPath(path);
    } on PathNotExist {
      return false;
    }

    if (subPath.dir != null) {
      final result = await subPath.dir!.removeFile(subPath.path);
      if (result) _filesRecursive = null; // Invalidate if a sub-dir changed
      return result;
    }
    if (!_files.contains(subPath.path)) {
      return false;
    }
    await removeFileLocal(subPath.path);
    _files.remove(subPath.path);
    _filesRecursive = null;
    return true;
  }

  // --- copyToDir methods are omitted for now, requires DirUtils port ---
  @override
  Future<void> copyToDir(Directory out) async {
    // TODO: Implement using ported DirUtils or direct logic
    throw UnimplementedError('copyToDir Directory not implemented yet');
  }

  @override
  Future<void> copyToDirPaths(Directory out, List<String> fileNames) async {
    // TODO: Implement using ported DirUtils or direct logic
    throw UnimplementedError('copyToDirPaths Directory not implemented yet');
  }

  @override
  Future<void> copyToDirPath(Directory out, String fileName) async {
    // TODO: Implement using ported DirUtils or direct logic
    throw UnimplementedError('copyToDirPath Directory not implemented yet');
  }

  @override
  Future<void> copyToDirFile(dart_io.File out) async {
    // TODO: Implement using ported DirUtils or direct logic
    throw UnimplementedError('copyToDirFile File not implemented yet');
  }

  @override
  Future<void> copyToDirFilePaths(
    dart_io.File out,
    List<String> fileNames,
  ) async {
    // TODO: Implement using ported DirUtils or direct logic
    throw UnimplementedError('copyToDirFilePaths File not implemented yet');
  }

  @override
  Future<void> copyToDirFilePath(dart_io.File out, String fileName) async {
    // TODO: Implement using ported DirUtils or direct logic
    throw UnimplementedError('copyToDirFilePath File not implemented yet');
  }
  // --- End of copyToDir methods ---

  @override
  Future<int> getCompressionLevel(String fileName) async {
    // Default implementation from Java AbstractDirectory
    return -1; // Unknown
  }

  @override
  Future<int> getSize(String fileName) async {
    // Subclasses should implement this if they can provide size directly
    // otherwise it might need to read the file stream which is inefficient here.
    _ensureInitialized();
    final subPath = _getSubPath(fileName);
    if (subPath.dir != null) {
      return subPath.dir!.getSize(subPath.path);
    }
    // Fallback: try to get stream and measure, or throw if not appropriate
    // This is a placeholder, as AbstractDirectory in Java doesn't implement it.
    throw DirectoryException(
      'getSize not implemented by this directory type for local files: $fileName',
    );
  }

  @override
  Future<int> getCompressedSize(String fileName) async {
    _ensureInitialized();
    final subPath = _getSubPath(fileName);
    if (subPath.dir != null) {
      return subPath.dir!.getCompressedSize(subPath.path);
    }
    throw DirectoryException(
      'getCompressedSize not implemented by this directory type for local files: $fileName',
    );
  }

  @override
  Future<void> close() async {}

  _SubPath _getSubPath(String path) {
    _ensureInitialized(); // Ensures _dirs is loaded
    final parsed = _parsePath(path);
    if (parsed.dir == null) {
      return _SubPath(null, parsed.subPath);
    }
    final String dirName = parsed.dir!;
    if (!_dirs.containsKey(dirName)) {
      throw PathNotExist('$path (directory part $dirName not found)');
    }
    return _SubPath(_dirs[dirName], parsed.subPath);
  }

  _ParsedPath _parsePath(String path) {
    final pos = path.indexOf(Directory.separator);
    if (pos == -1) {
      return _ParsedPath(null, path);
    }
    return _ParsedPath(path.substring(0, pos), path.substring(pos + 1));
  }

  // Abstract methods for subclasses to provide initial content.
  // These are called once by _ensureInitialized.
  Set<String> loadInitialFiles();
  Map<String, AbstractDirectoryBase> loadInitialDirs();

  // Abstract methods for local I/O operations, to be implemented by concrete subclasses.
  Future<AbstractInputStream> getFileInputLocal(String name);
  Future<AbstractOutputStream> getFileOutputLocal(String name);
  Future<AbstractDirectoryBase> createDirLocal(String name);
  Future<void> removeFileLocal(String name);
}

class _ParsedPath {
  final String? dir;
  final String subPath;

  _ParsedPath(this.dir, this.subPath);
}

class _SubPath {
  final AbstractDirectoryBase? dir;
  final String path;

  _SubPath(this.dir, this.path);
}
