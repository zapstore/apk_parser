import 'dart:io';
import 'dart:convert';
import 'package:apk_parser/src/androlib/apk_parser.dart';
import 'package:args/args.dart';

void main(List<String> args) async {
  final argParser = ArgParser()
    ..addOption(
      'arch',
      abbr: 'a',
      help: 'Specify a required architecture (e.g., arm64-v8a)',
    )
    ..addOption(
      'export-icon',
      help: 'Export app icon to specified file path (e.g., icon.png)',
    );

  final argResults = argParser.parse(args);
  final rest = argResults.rest;

  if (rest.isEmpty) {
    printUsage(argParser);
    exit(1);
  }

  final apkPath = rest.first;
  final requiredArch = argResults['arch'] as String?;
  final exportIconPath = argResults['export-icon'] as String?;

  // Check if APK exists
  final apkFile = File(apkPath);
  if (!await apkFile.exists()) {
    print('Error: APK file not found: $apkPath');
    exit(1);
  }

  try {
    final parser = ApkParser();

    // Fast analysis - returns ApkAnalysis object
    final result = await parser.analyzeApk(
      apkPath,
      requiredArchitecture: requiredArch,
    );

    if (result == null) {
      print('APK does not contain the required architecture: $requiredArch');
      exit(1);
    }

    // Export icon if requested
    if (exportIconPath != null) {
      final iconBase64 = result.iconBase64;
      if (iconBase64 != null) {
        try {
          final iconBytes = base64Decode(iconBase64);
          await File(exportIconPath).writeAsBytes(iconBytes);
          print('✅ Icon exported to: $exportIconPath');
        } catch (e) {
          print('❌ Failed to export icon: $e');
        }
      } else {
        print('❌ No icon found in APK');
      }
    }

    // Convert ApkAnalysis to Map for JSON output
    final jsonMap = {
      'package': result.package,
      'appName': result.appName,
      'versionName': result.versionName,
      'versionCode': result.versionCode,
      'minSdkVersion': result.minSdkVersion,
      'targetSdkVersion': result.targetSdkVersion,
      'permissions': result.permissions,
      'architectures': result.architectures,
      'iconBase64': result.iconBase64,
      'certificateHashes': result.certificateHashes,
    };

    // Output JSON result
    final jsonOutput = JsonEncoder.withIndent('  ').convert(jsonMap);
    print(jsonOutput);
  } catch (e) {
    print('Error analyzing APK: $e');
    exit(1);
  }
}

void printUsage(ArgParser args) {
  print('Apktool Dart - Fast APK Analyzer');
  print('');
  print('Usage: dart run apktool.dart [options] <apk_file>');
  print('');
  print('Arguments:');
  print('  <apk_file>      Path to the APK file to analyze');
  print('');
  print('Options:');
  print(args.usage);
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
  print('  • architectures    - Array of supported CPU architectures');
  print('  • iconBase64       - App icon as base64-encoded PNG (192x192px)');
  print('  • certificateHashes- Array of certificate hashes (SHA-256)');
  print('');
  print('Examples:');
  print('  dart run apktool.dart app.apk');
  print('  dart run apktool.dart --arch arm64-v8a app.apk');
  print('  dart run apktool.dart --export-icon icon.png app.apk');
  print('');
  print('Features:');
  print('  • Fast analysis without writing files to disk');
  print('  • Supports adaptive icons, vector drawables, and raster images');
  print('  • Automatic format conversion (WebP/JPG → PNG)');
  print('  • Fallback mechanism for problematic APKs');
  print('  • All essential info in single JSON output');
  print('  • Icon export to disk in PNG format');
  print('');
}
