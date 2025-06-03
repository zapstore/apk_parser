import 'package:apktool_dart/src/brut/androlib/apk_decoder.dart';
import 'package:test/test.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;

void main() {
  group('Resource Resolution Simple Test', () {
    test('Check resource resolution on all APKs', () async {
      final projectRoot = Directory.current.parent.path;
      final originalDir = Directory(p.join(projectRoot, 'original'));

      final apkFiles = await originalDir
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.apk'))
          .cast<File>()
          .toList();

      print(
        '\n=== Resource Resolution Summary for ${apkFiles.length} APKs ===\n',
      );

      var totalResolved = 0;
      var totalUnresolved = 0;
      var iconsResolved = 0;
      var totalApks = 0;

      // Disable debug logging
      final results = <String>[];

      for (final apkFile in apkFiles) {
        final apkName = p.basename(apkFile.path);

        try {
          // Capture stdout to suppress debug messages
          final originalStdout = stdout;

          final decoder = ApkDecoder();
          final decodedXml = await decoder.decodeManifestToXmlText(
            apkFile.path,
          );

          // Count unresolved resources
          final resourceRefPattern = RegExp(r'@0x[0-9a-fA-F]{8}');
          final unresolvedMatches = resourceRefPattern
              .allMatches(decodedXml)
              .toList();

          // Count resolved resources
          final resolvedRefPattern = RegExp(
            r'@(style|string|drawable|color|dimen|id|mipmap|layout|anim|attr|integer|bool|array|plurals|xml|raw)/\w+',
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

          final iconResolved = iconAttr != null && !iconAttr.startsWith('@0x');

          results.add(
            '${apkName.padRight(30)} | '
            'Resolved: ${resolvedMatches.length.toString().padLeft(4)} | '
            'Unresolved: ${unresolvedMatches.length.toString().padLeft(3)} | '
            'Icon: ${iconResolved ? "✅" : "❌"} ${iconAttr ?? "N/A"}',
          );

          totalResolved += resolvedMatches.length;
          totalUnresolved += unresolvedMatches.length;
          if (iconResolved) iconsResolved++;
          totalApks++;
        } catch (e) {
          results.add(
            '${apkName.padRight(30)} | ERROR: ${e.toString().split('\n').first}',
          );
        }
      }

      // Print results after all processing
      for (final result in results) {
        print(result);
      }

      print('\n=== Summary ===');
      print('Total APKs processed: $totalApks');
      print('Total resolved resources: $totalResolved');
      print('Total unresolved resources: $totalUnresolved');
      print(
        'Resolution rate: ${totalResolved > 0 ? ((totalResolved / (totalResolved + totalUnresolved)) * 100).toStringAsFixed(1) : "0.0"}%',
      );
      print(
        'Icons resolved: $iconsResolved/$totalApks (${(iconsResolved * 100.0 / totalApks).toStringAsFixed(0)}%)',
      );

      // Verify all icons are resolved
      expect(
        iconsResolved,
        equals(totalApks),
        reason: 'All APK icons should be resolved',
      );
    });
  });
}
