import 'dart:io';
import 'dart:convert';
import 'package:apktool_dart/src/brut/androlib/apk_decoder.dart';

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

  try {
    final decoder = ApkDecoder();

    // Fast analysis - returns all essential info as JSON
    final result = await decoder.analyzeApk(apkPath);

    // Output JSON result
    final jsonOutput = JsonEncoder.withIndent('  ').convert(result);
    print(jsonOutput);
  } catch (e) {
    print('Error analyzing APK: $e');
    exit(1);
  }
}

void printUsage() {
  print('Apktool Dart - Fast APK Analyzer');
  print('');
  print('Usage:');
  print('  dart run apktool.dart <apk_file>');
  print('');
  print('Arguments:');
  print('  apk_file      Path to the APK file to analyze');
  print('');
  print('Output:');
  print('  JSON containing:');
  print('  • package          - Package identifier');
  print('  • appName          - Human-readable app name');
  print('  • versionName      - Version string');
  print('  • versionCode      - Version code number');
  print('  • minSdkVersion    - Minimum Android API level');
  print('  • targetSdkVersion - Target Android API level');
  print('  • permissions      - Array of requested permissions');
  print('  • iconBase64       - App icon as base64-encoded PNG (192x192px)');
  print('  • analysisTimestamp- When the analysis was performed');
  print('');
  print('Features:');
  print('  • Fast analysis without writing files to disk');
  print('  • Supports adaptive icons, vector drawables, and raster images');
  print('  • Automatic format conversion (WebP/JPG → PNG)');
  print('  • Fallback mechanism for problematic APKs');
  print('  • All essential info in single JSON output');
  print('');
  print('Example:');
  print('  dart run apktool.dart app.apk > app_info.json');
}
