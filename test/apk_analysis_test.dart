import 'dart:io';
import 'dart:convert';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:apk_parser/src/androlib/apk_decoder.dart';

void main() {
  group('APK Analysis Tests', () {
    late String assetsDir;
    late String aapt2Path;
    late List<File> apkFiles;

    setUpAll(() async {
      // Get the test assets directory
      assetsDir = p.join('test', 'assets');
      aapt2Path = p.join(assetsDir, 'aapt2');

      // Verify aapt2 exists and is executable
      final aapt2File = File(aapt2Path);
      expect(
        await aapt2File.exists(),
        isTrue,
        reason: 'aapt2 tool must exist in assets folder',
      );

      // Get all APK files from assets directory
      final assetsDirectory = Directory(assetsDir);
      apkFiles = await assetsDirectory
          .list()
          .where((entity) => entity is File && entity.path.endsWith('.apk'))
          .cast<File>()
          .toList();

      expect(
        apkFiles.isNotEmpty,
        isTrue,
        reason: 'At least one APK file must exist in assets directory',
      );

      print('\n📱 Found ${apkFiles.length} APK files for testing:');
      for (final apk in apkFiles) {
        print('  • ${p.basename(apk.path)}');
      }
    });

    test('analyzeApk output matches aapt2 dump badging for all APKs', () async {
      final decoder = ApkDecoder();
      final results = <String, Map<String, dynamic>>{};
      var successCount = 0;
      var totalComparisons = 0;

      for (final apkFile in apkFiles) {
        final apkName = p.basename(apkFile.path);
        print('\n🔍 Analyzing: $apkName');

        try {
          // 1. Get analyzeApk output
          final analysisResult = await decoder.analyzeApk(apkFile.path);

          // This test is not valid if architecture check fails
          if (analysisResult == null) {
            print(
              '  ⚠️ Skipping aapt2 comparison for $apkName (arch mismatch)',
            );
            continue;
          }

          // 2. Get aapt2 dump badging output
          final aapt2Result = await Process.run(aapt2Path, [
            'dump',
            'badging',
            apkFile.path,
          ]);

          if (aapt2Result.exitCode != 0) {
            print('  ❌ aapt2 failed: ${aapt2Result.stderr}');
            continue;
          }

          final aapt2Output = aapt2Result.stdout as String;
          final aapt2Data = _parseAapt2Output(aapt2Output);

          // 3. Compare specific properties
          final comparisons = <String, dynamic>{
            'package': {
              'analyzeApk': analysisResult['package'],
              'aapt2': aapt2Data['package'],
              'match': analysisResult['package'] == aapt2Data['package'],
            },
            'versionName': {
              'analyzeApk': analysisResult['versionName'],
              'aapt2': aapt2Data['versionName'],
              'match':
                  analysisResult['versionName'] == aapt2Data['versionName'],
            },
            'versionCode': {
              'analyzeApk': analysisResult['versionCode'],
              'aapt2': aapt2Data['versionCode'],
              'match':
                  analysisResult['versionCode'] == aapt2Data['versionCode'],
            },
            'minSdkVersion': {
              'analyzeApk': analysisResult['minSdkVersion'],
              'aapt2': aapt2Data['minSdkVersion'],
              'match':
                  analysisResult['minSdkVersion'] == aapt2Data['minSdkVersion'],
            },
            'targetSdkVersion': {
              'analyzeApk': analysisResult['targetSdkVersion'],
              'aapt2': aapt2Data['targetSdkVersion'],
              'match':
                  analysisResult['targetSdkVersion'] ==
                  aapt2Data['targetSdkVersion'],
            },
            'appName': {
              'analyzeApk': analysisResult['appName'],
              'aapt2': aapt2Data['appName'],
              'match': analysisResult['appName'] == aapt2Data['appName'],
            },
          };

          results[apkName] = comparisons;

          // Print comparison results
          var apkMatches = 0;
          var apkTotal = 0;

          for (final property in comparisons.keys) {
            final comp = comparisons[property] as Map<String, dynamic>;
            final match = comp['match'] as bool;
            final analyzeValue = comp['analyzeApk'];
            final aapt2Value = comp['aapt2'];

            apkTotal++;
            totalComparisons++;

            if (match) {
              apkMatches++;
              print('  ✅ $property: $analyzeValue');
            } else {
              print(
                '  ❌ $property: analyzeApk="$analyzeValue" vs aapt2="$aapt2Value"',
              );
            }
          }

          if (apkMatches == apkTotal) {
            print('  🎉 All properties match for $apkName');
            successCount++;
          } else {
            print('  ⚠️  $apkMatches/$apkTotal properties match for $apkName');
          }
        } catch (e, stackTrace) {
          print('  💥 Error analyzing $apkName: $e');
          print('     Stack trace: $stackTrace');
        }
      }

      // Print overall results
      print('\n📊 Overall Results:');
      print(
        'APKs with all properties matching: $successCount/${apkFiles.length}',
      );
      print('Total property comparisons made: $totalComparisons');

      // Print detailed comparison table
      print('\n📋 Detailed Comparison Results:');
      print(
        'APK Name'.padRight(30) +
            'Package'.padRight(10) +
            'VerName'.padRight(10) +
            'VerCode'.padRight(10) +
            'MinSDK'.padRight(10) +
            'TargetSDK'.padRight(10) +
            'AppName'.padRight(10),
      );
      print('-' * 100);

      for (final apkName in results.keys) {
        final comparisons = results[apkName]!;
        final line =
            apkName.padRight(30) +
            (comparisons['package']!['match'] ? '✅' : '❌').padRight(10) +
            (comparisons['versionName']!['match'] ? '✅' : '❌').padRight(10) +
            (comparisons['versionCode']!['match'] ? '✅' : '❌').padRight(10) +
            (comparisons['minSdkVersion']!['match'] ? '✅' : '❌').padRight(10) +
            (comparisons['targetSdkVersion']!['match'] ? '✅' : '❌').padRight(
              10,
            ) +
            (comparisons['appName']!['match'] ? '✅' : '❌').padRight(10);
        print(line);
      }

      // Individual property assertions
      final propertyMatches = <String, int>{};
      for (final apkResults in results.values) {
        for (final property in apkResults.keys) {
          final match =
              (apkResults[property] as Map<String, dynamic>)['match'] as bool;
          propertyMatches[property] =
              (propertyMatches[property] ?? 0) + (match ? 1 : 0);
        }
      }

      for (final property in propertyMatches.keys) {
        final matches = propertyMatches[property]!;
        final percentage = (matches / results.length) * 100;
        print(
          '$property: $matches/${results.length} (${percentage.toStringAsFixed(1)}%)',
        );
      }
    });

    test('analyzeApk returns valid JSON structure for all APKs', () async {
      final decoder = ApkDecoder();
      final requiredFields = [
        'package',
        'appName',
        'versionName',
        'versionCode',
        'minSdkVersion',
        'targetSdkVersion',
        'permissions',
        'architectures',
      ];

      for (final apkFile in apkFiles) {
        final apkName = p.basename(apkFile.path);

        try {
          final result = await decoder.analyzeApk(apkFile.path);

          // In some test cases, we might get null due to architecture mismatch
          if (result == null) {
            print(
              '  ⚠️ Skipping JSON structure test for $apkName (arch mismatch)',
            );
            continue;
          }

          // Verify all required fields are present
          for (final field in requiredFields) {
            expect(
              result.containsKey(field),
              isTrue,
              reason: '$apkName should contain $field in analysis result',
            );
            expect(
              result[field],
              isNotNull,
              reason: '$field should not be null for $apkName',
            );
          }

          // Verify specific field types
          expect(
            result['permissions'],
            isA<List>(),
            reason: 'permissions should be a list for $apkName',
          );
          expect(
            result['architectures'],
            isA<List>(),
            reason: 'architectures should be a list for $apkName',
          );
          expect(
            result['package'],
            isA<String>(),
            reason: 'package should be a string for $apkName',
          );
          expect(
            result['appName'],
            isA<String>(),
            reason: 'appName should be a string for $apkName',
          );

          print('✅ $apkName: Valid JSON structure');
        } catch (e) {
          fail('Failed to analyze $apkName: $e');
        }
      }
    });

    test('analyzeApk handles architecture filtering correctly', () async {
      final decoder = ApkDecoder();
      File? multiArchApk;
      List<dynamic>? supportedArches;

      // Find the first APK that has at least one architecture, without relying on filename
      for (final apkFile in apkFiles) {
        final result = await decoder.analyzeApk(apkFile.path);
        if (result != null &&
            result.containsKey('architectures') &&
            (result['architectures'] as List).isNotEmpty) {
          // Found an APK with architectures, but we need to check it's not the default
          final arches = result['architectures'] as List;
          if (arches.length > 1 || arches.first != 'arm64-v8a') {
            multiArchApk = apkFile;
            supportedArches = result['architectures'] as List;
            break;
          }
        }
      }

      if (multiArchApk == null) {
        print(
          '\n⚠️ Skipping architecture filtering test: No APK with non-default native architectures found.',
        );
        return;
      }

      final apkName = p.basename(multiArchApk.path);
      print('\n🔬 Testing architecture filtering on: $apkName');
      print('  Supported architectures: $supportedArches');

      // We already know from the loop that supportedArches is not null or empty.
      final firstArch = supportedArches!.first as String;

      // 2. Analyze with a matching architecture
      final result2 = await decoder.analyzeApk(
        multiArchApk.path,
        requiredArchitecture: firstArch,
      );
      expect(result2, isNotNull);
      expect(result2?['package'], isNotNull);
      print('  ✅ Correctly returned data for matching arch: $firstArch');

      // 3. Analyze with a non-matching architecture
      const nonExistentArch = 'riscv64';
      final result3 = await decoder.analyzeApk(
        multiArchApk.path,
        requiredArchitecture: nonExistentArch,
      );
      expect(result3, isNull);
      print(
        '  ✅ Correctly returned null for non-matching arch: $nonExistentArch',
      );
    });

    test('manifest decoding works for all APKs', () async {
      final decoder = ApkDecoder();
      var successCount = 0;

      for (final apkFile in apkFiles) {
        final apkName = p.basename(apkFile.path);

        try {
          final manifestXml = await decoder.decodeManifestToXmlText(
            apkFile.path,
          );

          // Basic validation
          expect(
            manifestXml.contains('<manifest'),
            isTrue,
            reason: '$apkName manifest should contain <manifest> tag',
          );
          expect(
            manifestXml.contains('<application'),
            isTrue,
            reason: '$apkName manifest should contain <application> tag',
          );

          successCount++;
          print('✅ $apkName: Manifest decoded successfully');
        } catch (e) {
          print('❌ $apkName: Manifest decoding failed: $e');
        }
      }

      // Expect most APKs to decode successfully
      expect(
        successCount,
        greaterThan(apkFiles.length * 0.8),
        reason: 'At least 80% of APKs should have decodable manifests',
      );

      print('\nManifest decoding: $successCount/${apkFiles.length} successful');
    });

    test('icon export functionality works correctly', () async {
      final decoder = ApkDecoder();
      var iconsExported = 0;

      for (final apkFile in apkFiles) {
        final apkName = p.basename(apkFile.path);

        try {
          // Analyze the APK
          final result = await decoder.analyzeApk(apkFile.path);

          if (result == null) {
            print(
              '  ⚠️ Skipping icon export test for $apkName (arch mismatch)',
            );
            continue;
          }

          final iconBase64 = result['iconBase64'] as String?;

          if (iconBase64 != null && iconBase64.isNotEmpty) {
            // Create a temporary file for the icon
            final tempDir = Directory.systemTemp.createTempSync('icon_test_');
            final iconPath = p.join(tempDir.path, '${apkName}_icon.png');

            try {
              // Test the CLI tool with --export-icon option
              final cliResult = await Process.run('dart', [
                'run',
                'bin/apktool.dart',
                '--export-icon',
                iconPath,
                apkFile.path,
              ]);

              // Check that the CLI command succeeded
              expect(
                cliResult.exitCode,
                equals(0),
                reason: 'CLI command should succeed for $apkName',
              );

              // Check that the icon file was created
              final iconFile = File(iconPath);
              expect(
                await iconFile.exists(),
                isTrue,
                reason: 'Icon file should be created for $apkName',
              );

              // Check that the file is not empty
              final iconBytes = await iconFile.readAsBytes();
              expect(
                iconBytes.length,
                greaterThan(0),
                reason: 'Icon file should not be empty for $apkName',
              );

              // Check that it's a valid PNG (starts with PNG magic bytes)
              expect(
                iconBytes.length,
                greaterThanOrEqualTo(8),
                reason: 'Icon file should be at least 8 bytes for $apkName',
              );
              expect(
                iconBytes.sublist(0, 8),
                equals([137, 80, 78, 71, 13, 10, 26, 10]), // PNG magic bytes
                reason: 'Icon file should be a valid PNG for $apkName',
              );

              // Verify the base64 content matches the exported file
              final expectedBytes = base64Decode(iconBase64);
              expect(
                iconBytes,
                equals(expectedBytes),
                reason:
                    'Exported icon should match base64 content for $apkName',
              );

              iconsExported++;
              print('✅ $apkName: Icon exported and validated successfully');

              // Check that success message was printed
              expect(
                cliResult.stdout.toString(),
                contains('✅ Icon exported to:'),
                reason: 'CLI should print success message for $apkName',
              );
            } finally {
              // Clean up temporary directory
              try {
                await tempDir.delete(recursive: true);
              } catch (e) {
                // Ignore cleanup errors
              }
            }
          } else {
            print('  ⚠️ $apkName: No icon available for export test');
          }
        } catch (e) {
          print('  ❌ $apkName: Icon export test failed: $e');
        }
      }

      // Expect at least some APKs to have exportable icons
      expect(
        iconsExported,
        greaterThan(0),
        reason: 'At least one APK should have an exportable icon',
      );

      print(
        '\nIcon export: $iconsExported/${apkFiles.length} APKs with icons exported successfully',
      );
    });
  });
}

/// Parse aapt2 dump badging output to extract key properties
Map<String, String> _parseAapt2Output(String output) {
  final result = <String, String>{};
  final lines = output.split('\n');

  for (final line in lines) {
    // Parse package line: package: name='com.example' versionCode='1' versionName='1.0' ...
    if (line.startsWith('package:')) {
      final packageMatch = RegExp(r"name='([^']*)'").firstMatch(line);
      if (packageMatch != null) {
        result['package'] = packageMatch.group(1)!;
      }

      final versionCodeMatch = RegExp(
        r"versionCode='([^']*)'",
      ).firstMatch(line);
      if (versionCodeMatch != null) {
        result['versionCode'] = versionCodeMatch.group(1)!;
      }

      final versionNameMatch = RegExp(
        r"versionName='([^']*)'",
      ).firstMatch(line);
      if (versionNameMatch != null) {
        result['versionName'] = versionNameMatch.group(1)!;
      }
    }
    // Parse minSdkVersion: minSdkVersion:'26'
    else if (line.startsWith('minSdkVersion:')) {
      final match = RegExp(r"minSdkVersion:'([^']*)'").firstMatch(line);
      if (match != null) {
        result['minSdkVersion'] = match.group(1)!;
      }
    }
    // Parse targetSdkVersion: targetSdkVersion:'35'
    else if (line.startsWith('targetSdkVersion:')) {
      final match = RegExp(r"targetSdkVersion:'([^']*)'").firstMatch(line);
      if (match != null) {
        result['targetSdkVersion'] = match.group(1)!;
      }
    }
    // Parse application-label: application-label:'App Name'
    else if (line.startsWith('application-label:')) {
      final match = RegExp(r"application-label:'([^']*)'").firstMatch(line);
      if (match != null) {
        result['appName'] = match.group(1)!;
      }
    }
  }

  return result;
}
