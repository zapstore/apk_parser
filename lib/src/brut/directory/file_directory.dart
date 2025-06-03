library brut_directory;

import 'dart:io' as dart_io;
import 'dart:collection'; // For LinkedHashSet, LinkedHashMap
import 'package:path/path.dart' as p;

import 'ext_file.dart';
import 'abstract_directory.dart';
import 'directory.dart'; // For AbstractInputStream/OutputStream types
import '../util/os.dart'; // For OS.mkdirs, OS.rmfileEntity
import 'directory_exception.dart';
import 'apktool_io_exception.dart';
import 'path_not_exist.dart'; // Added missing import
import '../common/brut_exception.dart'; // Import BrutException

class FileDirectory extends AbstractDirectoryBase {
  final dart_io.Directory _dir;

  FileDirectory(ExtFile extFile) : _dir = dart_io.Directory(extFile.path);

  // Named constructor for synchronous creation, if ExtFile was already validated to be a directory.
  FileDirectory.sync(ExtFile extFile) : _dir = dart_io.Directory(extFile.path) {
    if (!_dir.existsSync()) {
      throw DirectoryException(
        'Directory does not exist for sync creation: ${_dir.path}',
      );
    }
    // No explicit loading needed here, _ensureInitialized will call loadInitialFiles/Dirs
  }

  String get path => _dir.path;

  @override
  Set<String> loadInitialFiles() {
    final filesSet = LinkedHashSet<String>();
    if (!_dir.existsSync()) return filesSet; // Or throw?
    final entities = _dir.listSync(followLinks: false);
    // Sort to match Java AbstractDirectory behavior (though not strictly required by interface)
    entities.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    for (final entity in entities) {
      if (entity is dart_io.File) {
        filesSet.add(p.basename(entity.path));
      }
    }
    return filesSet;
  }

  @override
  Map<String, AbstractDirectoryBase> loadInitialDirs() {
    final dirsMap = LinkedHashMap<String, AbstractDirectoryBase>();
    if (!_dir.existsSync()) return dirsMap;
    final entities = _dir.listSync(followLinks: false);
    entities.sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path)));
    for (final entity in entities) {
      if (entity is dart_io.Directory) {
        final dirName = p.basename(entity.path);
        // Use ExtFile to potentially handle nested zip/apks if FileDirectory was pointed at one (though unlikely for FileDirectory)
        dirsMap[dirName] = FileDirectory(ExtFile(entity.path));
      }
    }
    return dirsMap;
  }

  @override
  Future<AbstractInputStream> getFileInputLocal(String name) async {
    final file = dart_io.File(p.join(_dir.path, name));
    if (!await file.exists()) {
      throw PathNotExist('File not found: ${file.path}');
    }
    return DartFileStreamInput(file.path); // Using helper from directory.dart
  }

  @override
  Future<AbstractOutputStream> getFileOutputLocal(String name) async {
    final file = dart_io.File(p.join(_dir.path, name));
    // Ensure parent directory exists (though for local, _dir is the parent)
    // OS.mkdirs(file.parent.path); // Handled by dart:io's openWrite typically
    await file.parent.create(recursive: true);
    return DartFileStreamOutput(file.path); // Using helper from directory.dart
  }

  @override
  Future<AbstractDirectoryBase> createDirLocal(String name) async {
    final newDirPath = p.join(_dir.path, name);
    final newDir = dart_io.Directory(newDirPath);
    await newDir.create(
      recursive: true,
    ); // recursive: true handles mkdirs behavior
    return FileDirectory(ExtFile(newDir.path));
  }

  @override
  Future<void> removeFileLocal(String name) async {
    final file = dart_io.File(p.join(_dir.path, name));
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      throw DirectoryException(
        'Failed to delete file: ${file.path}',
        e,
      ); // e is Object, matches new cause type
    }
  }

  @override
  Future<int> getSize(String fileName) async {
    final file = dart_io.File(p.join(_dir.path, fileName));
    if (await file.exists()) {
      return file.length();
    }
    throw PathNotExist('File not found for getSize: ${file.path}');
  }

  @override
  Future<int> getCompressedSize(String fileName) async {
    // For FileDirectory, compressed size is the same as actual size.
    return getSize(fileName);
  }

  @override
  Future<int> getCompressionLevel(String fileName) async {
    return 0; // 0 often means no compression or not applicable, like ZipEntry.STORED
  }
}
