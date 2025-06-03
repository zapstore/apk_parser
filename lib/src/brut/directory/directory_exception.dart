library brut_directory;

class DirectoryException implements Exception {
  final String message;
  final Object? cause;

  DirectoryException(this.message, [this.cause]);

  @override
  String toString() {
    if (cause != null) {
      return 'DirectoryException: $message (Caused by: $cause)';
    }
    return 'DirectoryException: $message';
  }
}
