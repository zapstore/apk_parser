import 'package:apktool_dart/src/brut/androlib/apk_decoder.dart';
import 'package:test/test.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml_pkg;

void main() {
  group('Test All APKs Manifest Decoding', () {
    final projectRoot = Directory.current.parent.path;
    final originalDir = Directory(p.join(projectRoot, 'original'));

    // Get all APK files
    final apkFiles = originalDir
        .listSync()
        .where((entity) => entity is File && entity.path.endsWith('.apk'))
        .cast<File>()
        .toList();

    print('Found ${apkFiles.length} APK files to test');

    for (final apkFile in apkFiles) {
      final apkName = p.basename(apkFile.path);
      final apkBaseName = p.basenameWithoutExtension(apkFile.path);

      test('Decode $apkName manifest', () async {
        final decoder = ApkDecoder();

        try {
          print('\n=== Testing $apkName ===');
          final decodedXml = await decoder.decodeManifestToXmlText(
            apkFile.path,
          );

          // Save decoded manifest
          final outputFile = File(
            p.join(
              projectRoot,
              'apktool_dart',
              'test_output',
              '$apkBaseName-manifest.xml',
            ),
          );
          await outputFile.parent.create(recursive: true);
          await outputFile.writeAsString(decodedXml);

          // Basic validation
          expect(
            decodedXml.contains('<manifest'),
            isTrue,
            reason: 'Should contain manifest tag',
          );

          // Try to parse as XML
          final doc = xml_pkg.XmlDocument.parse(decodedXml);
          expect(doc.rootElement.name.local, equals('manifest'));

          // Check for package attribute
          final packageName = doc.rootElement.getAttribute('package');
          expect(
            packageName,
            isNotNull,
            reason: 'Manifest should have package attribute',
          );
          print('Package: $packageName');

          // Count key elements
          final activities = doc.findAllElements('activity').length;
          final services = doc.findAllElements('service').length;
          final receivers = doc.findAllElements('receiver').length;
          final permissions = doc.findAllElements('uses-permission').length;

          print(
            'Activities: $activities, Services: $services, Receivers: $receivers, Permissions: $permissions',
          );

          // Compare with golden if exists
          final goldenManifestPath = p.join(
            originalDir.path,
            apkBaseName,
            'AndroidManifest.xml',
          );
          final goldenFile = File(goldenManifestPath);

          if (await goldenFile.exists()) {
            final goldenXml = await goldenFile.readAsString();
            final goldenDoc = xml_pkg.XmlDocument.parse(goldenXml);

            // Compare element counts
            final goldenActivities = goldenDoc
                .findAllElements('activity')
                .length;
            final goldenServices = goldenDoc.findAllElements('service').length;
            final goldenReceivers = goldenDoc
                .findAllElements('receiver')
                .length;
            final goldenPermissions = goldenDoc
                .findAllElements('uses-permission')
                .length;

            expect(
              activities,
              equals(goldenActivities),
              reason: 'Activity count mismatch',
            );
            expect(
              services,
              equals(goldenServices),
              reason: 'Service count mismatch',
            );
            expect(
              receivers,
              equals(goldenReceivers),
              reason: 'Receiver count mismatch',
            );
            expect(
              permissions,
              equals(goldenPermissions),
              reason: 'Permission count mismatch',
            );

            print('✓ Element counts match golden file');
          } else {
            print('⚠️  No golden manifest found at $goldenManifestPath');
          }
        } catch (e, stack) {
          print('Error decoding $apkName: $e');
          print('Stack: $stack');
          rethrow;
        }
      }, timeout: Timeout(Duration(seconds: 30)));
    }
  });
}
