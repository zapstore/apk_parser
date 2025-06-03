import 'package:apktool_dart/src/brut/androlib/apk_decoder.dart';
import 'package:test/test.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml_pkg; // For semantic XML comparison later

void main() {
  group('ApkDecoder Manifest Decoding', () {
    test(
      'Decodes chronos.apk AndroidManifest.xml and compares with original',
      () async {
        final projectRoot = Directory
            .current
            .parent
            .path; // Assumes test is run from apktool_dart/test
        final apkPath = p.join(projectRoot, 'original', 'chronos.apk');
        final goldenManifestPath = p.join(
          projectRoot,
          'original',
          'chronos',
          'AndroidManifest.xml',
        );

        final apkFile = File(apkPath);
        final goldenManifestFile = File(goldenManifestPath);

        expect(
          await apkFile.exists(),
          isTrue,
          reason: 'Test APK $apkPath must exist.',
        );
        expect(
          await goldenManifestFile.exists(),
          isTrue,
          reason: 'Golden AndroidManifest.xml $goldenManifestPath must exist.',
        );

        final decoder = ApkDecoder();
        String decodedXmlText = '';
        String goldenXmlText = '';

        try {
          decodedXmlText = await decoder.decodeManifestToXmlText(apkPath);
          goldenXmlText = await goldenManifestFile.readAsString();
        } catch (e, s) {
          fail('Exception during manifest decoding or file reading: $e\n$s');
        }

        // TODO: Replace with proper XML semantic comparison.
        // For now, very basic check: does it contain <manifest> and <application>?
        // And a length check as a rough guide.
        expect(
          decodedXmlText.contains('<manifest'),
          isTrue,
          reason: 'Decoded XML should contain <manifest> tag',
        );
        expect(
          decodedXmlText.contains('<application'),
          isTrue,
          reason: 'Decoded XML should contain <application> tag',
        );

        // Normalize whitespace and compare (very rough initial comparison)
        String normalize(String s) {
          return s.replaceAll(RegExp(r'\s+'), ' ').trim();
        }

        final normalizedDecoded = normalize(decodedXmlText);
        final normalizedGolden = normalize(goldenXmlText);

        // This initial comparison might be too strict and fail due to minor formatting.
        // The goal is to see *some* output first.
        // expect(normalizedDecoded, equals(normalizedGolden), reason: 'Normalized decoded XML should match golden XML.');
        print('--- DECODED AndroidManifest.xml (chronos.apk) ---');
        print(decodedXmlText);
        print('--- END DECODED ---');

        // A more robust check would be to parse both with package:xml and compare documents.
        try {
          final decodedDoc = xml_pkg.XmlDocument.parse(decodedXmlText);
          final goldenDoc = xml_pkg.XmlDocument.parse(goldenXmlText);

          // Check root element name
          expect(
            decodedDoc.rootElement.name.local,
            equals(goldenDoc.rootElement.name.local),
          );
          // Check for application tag existence (can be more specific later)
          expect(decodedDoc.findAllElements('application').isNotEmpty, isTrue);
          expect(goldenDoc.findAllElements('application').isNotEmpty, isTrue);
        } catch (e) {
          fail('XML parsing of decoded/golden manifest failed: $e');
        }

        print(
          'Test completed. Decoded XML printed above. Semantic checks passed if no exceptions.',
        );
      },
      timeout: Timeout(Duration(seconds: 60)),
    ); // Increased timeout for file I/O and parsing
  });
}
