# ApkTool Dart

A Dart library for decoding Android APK files, providing functionality similar to the Java [Apktool](https://github.com/iBotPeaches/Apktool) project. This implementation focuses on parsing Android binary XML (AXML) format and extracting resources from APK files.

## Features

- **AndroidManifest.xml Decoding**: Converts binary XML format to readable XML text
- **Resource Resolution**: Resolves resource references (e.g., `@string/app_name`) to human-readable format
- **Resource Extraction**: Extracts resources (images, XML files) from APK files
- **ARSC Parser**: Parses Android resource table (`resources.arsc`) files
- **Cross-platform**: Pure Dart implementation that works on all platforms

## What it does

This library takes Android APK files as input and decodes their contents, specifically:

1. **Manifest Decoding**: Reads the binary `AndroidManifest.xml` file and converts it to readable XML format
2. **Resource Resolution**: Resolves numeric resource IDs (like `@0x7f020001`) to human-readable names (like `@drawable/icon`)
3. **Resource Extraction**: Extracts and decodes resources like images, layouts, and other XML files from the APK
4. **Icon Resolution**: Specifically resolves application icons from resource references

## Current Status

The library successfully decodes AndroidManifest.xml files and resolves resource references for most APK files. Resource extraction is partially implemented but may not handle all resource types perfectly yet.

## Usage

```dart
import 'package:apk_parser/src/brut/androlib/apk_decoder.dart';

final decoder = ApkDecoder();

// Decode just the manifest
final manifestXml = await decoder.decodeManifestToXmlText('path/to/app.apk');
print(manifestXml);

// Full decode with resource extraction
await decoder.decode('path/to/app.apk', 'output/directory');
```

## Testing

Run tests with:
```bash
dart test
```

The test suite validates the library against real APK files and compares output with the original Java Apktool implementation.
