import 'package:apktool_dart/src/brut/androlib/apk_decoder.dart';
import 'package:test/test.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;

void main() {
  group('Icon Resolution Test', () {
    test('Check android:icon resolution in application tag', () async {
      final projectRoot = Directory.current.parent.path;
      final apkPath = p.join(projectRoot, 'original', 'chronos.apk');
      final goldenDir = p.join(projectRoot, 'original', 'chronos');

      final decoder = ApkDecoder();
      final decodedXml = await decoder.decodeManifestToXmlText(apkPath);

      print('\n=== Testing android:icon resolution ===');

      // Parse the XML
      final doc = xml.XmlDocument.parse(decodedXml);
      final applicationElement = doc.findAllElements('application').first;

      // Get the android:icon attribute
      final iconAttr =
          applicationElement.getAttribute('icon', namespace: 'android') ??
          applicationElement.getAttribute('android:icon');

      print('Current android:icon value: $iconAttr');

      // Check if it's resolved
      if (iconAttr != null && iconAttr.startsWith('@0x')) {
        print('❌ Icon is not resolved - still shows resource ID: $iconAttr');

        // Try to manually resolve it
        final hexStr = iconAttr.substring(3);
        final resId = int.parse(hexStr, radix: 16);
        print('Resource ID: 0x${resId.toRadixString(16)} (decimal: $resId)');
      } else if (iconAttr != null && iconAttr.startsWith('@')) {
        print('✅ Icon is resolved: $iconAttr');

        // Extract the resource type and name
        final match = RegExp(r'@(\w+)/(.+)').firstMatch(iconAttr);
        if (match != null) {
          final resourceType = match.group(1);
          final resourceName = match.group(2);
          print('Resource type: $resourceType');
          print('Resource name: $resourceName');

          // Check if corresponding file exists in golden version
          if (resourceType == 'mipmap' || resourceType == 'drawable') {
            print('\nChecking for corresponding files in golden version:');

            // Common density qualifiers
            final densities = [
              'mdpi',
              'hdpi',
              'xhdpi',
              'xxhdpi',
              'xxxhdpi',
              'anydpi-v26',
            ];
            var foundAny = false;

            for (final density in densities) {
              final possiblePath = p.join(
                goldenDir,
                'res',
                '$resourceType-$density',
                '$resourceName.png',
              );
              final possibleFile = File(possiblePath);

              if (await possibleFile.exists()) {
                print('✅ Found: $possiblePath');
                foundAny = true;
              }

              // Also check webp format
              final webpPath = p.join(
                goldenDir,
                'res',
                '$resourceType-$density',
                '$resourceName.webp',
              );
              final webpFile = File(webpPath);

              if (await webpFile.exists()) {
                print('✅ Found: $webpPath');
                foundAny = true;
              }

              // Check XML vector drawable
              final xmlPath = p.join(
                goldenDir,
                'res',
                '$resourceType-$density',
                '$resourceName.xml',
              );
              final xmlFile = File(xmlPath);

              if (await xmlFile.exists()) {
                print('✅ Found: $xmlPath');
                foundAny = true;
              }
            }

            // Also check without density qualifier
            final basePath = p.join(
              goldenDir,
              'res',
              resourceType,
              '$resourceName.png',
            );
            final baseFile = File(basePath);
            if (await baseFile.exists()) {
              print('✅ Found: $basePath');
              foundAny = true;
            }

            if (!foundAny) {
              print('❌ No corresponding files found in golden version');
            }
          }
        }
      } else {
        print('❌ No android:icon attribute found');
      }

      // Also check golden manifest for comparison
      final goldenManifestPath = p.join(goldenDir, 'AndroidManifest.xml');
      final goldenManifestFile = File(goldenManifestPath);

      if (await goldenManifestFile.exists()) {
        print('\n=== Golden manifest comparison ===');
        final goldenXml = await goldenManifestFile.readAsString();
        final goldenDoc = xml.XmlDocument.parse(goldenXml);
        final goldenApp = goldenDoc.findAllElements('application').first;
        final goldenIcon =
            goldenApp.getAttribute('icon', namespace: 'android') ??
            goldenApp.getAttribute('android:icon');

        print('Golden android:icon value: $goldenIcon');

        if (iconAttr == goldenIcon) {
          print('✅ Icon matches golden version!');
        } else {
          print('❌ Icon does not match golden version');
          print('   Current: $iconAttr');
          print('   Golden:  $goldenIcon');
        }
      }
    });
  });
}
