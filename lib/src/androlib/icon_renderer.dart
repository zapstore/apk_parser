library;

import 'dart:io';
import 'dart:math' as math;
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart' as xml;
import 'package:image/image.dart' as img;

/// Renders Android drawable resources to raster images using pure Dart
/// Handles adaptive icons, vector drawables, and legacy PNG resources
class IconRenderer {
  final String _resourceDir;
  final bool verbose;

  IconRenderer(this._resourceDir, {this.verbose = false});

  /// Get the actual icon that would be displayed on an Android device
  /// Returns the path to the generated icon file
  Future<String?> renderIcon(
    String iconReference, {
    int targetSize = 192, // Standard launcher icon size
    String density = 'xxhdpi',
  }) async {
    if (!iconReference.startsWith('@drawable/') &&
        !iconReference.startsWith('@mipmap/')) {
      return null;
    }

    final iconName = iconReference
        .replaceAll('@drawable/', '')
        .replaceAll('@mipmap/', '');

    // PRIORITY 1: Try to find existing raster icons (PNG, WebP, JPG, etc.) first
    final existingRasterPath = await _findExistingRasterIcon(iconName, density);
    if (existingRasterPath != null) {
      if (verbose) {
        print(
          '✅ Found existing raster: ${p.basename(existingRasterPath)} (${await File(existingRasterPath).length() / 1024}KB)',
        );
      }
      return await _convertAndScaleRasterIcon(
        existingRasterPath,
        iconName,
        targetSize,
        density,
      );
    }

    // PRIORITY 2: Try adaptive icon (background + foreground)
    final adaptiveIconPath = await _renderAdaptiveIcon(
      iconName,
      targetSize,
      density,
    );
    if (adaptiveIconPath != null) {
      if (verbose) print('🎨 Generated adaptive icon');
      return adaptiveIconPath;
    }

    // PRIORITY 3: Try vector drawable
    final vectorIconPath = await _renderVectorDrawable(
      iconName,
      targetSize,
      density,
    );
    if (vectorIconPath != null) {
      if (verbose) print('🖼️  Generated vector icon');
      return vectorIconPath;
    }

    if (verbose) print('❌ No suitable icon found for $iconReference');
    return null;
  }

  /// Find existing raster icon (PNG, WebP, JPG, etc.) that matches the icon reference name
  /// This ensures we get the actual referenced icon in any raster format
  Future<String?> _findExistingRasterIcon(
    String iconName,
    String density,
  ) async {
    // Priority order: higher density first for better quality
    final densityPriority = [
      'xxxhdpi', // 640dpi (4x)
      'xxhdpi', // 480dpi (3x)
      'xhdpi', // 320dpi (2x)
      'hdpi', // 240dpi (1.5x)
      'mdpi', // 160dpi (1x baseline)
      'ldpi', // 120dpi (0.75x)
    ];

    // Check both drawable and mipmap directories
    final directoryPrefixes = ['drawable', 'mipmap'];

    // Support common raster formats
    final rasterFormats = ['png', 'webp', 'jpg', 'jpeg'];

    for (final prefix in directoryPrefixes) {
      for (final densityName in densityPriority) {
        for (final format in rasterFormats) {
          final candidates = [
            '$prefix-$densityName/$iconName.$format',
            '$prefix/$iconName.$format', // No density qualifier
          ];

          for (final candidate in candidates) {
            final path = p.join(_resourceDir, candidate);
            if (await File(path).exists()) {
              // Verify this is actually a valid raster file by checking file size
              final file = File(path);
              final stat = await file.stat();
              if (stat.size > 100) {
                // Reasonable minimum for an icon
                if (verbose) {
                  print(
                    '✅ Found existing raster: $candidate (${(stat.size / 1024).toStringAsFixed(1)}KB)',
                  );
                }
                return path;
              }
            }
          }
        }
      }
    }

    if (verbose) print('📋 No existing raster image found for icon: $iconName');
    return null;
  }

  /// Find adaptive icon XML (API 26+)
  Future<String?> _findAdaptiveIcon(String iconName) async {
    final candidates = [
      'drawable-anydpi-v26/$iconName.xml',
      'drawable-anydpi/$iconName.xml',
      'drawable/$iconName.xml',
      'mipmap-anydpi-v26/$iconName.xml',
      'mipmap-anydpi/$iconName.xml',
      'mipmap/$iconName.xml',
    ];

    for (final candidate in candidates) {
      final path = p.join(_resourceDir, candidate);
      if (await File(path).exists()) {
        final content = await File(path).readAsString();
        if (content.contains('<adaptive-icon')) {
          return path;
        }
      }
    }
    return null;
  }

  /// Find vector drawable XML
  Future<String?> _findVectorDrawable(String iconName) async {
    final candidates = [
      'drawable-anydpi-v24/$iconName.xml',
      'drawable-anydpi/$iconName.xml',
      'drawable/$iconName.xml',
      'mipmap-anydpi-v24/$iconName.xml',
      'mipmap-anydpi/$iconName.xml',
      'mipmap/$iconName.xml',
    ];

    for (final candidate in candidates) {
      final path = p.join(_resourceDir, candidate);
      if (await File(path).exists()) {
        final content = await File(path).readAsString();
        if (content.contains('<vector')) {
          return path;
        }
      }
    }
    return null;
  }

  /// Render adaptive icon by compositing background + foreground using pure Dart
  Future<String?> _renderAdaptiveIcon(
    String iconName,
    int size,
    String density,
  ) async {
    final adaptiveIconPath = await _findAdaptiveIcon(iconName);
    if (adaptiveIconPath == null) {
      return null;
    }

    final content = await File(adaptiveIconPath).readAsString();
    final doc = xml.XmlDocument.parse(content);

    final backgroundRef = doc.rootElement
        .findElements('background')
        .first
        .getAttribute('android:drawable');

    final foregroundRef = doc.rootElement
        .findElements('foreground')
        .first
        .getAttribute('android:drawable');

    if (verbose) print('🎨 Rasterizing adaptive icon: $iconName');
    if (verbose) print('   Background: $backgroundRef');
    if (verbose) print('   Foreground: $foregroundRef');

    // Load background layer
    img.Image? backgroundImg;
    if (backgroundRef != null) {
      backgroundImg = await _loadDrawableAsImage(backgroundRef, size);
    }

    // Load foreground layer
    img.Image? foregroundImg;
    if (foregroundRef != null) {
      foregroundImg = await _loadDrawableAsImage(foregroundRef, size);
    }

    // Create composite image
    final composite = img.Image(width: size, height: size);
    img.fill(
      composite,
      color: img.ColorRgb8(255, 255, 255),
    ); // White background

    // Composite background layer (full size)
    if (backgroundImg != null) {
      img.compositeImage(composite, backgroundImg);
    }

    // Composite foreground layer (scaled and centered for safe zone)
    if (foregroundImg != null) {
      // Adaptive icon safe zone: foreground is 72dp within 108dp background
      // Scale foreground to 66.7% of total size (72/108)
      final foregroundSize = (size * 0.667).round();
      final scaledForeground = img.copyResize(
        foregroundImg,
        width: foregroundSize,
        height: foregroundSize,
        interpolation: img.Interpolation.cubic,
      );

      // Center the foreground
      final offsetX = (size - foregroundSize) ~/ 2;
      final offsetY = (size - foregroundSize) ~/ 2;

      img.compositeImage(
        composite,
        scaledForeground,
        dstX: offsetX,
        dstY: offsetY,
      );
    }

    // Save as PNG first, then try to convert to WEBP
    final pngPath = p.join(
      Directory.systemTemp.path,
      '${iconName}_adaptive_${size}px.png',
    );

    final pngBytes = img.encodePng(composite);
    await File(pngPath).writeAsBytes(pngBytes);

    // Try to convert to WEBP, fall back to PNG if ffmpeg not available
    final finalPath = await _convertToWebpOrFallback(
      pngPath,
      '${iconName}_adaptive',
      size,
    );

    if (verbose) {
      print(
        '   ✅ Adaptive icon rasterized and saved: ${p.basename(finalPath)} (square format)',
      );
    }
    return finalPath;
  }

  /// Load a drawable reference as an image
  Future<img.Image?> _loadDrawableAsImage(
    String drawableRef,
    int targetSize,
  ) async {
    if (!drawableRef.startsWith('@drawable/')) {
      return null;
    }

    final drawableName = drawableRef.substring('@drawable/'.length);

    // Try to load as raster first (PNG, WebP, JPG, etc.)
    final rasterPath = await _findExistingRasterIcon(drawableName, 'xxhdpi');
    if (rasterPath != null) {
      final bytes = await File(rasterPath).readAsBytes();
      final image = img.decodeImage(bytes);
      if (image != null) {
        return img.copyResize(image, width: targetSize, height: targetSize);
      }
    }

    // Try to load as vector
    final vectorPath = await _findVectorDrawable(drawableName);
    if (vectorPath != null) {
      return await _renderVectorToImage(vectorPath, targetSize);
    }

    return null;
  }

  /// Render vector drawable to raster using pure Dart
  Future<String?> _renderVectorDrawable(
    String iconName,
    int size,
    String density,
  ) async {
    final vectorPath = await _findVectorDrawable(iconName);
    if (vectorPath == null) {
      return null;
    }

    final content = await File(vectorPath).readAsString();
    final doc = xml.XmlDocument.parse(content);

    if (verbose) print('🎨 Rasterizing vector drawable: $iconName');

    // Create image canvas
    final image = img.Image(width: size, height: size);
    img.fill(
      image,
      color: img.ColorRgba8(0, 0, 0, 0),
    ); // Transparent background

    // Parse vector attributes
    final vectorElement = doc.rootElement;
    final viewportWidth =
        double.tryParse(
          vectorElement.getAttribute('android:viewportWidth') ?? '24',
        ) ??
        24.0;
    final viewportHeight =
        double.tryParse(
          vectorElement.getAttribute('android:viewportHeight') ?? '24',
        ) ??
        24.0;

    // Calculate scaling factor
    final scaleX = size / viewportWidth;
    final scaleY = size / viewportHeight;

    if (verbose) {
      print('   Viewport: ${viewportWidth}x$viewportHeight');
      print(
        '   Scale: ${scaleX.toStringAsFixed(2)}x${scaleY.toStringAsFixed(2)}',
      );
    }

    // Parse and render paths
    var pathCount = 0;
    for (final pathElement in vectorElement.findAllElements('path')) {
      final pathData = pathElement.getAttribute('android:pathData');
      final fillColor =
          pathElement.getAttribute('android:fillColor') ?? '#000000';

      if (pathData != null) {
        pathCount++;
        if (verbose) print('   Path $pathCount: $fillColor');

        // Parse color
        final color = _parseColor(fillColor);
        if (color == null) continue;

        // Extract coordinates from path data (simplified)
        final coords = _extractCoordinates(pathData);

        // Render based on path type (simplified rendering)
        if (coords.length >= 4) {
          // Simple rectangle/shape rendering
          final x1 = (coords[0] * scaleX).round().clamp(0, size - 1);
          final y1 = (coords[1] * scaleY).round().clamp(0, size - 1);
          final x2 = (coords[2] * scaleX).round().clamp(0, size - 1);
          final y2 = (coords[3] * scaleY).round().clamp(0, size - 1);

          // Draw filled rectangle as approximation
          img.fillRect(image, x1: x1, y1: y1, x2: x2, y2: y2, color: color);
        } else if (coords.length >= 6) {
          // Draw circle if we have center + radius-like coordinates
          final centerX = (coords[0] * scaleX).round().clamp(0, size - 1);
          final centerY = (coords[1] * scaleY).round().clamp(0, size - 1);
          final radius = ((coords[2] * scaleX + coords[3] * scaleY) / 2)
              .round();

          img.fillCircle(
            image,
            x: centerX,
            y: centerY,
            radius: radius,
            color: color,
          );
        }
      }
    }

    // Save as PNG first, then try to convert to WEBP
    final pngPath = p.join(
      Directory.systemTemp.path,
      '${iconName}_vector_${size}px.png',
    );
    final pngBytes = img.encodePng(image);
    await File(pngPath).writeAsBytes(pngBytes);

    // Try to convert to WEBP, fall back to PNG if ffmpeg not available
    final finalPath = await _convertToWebpOrFallback(
      pngPath,
      '${iconName}_vector',
      size,
    );

    if (verbose) {
      print('   ✅ Vector drawable rasterized: ${p.basename(finalPath)}');
    }
    return finalPath;
  }

  /// Parse Android color string to image Color
  img.Color? _parseColor(String colorStr) {
    if (!colorStr.startsWith('#')) return null;

    try {
      final hexStr = colorStr.substring(1);
      if (hexStr.length == 6) {
        // RGB format
        final r = int.parse(hexStr.substring(0, 2), radix: 16);
        final g = int.parse(hexStr.substring(2, 4), radix: 16);
        final b = int.parse(hexStr.substring(4, 6), radix: 16);
        return img.ColorRgb8(r, g, b);
      } else if (hexStr.length == 8) {
        // ARGB format
        final a = int.parse(hexStr.substring(0, 2), radix: 16);
        final r = int.parse(hexStr.substring(2, 4), radix: 16);
        final g = int.parse(hexStr.substring(4, 6), radix: 16);
        final b = int.parse(hexStr.substring(6, 8), radix: 16);
        return img.ColorRgba8(r, g, b, a);
      }
    } catch (e) {
      // Ignore parse errors
    }

    return img.ColorRgb8(0, 0, 0); // Default to black
  }

  /// Simplified path rendering (handles basic shapes common in icons)
  void _renderSimplePath(
    img.Image image,
    String pathData,
    img.Color color,
    double viewportWidth,
    double viewportHeight,
    int imageSize,
  ) {
    // This is a simplified implementation that handles basic geometric shapes
    // A full implementation would need a complete SVG path parser

    final scaleX = imageSize / viewportWidth;
    final scaleY = imageSize / viewportHeight;

    // Handle simple circle commands (common in icons)
    if (pathData.contains('C') && pathData.contains('Z')) {
      // Likely a circle or rounded shape - draw a circle for simplicity
      final centerX = imageSize ~/ 2;
      final centerY = imageSize ~/ 2;
      final radius = math.min(imageSize ~/ 4, imageSize ~/ 4);

      img.fillCircle(
        image,
        x: centerX,
        y: centerY,
        radius: radius,
        color: color,
      );
      return;
    }

    // Handle rectangle commands
    if (pathData.startsWith('M') &&
        pathData.contains('L') &&
        pathData.endsWith('Z')) {
      // Simple rectangle - parse coordinates
      final coords = _extractCoordinates(pathData);
      if (coords.length >= 4) {
        final x1 = (coords[0] * scaleX).round();
        final y1 = (coords[1] * scaleY).round();
        final x2 = (coords[2] * scaleX).round();
        final y2 = (coords[3] * scaleY).round();

        img.fillRect(
          image,
          x1: math.min(x1, x2),
          y1: math.min(y1, y2),
          x2: math.max(x1, x2),
          y2: math.max(y1, y2),
          color: color,
        );
        return;
      }
    }

    // Fallback: fill a portion of the image with the color
    final fillSize = imageSize ~/ 2;
    final offsetX = (imageSize - fillSize) ~/ 2;
    final offsetY = (imageSize - fillSize) ~/ 2;

    img.fillRect(
      image,
      x1: offsetX,
      y1: offsetY,
      x2: offsetX + fillSize,
      y2: offsetY + fillSize,
      color: color,
    );
  }

  /// Extract basic coordinates from path data
  List<double> _extractCoordinates(String pathData) {
    final coords = <double>[];
    final regex = RegExp(r'[-+]?[0-9]*\.?[0-9]+');
    final matches = regex.allMatches(pathData);

    for (final match in matches) {
      final value = double.tryParse(match.group(0) ?? '');
      if (value != null) {
        coords.add(value);
      }
    }

    return coords;
  }

  /// Convert and scale existing raster icon (PNG/WebP/JPG) to PNG using pure Dart
  Future<String> _convertAndScaleRasterIcon(
    String rasterPath,
    String iconName,
    int targetSize,
    String density,
  ) async {
    final file = File(rasterPath);
    final bytes = await file.readAsBytes();
    final extension = p.extension(rasterPath).toLowerCase();

    if (verbose) {
      print('🎯 Using existing raster icon: $iconName');
      print(
        '   Source: ${p.basename(rasterPath)} ($extension, ${bytes.length} bytes)',
      );
    }

    // Decode the image (supports PNG, WebP, JPG, etc.)
    img.Image? originalImage;

    switch (extension) {
      case '.png':
        originalImage = img.decodePng(bytes);
        break;
      case '.webp':
        originalImage = img.decodeWebP(bytes);
        break;
      case '.jpg':
      case '.jpeg':
        originalImage = img.decodeJpg(bytes);
        break;
      default:
        // Try automatic detection
        originalImage = img.decodeImage(bytes);
    }

    if (originalImage == null) {
      throw Exception('Failed to decode raster image: $rasterPath');
    }

    if (verbose) {
      print(
        '   Original size: ${originalImage.width}x${originalImage.height}px',
      );
      print('   Target size: ${targetSize}px');
    }

    // Always convert to PNG format for consistency
    img.Image finalImage;

    // Only resize if necessary
    if (originalImage.width == targetSize &&
        originalImage.height == targetSize) {
      if (verbose) {
        print('   ✅ Perfect size match - converting format only');
      }
      finalImage = originalImage;
    } else {
      // Resize using high-quality interpolation
      if (verbose) {
        print('   🔄 Converting and scaling to target size...');
      }
      finalImage = img.copyResize(
        originalImage,
        width: targetSize,
        height: targetSize,
        interpolation: img.Interpolation.cubic,
      );
    }

    final pngPath = p.join(
      Directory.systemTemp.path,
      '${iconName}_${targetSize}px.png',
    );

    final pngBytes = img.encodePng(finalImage);
    await File(pngPath).writeAsBytes(pngBytes);

    // Try to convert to WEBP, fall back to PNG if ffmpeg not available
    final finalPath = await _convertToWebpOrFallback(
      pngPath,
      iconName,
      targetSize,
    );

    if (verbose) {
      print('   ✅ Raster icon converted and saved: ${p.basename(finalPath)}');
    }
    return finalPath;
  }

  /// Render vector XML to image
  Future<img.Image?> _renderVectorToImage(String xmlPath, int size) async {
    final content = await File(xmlPath).readAsString();
    final doc = xml.XmlDocument.parse(content);

    final vectorElement = doc.findAllElements('vector').first;
    final viewportWidth =
        double.tryParse(
          vectorElement.getAttribute('android:viewportWidth') ?? '24',
        ) ??
        24.0;
    final viewportHeight =
        double.tryParse(
          vectorElement.getAttribute('android:viewportHeight') ?? '24',
        ) ??
        24.0;

    if (verbose) {
      print('🎨 Rasterizing vector drawable to ${size}x${size}px');
      print('   Viewport: ${viewportWidth}x$viewportHeight');
    }

    // Create image
    final image = img.Image(width: size, height: size);
    img.fill(
      image,
      color: img.ColorRgba8(0, 0, 0, 0),
    ); // Transparent background

    // Extract and render paths
    final paths = doc.findAllElements('path');
    if (verbose) {
      print('   Rendering ${paths.length} vector paths');
    }

    for (final pathElement in paths) {
      final fillColorStr = pathElement.getAttribute('android:fillColor');
      final pathData = pathElement.getAttribute('android:pathData');

      if (fillColorStr != null && pathData != null) {
        final color = _parseColor(fillColorStr);
        if (color != null) {
          _renderSimplePath(
            image,
            pathData,
            color,
            viewportWidth,
            viewportHeight,
            size,
          );
        }
      }
    }

    return image;
  }

  /// Get icon information without rendering
  Future<IconInfo> getIconInfo(String iconReference) async {
    if (!iconReference.startsWith('@drawable/') &&
        !iconReference.startsWith('@mipmap/')) {
      return IconInfo(iconReference, IconType.unknown, null);
    }

    final iconName = iconReference
        .replaceAll('@drawable/', '')
        .replaceAll('@mipmap/', '');

    final adaptiveIconPath = await _findAdaptiveIcon(iconName);
    if (adaptiveIconPath != null) {
      return IconInfo(iconName, IconType.adaptive, adaptiveIconPath);
    }

    final vectorIconPath = await _findVectorDrawable(iconName);
    if (vectorIconPath != null) {
      return IconInfo(iconName, IconType.vector, vectorIconPath);
    }

    final rasterIconPath = await _findExistingRasterIcon(iconName, 'xxhdpi');
    if (rasterIconPath != null) {
      return IconInfo(iconName, IconType.raster, rasterIconPath);
    }

    return IconInfo(iconName, IconType.notFound, null);
  }

  /// Try to convert PNG to WEBP using ffmpeg, fall back to PNG if not available
  Future<String> _convertToWebpOrFallback(
    String pngPath,
    String iconName,
    int size,
  ) async {
    try {
      final webpPath = p.join(
        Directory.systemTemp.path,
        '${iconName}_${size}px.webp',
      );

      // Try to convert PNG to WEBP using ffmpeg
      final result = await Process.run('ffmpeg', [
        '-i', pngPath,
        '-y', // Overwrite output file
        '-q:v', '90', // Quality setting (0-100, higher is better)
        webpPath,
      ], runInShell: true);

      if (result.exitCode == 0 && await File(webpPath).exists()) {
        // WEBP conversion successful
        final webpSize = await File(webpPath).length();
        final pngSize = await File(pngPath).length();

        if (verbose) {
          print(
            '   ✅ Converted to WEBP: ${p.basename(webpPath)} (${(webpSize / 1024).toStringAsFixed(1)}KB vs ${(pngSize / 1024).toStringAsFixed(1)}KB PNG)',
          );
        }

        // Clean up temporary PNG file
        try {
          await File(pngPath).delete();
        } catch (e) {
          // Ignore cleanup errors
        }

        return webpPath;
      } else {
        if (verbose) print('   ⚠️  WEBP conversion failed, using PNG');
        return pngPath;
      }
    } catch (e) {
      if (verbose) print('   ⚠️  ffmpeg not available, using PNG format');
      return pngPath;
    }
  }
}

enum IconType { adaptive, vector, raster, unknown, notFound }

class IconInfo {
  final String name;
  final IconType type;
  final String? sourcePath;

  IconInfo(this.name, this.type, this.sourcePath);

  @override
  String toString() {
    switch (type) {
      case IconType.adaptive:
        return '📱 Adaptive Icon: $name (modern layered icon)';
      case IconType.vector:
        return '🎨 Vector Drawable: $name (scalable vector graphics)';
      case IconType.raster:
        return '🖼️  Raster Icon: $name (PNG bitmap)';
      case IconType.unknown:
        return '❓ Unknown: $name';
      case IconType.notFound:
        return '❌ Not Found: $name';
    }
  }
}
