library apktool_dart;

// Export main decoder class
export 'src/brut/androlib/apk_decoder.dart' show ApkDecoder;

// Export exceptions that users might need to handle
export 'src/brut/common/brut_exception.dart' show BrutException;
export 'src/brut/directory/directory_exception.dart' show DirectoryException;

// TODO: Export more classes as they become stable and part of the public API

/// Decodes the given APK file into the output directory.
///
/// This is a placeholder and will be implemented by porting ApkDecoder.java
Future<void> decodeApk(String apkPath, String outputDirPath) async {
  // Implementation to come
  print('Decoding \$apkPath to \$outputDirPath (not implemented yet)');
}
