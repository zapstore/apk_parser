library;

class BrutException implements Exception {
  final String message;
  final Object? cause;

  BrutException(this.message, [this.cause]);

  BrutException.empty() : this("");
  BrutException.withCause(Object cause) : this("", cause);

  @override
  String toString() {
    if (cause != null) {
      return 'BrutException: $message (Caused by: $cause)';
    }
    return 'BrutException: $message';
  }
}
