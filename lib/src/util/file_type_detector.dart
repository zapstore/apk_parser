/// Utility class for detecting file types using magic bytes
class FileTypeDetector {
  /// Checks if the given bytes represent a PNG file
  static bool isPng(List<int> bytes) {
    if (bytes.length < 8) return false;
    return bytes[0] == 0x89 &&
        bytes[1] == 0x50 && // P
        bytes[2] == 0x4E && // N
        bytes[3] == 0x47 && // G
        bytes[4] == 0x0D && // \r
        bytes[5] == 0x0A && // \n
        bytes[6] == 0x1A && // \x1A
        bytes[7] == 0x0A; // \n
  }

  /// Checks if the given bytes represent a JPEG file
  static bool isJpeg(List<int> bytes) {
    if (bytes.length < 3) return false;
    return bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;
  }

  /// Checks if the given bytes represent a WebP file (both lossy and lossless)
  static bool isWebP(List<int> bytes) {
    if (bytes.length < 12) return false;

    // Check RIFF header
    if (bytes[0] != 0x52 || // R
        bytes[1] != 0x49 || // I
        bytes[2] != 0x46 || // F
        bytes[3] != 0x46) {
      // F
      return false;
    }

    // Check WEBP signature
    return bytes[8] == 0x57 && // W
        bytes[9] == 0x45 && // E
        bytes[10] == 0x42 && // B
        bytes[11] == 0x50; // P
  }

  /// Checks if the given bytes represent a text XML file
  static bool isXml(List<int> bytes) {
    if (bytes.length < 5) return false;
    return bytes[0] == 0x3C && // <
        bytes[1] == 0x3F && // ?
        bytes[2] == 0x78 && // x
        bytes[3] == 0x6D && // m
        bytes[4] == 0x6C; // l
  }

  /// Detects the file type from the given bytes
  static String? detectFileType(List<int> bytes) {
    if (isPng(bytes)) return 'png';
    if (isJpeg(bytes)) return 'jpeg';
    if (isWebP(bytes)) return 'webp';
    if (isXml(bytes)) return 'xml';
    return null;
  }
}
