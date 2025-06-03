library;

import 'dart:convert'; // For Utf8Decoder, Utf16leDecoder (not directly available, use utf8, implement manual utf16le)
import 'dart:typed_data';

import 'package:apktool_dart/src/brut/common/brut_exception.dart';
import 'package:apktool_dart/src/brut/util/ext_data_input.dart';

// ARSCHeader constants will be needed
// import '../data/arsc/arsc_header.dart';
// For now, define locally or use direct values from ARSCHeader.java search results
// public static final int RES_STRING_POOL_TYPE = 0x0001;
const int _resStringPoolType = 0x0001;

// Placeholder for ResXmlEncoders.escapeXmlChars - will be needed for getHTML
// For now, getString will not escape.
String _escapeXmlChars(String s) => s; // Basic placeholder

class StringBlock {
  static const int _utf8Flag = 0x00000100;
  static const int _stringBlockHeaderSize = 28;

  late List<int> _stringOffsets;
  late Uint8List _strings;
  late bool _isUtf8;

  // Private constructor, use factory methods
  StringBlock._();

  int getCount() => _stringOffsets.length;

  static Future<StringBlock> readWithChunk(ExtDataInput dei) async {
    final startPosition = dei.position();

    final chunkType = dei.readUnsignedShort();

    if (chunkType != _resStringPoolType) {
      throw BrutException(
        'Invalid StringBlock chunk type: expected=0x${_resStringPoolType.toRadixString(16)}, got=0x${chunkType.toRadixString(16)}',
      );
    }
    final headerSize = dei.readUnsignedShort();
    final chunkSize = dei.readInt();

    return _read(dei, startPosition, headerSize, chunkSize);
  }

  static Future<StringBlock> readWithHeader(
    ExtDataInput dei,
    int startPosition,
    int headerSize,
    int chunkSize,
  ) async {
    return _read(dei, startPosition, headerSize, chunkSize);
  }

  // Corresponds to static StringBlock readWithoutChunk in Java
  static Future<StringBlock> _read(
    ExtDataInput dei,
    int startPosition,
    int headerSize,
    int chunkSize,
  ) async {
    final block = StringBlock._();

    final stringCount = dei.readInt();
    final styleCount = dei.readInt();
    final flags = dei.readInt();
    final stringsOffset = dei.readInt();
    final stylesOffset = dei
        .readInt(); // This is the offset FROM THE START OF THE CHUNK

    if (headerSize > _stringBlockHeaderSize) {
      dei.skipBytes(headerSize - _stringBlockHeaderSize);
    }

    block._isUtf8 = (flags & _utf8Flag) != 0;
    // maxAllowedPosition for offsets should be start of string data
    block._stringOffsets = dei.readSafeIntArray(
      stringCount,
      startPosition + stringsOffset,
    );

    if (styleCount != 0) {
      // This case means stylesOffset is invalid or points before strings, implies no style data despite styleCount > 0
      // This might happen with obfuscated files. Proceed as if no styles.
    }

    final bool hasStyles = stylesOffset != 0 && styleCount != 0;
    int sizeOfStringsData = chunkSize - stringsOffset;

    if (hasStyles) {
      // If stylesOffset is valid and > stringsOffset, string data ends there
      if (stylesOffset > stringsOffset) {
        sizeOfStringsData = stylesOffset - stringsOffset;
      } else {
        // This case means stylesOffset is invalid or points before strings, implies no style data despite styleCount > 0
        // This might happen with obfuscated files. Proceed as if no styles.
      }
    }

    block._strings = dei.readBytes(sizeOfStringsData);

    // Ensure we're positioned at the end of the chunk
    final endPosition = startPosition + chunkSize;
    final currentPos = dei.position();
    if (currentPos < endPosition) {
      dei.jumpTo(endPosition);
    }

    return block;
  }

  String? getString(int index) {
    if (index < 0 || _stringOffsets.isEmpty || index >= _stringOffsets.length) {
      return null;
    }
    int offset = _stringOffsets[index];

    List<int>
    valResult; // {newOffsetAfterLengthBytes, stringLengthInBytesOrChars}
    if (_isUtf8) {
      valResult = _getUtf8LengthInfo(_strings, offset);
      // valResult[0] is the offset in _strings *after* the length field(s)
      // valResult[1] is the length of the string in bytes
    } else {
      valResult = _getUtf16LengthInfo(_strings, offset);
      // valResult[0] is the offset in _strings *after* the length field(s)
      // valResult[1] is the length of the string in characters (not bytes)
    }

    final int stringStartOffset = valResult[0];
    final int stringLength = valResult[1];

    if (stringStartOffset + stringLength > _strings.length) {
      // print(
      //   '[StringBlock] Warning: String $index (offset $stringStartOffset, len $stringLength) extends outside of pool (size ${_strings.length})',
      // );
      return null;
    }

    return _decodeString(stringStartOffset, stringLength);
  }

  // Returns {offset after length field(s), string length in bytes}
  List<int> _getUtf8LengthInfo(Uint8List array, int offset) {
    // Skip UTF-16 length (2 bytes). The first byte has a flag if it's 2 bytes or 1.
    int utf16LenByte1 = array[offset];
    offset += ((utf16LenByte1 & 0x80) != 0) ? 2 : 1;

    // Read UTF-8 length (1 or 2 bytes). The first byte has a flag.
    int utf8LenByte1 = array[offset];
    offset += 1;
    int lengthInBytes;
    if ((utf8LenByte1 & 0x80) != 0) {
      int utf8LenByte2 = array[offset] & 0xFF;
      lengthInBytes = ((utf8LenByte1 & 0x7F) << 8) + utf8LenByte2;
      offset += 1;
    } else {
      lengthInBytes = utf8LenByte1;
    }
    return [offset, lengthInBytes];
  }

  // Returns {offset after length field(s), string length in characters}
  List<int> _getUtf16LengthInfo(Uint8List array, int offset) {
    int lengthInChars =
        ((array[offset + 1] & 0xFF) << 8) | (array[offset] & 0xFF);

    if ((lengthInChars & 0x8000) != 0) {
      // High bit indicates 2 more bytes for length
      int highBytes =
          ((array[offset + 3] & 0xFF) << 8) | (array[offset + 2] & 0xFF);
      lengthInChars = ((lengthInChars & 0x7FFF) << 16) + highBytes;
      return [offset + 4, lengthInChars]; // 4 bytes for length field
    }
    return [offset + 2, lengthInChars]; // 2 bytes for length field
  }

  String? _decodeString(int offset, int lengthInUnits) {
    try {
      if (_isUtf8) {
        return utf8.decode(_strings.sublist(offset, offset + lengthInUnits));
      } else {
        // UTF-16LE: lengthInUnits is number of chars, so lengthInBytes = lengthInUnits * 2
        final numBytes = lengthInUnits * 2;
        if (offset + numBytes > _strings.length) {
          // print(
          //   '[StringBlock] UTF-16 string (offset $offset, chars $lengthInUnits, bytes $numBytes) extends outside of pool (size ${_strings.length})',
          // );
          return null;
        }
        // Manual UTF-16LE decoding (dart:convert doesn't have a direct Utf16Decoder)
        List<int> codeUnits = [];
        for (int i = 0; i < numBytes; i += 2) {
          int charCode = (_strings[offset + i + 1] << 8) | _strings[offset + i];
          codeUnits.add(charCode);
        }
        return String.fromCharCodes(codeUnits);
      }
    } catch (e) {
      // print(
      //   '[StringBlock] Failed to decode string (utf8: $_isUtf8) at offset $offset, length $lengthInUnits: $e',
      // );
      // Java version tries CESU-8 on UTF-8 failure. Dart's utf8.decode is strict.
      // For now, we don't have a readily available CESU-8 decoder in Dart standard libs.
      return null;
    }
  }

  // getHTML and find methods are lower priority for initial manifest decoding.
  // They can be ported later if needed.
  String? getHtml(int index) {
    // TODO: Port getHTML if styled text is needed
    String? rawString = getString(index);
    if (rawString == null) return null;
    // Basic escaping for now, real impl needs style processing
    return _escapeXmlChars(rawString);
  }

  int find(String string) {
    // TODO: Port find if needed
    return -1;
  }
}
