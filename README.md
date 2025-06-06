# APK Parser

A Dart library for analyzing and decoding Android APK files, providing functionality similar to the Java [Apktool](https://github.com/iBotPeaches/Apktool) project. This implementation focuses on parsing Android binary XML (AXML) format, extracting resources, and providing detailed APK analysis.

## Features

- **APK Analysis**: Fast analysis of APK files returning essential information as JSON
- **AndroidManifest.xml Decoding**: Converts binary XML format to readable XML text
- **Resource Resolution**: Resolves resource references (e.g., `@string/app_name`) to human-readable format
- **Resource Extraction**: Extracts resources (images, XML files) from APK files
- **ARSC Parser**: Parses Android resource table (`resources.arsc`) files
- **Signature Analysis**: Extracts and validates APK signing information (V2/V3 signatures)
- **Architecture Detection**: Identifies supported CPU architectures in the APK
- **Icon Extraction**: Extracts and exports application icons
- **Cross-platform**: Pure Dart implementation that works on all platforms

## What it does

This library takes Android APK files as input and provides comprehensive analysis and decoding capabilities:

1. **APK Analysis**: The `analyzeApk` method returns a JSON object containing:
   - Package name and application name
   - Version information (name and code)
   - SDK version requirements (min and target)
   - List of permissions
   - Supported CPU architectures
   - Application icon (as base64-encoded PNG)
   - Certificate hashes for signature verification
   - Optional architecture filtering

2. **Manifest Decoding**: Reads the binary `AndroidManifest.xml` file and converts it to readable XML format
3. **Resource Resolution**: Resolves numeric resource IDs (like `@0x7f020001`) to human-readable names (like `@drawable/icon`)
4. **Resource Extraction**: Extracts and decodes resources like images, layouts, and other XML files from the APK
5. **Signature Analysis**: Parses and validates APK signing blocks (V2/V3) including:
   - Signature algorithms (RSA, ECDSA, DSA)
   - Certificate chains
   - SDK version requirements for signatures

## Usage

```dart
import 'package:apk_parser/src/androlib/apk_decoder.dart';

final decoder = ApkDecoder();

// Analyze APK and get JSON output
final analysis = await decoder.analyzeApk('path/to/app.apk');
print(analysis);

// Analyze with architecture filter
final arm64Analysis = await decoder.analyzeApk(
  'path/to/app.apk',
  requiredArchitecture: 'arm64-v8a',
);

// Decode just the manifest
final manifestXml = await decoder.decodeManifestToXmlText('path/to/app.apk');
print(manifestXml);

// Full decode with resource extraction
await decoder.decode('path/to/app.apk', 'output/directory');
```

### Command Line Interface

The library includes a CLI tool for quick APK analysis:

```bash
# Basic analysis
dart run bin/apktool.dart path/to/app.apk

# Analysis with architecture filter
dart run bin/apktool.dart --arch arm64-v8a path/to/app.apk

# Export app icon
dart run bin/apktool.dart --export-icon icon.png path/to/app.apk
```

## Testing

Run tests with:
```bash
dart test
```

The test suite validates the library against real APK files and compares output with the original Java Apktool implementation. Tests cover:
- APK analysis accuracy
- Manifest decoding
- Resource resolution
- Icon extraction
- Architecture detection
- Signature parsing

## Current Status

The library successfully implements all core APK analysis features and provides reliable results for most APK files. The implementation is actively maintained and tested against a variety of real-world APK files.

## License

MIT