library;

import 'dart:async';
import 'dart:io' as dart_io;
import 'dart:io';
import 'dart:convert';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;
import 'package:apktool_dart/src/brut/androlib/icon_renderer.dart';

import '../directory/directory.dart';
import '../directory/ext_file.dart';
import 'res/data/res_table.dart';
import 'res/decoder/axml_resource_parser.dart';
import 'res/decoder/manifest_xml_serializer.dart';
import 'res/data/value/res_value.dart';

// Placeholder for AndrolibException if not already defined broadly
// Assuming it's in common or defined as previously.
// For now, let's ensure it's available for AXmlResourceParser

class ApkDecoder {
  ApkDecoder();

  Future<ResTable> _getResTable(String apkPath) async {
    // Always create a fresh ResTable to avoid caching issues
    final resTable = ResTable();
    try {
      await resTable.loadMainPackage(apkPath);
    } catch (e) {
      print('Warning: Could not load resource table: $e');
      // Continue without resource resolution
    }
    return resTable;
  }

  Future<void> decode(String apkPath, String outputDir) async {
    // Create output directory
    final outDir = dart_io.Directory(outputDir);
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    // Decode manifest
    final manifestXml = await decodeManifestToXmlText(apkPath);
    final manifestFile = dart_io.File(p.join(outputDir, 'AndroidManifest.xml'));
    await manifestFile.writeAsString(manifestXml);

    // Decode resources
    await decodeResources(apkPath, outputDir);
  }

  Future<void> decodeResources(String apkPath, String outputDir) async {
    final apkFile = ExtFile(apkPath);
    Directory? apkDirectory;

    try {
      apkDirectory = await apkFile.getDirectory();

      // Create res directory
      final resDir = dart_io.Directory(p.join(outputDir, 'res'));
      if (!await resDir.exists()) {
        await resDir.create(recursive: true);
      }

      // Load resource table
      final resTable = await _getResTable(apkPath);
      final package = resTable.getMainPackage();

      // Build resource file mapping (like ResFileDecoder in Java)
      final resFileMapping = <String, String>{};

      // Iterate through all file resources (like pkg.listFiles() in Java)
      for (final resSpec in package.listResSpecs()) {
        for (final resource in resSpec.listResources()) {
          final value = resource.getValue();

          // Only process file resources
          if (value is ResFileValue) {
            // Get input file path from ResFileValue
            final inFilePath = value.toString();
            final inFileName = _stripResFilePath(inFilePath);
            final outResName = resource.getFilePath();

            // Extract extension
            String outFileName;
            final extPos = inFileName.lastIndexOf('.');
            if (extPos == -1) {
              outFileName = outResName;
            } else {
              final ext = inFileName.substring(extPos).toLowerCase();
              outFileName = '$outResName$ext';
            }

            final outFilePath = 'res/$outFileName';

            // Add to mapping if paths are different
            if (inFilePath != outFilePath) {
              resFileMapping[inFilePath] = outFilePath;
            }
          }
        }
      }

      // Process all files in APK (not just mapped ones)
      final files = apkDirectory.getFiles();

      for (final fileName in files) {
        // Only process files in res/ directory
        if (fileName.startsWith('res/')) {
          // Skip resources.arsc - it's already processed
          if (fileName == 'resources.arsc') continue;

          // Determine output path using mapping
          final outputPath = resFileMapping[fileName] ?? fileName;
          final outputFile = dart_io.File(p.join(outputDir, outputPath));

          // Create parent directories
          await outputFile.parent.create(recursive: true);

          // Check file extension
          final ext = p.extension(fileName).toLowerCase();

          if (ext == '.xml') {
            // Try to decode binary XML files
            try {
              final xmlStream = await apkDirectory.getFileInput(fileName);
              final xmlParser = AXmlResourceParser(resTable);
              await xmlParser.setInput(xmlStream.asStream(), null);

              final serializer = ManifestXmlSerializer(xmlParser);
              final xmlText = await serializer.buildXmlDocumentToString();

              await outputFile.writeAsString(xmlText);
              await xmlStream.close();
              await xmlParser.close();
            } catch (e) {
              // If XML decoding fails, copy as binary
              await _copyBinaryFile(apkDirectory, fileName, outputFile);
            }
          } else {
            // Copy binary files as-is (PNG, JPG, etc.)
            await _copyBinaryFile(apkDirectory, fileName, outputFile);
          }
        }
      }
    } finally {
      await apkDirectory?.close();
      await apkFile.close();
    }
  }

  Future<void> _copyBinaryFile(
    Directory apkDirectory,
    String fileName,
    dart_io.File outputFile,
  ) async {
    final inputStream = await apkDirectory.getFileInput(fileName);
    final outputSink = outputFile.openWrite();

    try {
      await for (final chunk in inputStream.asStream()) {
        outputSink.add(chunk);
      }
    } finally {
      await outputSink.close();
      await inputStream.close();
    }
  }

  Future<String> decodeManifestToXmlText(String apkPath) async {
    ExtFile apkFile = ExtFile(apkPath);
    Directory? apkDirectory;
    AXmlResourceParser? parser;
    AbstractInputStream? manifestStream;

    try {
      // Try to load resource table first
      final resTable = await _getResTable(apkPath);

      apkDirectory = await apkFile.getDirectory();
      manifestStream = await apkDirectory.getFileInput("AndroidManifest.xml");

      // AXmlResourceParser needs a Stream<List<int>>, our AbstractInputStream provides asStream()
      final Stream<List<int>> rawManifestStream = manifestStream.asStream();

      parser = AXmlResourceParser(resTable); // Pass ResTable now
      await parser.setInput(
        rawManifestStream,
        null,
      ); // AXML encoding is handled internally

      final serializer = ManifestXmlSerializer(parser);
      return await serializer.buildXmlDocumentToString();
    } catch (e, s) {
      print("Error decoding manifest: $e");
      print("Stack trace: $s");
      rethrow;
    } finally {
      await manifestStream?.close();
      await parser
          ?.close(); // Close parser before directory, as parser uses stream from directory
      await apkDirectory?.close();
      await apkFile.close();
    }
  }

  String _stripResFilePath(String path) {
    // Strip res/ prefix if present (like ApkInfo.RESOURCES_DIRNAMES in Java)
    if (path.startsWith('res/')) {
      return path.substring(4);
    }
    return path;
  }

  /// Fast APK analysis that returns essential information as JSON
  /// without writing files to disk (except temporary icon processing)
  Future<Map<String, dynamic>> analyzeApk(String apkPath) async {
    final apkFile = dart_io.File(apkPath);
    if (!await apkFile.exists()) {
      throw FileSystemException('APK file not found', apkPath);
    }

    try {
      // 1. Decode manifest using existing method
      final manifestXml = await decodeManifestToXmlText(apkPath);
      final manifestDoc = xml.XmlDocument.parse(manifestXml);
      final manifestElement = manifestDoc.rootElement;

      // Extract basic app info
      final packageId = manifestElement.getAttribute('package') ?? 'unknown';
      final versionName =
          manifestElement.getAttribute('android:versionName') ?? 'unknown';
      final versionCode =
          manifestElement.getAttribute('android:versionCode') ?? 'unknown';

      // Extract SDK versions
      final usesSdkElement = manifestDoc
          .findAllElements('uses-sdk')
          .firstOrNull;
      final minSdkVersion =
          usesSdkElement?.getAttribute('android:minSdkVersion') ?? 'unknown';
      final targetSdkVersion =
          usesSdkElement?.getAttribute('android:targetSdkVersion') ?? 'unknown';

      // Extract permissions
      final permissions = <String>[];
      for (final permElement in manifestDoc.findAllElements(
        'uses-permission',
      )) {
        final permission = permElement.getAttribute('android:name');
        if (permission != null) {
          permissions.add(permission);
        }
      }

      // Extract icon reference
      final applicationElement = manifestDoc
          .findAllElements('application')
          .firstOrNull;
      final iconRef =
          applicationElement?.getAttribute('android:icon') ??
          applicationElement?.getAttribute('icon');

      // 2. Load resource table for app name resolution
      final resTable = await _getResTable(apkPath);

      // 3. Get app name from string resources
      String appName = packageId; // Fallback to package ID
      final appLabelRef =
          applicationElement?.getAttribute('android:label') ??
          applicationElement?.getAttribute('label');

      if (appLabelRef != null) {
        String? resolvedRef = appLabelRef;

        // Handle hex resource IDs like @0x7f12001d
        if (appLabelRef.startsWith('@0x')) {
          try {
            final hexStr = appLabelRef.substring(3); // Remove '@0x'
            final resId = int.parse(hexStr, radix: 16);
            resolvedRef = resTable.resolveReference(resId);
          } catch (e) {
            // Could not parse resource ID, continue with original value
          }
        }

        // Now handle the resolved reference
        if (resolvedRef != null) {
          if (resolvedRef.startsWith('@string/')) {
            final stringName = resolvedRef.substring('@string/'.length);
            try {
              // Look up string resource in the main package
              final mainPackage = resTable.getMainPackage();
              final stringType = mainPackage.getType('string');
              final stringSpec = stringType.getResSpec(stringName);
              final resource = stringSpec.getDefaultResource();
              final value = resource.getValue();
              if (value is ResStringValue) {
                appName = value.value;
              }
            } catch (e) {
              // Could not resolve string resource, keep fallback
            }
          } else if (!resolvedRef.startsWith('@')) {
            // Direct string value
            appName = resolvedRef;
          }
        }
      }

      // 4. Get best icon as base64
      String? iconBase64;
      if (iconRef != null) {
        iconBase64 = await _getIconAsBase64(apkPath, iconRef);
      }

      // 5. Build result JSON
      final result = {
        'package': packageId,
        'appName': appName,
        'versionName': versionName,
        'versionCode': versionCode,
        'minSdkVersion': minSdkVersion,
        'targetSdkVersion': targetSdkVersion,
        'permissions': permissions,
        'iconBase64': iconBase64,
      };

      return result;
    } catch (e) {
      // print('❌ Analysis failed: $e');
      rethrow;
    }
  }

  /// Get the best icon as base64 encoded PNG
  Future<String?> _getIconAsBase64(String apkPath, String iconRef) async {
    try {
      // Create temporary directory for resource extraction with proper mapping
      final tempDir = await dart_io.Directory.systemTemp.createTemp(
        'apk_analysis_',
      );

      // Use the full decodeResources method which handles resource table mapping
      // This is essential for obfuscated APKs where files have obfuscated names
      await decodeResources(apkPath, tempDir.path);

      final resourceDir = dart_io.Directory(p.join(tempDir.path, 'res'));

      // Use IconRenderer to get the best icon
      final iconRenderer = IconRenderer(resourceDir.path, verbose: false);

      final renderedIconPath = await iconRenderer.renderIcon(iconRef);

      if (renderedIconPath == null) {
        await tempDir.delete(recursive: true);
        return null;
      }

      // Read icon file and convert to base64
      final iconBytes = await dart_io.File(renderedIconPath).readAsBytes();
      final base64Icon = base64Encode(iconBytes);

      // Clean up temporary files
      await tempDir.delete(recursive: true);

      return base64Icon;
    } catch (e) {
      print('⚠️  Icon processing failed: $e');
      return null;
    }
  }
}
