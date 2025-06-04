import 'package:apktool_dart/src/brut/androlib/apk_decoder.dart';
import 'package:test/test.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml_pkg;

void main() {
  group('ApkDecoder Manifest Decoding', () {
    test(
      'Decodes AndroidManifest.xml for all APKs and compares with originals',
      () async {
        final projectRoot = Directory.current.parent.path;
        final originalDir = Directory(p.join(projectRoot, 'original'));

        expect(
          await originalDir.exists(),
          isTrue,
          reason: 'Original directory must exist.',
        );

        // Get all APK files
        final apkFiles = await originalDir
            .list()
            .where((entity) => entity is File && entity.path.endsWith('.apk'))
            .cast<File>()
            .toList();

        expect(
          apkFiles.isNotEmpty,
          isTrue,
          reason: 'At least one APK file must exist in original directory.',
        );

        final decoder = ApkDecoder();

        for (final apkFile in apkFiles) {
          final apkName = p.basenameWithoutExtension(apkFile.path);
          final goldenManifestPath = p.join(
            projectRoot,
            'original',
            apkName,
            'AndroidManifest.xml',
          );
          final goldenManifestFile = File(goldenManifestPath);

          expect(
            await goldenManifestFile.exists(),
            isTrue,
            reason:
                'Golden AndroidManifest.xml must exist for $apkName at $goldenManifestPath',
          );

          String decodedXmlText = '';
          String goldenXmlText = '';

          try {
            decodedXmlText = await decoder.decodeManifestToXmlText(
              apkFile.path,
            );
            goldenXmlText = await goldenManifestFile.readAsString();
          } catch (e, s) {
            fail(
              'Exception during manifest decoding or file reading for $apkName: $e\n$s',
            );
          }

          // Basic validation - does it contain expected tags?
          expect(
            decodedXmlText.contains('<manifest'),
            isTrue,
            reason: 'Decoded XML for $apkName should contain <manifest> tag',
          );
          expect(
            decodedXmlText.contains('<application'),
            isTrue,
            reason: 'Decoded XML for $apkName should contain <application> tag',
          );

          // Semantic comparison - parse both with package:xml and compare
          try {
            final decodedDoc = xml_pkg.XmlDocument.parse(decodedXmlText);
            final goldenDoc = xml_pkg.XmlDocument.parse(goldenXmlText);

            // Check root element name
            expect(
              decodedDoc.rootElement.name.local,
              equals(goldenDoc.rootElement.name.local),
              reason: 'Root element mismatch for $apkName',
            );

            // Check for application tag existence
            expect(
              decodedDoc.findAllElements('application').isNotEmpty,
              isTrue,
              reason:
                  'Decoded manifest for $apkName should have application element',
            );
            expect(
              goldenDoc.findAllElements('application').isNotEmpty,
              isTrue,
              reason:
                  'Golden manifest for $apkName should have application element',
            );
          } catch (e) {
            fail(
              'XML parsing of decoded/golden manifest failed for $apkName: $e',
            );
          }
        }
      },
      timeout: Timeout(
        Duration(seconds: 300),
      ), // Increased timeout for multiple APKs
    );
  });
}
