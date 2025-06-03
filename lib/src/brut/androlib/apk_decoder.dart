library brut_androlib;

import 'dart:async';
import 'dart:convert';
import 'dart:io' as dart_io;
import 'dart:typed_data';

import '../directory/directory.dart';
import '../directory/ext_file.dart';
import 'res/decoder/axml_resource_parser.dart';
import 'res/decoder/manifest_xml_serializer.dart';
import 'res/data/res_table.dart';
import 'res/data/res_package.dart';
import 'res/data/res_resource.dart';
import 'res/data/res_id.dart';
import 'res/data/value/res_value.dart';

// Placeholder for AndrolibException if not already defined broadly
// Assuming it's in common or defined as previously.
// For now, let's ensure it's available for AXmlResourceParser
import '../../brut/common/brut_exception.dart';

import 'package:xml/xml.dart' as xml_pkg;
import 'package:path/path.dart' as p;

class ApkDecoder {
  ResTable? _resTable;

  ApkDecoder();

  Future<ResTable> _getResTable(String apkPath) async {
    if (_resTable == null) {
      _resTable = ResTable();
      try {
        await _resTable!.loadMainPackage(apkPath);
      } catch (e) {
        print('Warning: Could not load resource table: $e');
        // Continue without resource resolution
      }
    }
    return _resTable!;
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

      print(
        'Built resource file mapping with ${resFileMapping.length} entries',
      );

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
}
