import 'dart:io';
import 'package:apktool_dart/src/brut/androlib/apk_decoder.dart';
import 'package:apktool_dart/src/brut/androlib/icon_renderer.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;

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

    // First, extract the manifest to get icon reference
    print('\n📱 Extracting app icon...');
    final manifestXml = await decoder.decodeManifestToXmlText(apkPath);
    final iconPath = await extractAppIcon(manifestXml, apkPath, outputDir);

    if (iconPath != null) {
      print('✅ App icon saved: $iconPath');
    } else {
      print('⚠️  No app icon found or unable to extract');
    }

    // Then decode the full APK
    print('\n📦 Decoding APK resources...');
    await decoder.decode(apkPath, outputDir);

    print('\n🎉 Decoding completed successfully!');
    print('Output directory: $outputDir');
    if (iconPath != null) {
      print('App icon: $iconPath');
    }
  } catch (e) {
    print('\nError decoding APK: $e');
    exit(1);
  }
}

/// Extract app icon and save it next to the APK file
Future<String?> extractAppIcon(
  String manifestXml,
  String apkPath,
  String outputDir,
) async {
  try {
    // Parse manifest to get icon reference
    final doc = xml.XmlDocument.parse(manifestXml);
    final applicationElement = doc.findAllElements('application').firstOrNull;

    if (applicationElement == null) {
      print('❌ No application element found in manifest');
      return null;
    }

    final iconAttr =
        applicationElement.getAttribute('icon') ??
        applicationElement.getAttribute('icon', namespace: 'android') ??
        applicationElement.getAttribute('android:icon');

    if (iconAttr == null) {
      print('❌ No icon attribute found in application element');
      return null;
    }

    print('📱 Found icon reference: $iconAttr');

    // Check if resources have been extracted
    final resourceDir = p.join(outputDir, 'res');
    if (!await Directory(resourceDir).exists()) {
      // Need to extract resources first for icon rendering
      print('📦 Extracting resources for icon rendering...');
      final decoder = ApkDecoder();
      await decoder.decodeResources(apkPath, outputDir);
    }

    // Render the icon
    final renderer = IconRenderer(resourceDir);
    final iconInfo = await renderer.getIconInfo(iconAttr);
    print('🔍 Icon type: $iconInfo');

    final renderedIconPath = await renderer.renderIcon(
      iconAttr,
      targetSize: 192, // Standard launcher icon size
    );

    if (renderedIconPath == null) {
      print('❌ Failed to render icon');
      return null;
    }

    // Copy icon to location next to APK
    final apkDir = p.dirname(apkPath);
    final apkBaseName = p.basenameWithoutExtension(apkPath);
    final iconFileName = '${apkBaseName}_icon.png';
    final finalIconPath = p.join(apkDir, iconFileName);

    await File(renderedIconPath).copy(finalIconPath);

    // Clean up temporary file
    await File(renderedIconPath).delete();

    return finalIconPath;
  } catch (e) {
    print('❌ Error extracting icon: $e');
    return null;
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
  print('Features:');
  print('  • Decodes AndroidManifest.xml');
  print('  • Extracts and decodes resources');
  print('  • Automatically extracts app icon as PNG (placed next to APK)');
  print('  • Supports adaptive icons, vector drawables, and raster images');
  print('  • Uses fallback mechanism for problematic APKs');
  print('');
  print('Example:');
  print('  dart run apktool.dart app.apk');
  print('  dart run apktool.dart app.apk -o decoded_app');
  print('');
  print('Output:');
  print('  • decoded_app/           - Decoded APK contents');
  print('  • app_icon.png          - Extracted app icon (192x192px)');
}
