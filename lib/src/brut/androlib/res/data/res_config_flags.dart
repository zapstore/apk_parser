library brut_androlib_res_data;

// Simplified version - full implementation would include all configuration dimensions
class ResConfigFlags {
  // Basic fields for now
  final int mcc;
  final int mnc;
  final String? language;
  final String? region;
  final int orientation;
  final int touchscreen;
  final int density;
  final int keyboard;
  final int navigation;
  final int inputFlags;
  final int screenWidth;
  final int screenHeight;
  final int sdkVersion;
  final int minorVersion;

  // Add more fields as needed for full implementation

  ResConfigFlags({
    this.mcc = 0,
    this.mnc = 0,
    this.language,
    this.region,
    this.orientation = 0,
    this.touchscreen = 0,
    this.density = 0,
    this.keyboard = 0,
    this.navigation = 0,
    this.inputFlags = 0,
    this.screenWidth = 0,
    this.screenHeight = 0,
    this.sdkVersion = 0,
    this.minorVersion = 0,
  });

  factory ResConfigFlags.createDefault() {
    return ResConfigFlags();
  }

  String getQualifiers() {
    // Build configuration qualifier string using StringBuilder approach like Java
    final sb = StringBuffer();

    if (mcc != 0) {
      sb.write('-mcc$mcc');
    }
    if (mnc != 0) {
      sb.write('-mnc$mnc');
    }
    if (language != null && language!.isNotEmpty) {
      sb.write('-$language');
      if (region != null && region!.isNotEmpty) {
        sb.write('-r$region');
      }
    }
    if (orientation == 2) {
      sb.write('-land');
    } else if (orientation == 1) {
      sb.write('-port');
    }

    if (density == 120) {
      sb.write('-ldpi');
    } else if (density == 160) {
      sb.write('-mdpi');
    } else if (density == 213) {
      sb.write('-tvdpi');
    } else if (density == 240) {
      sb.write('-hdpi');
    } else if (density == 320) {
      sb.write('-xhdpi');
    } else if (density == 480) {
      sb.write('-xxhdpi');
    } else if (density == 640) {
      sb.write('-xxxhdpi');
    }

    if (screenWidth > 0 && screenHeight > 0) {
      sb.write('-${screenWidth}x$screenHeight');
    }

    if (sdkVersion > 0) {
      sb.write('-v$sdkVersion');
    }

    return sb.toString();
  }

  @override
  String toString() {
    final qualifiers = getQualifiers();
    return qualifiers.isNotEmpty ? qualifiers : '[DEFAULT]';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResConfigFlags &&
          runtimeType == other.runtimeType &&
          mcc == other.mcc &&
          mnc == other.mnc &&
          language == other.language &&
          region == other.region &&
          orientation == other.orientation &&
          density == other.density &&
          screenWidth == other.screenWidth &&
          screenHeight == other.screenHeight &&
          sdkVersion == other.sdkVersion;

  @override
  int get hashCode =>
      mcc.hashCode ^
      mnc.hashCode ^
      language.hashCode ^
      region.hashCode ^
      orientation.hashCode ^
      density.hashCode ^
      screenWidth.hashCode ^
      screenHeight.hashCode ^
      sdkVersion.hashCode;
}
