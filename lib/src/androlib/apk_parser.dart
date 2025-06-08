library;

import 'dart:async';
import 'dart:io' as dart_io;
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;
import '../util/signature_parser.dart';

import '../directory/directory.dart';
import '../directory/ext_file.dart';
import 'res/data/res_table.dart';
import 'res/decoder/axml_resource_parser.dart';
import 'res/decoder/manifest_xml_serializer.dart';
import 'res/data/value/res_value.dart';
import 'package:image/image.dart' as img;

/// Represents the analysis results of an APK file
class ApkAnalysis {
  final String package;
  final String? appName;
  final String versionName;
  final String versionCode;
  final String minSdkVersion;
  final String targetSdkVersion;
  final List<String> permissions;
  final List<String> architectures;
  final String? iconBase64;
  final List<String> certificateHashes;

  ApkAnalysis({
    required this.package,
    required this.appName,
    required this.versionName,
    required this.versionCode,
    required this.minSdkVersion,
    required this.targetSdkVersion,
    required this.permissions,
    required this.architectures,
    this.iconBase64,
    required this.certificateHashes,
  });
  Map<String, dynamic> toMap() {
    return {
      'package': package,
      'appName': appName,
      'versionName': versionName,
      'versionCode': versionCode,
      'minSdkVersion': minSdkVersion,
      'targetSdkVersion': targetSdkVersion,
      'permissions': permissions,
      'architectures': architectures,
      'iconBase64': iconBase64,
      'certificateHashes': certificateHashes,
    };
  }
}

class ApkParser {
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
      final files = await apkDirectory.getFiles();

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
      final xmlText = await serializer.buildXmlDocumentToString();

      return xmlText;
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

  /// Fast APK analysis that returns essential information
  Future<ApkAnalysis?> analyzeApk(
    String apkPath, {
    String? requiredArchitecture,
  }) async {
    final apkFile = dart_io.File(apkPath);
    if (!await apkFile.exists()) {
      throw FileSystemException('APK file not found', apkPath);
    }

    // Isolate architecture check to its own ExtFile instance to avoid state issues.
    final architectures = await _getArchitectures(apkPath);

    // If a required architecture is specified, check if it's present
    if (requiredArchitecture != null &&
        !architectures.contains(requiredArchitecture)) {
      return null; // Mismatch, so return null as requested
    }

    try {
      // 2. Decode manifest using existing method
      final manifestXml = await decodeManifestToXmlText(apkPath);
      final manifestDoc = xml.XmlDocument.parse(manifestXml);
      final manifestElement = manifestDoc.rootElement;

      // Extract basic app info
      final packageId = manifestElement.getAttribute('package') ?? '';

      String? versionName = manifestElement.getAttribute('versionName');
      if (versionName == null || versionName.isEmpty) {
        versionName = manifestElement.getAttribute('android:versionName') ?? '';
      }

      String? versionCode = manifestElement.getAttribute('versionCode');
      if (versionCode == null || versionCode.isEmpty) {
        versionCode = manifestElement.getAttribute('android:versionCode') ?? '';
      }

      // Extract SDK versions
      final usesSdkElement = manifestDoc
          .findAllElements('uses-sdk')
          .firstOrNull;

      String? minSdkVersion = usesSdkElement?.getAttribute('minSdkVersion');
      if (minSdkVersion == null || minSdkVersion.isEmpty) {
        minSdkVersion =
            usesSdkElement?.getAttribute('android:minSdkVersion') ?? '';
      }

      String? targetSdkVersion = usesSdkElement?.getAttribute(
        'targetSdkVersion',
      );
      if (targetSdkVersion == null || targetSdkVersion.isEmpty) {
        targetSdkVersion =
            usesSdkElement?.getAttribute('android:targetSdkVersion') ?? '';
      }

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

      // 3. Load resource table for app name resolution
      final resTable = await _getResTable(apkPath);

      // 4. Get app name from string resources
      String? appName;
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

        // Recursively resolve string references
        if (resolvedRef != null) {
          appName = _resolveStringResource(resTable, resolvedRef);
        }
      }

      // 5. Get best icon as base64
      String? iconBase64;
      if (iconRef != null) {
        iconBase64 = await _getIconAsBase64(apkPath, iconRef);
      }

      // 6. Get certificate hashes
      Set<String> certificateHashes = {};
      try {
        certificateHashes = await getSignatureHashes(apkPath);
      } catch (e) {
        print('⚠️  Could not extract certificate hashes: $e');
        // Continue without certificate hashes
      }

      return ApkAnalysis(
        package: packageId,
        appName: appName,
        versionName: versionName,
        versionCode: versionCode,
        minSdkVersion: minSdkVersion,
        targetSdkVersion: targetSdkVersion,
        permissions: permissions,
        architectures: architectures.toList(),
        iconBase64: iconBase64,
        certificateHashes: certificateHashes.toList(),
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<Set<String>> _getArchitectures(String apkPath) async {
    ExtFile? extFile;
    Directory? apkDirectory;
    try {
      extFile = ExtFile(apkPath);
      apkDirectory = await extFile.getDirectory();
      final files = await apkDirectory.getFiles(recursive: true);
      final architectures = <String>{};

      for (final file in files) {
        if (file.startsWith('lib/')) {
          final parts = file.split('/');
          if (parts.length > 1 && parts[1].isNotEmpty) {
            architectures.add(parts[1]);
          }
        }
      }

      if (architectures.isEmpty) {
        architectures.add('arm64-v8a');
      }
      return architectures;
    } finally {
      await apkDirectory?.close();
      await extFile?.close();
    }
  }

  /// Get the best icon as base64 encoded PNG
  Future<String?> _getIconAsBase64(String apkPath, String iconRef) async {
    try {
      // Try to resolve the icon reference through the resource table
      final resTable = await _getResTable(apkPath);
      String? resolvedIconPath = await _resolveIconToFilePath(
        resTable,
        iconRef,
        apkPath,
      );

      if (resolvedIconPath != null) {
        // Extract the specific icon file from APK
        final iconBytes = await _extractFileFromApk(apkPath, resolvedIconPath);
        if (iconBytes != null) {
          // Process the icon (resize, convert to PNG)
          final processedIcon = await _processIconBytes(
            iconBytes,
            resolvedIconPath,
          );
          if (processedIcon != null) {
            final base64Icon = base64Encode(processedIcon);
            return base64Icon;
          }
        }
      }

      return null;
    } catch (e) {
      print('⚠️  Icon processing failed: $e');
      return null;
    }
  }

  /// Resolve icon reference to actual file path using resource table
  Future<String?> _resolveIconToFilePath(
    ResTable resTable,
    String iconRef,
    String apkPath,
  ) async {
    try {
      if (!iconRef.startsWith('@mipmap/') &&
          !iconRef.startsWith('@drawable/')) {
        return null;
      }

      final resourceName = iconRef.startsWith('@mipmap/')
          ? iconRef.substring('@mipmap/'.length)
          : iconRef.substring('@drawable/'.length);
      final resourceType = iconRef.startsWith('@mipmap/')
          ? 'mipmap'
          : 'drawable';

      final mainPackage = resTable.getMainPackage();

      try {
        final iconType = mainPackage.getType(resourceType);
        final iconSpec = iconType.getResSpec(resourceName);

        // Collect all raster image resources and their densities
        final Map<String, int> densityPriority = {
          'xxxhdpi': 640, // 4x
          'xxhdpi': 480, // 3x
          'xhdpi': 320, // 2x
          'hdpi': 240, // 1.5x
          'mdpi': 160, // 1x (baseline)
          'ldpi': 120, // 0.75x
          '': 160, // Default density if no qualifier
        };

        String? bestIconPath;
        int bestDensity = 0;
        String? adaptiveIconXmlPath;

        // Look through all resources in this spec to find the highest density raster image or adaptive icon
        for (final resource in iconSpec.listResources()) {
          final value = resource.getValue();
          if (value is ResFileValue) {
            final filePath = value.toString();

            // Check if it's an adaptive icon XML file (API 26+)
            if (filePath.toLowerCase().endsWith('.xml')) {
              adaptiveIconXmlPath = filePath;
              continue;
            }

            // Check if it's a raster image format
            if (filePath.toLowerCase().endsWith('.png') ||
                filePath.toLowerCase().endsWith('.webp') ||
                filePath.toLowerCase().endsWith('.jpg') ||
                filePath.toLowerCase().endsWith('.jpeg')) {
              // Extract density from the resource configuration
              final config = resource.getConfig();
              final qualifiers = config.getFlags().getQualifiers();

              // Parse density qualifier (e.g., "-xxxhdpi", "-xxhdpi", etc.)
              int currentDensity = 160; // Default mdpi
              for (final densityName in densityPriority.keys) {
                if (qualifiers.contains('-$densityName')) {
                  currentDensity = densityPriority[densityName]!;
                  break;
                }
              }

              // If no density qualifier found, it might be the default
              if (qualifiers.isEmpty || qualifiers == '') {
                currentDensity = densityPriority['']!;
              }

              // Select the highest density version
              if (currentDensity > bestDensity) {
                bestDensity = currentDensity;
                bestIconPath = filePath;
              }
            }
          }
        }

        // If we found a raster image, return it
        if (bestIconPath != null) {
          return bestIconPath;
        }

        // If we found an adaptive icon XML, try to extract the best drawable from it
        if (adaptiveIconXmlPath != null) {
          final extractedIcon = await _extractIconFromAdaptiveXml(
            resTable,
            adaptiveIconXmlPath,
            apkPath,
          );
          if (extractedIcon != null) {
            return extractedIcon;
          }
        }
      } catch (e) {
        // Resource not found, continue
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Extract a specific file from the APK
  Future<Uint8List?> _extractFileFromApk(
    String apkPath,
    String filePath,
  ) async {
    final apkFile = ExtFile(apkPath);
    Directory? apkDirectory;

    try {
      apkDirectory = await apkFile.getDirectory();

      // Check if the file exists in the APK
      final files = await apkDirectory.getFiles(recursive: true);
      if (!files.contains(filePath)) {
        return null;
      }

      // Extract the file
      final fileStream = await apkDirectory.getFileInput(filePath);
      final fileBytes = <int>[];

      await for (final chunk in fileStream.asStream()) {
        fileBytes.addAll(chunk);
      }
      await fileStream.close();

      return Uint8List.fromList(fileBytes);
    } catch (e) {
      return null;
    } finally {
      await apkDirectory?.close();
      await apkFile.close();
    }
  }

  /// Process raw icon bytes - convert formats and resize as needed
  Future<Uint8List?> _processIconBytes(
    Uint8List iconBytes,
    String fileName,
  ) async {
    try {
      // Try to decode the image
      final img.Image? image;
      final extension = p.extension(fileName).toLowerCase();

      switch (extension) {
        case '.png':
          image = img.decodePng(iconBytes);
          break;
        case '.webp':
          image = img.decodeWebP(iconBytes);
          break;
        case '.jpg':
        case '.jpeg':
          image = img.decodeJpg(iconBytes);
          break;
        default:
          image = img.decodeImage(iconBytes);
      }

      if (image == null) {
        return null;
      }

      // Resize to standard icon size (192x192)
      const targetSize = 192;
      final resizedImage = img.copyResize(
        image,
        width: targetSize,
        height: targetSize,
        interpolation: img.Interpolation.cubic,
      );

      // Always output as PNG for consistency
      final pngBytes = img.encodePng(resizedImage);

      return Uint8List.fromList(pngBytes);
    } catch (e) {
      return null;
    }
  }

  String? _resolveStringResource(ResTable resTable, String ref) {
    // Maximum recursion depth to prevent infinite loops
    const maxDepth = 10;
    return _resolveStringResourceRecursive(resTable, ref, 0, maxDepth);
  }

  String? _resolveStringResourceRecursive(
    ResTable resTable,
    String ref,
    int depth,
    int maxDepth,
  ) {
    // Prevent infinite recursion
    if (depth >= maxDepth) {
      return null;
    }

    if (ref.startsWith('@string/')) {
      final stringName = ref.substring('@string/'.length);
      try {
        // Look up string resource in the main package
        final mainPackage = resTable.getMainPackage();
        final stringType = mainPackage.getType('string');
        final stringSpec = stringType.getResSpec(stringName);
        final resource = stringSpec.getDefaultResource();
        final value = resource.getValue();

        if (value is ResStringValue) {
          final resolvedValue = value.value;
          // If the resolved value is another string reference, resolve it recursively
          if (resolvedValue.startsWith('@string/')) {
            return _resolveStringResourceRecursive(
              resTable,
              resolvedValue,
              depth + 1,
              maxDepth,
            );
          } else {
            // Final string value, return it
            return resolvedValue;
          }
        } else if (value is ResReferenceValue) {
          // Handle reference values by resolving the reference ID
          final refId = value.referenceId;

          // Resolve the reference to get the target resource reference string
          final resolvedRef = resTable.resolveReference(refId);
          if (resolvedRef != null) {
            // Recursively resolve the referenced resource
            return _resolveStringResourceRecursive(
              resTable,
              resolvedRef,
              depth + 1,
              maxDepth,
            );
          }
        }
      } catch (e) {
        // Could not resolve string resource, return null
        return null;
      }
    } else if (!ref.startsWith('@')) {
      // Direct string value (not a reference)
      return ref;
    }

    // Unknown reference type or resolution failed
    return null;
  }

  /// Extract icon from adaptive icon XML by parsing the XML and resolving drawable references
  Future<String?> _extractIconFromAdaptiveXml(
    ResTable resTable,
    String xmlPath,
    String apkPath,
  ) async {
    try {
      // Extract the XML file from the APK
      final xmlBytes = await _extractFileFromApk(apkPath, xmlPath);
      if (xmlBytes == null) {
        return null;
      }

      // Try to decode the XML (it might be binary XML)
      String xmlContent;
      try {
        // Try to decode as binary XML first
        final tempStream = Stream.fromIterable([xmlBytes]);
        final xmlParser = AXmlResourceParser(resTable);
        await xmlParser.setInput(tempStream, null);

        final serializer = ManifestXmlSerializer(xmlParser);
        xmlContent = await serializer.buildXmlDocumentToString();
        await xmlParser.close();
      } catch (e) {
        // If binary XML parsing fails, try as plain text
        xmlContent = String.fromCharCodes(xmlBytes);
      }

      // Parse the XML to find drawable references
      final xmlDoc = xml.XmlDocument.parse(xmlContent);
      final adaptiveIconElement = xmlDoc
          .findAllElements('adaptive-icon')
          .firstOrNull;

      if (adaptiveIconElement == null) {
        return null;
      }

      // Look for drawable references, prioritizing @mipmap references
      final drawableRefs = <String>[];

      // Check foreground first
      final foregroundElement = adaptiveIconElement
          .findAllElements('foreground')
          .firstOrNull;
      if (foregroundElement != null) {
        final drawable =
            foregroundElement.getAttribute('android:drawable') ??
            foregroundElement.getAttribute('drawable');
        if (drawable != null) {
          drawableRefs.add(drawable);
        }
      }

      // Check background as fallback
      final backgroundElement = adaptiveIconElement
          .findAllElements('background')
          .firstOrNull;
      if (backgroundElement != null) {
        final drawable =
            backgroundElement.getAttribute('android:drawable') ??
            backgroundElement.getAttribute('drawable');
        if (drawable != null) {
          drawableRefs.add(drawable);
        }
      }

      // Prioritize @mipmap references over @drawable references
      drawableRefs.sort((a, b) {
        if (a.startsWith('@mipmap/') && !b.startsWith('@mipmap/')) {
          return -1; // a comes first
        } else if (!a.startsWith('@mipmap/') && b.startsWith('@mipmap/')) {
          return 1; // b comes first
        }
        return 0; // same priority
      });

      // Try to resolve each drawable reference to a raster image
      for (final drawableRef in drawableRefs) {
        if (drawableRef.startsWith('@mipmap/') ||
            drawableRef.startsWith('@drawable/')) {
          final resolvedPath = await _resolveDrawableToRasterPath(
            resTable,
            drawableRef,
          );
          if (resolvedPath != null) {
            return resolvedPath;
          }
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Resolve a drawable reference to the highest quality raster image path
  Future<String?> _resolveDrawableToRasterPath(
    ResTable resTable,
    String drawableRef,
  ) async {
    try {
      if (!drawableRef.startsWith('@mipmap/') &&
          !drawableRef.startsWith('@drawable/')) {
        return null;
      }

      final resourceName = drawableRef.startsWith('@mipmap/')
          ? drawableRef.substring('@mipmap/'.length)
          : drawableRef.substring('@drawable/'.length);
      final resourceType = drawableRef.startsWith('@mipmap/')
          ? 'mipmap'
          : 'drawable';

      final mainPackage = resTable.getMainPackage();

      try {
        final drawableType = mainPackage.getType(resourceType);
        final drawableSpec = drawableType.getResSpec(resourceName);

        // Find the highest density raster image
        final Map<String, int> densityPriority = {
          'xxxhdpi': 640, // 4x
          'xxhdpi': 480, // 3x
          'xhdpi': 320, // 2x
          'hdpi': 240, // 1.5x
          'mdpi': 160, // 1x (baseline)
          'ldpi': 120, // 0.75x
          '': 160, // Default density if no qualifier
        };

        String? bestPath;
        int bestDensity = 0;

        for (final resource in drawableSpec.listResources()) {
          final value = resource.getValue();
          if (value is ResFileValue) {
            final filePath = value.toString();

            // Check if it's a raster image format OR a file without extension (might be an image)
            if (filePath.toLowerCase().endsWith('.png') ||
                filePath.toLowerCase().endsWith('.webp') ||
                filePath.toLowerCase().endsWith('.jpg') ||
                filePath.toLowerCase().endsWith('.jpeg') ||
                !filePath.contains('.')) {
              // Files without extensions might be images

              final config = resource.getConfig();
              final qualifiers = config.getFlags().getQualifiers();

              int currentDensity = 160; // Default mdpi
              for (final densityName in densityPriority.keys) {
                if (qualifiers.contains('-$densityName')) {
                  currentDensity = densityPriority[densityName]!;
                  break;
                }
              }

              if (qualifiers.isEmpty || qualifiers == '') {
                currentDensity = densityPriority['']!;
              }

              if (currentDensity > bestDensity) {
                bestDensity = currentDensity;
                bestPath = filePath;
              }
            } else {
              // Skipping non-raster file: $filePath
            }
          }
        }

        return bestPath;
      } catch (e) {
        return null;
      }
    } catch (e) {
      return null;
    }
  }
}
