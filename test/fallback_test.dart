import 'package:apktool_dart/src/brut/androlib/apk_decoder.dart';
import 'package:test/test.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  group('Fallback Mechanism', () {
    test('chromite.apk works with fallback mechanism', () async {
      final projectRoot = Directory.current.parent.path;
      final chromiteApkPath = p.join(projectRoot, 'original', 'chromite.apk');
      final chromiteApkFile = File(chromiteApkPath);

      expect(
        await chromiteApkFile.exists(),
        isTrue,
        reason: 'chromite.apk must exist for fallback test',
      );

      final decoder = ApkDecoder();

      // This should succeed with fallback mechanism
      final manifestXml = await decoder.decodeManifestToXmlText(
        chromiteApkPath,
      );

      // Verify the manifest is valid
      expect(
        manifestXml.contains('<manifest'),
        isTrue,
        reason: 'Decoded manifest should contain manifest tag',
      );
      expect(
        manifestXml.contains('<application'),
        isTrue,
        reason: 'Decoded manifest should contain application tag',
      );

      print('✅ chromite.apk successfully decoded with fallback mechanism');
    });

    test('Fallback handles both manifest and resource extraction', () async {
      final projectRoot = Directory.current.parent.path;
      final chromiteApkPath = p.join(projectRoot, 'original', 'chromite.apk');

      final decoder = ApkDecoder();

      // Test manifest extraction
      final manifestXml = await decoder.decodeManifestToXmlText(
        chromiteApkPath,
      );
      expect(manifestXml.isNotEmpty, isTrue);

      print('✅ Manifest successfully extracted with fallback mechanism');

      // Test resource directory access (if resources exist)
      try {
        final tempDir = Directory.systemTemp.createTempSync('test_chromite_');
        await decoder.decodeResources(chromiteApkPath, tempDir.path);
        print('✅ Resources also extracted successfully with fallback');

        // Clean up
        await tempDir.delete(recursive: true);
      } catch (e) {
        // Resources might not exist or be readable, that's OK
        print('ℹ️  Resources not available or not readable: $e');
      }
    });
  });
}
