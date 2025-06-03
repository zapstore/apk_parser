import 'dart:io';
import 'package:apktool_dart/src/brut/androlib/apk_decoder.dart';
import 'package:path/path.dart' as p;

void main(List<String> args) async {
  if (args.isEmpty) {
    printUsage();
    exit(1);
  }

  final apkPath = args[0];

  // Check if APK exists
  final apkFile = File(apkPath);
  if (!await apkFile.exists()) {
    print('Error: APK file not found: $apkPath');
    exit(1);
  }

  // Determine output directory
  String outputDir;
  if (args.length >= 3 && args[1] == '-o') {
    outputDir = args[2];
  } else {
    // Default output directory is APK name without extension
    final baseName = p.basenameWithoutExtension(apkPath);
    outputDir = p.join(Directory.current.path, baseName);
  }

  print('Decoding APK: $apkPath');
  print('Output directory: $outputDir');

  try {
    final decoder = ApkDecoder();
    await decoder.decode(apkPath, outputDir);

    print('\nDecoding completed successfully!');
    print('Output directory: $outputDir');
  } catch (e) {
    print('\nError decoding APK: $e');
    exit(1);
  }
}

void printUsage() {
  print('Apktool Dart - APK decoder');
  print('');
  print('Usage:');
  print('  dart run apktool.dart <apk_file> [-o <output_dir>]');
  print('');
  print('Arguments:');
  print('  apk_file      Path to the APK file to decode');
  print('  -o            Output directory (optional, defaults to APK name)');
  print('');
  print('Example:');
  print('  dart run apktool.dart app.apk');
  print('  dart run apktool.dart app.apk -o decoded_app');
}
