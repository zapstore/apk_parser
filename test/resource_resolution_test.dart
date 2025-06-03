import 'package:apktool_dart/src/brut/androlib/apk_decoder.dart';
import 'package:test/test.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  group('Resource Resolution Test', () {
    test('Check if resources are resolved in manifest', () async {
      final projectRoot = Directory.current.parent.path;
      final apkPath = p.join(projectRoot, 'original', 'chronos.apk');

      final decoder = ApkDecoder();
      final decodedXml = await decoder.decodeManifestToXmlText(apkPath);

      print('\n=== Checking resource resolution ===');

      // Look for resource references
      final resourceRefPattern = RegExp(r'@0x[0-9a-fA-F]{8}');
      final matches = resourceRefPattern.allMatches(decodedXml);

      if (matches.isEmpty) {
        print('✅ No unresolved resource references found!');
      } else {
        print('❌ Found ${matches.length} unresolved resource references:');
        for (final match in matches.take(5)) {
          final start = match.start;
          final context = decodedXml.substring(
            start - 50 > 0 ? start - 50 : 0,
            start + 50 < decodedXml.length ? start + 50 : decodedXml.length,
          );
          print(
            '  ${match.group(0)} in context: ...${context.replaceAll('\n', ' ')}...',
          );
        }
      }

      // Check if we have resolved references like @style/, @string/, etc.
      final resolvedRefPattern = RegExp(
        r'@(style|string|drawable|color|dimen|id)/\w+',
      );
      final resolvedMatches = resolvedRefPattern.allMatches(decodedXml);

      if (resolvedMatches.isNotEmpty) {
        print('\n✅ Found ${resolvedMatches.length} resolved references:');
        for (final match in resolvedMatches.take(5)) {
          print('  ${match.group(0)}');
        }
      } else {
        print(
          '\n❌ No resolved references found (expected @style/, @string/, etc.)',
        );
      }

      // Print a sample of the manifest
      print('\n=== Sample of decoded manifest ===');
      final lines = decodedXml.split('\n');
      for (final line in lines.take(30)) {
        if (line.contains('android:')) {
          print(line.trim());
        }
      }
    });
  });
}
