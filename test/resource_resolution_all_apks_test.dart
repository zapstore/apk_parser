import 'package:apktool_dart/src/brut/androlib/apk_decoder.dart';
import 'package:test/test.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;

void main() {
  group('Resource Resolution All APKs Test', () {
    test('Check resource resolution on all APKs', () async {
      final projectRoot = Directory.current.parent.path;
      final originalDir = Directory(p.join(projectRoot, 'original'));

      final apkFiles = await originalDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.apk'))
          .cast<File>()
          .toList();

      print(
        '\n=== Testing resource resolution on ${apkFiles.length} APKs ===\n',
      );

      for (final apkFile in apkFiles) {
        final apkName = p.basename(apkFile.path);
        print('Testing $apkName...');

        final decoder = ApkDecoder();
        final decodedXml = await decoder.decodeManifestToXmlText(apkFile.path);

        // Count unresolved resources
        final resourceRefPattern = RegExp(r'@0x[0-9a-fA-F]{8}');
        final unresolvedMatches = resourceRefPattern
            .allMatches(decodedXml)
            .toList();

        // Count resolved resources
        final resolvedRefPattern = RegExp(
          r'@(style|string|drawable|color|dimen|id|mipmap|layout|anim|attr|integer|bool|array|plurals)/\w+',
        );
        final resolvedMatches = resolvedRefPattern
            .allMatches(decodedXml)
            .toList();

        // Parse XML and check android:icon specifically
        final doc = xml.XmlDocument.parse(decodedXml);
        final applicationElement = doc
            .findAllElements('application')
            .firstOrNull;
        final iconAttr =
            applicationElement?.getAttribute('icon', namespace: 'android') ??
            applicationElement?.getAttribute('android:icon');

        print('  Unresolved resources: ${unresolvedMatches.length}');
        print('  Resolved resources: ${resolvedMatches.length}');
        print('  android:icon: ${iconAttr ?? "not found"}');

        // Check if icon is resolved
        if (iconAttr != null && iconAttr.startsWith('@0x')) {
          print('  ❌ Icon not resolved');
        } else if (iconAttr != null && iconAttr.startsWith('@')) {
          print('  ✅ Icon resolved');
        }

        // Show sample of resolved resources
        if (resolvedMatches.isNotEmpty) {
          print('  Sample resolved resources:');
          for (final match in resolvedMatches.take(3)) {
            print('    ${match.group(0)}');
          }
        }

        // Show sample of unresolved resources
        if (unresolvedMatches.isNotEmpty) {
          print('  Sample unresolved resources:');
          for (final match in unresolvedMatches.take(3)) {
            final start = match.start;
            final context = decodedXml
                .substring(
                  start - 20 > 0 ? start - 20 : 0,
                  start + 50 < decodedXml.length
                      ? start + 50
                      : decodedXml.length,
                )
                .replaceAll('\n', ' ');
            print('    ${match.group(0)} in: ...$context...');
          }
        }

        print('');
      }
    });
  });
}
