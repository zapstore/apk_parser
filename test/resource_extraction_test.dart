import 'package:test/test.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  group('Resource Extraction Test', () {
    test('Check if PNG files are extracted', () async {
      final projectRoot = Directory.current.parent.path;

      // Check if our implementation has extracted any resources
      final outputDir = Directory(p.join(projectRoot, 'output', 'chronos'));

      if (await outputDir.exists()) {
        print('\nChecking extracted resources in ${outputDir.path}:');

        final resDir = Directory(p.join(outputDir.path, 'res'));
        if (await resDir.exists()) {
          print('Found res directory');

          // List mipmap directories
          await for (final entity in resDir.list()) {
            if (entity is Directory &&
                p.basename(entity.path).startsWith('mipmap')) {
              print('  ${p.basename(entity.path)}:');
              await for (final file in entity.list()) {
                print('    ${p.basename(file.path)}');
              }
            }
          }
        } else {
          print('❌ No res directory found - resources not extracted');
        }
      } else {
        print('❌ No output directory found - decodeResources not implemented');
      }

      // Check what's in the original (golden) directory for comparison
      print('\nGolden directory structure (from original Apktool):');
      final goldenDir = Directory(
        p.join(projectRoot, 'original', 'chronos', 'res'),
      );

      if (await goldenDir.exists()) {
        // Count PNG files
        var pngCount = 0;
        var xmlCount = 0;
        var otherCount = 0;

        await for (final entity in goldenDir.list(recursive: true)) {
          if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            if (ext == '.png')
              pngCount++;
            else if (ext == '.xml')
              xmlCount++;
            else
              otherCount++;
          }
        }

        print('  PNG files: $pngCount');
        print('  XML files: $xmlCount');
        print('  Other files: $otherCount');

        // Show sample mipmap files
        print('\nSample mipmap files in golden:');
        await for (final entity in goldenDir.list()) {
          if (entity is Directory &&
              p.basename(entity.path).startsWith('mipmap')) {
            final dirName = p.basename(entity.path);
            final files = await entity.list().where((e) => e is File).toList();
            if (files.isNotEmpty) {
              print('  $dirName: ${files.length} files');
              for (final file in files.take(2)) {
                print('    - ${p.basename(file.path)}');
              }
            }
          }
        }
      }

      print(
        '\n⚠️  Resource extraction (decodeResources) is not yet implemented',
      );
      print('   Only manifest decoding is currently working');
    });
  });
}
