import 'package:apktool_dart/src/brut/androlib/apk_decoder.dart';
import 'package:test/test.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;

void main() {
  group('Apktool Dart Tests', () {
    test('Manifest decoding with resource resolution for all APKs', () async {
      final projectRoot = Directory.current.parent.path;
      final originalDir = Directory(p.join(projectRoot, 'original'));

      final apkFiles = await originalDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.apk'))
          .cast<File>()
          .toList();

      print('\n=== Testing ${apkFiles.length} APKs ===\n');

      var successCount = 0;
      var iconResolvedCount = 0;

      for (final apkFile in apkFiles) {
        final apkName = p.basename(apkFile.path);

        try {
          final decoder = ApkDecoder();
          final decodedXml = await decoder.decodeManifestToXmlText(
            apkFile.path,
          );

          // Parse XML and check android:icon
          final doc = xml.XmlDocument.parse(decodedXml);
          final applicationElement = doc
              .findAllElements('application')
              .firstOrNull;
          final iconAttr =
              applicationElement?.getAttribute('icon') ??
              applicationElement?.getAttribute('icon', namespace: 'android') ??
              applicationElement?.getAttribute('android:icon');

          // Count resolved resources
          final resourceRefPattern = RegExp(r'@0x[0-9a-fA-F]{8}');
          final unresolvedMatches = resourceRefPattern
              .allMatches(decodedXml)
              .toList();

          final iconResolved = iconAttr != null && !iconAttr.startsWith('@0x');
          if (iconResolved) {
            iconResolvedCount++;
          }

          print(
            '$apkName: ✅ Manifest decoded | Icon: ${iconResolved ? "✅" : "❌"} $iconAttr | Unresolved: ${unresolvedMatches.length}',
          );
          successCount++;
        } catch (e) {
          print('$apkName: ❌ Error: ${e.toString().split('\n').first}');
        }
      }

      print('\n=== Summary ===');
      print('Manifest decoding: $successCount/${apkFiles.length} successful');
      print('Icon resolution: $iconResolvedCount/${apkFiles.length} resolved');

      // All manifests should decode and icons should be resolved
      expect(successCount, equals(apkFiles.length));
      expect(iconResolvedCount, equals(apkFiles.length));
    });

    test('Full APK decoding with resource extraction', () async {
      final projectRoot = Directory.current.parent.path;
      final testApk = p.join(projectRoot, 'original', 'quickdic.apk');
      final outputDir = p.join(projectRoot, 'output', 'test_quickdic');

      // Clean up previous output
      final outDir = Directory(outputDir);
      if (await outDir.exists()) {
        await outDir.delete(recursive: true);
      }

      print('\n=== Testing full APK decoding ===');

      final decoder = ApkDecoder();
      await decoder.decode(testApk, outputDir);

      // Check manifest was decoded
      final manifestFile = File(p.join(outputDir, 'AndroidManifest.xml'));
      expect(await manifestFile.exists(), isTrue);

      final manifestContent = await manifestFile.readAsString();
      final doc = xml.XmlDocument.parse(manifestContent);
      final applicationElement = doc.findAllElements('application').firstOrNull;
      final iconAttr =
          applicationElement?.getAttribute('icon') ??
          applicationElement?.getAttribute('icon', namespace: 'android') ??
          applicationElement?.getAttribute('android:icon');

      print('Manifest extracted: ✅');
      print('Icon attribute: $iconAttr');

      // Check resources were extracted
      final resDir = Directory(p.join(outputDir, 'res'));
      expect(await resDir.exists(), isTrue);

      // Count extracted files
      var fileCount = 0;
      var pngCount = 0;
      var xmlCount = 0;

      await for (final entity in resDir.list(recursive: true)) {
        if (entity is File) {
          fileCount++;
          final ext = p.extension(entity.path).toLowerCase();
          if (ext == '.png') {
            pngCount++;
          } else if (ext == '.xml') {
            xmlCount++;
          }
        }
      }

      print('Resources extracted: ✅');
      print('  Total files: $fileCount');
      print('  PNG files: $pngCount');
      print('  XML files: $xmlCount');

      expect(fileCount, greaterThan(0));

      // Note about obfuscated resources
      if (iconAttr == '@drawable/icon') {
        print('\nNote: This APK has obfuscated resource names.');
        print('The icon file exists but with an obfuscated name like "-B.png"');
        print(
          'Full deobfuscation requires implementing resource table file mapping.',
        );
      }
    });

    test('Icon resolution matches golden version', () async {
      final projectRoot = Directory.current.parent.path;
      final apkPath = p.join(projectRoot, 'original', 'chronos.apk');
      final goldenDir = p.join(projectRoot, 'original', 'chronos');

      final decoder = ApkDecoder();
      final decodedXml = await decoder.decodeManifestToXmlText(apkPath);

      // Parse both manifests
      final doc = xml.XmlDocument.parse(decodedXml);
      final applicationElement = doc.findAllElements('application').first;
      final iconAttr =
          applicationElement.getAttribute('icon') ??
          applicationElement.getAttribute('icon', namespace: 'android') ??
          applicationElement.getAttribute('android:icon');

      final goldenManifestFile = File(p.join(goldenDir, 'AndroidManifest.xml'));
      final goldenXml = await goldenManifestFile.readAsString();
      final goldenDoc = xml.XmlDocument.parse(goldenXml);
      final goldenApp = goldenDoc.findAllElements('application').first;
      final goldenIcon =
          goldenApp.getAttribute('icon') ??
          goldenApp.getAttribute('icon', namespace: 'android') ??
          goldenApp.getAttribute('android:icon');

      print('\n=== Icon Resolution Comparison ===');
      print('Our implementation: $iconAttr');
      print('Golden (Apktool):   $goldenIcon');

      expect(iconAttr, equals(goldenIcon));

      // Check if the referenced icon files exist in golden
      if (goldenIcon != null && goldenIcon.startsWith('@')) {
        final match = RegExp(r'@(\w+)/(.+)').firstMatch(goldenIcon);
        if (match != null) {
          final resourceType = match.group(1);
          final resourceName = match.group(2);

          print('\nChecking for icon files in golden:');
          final densities = ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi'];
          var foundCount = 0;

          for (final density in densities) {
            final iconPath = p.join(
              goldenDir,
              'res',
              '$resourceType-$density',
              '$resourceName.png',
            );
            if (await File(iconPath).exists()) {
              print('  ✅ $resourceType-$density/$resourceName.png');
              foundCount++;
            }
          }

          expect(
            foundCount,
            greaterThan(0),
            reason: 'Icon files should exist in golden',
          );
        }
      }
    });
  });
}
