library;

// Export main decoder class
export 'src/androlib/apk_decoder.dart' show ApkDecoder;

// Export exceptions that users might need to handle
export 'src/common/brut_exception.dart' show BrutException;
export 'src/directory/directory_exception.dart' show DirectoryException;

/// Decodes the given APK file into the output directory.
///
/// This is a placeholder and will be implemented by porting ApkDecoder.java
Future<void> decodeApk(String apkPath, String outputDirPath) async {
  // Implementation to come
  print('Decoding \$apkPath to \$outputDirPath (not implemented yet)');
}
