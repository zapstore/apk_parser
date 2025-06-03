library brut_util;

import 'dart:typed_data';

// Ported from brut.util.ExtDataInput which extends java.io.DataInput
abstract class ExtDataInput {
  // Methods from java.io.DataInput
  void readFully(Uint8List b, [int off = 0, int? len]);
  // int skipBytes(int n); // Can be implemented by advancing position
  bool readBoolean();
  int readByte(); // read S8
  int readUnsignedByte(); // read U8
  int readShort(); // read S16
  int readUnsignedShort(); // read U16
  int readChar(); // read U16 (Java char is 2 bytes)
  int readInt(); // read S32
  // long readLong(); // Dart int handles 64-bit, so readInt64()
  BigInt readLong(); // read S64 - use BigInt for full 64-bit range
  double readFloat(); // read F32
  double readDouble(); // read F64
  String
  readLine(); // Complex, usually involves reading until newline. May not be directly needed for AXML.
  String readUTF();

  // Methods from brut.util.ExtDataInput
  int position();
  void setPosition(int pos); // Added for convenience in Dart
  void skipBytes(int n);
  void skipInt();
  void skipByte();
  void skipShort();
  String readNullEndedString(int maxLength);
  Uint8List readBytes(int count);
  List<int> readIntArray(int len);
  List<int> readSafeIntArray(int len, int maxAllowedPosition);

  // String readAscii(int len); // Specialized string reading, can be utility on top
  // String readUtf16(int len); // Specialized string reading

  void jumpTo(int position);
}
