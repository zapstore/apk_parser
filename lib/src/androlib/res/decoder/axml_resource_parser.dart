library;

import 'dart:async';
import 'dart:typed_data';

import 'package:apk_parser/src/common/brut_exception.dart'; // For AndrolibException placeholder
import 'package:apk_parser/src/util/ext_data_input.dart';
import 'package:apk_parser/src/util/ext_data_input_stream.dart';
import 'package:apk_parser/src/xmlpull/xml_pull_parser.dart';
import 'package:apk_parser/src/xmlpull/xml_pull_parser_exception.dart';

import '../data/arsc/arsc_header.dart';
import '../data/axml/namespace_stack.dart';
import '../data/res_table.dart';
import 'string_block.dart';
import 'typed_value.dart';

// Placeholder for AndrolibException until its proper location/definition
class AndrolibException extends BrutException {
  AndrolibException(super.message, [super.cause]);
}

class AXmlResourceParser implements XmlPullParser {
  // Constants from Java class
  static const String _eNotSupported = "Method is not supported.";
  static const String androidResNsAuto =
      "http://schemas.android.com/apk/res-auto";
  static const String androidResNs =
      "http://schemas.android.com/apk/res/android";

  static const int _attributeIxNamespaceUri = 0;
  static const int _attributeIxName = 1;
  static const int _attributeIxValueString = 2;
  static const int _attributeIxValueType = 3;
  static const int _attributeIxValueData = 4;
  static const int _attributeLength = 5;

  // Instance members
  final ResTable? _resTable; // Nullable for now, or use placeholder
  final NamespaceStack _namespaces;

  bool _isOperational = false;
  bool _hasEncounteredStartElement = false;
  ExtDataInput? _in;
  StringBlock? _stringBlock;
  List<int>? _resourceIds;
  bool _decreaseDepth = false;
  AndrolibException? _firstError; // Store first encountered error

  // Event specific information
  int _event = -1; // Current event type, -1 initially
  int _lineNumber = -1;
  int _nameIndex = -1; // Index in string block
  int _namespaceIndex =
      -1; // Index in string block for current element's namespace URI
  List<int>?
  _attributes; // Decoded attributes for current START_TAG {ns, name, valStr, valType, valData, ...}
  int _idIndex = -1; // Attr index for R.id attributes
  int _classIndex = -1; // Attr index for 'class' attributes
  int _styleIndex = -1; // Attr index for 'style' attributes

  AXmlResourceParser([ResTable? resTable])
    : _resTable = resTable,
      _namespaces = NamespaceStack() {
    _resetEventInfo();
  }

  AndrolibException? getFirstError() => _firstError;
  void _setFirstError(AndrolibException err) {
    _firstError ??= err;
  }

  ResTable? getResTable() => _resTable;

  Future<void> open(Stream<List<int>> stream) async {
    await close(); // Close previous before opening new
    // Wrap the Dart stream with our ExtDataInputStream logic.
    // This requires ExtDataInputStream to be able to consume a Stream<List<int>>
    // or for the caller to provide a fully loaded Uint8List.
    // For now, assume ExtDataInputStream can take a Uint8List, and we read the whole stream here.
    // This is not ideal for large streams but matches AXMLParser needing full buffer for StringBlock.

    // Consume the stream into a Uint8List
    final bytesBuilder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      bytesBuilder.add(chunk);
    }
    final allBytes = bytesBuilder.toBytes();
    _in = ExtDataInputStream(
      allBytes,
      endian: Endian.little,
    ); // AXML is little-endian
    _isOperational =
        false; // Not operational until first chunk read in doNext()
  }

  Future<void> close() async {
    if (!_isOperational && _in == null) {
      // Check _in == null as well for initial state
      return;
    }
    _isOperational = false;
    _hasEncounteredStartElement = false;
    _in = null; // Allow GC
    _stringBlock = null;
    _resourceIds = null;
    _namespaces.reset();
    _resetEventInfo();
  }

  void _resetEventInfo() {
    _event = -1; // Initial state before first next()
    _lineNumber = -1;
    _nameIndex = -1;
    _namespaceIndex = -1;
    _attributes = null;
    _idIndex = -1;
    _classIndex = -1;
    _styleIndex = -1;
  }

  Future<void> _doNext() async {
    if (_stringBlock == null) {
      _in!.readInt(); // RES_XML_TYPE = 0x0003
      _in!.readInt(); // Chunk size for the RES_XML_TYPE chunk
      _stringBlock = await StringBlock.readWithChunk(_in!);
      _namespaces.increaseDepth();
      _isOperational = true;
      _event = XmlPullParser.kStartDocument; // Set initial event after setup
      // START_DOCUMENT is a conceptual event before any real tags. The first actual chunk will be processed in the loop.
      // To match XmlPullParser lifecycle, next() should advance from START_DOCUMENT to the first actual tag/event.
      // So, we set START_DOCUMENT here, and the loop below will find the *first* real event.
      return; // Return immediately, next call to _doNext will parse actual content.
    }

    if (_event == XmlPullParser.kEndDocument) {
      return;
    }

    int previousEvent = _event;
    _resetEventInfo(); // Clear previous event details, _event becomes -1

    while (true) {
      if (_decreaseDepth) {
        _decreaseDepth = false;
        _namespaces.decreaseDepth();
      }

      // Fake END_DOCUMENT event after last END_TAG and namespace pop
      if (previousEvent == XmlPullParser.kEndTag &&
          _namespaces.getDepth() == 1 &&
          _namespaces.getCurrentCount() == 0) {
        _event = XmlPullParser.kEndDocument;
        break;
      }

      // Check for end of stream if ExtDataInput had an available() method
      // Currently, _ensureAvailable() in ExtDataInputStream will throw if EOF is unexpectedly hit during a read.
      // A more graceful check might be needed if _in can report emptiness before a read attempt.
      // For now, assume reads will throw if stream ends prematurely.

      int chunkStartPosition = _in!.position();
      int chunkType;
      int
      headerSize; // Size of the ResChunk_header struct itself (usually 8 bytes)
      int chunkSize; // Total size of the chunk (header + data)

      // In Java, after START_DOCUMENT, it fakes chunkType = ARSCHeader.RES_XML_START_ELEMENT_TYPE.
      // We have already returned START_DOCUMENT. So, any subsequent call is for actual content chunks.
      try {
        chunkType = _in!.readUnsignedShort();
        headerSize = _in!.readUnsignedShort();
        chunkSize = _in!.readInt();
      } catch (e) {
        _setFirstError(
          AndrolibException("Premature end of file encountered in AXML.", e),
        );
        _event = XmlPullParser.kEndDocument;
        break;
      }

      ARSCHeader chunkHeader = ARSCHeader(
        chunkType,
        headerSize,
        chunkSize,
        chunkStartPosition,
      );

      if (chunkType == ARSCConstants.RES_XML_RESOURCE_MAP_TYPE) {
        if (chunkSize < 8 || (chunkSize % 4) != 0) {
          _setFirstError(
            AndrolibException('Invalid resource map chunk size ($chunkSize).'),
          );
          _in!.jumpTo(chunkHeader.endPosition);
          continue; // Skip malformed chunk
        }
        _resourceIds = _in!.readIntArray(
          chunkSize ~/ 4 - 2,
        ); // 2 for type and size
        continue; // Successfully read, continue to next chunk
      }

      if (chunkType < ARSCConstants.RES_XML_FIRST_CHUNK_TYPE ||
          chunkType > ARSCConstants.RES_XML_LAST_CHUNK_TYPE) {
        // print(
        //   '[AXmlResourceParser] Unknown XML chunk type 0x${chunkType.toRadixString(16)} at offset 0x${chunkStartPosition.toRadixString(16)}, size $chunkSize. Skipping.',
        // );
        _setFirstError(
          AndrolibException(
            'Unknown XML chunk type: 0x${chunkType.toRadixString(16)}',
          ),
        );
        _in!.jumpTo(chunkHeader.endPosition); // Try to skip it
        // If we skip an unknown critical chunk, we might be out of sync.
        // It might be better to terminate parsing if this happens inside the main document structure.
        // For now, we continue, hoping subsequent chunks are valid. If not, EOF or other errors will occur.
        continue;
      }

      // Common ResXMLTree_node fields (after ResChunk_header fields)
      // headerSize for these nodes is typically 16 bytes (8 for ResChunk_header, 8 for ResXMLTree_node)
      _lineNumber = _in!.readInt();
      /*final int commentIndex =*/
      _in!.readInt(); // String pool index for comment, or -1

      if (chunkType == ARSCConstants.RES_XML_START_NAMESPACE_TYPE) {
        final int prefix = _in!.readInt();
        final int uri = _in!.readInt();
        _namespaces.push(prefix, uri);
        _ensureChunkConsumed(chunkHeader); // Ensure the whole chunk is consumed
        previousEvent =
            -1; // Reset previousEvent as this is not a reportable XML event by itself
        continue; // Not an event for next(), get next chunk
      }

      if (chunkType == ARSCConstants.RES_XML_END_NAMESPACE_TYPE) {
        if (!_hasEncounteredStartElement && _namespaces.getDepth() <= 1) {
          // print(
          //   '[AXmlResourceParser] Warning: Skipping end namespace at 0x${chunkStartPosition.toRadixString(16)} before any start element.',
          // );
        } // else allow normal pop

        /*final int prefix =*/
        _in!.readInt();
        /*final int uri =*/
        _in!.readInt();
        _namespaces.pop();
        _ensureChunkConsumed(chunkHeader);
        previousEvent = -1;
        continue;
      }

      if (chunkType == ARSCConstants.RES_XML_START_ELEMENT_TYPE) {
        _hasEncounteredStartElement = true;
        _namespaceIndex = _in!.readInt();
        _nameIndex = _in!.readInt();

        /*final int attributeStartOffset =*/
        _in!.readUnsignedShort(); // Offset from start of this chunk to attribute structures
        _in!.readUnsignedShort(); // Size of each attribute structure (usually 20 bytes)
        final int attributeCount = _in!.readUnsignedShort();

        _idIndex =
            _in!.readUnsignedShort() -
            1; // Convert from 1-based to 0-based, or -1 if 0
        _classIndex = _in!.readUnsignedShort() - 1;
        _styleIndex = _in!.readUnsignedShort() - 1;

        if (attributeCount > 0) {
          _attributes = List<int>.filled(attributeCount * _attributeLength, 0);
          for (int i = 0; i < attributeCount * _attributeLength; ++i) {
            _attributes![i] = _in!.readInt();
          }
          for (
            int i = _attributeIxValueType;
            i < _attributes!.length;
            i += _attributeLength
          ) {
            _attributes![i] =
                (_attributes![i] >> 24) & 0xFF; // Isolate type byte
          }
        } else {
          _attributes = []; // Ensure it's not null
        }

        _namespaces.increaseDepth();
        _event = XmlPullParser.kStartTag;
        _ensureChunkConsumed(chunkHeader);
        break;
      }

      if (chunkType == ARSCConstants.RES_XML_END_ELEMENT_TYPE) {
        _namespaceIndex = _in!.readInt();
        _nameIndex = _in!.readInt();
        _event = XmlPullParser.kEndTag;
        _decreaseDepth = true;
        _ensureChunkConsumed(chunkHeader);
        break;
      }

      if (chunkType == ARSCConstants.RES_XML_CDATA_TYPE) {
        _nameIndex = _in!.readInt(); // String pool index for CDATA content
        /*final int typedDataValue =*/
        _in!.readInt(); // Should be TypedValue for the string type
        /*final int rawDataValue =*/
        _in!.readInt(); // Raw data, usually 0 or same as _nameIndex
        _event = XmlPullParser.kText;
        _ensureChunkConsumed(chunkHeader);
        break;
      }

      // If we reach here, it means an XML chunk type that should have been handled was not.
      // This indicates a logic error or an unhandled valid chunk.
      // print(
      //   '[AXmlResourceParser] Internal Error: Unhandled XML chunk type 0x${chunkType.toRadixString(16)} after initial checks.',
      // );
      _setFirstError(
        AndrolibException(
          'Internal AXML parsing error for chunk type: 0x${chunkType.toRadixString(16)}',
        ),
      );
      _event =
          XmlPullParser.kEndDocument; // Terminate parsing on internal error
      break;
    } // end while(true)
  }

  // Simplified _ensureChunkConsumed without declaredHeaderSize from specific chunk struct for now.
  // It relies on chunkSize from the ResChunk_header.
  void _ensureChunkConsumed(ARSCHeader chunkHeader) {
    int bytesActuallyReadForThisChunk =
        _in!.position() - chunkHeader.startPosition;
    if (bytesActuallyReadForThisChunk < chunkHeader.chunkSize) {
      final remaining = chunkHeader.chunkSize - bytesActuallyReadForThisChunk;
      if (remaining > 0) {
        // Only skip if there's something to skip
        // print(
        //   '[AXmlResourceParser] Chunk 0x${chunkHeader.type.toRadixString(16)} (size ${chunkHeader.chunkSize}) not fully consumed. Read: $bytesActuallyReadForThisChunk. Skipping $remaining bytes.',
        // );
        _in!.skipBytes(remaining);
      }
    } else if (bytesActuallyReadForThisChunk > chunkHeader.chunkSize) {
      // print(
      //   '[AXmlResourceParser] Error: Chunk 0x${chunkHeader.type.toRadixString(16)} overran. Read $bytesActuallyReadForThisChunk, chunk size ${chunkHeader.chunkSize}.',
      // );
    }
  }

  // --- XmlPullParser interface methods ---
  @override
  Future<int> next() async {
    if (_in == null) {
      throw XmlPullParserException("Parser is not opened.", parser: this);
    }
    try {
      await _doNext();
      return _event;
    } on Exception catch (e) {
      await close(); // Ensure resources are released
      if (e is XmlPullParserException) rethrow;
      throw XmlPullParserException(
        "Error during parsing: ${e.toString()}",
        parser: this,
        detail: e,
      );
    }
  }

  @override
  Future<int> nextToken() => next(); // AXML parser doesn't differentiate for most tokens like Java impl.

  @override
  Future<int> nextTag() async {
    int eventType = await next();
    if (eventType == XmlPullParser.kText && isWhitespace()) {
      eventType = await next();
    }
    if (eventType != XmlPullParser.kStartTag &&
        eventType != XmlPullParser.kEndTag) {
      throw XmlPullParserException("Expected start or end tag.", parser: this);
    }
    return eventType;
  }

  @override
  Future<String?> nextText() async {
    if (getEventType() != XmlPullParser.kStartTag) {
      throw XmlPullParserException(
        "Parser must be on START_TAG to read next text.",
        parser: this,
      );
    }
    int eventType = await next();
    if (eventType == XmlPullParser.kText) {
      String? result = getText();
      eventType = await next();
      if (eventType != XmlPullParser.kEndTag) {
        throw XmlPullParserException(
          "Event TEXT must be immediately followed by END_TAG.",
          parser: this,
        );
      }
      return result;
    } else if (eventType == XmlPullParser.kEndTag) {
      return "";
    } else {
      throw XmlPullParserException(
        "Parser must be on START_TAG or TEXT to read text.",
        parser: this,
      );
    }
  }

  @override
  Future<void> require(int type, String? namespace, String? name) async {
    final currentEvent = getEventType();
    if (type != currentEvent ||
        (namespace != null && namespace != getNamespace()) ||
        (name != null && name != getName())) {
      throw XmlPullParserException(
        "expected ${XmlPullParser.kTypes[type]} (ns=$namespace name=$name) found ${XmlPullParser.kTypes[currentEvent]} (ns=${getNamespace()} name=${getName()})",
        parser: this,
      );
    }
  }

  @override
  int getDepth() => _namespaces.getDepth() - 1; // -1 because we increase depth at string block read

  @override
  int getEventType() => _event; // Now sync

  @override
  int getLineNumber() => _lineNumber;

  @override
  String? getName() {
    if (_nameIndex == -1 ||
        (_event != XmlPullParser.kStartTag &&
            _event != XmlPullParser.kEndTag)) {
      return null;
    }
    return _stringBlock?.getString(_nameIndex);
  }

  @override
  String? getText() {
    // For START_TAG and END_TAG, text is null.
    // For TEXT (from CDATA), _nameIndex holds the string index.
    if (_nameIndex == -1 || _event != XmlPullParser.kText) {
      return null;
    }
    return _stringBlock?.getString(_nameIndex);
  }

  // getTextCharacters not implemented as per previous decision.
  // It can be added if AXmlResourceParser relies on it for specific data not available via getText().
  // The Java impl of AXmlResourceParser provides a basic version using getText().

  @override
  String? getNamespace([String? prefix]) {
    if (prefix == null) {
      return _stringBlock?.getString(_namespaceIndex);
    }
    if (_stringBlock == null) return null;
    final prefixIdx = _stringBlock!.find(prefix);
    if (prefixIdx == -1) return null;
    // In NamespaceStack, findUri expects prefix index and returns URI index.
    // My NamespaceStack._find(valueToFind, findUriForPrefix: true) where valueToFind is prefixIdx
    return _stringBlock!.getString(_namespaces.findUri(prefixIdx));
  }

  @override
  String? getPrefix() {
    if (_stringBlock == null || _namespaceIndex == -1) return null;
    final prefixStrIdx = _namespaces.findPrefix(_namespaceIndex);
    if (prefixStrIdx == -1) return null; // Prefix for default namespace is null
    return _stringBlock!.getString(prefixStrIdx);
  }

  @override
  String getPositionDescription() =>
      "XML line #$_lineNumber, event ${_event != -1 ? XmlPullParser.kTypes[_event] : 'NONE'}";

  @override
  int getNamespaceCount(int depth) => _namespaces.getAccumulatedCount(depth);

  @override
  String? getNamespacePrefix(int pos) {
    final prefixStrIdx = _namespaces.getPrefix(pos);
    if (prefixStrIdx == -1) {
      return null; // Default namespace has no prefix string
    }
    return _stringBlock?.getString(prefixStrIdx);
  }

  @override
  String getNamespaceUri(int pos) {
    final uriStrIdx = _namespaces.getUri(pos);
    return _stringBlock?.getString(uriStrIdx) ?? "";
  }

  @override
  String? getNamespaceByUri(String uri) {
    if (_stringBlock == null) return null;
    for (int d = getDepth(); d >= 0; d--) {
      final int countAtDepth =
          _namespaces.getAccumulatedCount(d) -
          (d > 0 ? _namespaces.getAccumulatedCount(d - 1) : 0);
      final int frameStart = d > 0 ? _namespaces.getAccumulatedCount(d - 1) : 0;
      for (int i = 0; i < countAtDepth; i++) {
        final currentUriIdx = _namespaces.getUri(frameStart + i);
        if (_stringBlock!.getString(currentUriIdx) == uri) {
          final prefixIdx = _namespaces.getPrefix(frameStart + i);
          if (prefixIdx == -1) return ""; // Default namespace found
          return _stringBlock!.getString(prefixIdx);
        }
      }
    }
    return null;
  }

  // getTextCharacters (similar to Java AXmlResourceParser)
  List<int>? getTextCharacters(List<int> holderForStartAndLength) {
    String? text = getText();
    if (text == null) {
      return null;
    }
    holderForStartAndLength[0] = 0;
    holderForStartAndLength[1] = text.length;
    return text.codeUnits;
  }

  // --- AttributeSet specific methods from Android ---
  String? getClassAttribute() {
    if (_classIndex == -1 || _attributes == null) {
      return null;
    }
    final offset = _getAttributeOffset(_classIndex);
    final valueStringIdx = _attributes![offset + _attributeIxValueString];
    return _stringBlock?.getString(valueStringIdx);
  }

  String? getIdAttribute() {
    if (_idIndex == -1 || _attributes == null) {
      return null;
    }
    final offset = _getAttributeOffset(_idIndex);
    final valueStringIdx = _attributes![offset + _attributeIxValueString];
    return _stringBlock?.getString(valueStringIdx);
  }

  int getIdAttributeResourceValue(int defaultValue) {
    if (_idIndex == -1 || _attributes == null) {
      return defaultValue;
    }
    final offset = _getAttributeOffset(_idIndex);
    final valueType = _attributes![offset + _attributeIxValueType];
    if (valueType != TypedValue.TYPE_REFERENCE) {
      return defaultValue;
    }
    return _attributes![offset + _attributeIxValueData];
  }

  int getStyleAttribute() {
    if (_styleIndex == -1 || _attributes == null) {
      return 0; // As per Java version, returns 0 if not found or not style
    }
    final offset = _getAttributeOffset(_styleIndex);
    // The style attribute is a resource reference, so data field holds the ID.
    return _attributes![offset + _attributeIxValueData];
  }

  // --- XmlPullParser Attribute methods ---
  @override
  int getAttributeCount() {
    if (_event != XmlPullParser.kStartTag || _attributes == null) {
      return -1;
    }
    return _attributes!.length ~/ _attributeLength;
  }

  int _getAttributeOffset(int index) {
    if (_event != XmlPullParser.kStartTag) {
      throw StateError(
        "Current event is not START_TAG for getAttributeOffset.",
      );
    }
    if (_attributes == null) throw StateError("Attributes not loaded.");
    final offset = index * _attributeLength;
    if (offset >= _attributes!.length) {
      throw RangeError(
        "Invalid attribute index ($index) for count ${getAttributeCount()}.",
      );
    }
    return offset;
  }

  @override
  String? getAttributeNamespace(int index) {
    final offset = _getAttributeOffset(index);
    final uriIdx = _attributes![offset + _attributeIxNamespaceUri];
    if (uriIdx == -1) return ""; // No namespace (empty string) is common
    return _stringBlock?.getString(uriIdx);
  }

  @override
  String? getAttributeName(int index) {
    final offset = _getAttributeOffset(index);
    final nameIdx = _attributes![offset + _attributeIxName];
    if (nameIdx == -1) return "";

    String? nameStr = _stringBlock?.getString(nameIdx);

    // Attempt to resolve from resource map if available and ResTable is configured
    final resId = getAttributeNameResourceId(index);
    if (resId != 0 && _resTable != null) {
      try {
        // Placeholder for actual ResTable lookup
        // final ResResSpec spec = _resTable.getResSpec(resId);
        // if (spec != null) { String resolvedName = spec.getName(); if (resolvedName != null && resolvedName.isNotEmpty) return resolvedName; }
      } catch (e) {
        /* ignore */
      }
    }
    return nameStr ??
        ""; // Default to empty string if resolution fails or string is null
  }

  @override
  String? getAttributePrefix(int index) {
    final offset = _getAttributeOffset(index);
    final uriIdx = _attributes![offset + _attributeIxNamespaceUri];
    if (uriIdx == -1 || _stringBlock == null) return null;
    final prefixIdx = _namespaces.findPrefix(uriIdx);
    if (prefixIdx == -1) {
      return null; // Default namespace has no prefix string (or prefix not found)
    }
    return _stringBlock!.getString(prefixIdx);
  }

  int getAttributeNameResourceId(int index) {
    final offset = _getAttributeOffset(index);
    final nameIdx = _attributes![offset + _attributeIxName];
    if (_resourceIds == null ||
        nameIdx < 0 ||
        nameIdx >= _resourceIds!.length) {
      return 0;
    }
    return _resourceIds![nameIdx];
  }

  // getAttributeValueType - not in XmlPullParser interface, but AXML has it.
  int getAttributeValueType(int index) {
    final offset = _getAttributeOffset(index);
    return _attributes![offset + _attributeIxValueType];
  }

  // getAttributeValueData - not in XmlPullParser interface.
  int getAttributeValueData(int index) {
    final offset = _getAttributeOffset(index);
    return _attributes![offset + _attributeIxValueData];
  }

  @override
  String getAttributeType(int index) => "CDATA";

  @override
  bool isAttributeDefault(int index) => false;

  @override
  String? getAttributeValue(int index) {
    final offset = _getAttributeOffset(index);
    final valueType = _attributes![offset + _attributeIxValueType];
    final valueData = _attributes![offset + _attributeIxValueData];
    final valueRawStringIdx = _attributes![offset + _attributeIxValueString];

    if (valueRawStringIdx != -1) {
      final rawStr = _stringBlock?.getString(valueRawStringIdx);
      if (rawStr != null) return rawStr;
    }

    switch (valueType) {
      case TypedValue.TYPE_NULL:
        return null;
      case TypedValue.TYPE_REFERENCE:
        return "@0x${valueData.toRadixString(16)}";
      case TypedValue.TYPE_ATTRIBUTE:
        return "?0x${valueData.toRadixString(16)}";
      case TypedValue.TYPE_STRING:
        return _stringBlock?.getString(valueData);
      case TypedValue.TYPE_FLOAT:
        final bdFloat = ByteData(4);
        bdFloat.setInt32(0, valueData, _endianForByteData);
        return bdFloat.getFloat32(0, _endianForByteData).toString();
      case TypedValue.TYPE_DIMENSION:
        return "${valueData}dim (TODO: decode complex)";
      case TypedValue.TYPE_FRACTION:
        return "${valueData}frac (TODO: decode complex)";
      case TypedValue.TYPE_INT_DEC:
        return valueData.toString();
      case TypedValue.TYPE_INT_HEX:
        return "0x${valueData.toRadixString(16)}";
      case TypedValue.TYPE_INT_BOOLEAN:
        return (valueData != 0).toString();
      case TypedValue.TYPE_INT_COLOR_ARGB8:
      case TypedValue.TYPE_INT_COLOR_RGB8:
      case TypedValue.TYPE_INT_COLOR_ARGB4:
        // case 0x1f: // TYPE_INT_COLOR_RGB4
        return "#${valueData.toRadixString(16).padLeft(valueType == TypedValue.TYPE_INT_COLOR_ARGB8 || valueType == TypedValue.TYPE_INT_COLOR_ARGB4 ? 8 : 6, '0')}";
      default:
        if (valueType >= TypedValue.TYPE_FIRST_INT &&
            valueType <= TypedValue.TYPE_LAST_INT) {
          return valueData.toString(); // Other int types
        }
        return "(unknown type 0x${valueType.toRadixString(16)} data 0x${valueData.toRadixString(16)})";
    }
  }

  Endian get _endianForByteData => Endian.little;

  @override
  String? getAttributeValueByName(String? namespace, String name) {
    if (_stringBlock == null || _attributes == null) return null;

    // Find index of attribute name
    int attrNameIdx = -1;
    for (int i = 0; i < getAttributeCount(); i++) {
      final currentNameOffset = _getAttributeOffset(i) + _attributeIxName;
      final currentNameIdx = _attributes![currentNameOffset];
      if (_stringBlock!.getString(currentNameIdx) == name) {
        // Now check namespace
        final currentNsOffset =
            _getAttributeOffset(i) + _attributeIxNamespaceUri;
        final currentNsUriIdx = _attributes![currentNsOffset];

        if (namespace == null) {
          // Match if desired namespace is null (any)
          if (currentNsUriIdx == -1) {
            // And attribute has no namespace
            attrNameIdx = i;
            break;
          }
        } else {
          final desiredNsUriIdx = _stringBlock!.find(namespace);
          if (currentNsUriIdx == desiredNsUriIdx) {
            attrNameIdx = i;
            break;
          }
        }
      }
    }
    if (attrNameIdx != -1) return getAttributeValue(attrNameIdx);
    return null;
  }

  // Typed Attribute Getters
  bool getAttributeBooleanValue(int index, bool defaultValue) {
    final valStr = getAttributeValue(index);
    if (valStr == null) return defaultValue;
    if (valStr == "true") return true;
    if (valStr == "false") return false;
    try {
      // Check if it's an integer (0 for false, non-zero for true)
      final intVal = int.parse(valStr);
      return intVal != 0;
    } catch (e) {
      /* Not a parseable int */
    }
    return defaultValue;
  }

  double getAttributeFloatValue(int index, double defaultValue) {
    final valStr = getAttributeValue(index);
    if (valStr == null) return defaultValue;
    return double.tryParse(valStr) ?? defaultValue;
  }

  int getAttributeIntValue(int index, int defaultValue) {
    final valStr = getAttributeValue(index);
    if (valStr == null) return defaultValue;
    // Handles "0x..." hex and decimal
    if (valStr.startsWith("0x") || valStr.startsWith("0X")) {
      return int.tryParse(valStr.substring(2), radix: 16) ?? defaultValue;
    }
    return int.tryParse(valStr) ?? defaultValue;
  }

  // AXML doesn't really distinguish signed/unsigned for int values in XML text, TypedValue does.
  // This will behave same as getAttributeIntValue for common cases.
  int getAttributeUnsignedIntValue(int index, int defaultValue) {
    return getAttributeIntValue(index, defaultValue);
  }

  int getAttributeResourceValue(int index, int defaultValue) {
    final offset = _getAttributeOffset(index);
    final valueType = _attributes![offset + _attributeIxValueType];
    final valueData = _attributes![offset + _attributeIxValueData];
    if (valueType == TypedValue.TYPE_REFERENCE) {
      return valueData;
    }
    return defaultValue;
  }

  int getAttributeListValue(int index, List<String> options, int defaultValue) {
    // Java AXmlResourceParser returns 0;
    return 0;
  }

  // --- Methods from XmlPullParser not applicable or not implemented in Java AXml ---
  @override
  Future<void> setFeature(String name, bool state) async =>
      throw XmlPullParserException(_eNotSupported, parser: this);
  @override
  bool getFeature(String name) {
    if (name == XmlPullParser.kFeatureProcessNamespaces) {
      return true; // AXML is namespace aware
    }
    if (name == XmlPullParser.kFeatureReportNamespaceAttributes) {
      return true; // Reports xmlns attributes
    }
    return false;
  }

  @override
  Future<void> setProperty(String name, Object value) async =>
      throw XmlPullParserException(_eNotSupported, parser: this);
  @override
  Object? getProperty(String name) => null;

  @override
  Future<void> setInput(
    Stream<List<int>> inputStream,
    String? inputEncoding,
  ) async {
    // Android AXmlResourceParser's setInput(InputStream, enc) calls open(InputStream)
    // and open() then makes ExtDataInputStream.littleEndian(stream). Encoding is not used.
    return open(inputStream);
  }

  @override
  Future<void> setInputReader(Stream<String> reader) async =>
      throw XmlPullParserException(_eNotSupported, parser: this);

  @override
  String? getInputEncoding() => null; // Binary format, string encoding is in StringBlock

  @override
  void defineEntityReplacementText(String entityName, String replacementText) =>
      throw XmlPullParserException(_eNotSupported, parser: this);

  @override
  bool isEmptyElementTag() => false; // AXML START_ELEMENT is always followed by END_ELEMENT or content.

  @override
  bool isWhitespace() {
    if (_event == XmlPullParser.kText) {
      String? txt = getText();
      if (txt == null || txt.isEmpty) return true;
      for (int i = 0; i < txt.length; i++) {
        if (txt.codeUnitAt(i) > 0x20) {
          return false;
        }
      }
      return true;
    }
    return false;
  }

  @override
  int getColumnNumber() => -1; // AXML does not provide column numbers.
}
