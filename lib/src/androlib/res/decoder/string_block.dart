library;

import 'dart:convert'; // For Utf8Decoder, Utf16leDecoder (not directly available, use utf8, implement manual utf16le)
import 'dart:typed_data';

import 'package:apk_parser/src/common/brut_exception.dart';
import 'package:apk_parser/src/util/ext_data_input.dart';

const int _resStringPoolType = 0x0001;

class StringBlock {
  static const int _utf8Flag = 0x00000100;

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
    int
    startPosition, // Absolute start of the ResStringPool chunk in the file/buffer
    int
    headerSize, // Size of the ResStringPool_header (ResChunk_header part + uint32 fields + padding)
    // This is ResStringPool_header.header.headerSize
    int
    chunkSize, // Total size of the ResStringPool chunk (ResStringPool_header.header.chunkSize)
  ) async {
    final block = StringBlock._();

    // dei is currently positioned at the start of the ResStringPool_header's specific fields
    // (i.e., after the ResChunk_header type, headerSize, chunkSize for this StringPool chunk).
    // It's at startPosition + sizeof(ResChunk_header itself, e.g. 8 bytes).

    final stringCount = dei.readInt();
    final styleCount = dei.readInt();
    final flags = dei.readInt();
    final stringsStart = dei
        .readInt(); // Offset from start of chunk to string data
    final stylesStart = dei
        .readInt(); // Offset from start of chunk to style data

    // The 'headerSize' argument is ResStringPool_header.header.headerSize.
    // It defines the total size of the ResStringPool_header structure (which includes its own ResChunk_header part).
    // We've already read 5 ints (20 bytes). The ResChunk_header part is 8 bytes. Total 28.
    // If headerSize > 28, there's extra data in the header we need to skip.
    // Current position after reading 5 ints: (startPosition + 8) + 20 = startPosition + 28.
    // We need to skip up to (startPosition + headerSize).
    final alreadyReadFromHeaderSpecificFields = 20; // 5 ints
    final resChunkHeaderSelfSize = 8; // Standard size of ResChunk_header struct
    final minExpectedHeaderSize =
        resChunkHeaderSelfSize + alreadyReadFromHeaderSpecificFields;

    if (headerSize > minExpectedHeaderSize) {
      dei.skipBytes(headerSize - minExpectedHeaderSize);
    }
    // dei is now at startPosition + headerSize. This is where the string offsets array begins.

    block._isUtf8 = (flags & _utf8Flag) != 0;
    block._stringOffsets = dei.readIntArray(
      stringCount,
    ); // Reads stringCount * 4 bytes. dei advances.

    if (styleCount > 0) {
      // StringBlock in Java reads mStyleOffsets here. We need to at least skip these bytes
      // to correctly position for string data if string data comes after style offsets array.
      // However, string data starts at (startPosition + stringsStart).
      // The style offsets array would be between string offsets array and string data
      // IF stringsStart accounts for it. This is typical.
      dei.skipBytes(
        styleCount * 4,
      ); // Skip over the style_offsets_array. dei advances.
    }

    // Now, position 'dei' to the absolute start of the string data.
    // stringsStart is an offset from the beginning of the chunk (startPosition).
    dei.jumpTo(startPosition + stringsStart);

    int stringDataLength;
    if (styleCount > 0 && stylesStart > 0) {
      // If styles are present, string data runs from stringsStart to stylesStart.
      // Both are absolute offsets from chunk start (startPosition).
      stringDataLength = stylesStart - stringsStart;
    } else {
      // No styles, or stylesStart is 0. String data runs from stringsStart to chunk end.
      // chunkSize is total size of chunk. stringsStart is offset from chunk start.
      stringDataLength = chunkSize - stringsStart;
    }

    if (stringDataLength < 0) {
      // This case should ideally not happen if offsets are correct.
      // print('[StringBlock] Warning: Calculated negative string data length ($stringDataLength). Setting to 0.');
      stringDataLength = 0;
    }

    block._strings = dei.readBytes(stringDataLength);

    // Ensure 'dei' is positioned at the end of the chunk, to be safe for subsequent chunk reads.
    final expectedEndPosition = startPosition + chunkSize;
    if (dei.position() < expectedEndPosition) {
      dei.jumpTo(expectedEndPosition);
    } else if (dei.position() > expectedEndPosition) {
      // This might indicate an issue with length calculations or prior reads.
      // print(
      //   '[StringBlock] Warning: Stream position (${dei.position()}) is past expected chunk end ($expectedEndPosition). Resetting to chunk end.',
      // );
      dei.jumpTo(expectedEndPosition); // Or handle as error
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

  int find(String string) {
    return -1;
  }
}
