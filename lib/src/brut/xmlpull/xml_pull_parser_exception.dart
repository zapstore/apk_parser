library;

import 'xml_pull_parser.dart'; // For XmlPullParser type

// Ported from org.xmlpull.v1.XmlPullParserException
class XmlPullParserException implements Exception {
  final String? message;
  final XmlPullParser? parser; // Added parser reference, like Java
  final Object?
  detail; // In Java, this is Throwable, here using Object? for broader compatibility
  final int lineNumber;
  final int columnNumber;

  XmlPullParserException(
    this.message, {
    this.parser,
    this.detail,
    this.lineNumber = -1, // Default from parser if available, else -1
    this.columnNumber = -1, // Default from parser if available, else -1
  });

  // The printStackTrace() methods from Java are not directly portable.
  // Dart's Exception has a stackTrace property if the exception was caught.

  @override
  String toString() {
    StringBuffer sb = StringBuffer();
    if (message != null) {
      sb.write(message);
    }
    // Try to get position from parser if not explicitly set and parser is available
    final ln = lineNumber != -1 ? lineNumber : parser?.getLineNumber() ?? -1;
    final cn = columnNumber != -1
        ? columnNumber
        : parser?.getColumnNumber() ?? -1;

    sb.write(' (position: line ');
    sb.write(ln);
    sb.write(' column ');
    sb.write(cn);
    sb.write(')');
    if (detail != null) {
      sb.write('; caused by: ');
      sb.write(detail.toString());
    }
    return sb.toString();
  }
}
