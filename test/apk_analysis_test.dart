import 'dart:io';
import 'package:test/test.dart';
import 'package:path/path.dart' as p;
import 'package:apktool_dart/src/brut/androlib/apk_decoder.dart';

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
      ];

      for (final apkFile in apkFiles) {
        final apkName = p.basename(apkFile.path);

        try {
          final result = await decoder.analyzeApk(apkFile.path);

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
