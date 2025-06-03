library brut_xmlpull;

import 'dart:async';
import 'dart:typed_data';
import '../directory/directory.dart'
    show AbstractInputStream; // For setInput with InputStream
import 'xml_pull_parser_exception.dart';

// Ported from org.xmlpull.v1.XmlPullParser
abstract class XmlPullParser {
  static const String NO_NAMESPACE = "";

  // Event Types
  static const int START_DOCUMENT = 0;
  static const int END_DOCUMENT = 1;
  static const int START_TAG = 2;
  static const int END_TAG = 3;
  static const int TEXT = 4;
  // Additional events from nextToken()
  static const int CDSECT = 5;
  static const int ENTITY_REF = 6;
  static const int IGNORABLE_WHITESPACE = 7;
  static const int PROCESSING_INSTRUCTION = 8;
  static const int COMMENT = 9;
  static const int DOCDECL = 10;

  static const List<String> TYPES = [
    "START_DOCUMENT",
    "END_DOCUMENT",
    "START_TAG",
    "END_TAG",
    "TEXT",
    "CDSECT",
    "ENTITY_REF",
    "IGNORABLE_WHITESPACE",
    "PROCESSING_INSTRUCTION",
    "COMMENT",
    "DOCDECL",
  ];

  // Features - String constants
  static const String FEATURE_PROCESS_NAMESPACES =
      "http://xmlpull.org/v1/doc/features.html#process-namespaces";
  static const String FEATURE_REPORT_NAMESPACE_ATTRIBUTES =
      "http://xmlpull.org/v1/doc/features.html#report-namespace-prefixes";
  static const String FEATURE_PROCESS_DOCDECL =
      "http://xmlpull.org/v1/doc/features.html#process-docdecl";
  static const String FEATURE_VALIDATION =
      "http://xmlpull.org/v1/doc/features.html#validation";

  // Methods
  Future<void> setFeature(String name, bool state);
  bool getFeature(String name);

  Future<void> setProperty(String name, Object value);
  Object? getProperty(String name);

  // Using Stream<String> as a Dart equivalent for java.io.Reader
  // Using AbstractInputStream (which wraps Stream<List<int>>) for java.io.InputStream
  Future<void> setInput(Stream<List<int>> inputStream, String? inputEncoding);
  Future<void> setInputReader(
    Stream<String> reader,
  ); // Renamed to avoid conflict, Java uses overloading

  String? getInputEncoding();

  void defineEntityReplacementText(String entityName, String replacementText);

  int getNamespaceCount(int depth);
  String? getNamespacePrefix(int pos);
  String getNamespaceUri(int pos);
  String? getNamespace([String? prefix]);

  int getDepth();
  String getPositionDescription();
  int getLineNumber();
  int getColumnNumber();

  bool isWhitespace();
  String? getText();
  // getTextCharacters: Java returns char[], int[] holder. Dart might use a custom class or a record.
  // For now, let's define a helper class or return String and let implementer handle char array if needed.
  // String getTextCharacters(List<int> holderForStartAndLength); // holderForStartAndLength: [start, length]
  // Simpler: AXmlResourceParser specific implementation details will dictate this.
  // For now, just rely on getText(). AXmlResourceParser doesn't use getTextCharacters heavily for its core logic.

  String? getNamespaceByUri(
    String uri,
  ); // Added helper, not in original XmlPullParser but useful
  String? getName();
  String? getPrefix();

  bool isEmptyElementTag();

  int getAttributeCount();
  String? getAttributeNamespace(int index);
  String? getAttributeName(int index);
  String? getAttributePrefix(int index);
  String getAttributeType(int index); // Typically "CDATA"
  bool isAttributeDefault(int index);
  String? getAttributeValue(int index);
  String? getAttributeValueByName(
    String? namespace,
    String name,
  ); // Renamed from getAttributeValue(String, String)

  int getEventType();

  Future<int> next();
  Future<int> nextToken();
  Future<int> nextTag(); // Added from KXmlParser, useful

  Future<void> require(int type, String? namespace, String? name);
  Future<String?> nextText(); // Now async
}
