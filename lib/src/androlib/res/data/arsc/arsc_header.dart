library;

// Chunk types from ARSCHeader.java
class ARSCConstants {
  ARSCConstants._(); // no instances

  // ignore_for_file: constant_identifier_names

  static const int RES_NONE_TYPE = -1;
  static const int RES_NULL_TYPE = 0x0000;
  static const int RES_STRING_POOL_TYPE = 0x0001;
  static const int RES_TABLE_TYPE = 0x0002;
  static const int RES_XML_TYPE =
      0x0003; // Main XML chunk type, not a specific sub-chunk

  // RES_XML_TYPE sub-chunks (binary XML structure)
  static const int RES_XML_FIRST_CHUNK_TYPE = 0x0100;
  static const int RES_XML_START_NAMESPACE_TYPE = 0x0100;
  static const int RES_XML_END_NAMESPACE_TYPE = 0x0101;
  static const int RES_XML_START_ELEMENT_TYPE = 0x0102;
  static const int RES_XML_END_ELEMENT_TYPE = 0x0103;
  static const int RES_XML_CDATA_TYPE = 0x0104;
  static const int RES_XML_LAST_CHUNK_TYPE =
      0x017F; // Not a real chunk, but a range limit

  static const int RES_XML_RESOURCE_MAP_TYPE = 0x0180;

  // RES_TABLE_TYPE chunks types (for resources.arsc)
  static const int RES_TABLE_PACKAGE_TYPE = 0x0200;
  static const int RES_TABLE_TYPE_TYPE = 0x0201;
  static const int RES_TABLE_TYPE_SPEC_TYPE = 0x0202;
  static const int RES_TABLE_LIBRARY_TYPE = 0x0203;
  static const int RES_TABLE_OVERLAYABLE_TYPE = 0x0204;
  static const int RES_TABLE_OVERLAYABLE_POLICY_TYPE = 0x0205;
  static const int RES_TABLE_STAGED_ALIAS_TYPE = 0x0206;
  // ... other TABLE types not immediately needed for AXML parsing
}

// Now using the standard name ARSCHeader for the actual header data
class ARSCHeader {
  final int type;
  final int headerSize; // Size of this header struct
  final int chunkSize; // Total size of this chunk including header and data
  final int startPosition; // Position in stream where this header started
  late final int endPosition; // Position in stream where this chunk ends

  ARSCHeader(this.type, this.headerSize, this.chunkSize, this.startPosition) {
    endPosition = startPosition + chunkSize;
  }
}
