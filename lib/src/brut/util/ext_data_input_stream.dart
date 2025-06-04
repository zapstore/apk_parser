library;

import 'dart:convert'; // For utf8
import 'dart:typed_data';
import 'package:apktool_dart/src/brut/util/ext_data_input.dart';
import '../common/brut_exception.dart'; // For potential exceptions
import '../directory/apktool_io_exception.dart'; // For IO related exceptions

class ExtDataInputStream implements ExtDataInput {
  final Uint8List _bytes;
  final ByteData _byteData;
  int _currentPosition = 0;
  final Endian _endian;

  ExtDataInputStream(this._bytes, {Endian endian = Endian.little})
    : _byteData = ByteData.view(
        _bytes.buffer,
        _bytes.offsetInBytes,
        _bytes.length,
      ),
      _endian = endian;

  ExtDataInputStream.fromByteBuffer(
    ByteBuffer buffer, {
    Endian endian = Endian.little,
  }) : _bytes = buffer.asUint8List(),
       _byteData = ByteData.view(buffer),
       _endian = endian;

  @override
  int position() => _currentPosition;

  @override
  void setPosition(int pos) {
    if (pos < 0 || pos > _bytes.length) {
      throw RangeError(
        'Position out of bounds: $pos (length: ${_bytes.length})',
      );
    }
    _currentPosition = pos;
  }

  void _ensureAvailable(int bytesNeeded) {
    if (_currentPosition + bytesNeeded > _bytes.length) {
      throw ApktoolIOException(
        'Attempt to read past end of stream. Needed: $bytesNeeded, available: ${_bytes.length - _currentPosition} at pos $_currentPosition',
      );
    }
  }

  @override
  void readFully(Uint8List b, [int off = 0, int? len]) {
    len ??= b.length - off;
    _ensureAvailable(len);
    b.setRange(
      off,
      off + len,
      _bytes.sublist(_currentPosition, _currentPosition + len),
    );
    _currentPosition += len;
  }

  @override
  bool readBoolean() {
    _ensureAvailable(1);
    final val = _bytes[_currentPosition] != 0;
    _currentPosition += 1;
    return val;
  }

  @override
  int readByte() {
    _ensureAvailable(1);
    final val = _byteData.getInt8(_currentPosition);
    _currentPosition += 1;
    return val;
  }

  @override
  int readUnsignedByte() {
    _ensureAvailable(1);
    final val = _byteData.getUint8(_currentPosition);
    _currentPosition += 1;
    return val;
  }

  @override
  int readShort() {
    _ensureAvailable(2);
    final val = _byteData.getInt16(_currentPosition, _endian);
    _currentPosition += 2;
    return val;
  }

  @override
  int readUnsignedShort() {
    _ensureAvailable(2);
    final val = _byteData.getUint16(_currentPosition, _endian);
    _currentPosition += 2;
    return val;
  }

  @override
  int readChar() {
    // Java char is U16
    return readUnsignedShort();
  }

  @override
  int readInt() {
    _ensureAvailable(4);
    final val = _byteData.getInt32(_currentPosition, _endian);
    _currentPosition += 4;
    return val;
  }

  @override
  BigInt readLong() {
    _ensureAvailable(8);
    final val = _byteData.getInt64(
      _currentPosition,
      _endian,
    ); // ByteData.getInt64 returns a Dart int (64-bit signed)
    _currentPosition += 8;
    return BigInt.from(val);
  }

  @override
  double readFloat() {
    _ensureAvailable(4);
    final val = _byteData.getFloat32(_currentPosition, _endian);
    _currentPosition += 4;
    return val;
  }

  @override
  double readDouble() {
    _ensureAvailable(8);
    final val = _byteData.getFloat64(_currentPosition, _endian);
    _currentPosition += 8;
    return val;
  }

  @override
  String readLine() {
    // This is a complex method in Java DataInputStream, typically not used in binary parsers like AXML.
    // AXML uses specific string formats (e.g., length-prefixed UTF-8/UTF-16).
    throw UnimplementedError(
      'readLine is not implemented for ExtDataInputStream. Use specific string readers for AXML.',
    );
  }

  @override
  String readUTF() {
    // Java's DataInput.readUTF() reads a UTf-8 string prefixed by its 2-byte length.
    final len = readUnsignedShort();
    _ensureAvailable(len);
    final stringBytes = _bytes.sublist(
      _currentPosition,
      _currentPosition + len,
    );
    _currentPosition += len;
    try {
      return utf8.decode(stringBytes);
    } catch (e) {
      throw BrutException('Failed to decode UTF-8 string: $e');
    }
  }

  String readUTF16String(int numChars) {
    // Reads a UTF-16 string of numChars characters (numChars * 2 bytes).
    // Handles potential null termination within those chars.
    final numBytes = numChars * 2;
    _ensureAvailable(numBytes);

    StringBuffer sb = StringBuffer();
    for (int i = 0; i < numChars; ++i) {
      int charVal = readChar(); // Reads U16
      if (charVal == 0) {
        // Null terminator found, skip remaining chars in this string block
        final remainingChars = numChars - (i + 1);
        if (remainingChars > 0) {
          skipBytes(remainingChars * 2);
        }
        break;
      }
      sb.writeCharCode(charVal);
    }
    return sb.toString();
  }

  @override
  void skipBytes(int count) {
    if (count < 0) return;
    _ensureAvailable(count);
    _currentPosition += count;
  }

  @override
  Uint8List readBytes(int len) {
    if (len < 0) throw ArgumentError('Length cannot be negative: $len');
    _ensureAvailable(len);
    final result = Uint8List.fromList(
      _bytes.sublist(_currentPosition, _currentPosition + len),
    );
    _currentPosition += len;
    return result;
  }

  @override
  List<int> readIntArray(int len) {
    if (len < 0) throw ArgumentError('Length cannot be negative: $len');
    List<int> array = List<int>.filled(len, 0, growable: false);
    for (int i = 0; i < len; i++) {
      array[i] = readInt();
    }
    return array;
  }

  @override
  List<int> readSafeIntArray(int len, int maxAllowedPosition) {
    if (len < 0) throw ArgumentError('Length cannot be negative: $len');
    List<int> array = List<int>.filled(len, 0, growable: false);
    for (int i = 0; i < len; i++) {
      if (position() >= maxAllowedPosition) {
        // Or throw, or return partially filled array? Java version returns partially filled.
        // For safety, let's match Java: return what we have.
        // However, the Java version in StringBlock seems to just continue reading, relying on ExtDataInput to throw.
        // The log in ExtDataInputStream was: "Bad string block: string entry is at %d, past end at %d"
        // This implies it continues but the values might be bogus. Let's throw for now for clarity.
        throw ApktoolIOException(
          'readSafeIntArray: current position ${position()} would exceed maxAllowedPosition $maxAllowedPosition before reading all $len integers.',
        );
      }
      array[i] = readInt();
    }
    return array;
  }

  @override
  void jumpTo(int expectedPosition) {
    if (position() > expectedPosition) {
      throw ApktoolIOException(
        'Jumping backwards from ${position()} to $expectedPosition',
      );
    }
    if (position() < expectedPosition) {
      int toSkip = expectedPosition - position();
      skipBytes(toSkip); // skipBytes already checks bounds
      if (position() != expectedPosition) {
        // Should not happen if skipBytes is correct
        throw ApktoolIOException(
          'Jump failed: expected to skip $toSkip, but new position is ${position()} instead of $expectedPosition',
        );
      }
    }
  }

  @override
  void skipInt() {
    skipBytes(4);
  }

  @override
  void skipByte() {
    skipBytes(1);
  }

  @override
  void skipShort() {
    skipBytes(2);
  }

  @override
  String readNullEndedString(int maxLength) {
    final bytes = <int>[];
    int count = 0;

    while (count < maxLength) {
      final byte = readUnsignedByte();
      count++;

      if (byte == 0) {
        break;
      }
      bytes.add(byte);
    }

    // Skip remaining bytes up to maxLength
    if (count < maxLength) {
      skipBytes(maxLength - count);
    }

    return String.fromCharCodes(bytes);
  }
}
