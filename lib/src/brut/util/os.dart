library brut_util;

import 'dart:io';
// import '../common/brut_exception.dart'; // Not needed for the selected methods

// Awaiting https://github.com/dart-lang/language/issues/2751 for top-level static classes
// For now, use top-level functions or a class with static methods.
class OS {
  OS._(); // Private constructor to prevent instantiation

  static void mkdirs(String dirPath) {
    Directory(dirPath).createSync(recursive: true);
  }

  static void mkdir(Directory dir) {
    dir.createSync(recursive: true); // equivalent of mkdirs
  }

  static void rmfile(String filePath) {
    final file = File(filePath);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  static void rmfileEntity(File file) {
    // Renamed from rmfile(File) to avoid conflict
    if (file.existsSync()) {
      file.deleteSync();
    }
  }

  static void rmdir(String dirPath) {
    final dir = Directory(dirPath);
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }

  static void rmdirEntity(Directory dir) {
    // Renamed from rmdir(File)
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }
}
