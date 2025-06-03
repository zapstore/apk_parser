library brut_directory;

class ApktoolIOException implements Exception {
  final String message;

  ApktoolIOException(this.message);

  @override
  String toString() => 'ApktoolIOException: $message';
}
