library;

// Minimal port of android.util.TypedValue constants used by AXmlResourceParser
class TypedValue {
  TypedValue._();

  // ignore_for_file: constant_identifier_names

  // Complex data type mode: bits that indicate that the data is a complex type.
  static const int COMPLEX_UNIT_SHIFT = 0;
  static const int COMPLEX_UNIT_MASK = 0xf;

  // TYPE_DIMENSION: Value is a dimension.
  static const int TYPE_DIMENSION = 0x05;
  // TYPE_ATTRIBUTE: Value is a reference to an attribute resource
  static const int TYPE_ATTRIBUTE = 0x02;
  // TYPE_FLOAT: Value is a floating point number.
  static const int TYPE_FLOAT = 0x04;
  // TYPE_FRACTION: Value is a fraction.
  static const int TYPE_FRACTION = 0x06;
  // TYPE_INT_BOOLEAN: Value is a boolean.
  static const int TYPE_INT_BOOLEAN = 0x12;
  // TYPE_INT_COLOR_ARGB4: Value is a color, representing #AARRGGBB.
  static const int TYPE_INT_COLOR_ARGB4 = 0x1e;
  // TYPE_INT_COLOR_ARGB8: Value is a color, representing #AARRGGBB.
  static const int TYPE_INT_COLOR_ARGB8 = 0x1c;
  // TYPE_INT_COLOR_RGB4: Value is a color, representing #RRGGBB.
  static const int TYPE_INT_COLOR_RGB8 = 0x1d;
  // TYPE_INT_DEC: Value is a simple integer.
  static const int TYPE_INT_DEC = 0x10;
  // TYPE_INT_HEX: Value is a simple integer, hexadecimal formatted.
  static const int TYPE_INT_HEX = 0x11;
  // TYPE_NULL: Value is null.
  static const int TYPE_NULL = 0x00;
  // TYPE_REFERENCE: Value is a reference to another resource.
  static const int TYPE_REFERENCE = 0x01;
  // TYPE_STRING: Value is a string.
  static const int TYPE_STRING = 0x03;

  // Range of types that are integers, for faster checking.
  static const int TYPE_FIRST_INT = TYPE_INT_DEC; // 0x10
  static const int TYPE_LAST_INT =
      0x1f; // TYPE_INT_COLOR_RGB4 is 0x1f in some versions, TYPE_INT_BOOLEAN is 0x12
  // AOSP TypedValue.java has TYPE_LAST_INT = TYPE_INT_COLOR_RGB4 = 0x1f.
  // For safety, let's use the AOSP constant value. Max is 0x1f.

  // Dynamic references (added in later Android versions, may not be in older AXML formats)
  static const int TYPE_DYNAMIC_REFERENCE = 0x07;
  static const int TYPE_DYNAMIC_ATTRIBUTE = 0x08;

  // Helper to get a string representation of a type (for debugging)
  static String typeToString(int type) {
    switch (type) {
      case TYPE_NULL:
        return "TYPE_NULL";
      case TYPE_REFERENCE:
        return "TYPE_REFERENCE";
      case TYPE_ATTRIBUTE:
        return "TYPE_ATTRIBUTE";
      case TYPE_STRING:
        return "TYPE_STRING";
      case TYPE_FLOAT:
        return "TYPE_FLOAT";
      case TYPE_DIMENSION:
        return "TYPE_DIMENSION";
      case TYPE_FRACTION:
        return "TYPE_FRACTION";
      case TYPE_DYNAMIC_REFERENCE:
        return "TYPE_DYNAMIC_REFERENCE";
      case TYPE_DYNAMIC_ATTRIBUTE:
        return "TYPE_DYNAMIC_ATTRIBUTE";
      case TYPE_INT_DEC:
        return "TYPE_INT_DEC";
      case TYPE_INT_HEX:
        return "TYPE_INT_HEX";
      case TYPE_INT_BOOLEAN:
        return "TYPE_INT_BOOLEAN";
      case TYPE_INT_COLOR_ARGB8:
        return "TYPE_INT_COLOR_ARGB8";
      case TYPE_INT_COLOR_RGB8:
        return "TYPE_INT_COLOR_RGB8";
      case TYPE_INT_COLOR_ARGB4:
        return "TYPE_INT_COLOR_ARGB4";
      // TYPE_INT_COLOR_RGB4 is also 0x1f in some AOSP versions for TYPE_LAST_INT.
      // If it has a distinct meaning, add it. Otherwise, it might be covered by TYPE_LAST_INT range.
      // It seems TYPE_INT_COLOR_RGB4 = 0x1f, so it can be explicitly named.
      case 0x1f:
        return "TYPE_INT_COLOR_RGB4"; // Or just handle as part of last_int range.
      default:
        if (type >= TYPE_FIRST_INT && type <= TYPE_LAST_INT) {
          return "TYPE_INT (unknown subtype)";
        }
        return "TYPE_UNKNOWN (0x${type.toRadixString(16)})";
    }
  }
}
