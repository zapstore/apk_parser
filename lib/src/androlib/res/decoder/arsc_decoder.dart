library;

import 'package:apk_parser/src/util/ext_data_input.dart';
import '../data/arsc/arsc_header.dart';
import '../data/res_table.dart';
import '../data/res_package.dart';
import '../data/res_type_spec.dart';
import '../data/res_type.dart';
import '../data/res_id.dart';
import '../data/res_res_spec.dart';
import '../data/res_resource.dart';
import '../data/res_config_flags.dart';
import '../data/value/res_value.dart';
import 'string_block.dart';
import 'typed_value.dart';

// Constants for ARSC file format
class ARSCConstants {
  // Resource types
  static const int kResNullType = 0x0000;
  static const int kResStringPoolType = 0x0001;
  static const int kResTableType = 0x0002;
  static const int kResNoneType = 0xFFFF;

  // Table resource types
  static const int kResTablePackageType = 0x0200;
  static const int kResTableTypeType = 0x0201;
  static const int kResTableTypeSpecType = 0x0202;
  static const int kResTableLibraryType = 0x0203;
  static const int kResTableOverlayableType = 0x0204;
  static const int kResTableOverlayablePolicyType = 0x0205;
  static const int kResTableStagedAliasType = 0x0206;
}

// Entry flags
const int kEntryFlagComplex = 0x0001;
const int kEntryFlagPublic = 0x0002;
const int kEntryFlagWeak = 0x0004;
const int kEntryFlagCompact = 0x0008;

// Table type flags
const int kTableTypeFlagSparse = 0x01;
const int kTableTypeFlagOffset16 = 0x02;

// Special entry values
const int kNoEntry = 0xFFFFFFFF;
const int kNoEntryOffset16 = 0xFFFF;

class ARSCDecoder {
  final ExtDataInput _in;
  final ResTable _resTable;

  ARSCHeader? _header;
  StringBlock? _tableStrings;
  StringBlock? _typeNames;
  StringBlock? _specNames;
  ResPackage? _package;
  ResTypeSpec? _typeSpec;
  ResType? _type;
  int _resId = 0;
  int _typeIdOffset = 0;

  final Map<int, ResTypeSpec> _resTypeSpecs = {};

  ARSCDecoder(this._in, this._resTable, {bool keepBroken = false});

  Future<ARSCData> decode() async {
    final packages = <ResPackage>[];
    final packageMap = <int, ResPackage>{};
    ResTypeSpec? typeSpec;

    await _readTable();

    while (true) {
      try {
        _header = await _readChunkHeader();
      } catch (e) {
        // EOF reached
        break;
      }

      if (_header == null) break;

      switch (_header!.type) {
        case ARSCConstants.kResNullType:
          await _readUnknownChunk();
          break;
        case ARSCConstants.kResStringPoolType:
          await _readStringPoolChunk();
          break;
        case ARSCConstants.kResTableType:
          await _readTableChunk();
          break;
        case ARSCConstants.kResTablePackageType:
          _typeIdOffset = 0;
          final pkg = await _readTablePackage();
          if (pkg != null) {
            packages.add(pkg);
            packageMap[pkg.getId()] = pkg;
          }
          break;
        case ARSCConstants.kResTableTypeType:
          await _readTableType();
          break;
        case ARSCConstants.kResTableTypeSpecType:
          typeSpec = await _readTableSpecType();
          if (typeSpec != null) {
            _resTypeSpecs[typeSpec.getId()] = typeSpec;
          }
          break;
        case ARSCConstants.kResTableLibraryType:
          await _readLibraryType();
          break;
        case ARSCConstants.kResTableOverlayableType:
          await _readOverlaySpec();
          break;
        case ARSCConstants.kResTableOverlayablePolicyType:
          await _readOverlayPolicySpec();
          break;
        case ARSCConstants.kResTableStagedAliasType:
          await _readStagedAliasSpec();
          break;
        default:
          if (_header!.type != ARSCConstants.kResNoneType) {
            // print('Unknown chunk type: 0x${_header!.type.toRadixString(16)}');
          }
          break;
      }

      // Ensure we're positioned at the end of the chunk
      if (_header!.type != ARSCConstants.kResTablePackageType) {
        final expectedEndPos = _header!.endPosition;
        final currentPos = _in.position();
        if (currentPos < expectedEndPos) {
          _in.jumpTo(expectedEndPos);
        }
      }
    }

    return ARSCData(packages);
  }

  Future<ARSCHeader?> _readChunkHeader() async {
    try {
      final type = _in.readUnsignedShort();
      final headerSize = _in.readUnsignedShort();
      final chunkSize = _in.readInt();
      final startPosition =
          _in.position() - 8; // Account for already read bytes

      return ARSCHeader(type, headerSize, chunkSize, startPosition);
    } catch (e) {
      return null; // EOF
    }
  }

  Future<void> _readTable() async {
    final header = await _readChunkHeader();
    if (header == null || header.type != ARSCConstants.kResTableType) {
      throw Exception('No RES_TABLE_TYPE found');
    }
    _in.readInt(); // packageCount
  }

  Future<void> _readStringPoolChunk() async {
    // Always overwrite the global table strings (matches Java behavior)
    // Java always overwrites mTableStrings with the latest RES_STRING_POOL_TYPE chunk

    final stringBlock = await StringBlock.readWithHeader(
      _in,
      _header!.startPosition,
      _header!.headerSize,
      _header!.chunkSize,
    );

    // Always overwrite, just like Java does
    _tableStrings = stringBlock;
  }

  Future<void> _readTableChunk() async {
    _in.readInt(); // packageCount
  }

  Future<void> _readUnknownChunk() async {
    _in.jumpTo(_header!.endPosition);
  }

  Future<ResPackage?> _readTablePackage() async {
    final packageStart = _header!.startPosition;

    final id = _in.readInt();
    final name = _in.readNullEndedString(128);

    // Check for split header size
    const splitHeaderSize = 2 + 2 + 4 + 4 + (2 * 128) + (4 * 5);
    if (_header!.headerSize == splitHeaderSize) {
      _typeIdOffset = _in.readInt();
    }

    // After reading the string pools, position at the end of the header
    // so we can continue reading type chunks
    _in.jumpTo(packageStart + _header!.headerSize);

    // Read typeNames and specNames directly (like Java version)
    _typeNames = await StringBlock.readWithChunk(_in);

    _specNames = await StringBlock.readWithChunk(_in);

    var packageId = id;
    if (id == 0 && _resTable.isMainPackageLoaded()) {
      // Shared library package
      packageId = _resTable.getDynamicRefPackageId(name);
    }

    _resId = packageId << 24;
    _package = ResPackage(_resTable, packageId, name);

    return _package;
  }

  Future<void> _readLibraryType() async {
    final libraryCount = _in.readInt();

    for (int i = 0; i < libraryCount; i++) {
      final id = _in.readInt();
      final name = _in.readNullEndedString(128);
      _resTable.addDynamicRefPackage(id, name);
      // print('Shared library id: $id, name: "$name"');
    }
  }

  Future<void> _readStagedAliasSpec() async {
    final count = _in.readInt();

    for (int i = 0; i < count; i++) {
      // print(
      //   'Staged alias: 0x${_in.readInt().toRadixString(16)} -> 0x${_in.readInt().toRadixString(16)}',
      // );
      _in.readInt();
      _in.readInt();
    }
  }

  Future<void> _readOverlaySpec() async {
    _in.readNullEndedString(256);
    _in.readNullEndedString(256);
    // print('Overlay name: "$name", actor: "$actor"');
  }

  Future<void> _readOverlayPolicySpec() async {
    _in.skipInt(); // policyFlags
    final count = _in.readInt();

    for (int i = 0; i < count; i++) {
      // print('Skipping overlay (0x${_in.readInt().toRadixString(16)})');
      _in.readInt();
    }
  }

  Future<ResTypeSpec?> _readTableSpecType() async {
    final id = _in.readUnsignedByte();
    _in.skipByte(); // reserved0
    _in.skipShort(); // reserved1
    final entryCount = _in.readInt();

    // Skip flags
    for (int i = 0; i < entryCount; i++) {
      _in.skipInt(); // flags
    }

    if (_typeNames == null || id == 0 || id > _typeNames!.getCount()) {
      return null;
    }

    final typeName = _typeNames!.getString(id - 1);
    if (typeName == null) {
      return null;
    }

    _typeSpec = ResTypeSpec(typeName, id);
    _package?.addType(_typeSpec!);

    return _typeSpec;
  }

  Future<void> _readTableType() async {
    final chunkEnd = _header!.endPosition;

    final typeId = _in.readUnsignedByte() - _typeIdOffset;

    // Get or create type spec
    if (_resTypeSpecs.containsKey(typeId)) {
      _typeSpec = _resTypeSpecs[typeId];
    } else {
      if (_typeNames == null ||
          typeId == 0 ||
          typeId > _typeNames!.getCount()) {
        return;
      }
      final typeName = _typeNames!.getString(typeId - 1);
      if (typeName == null) {
        return;
      }

      _typeSpec = ResTypeSpec(typeName, typeId);
      _resTypeSpecs[typeId] = _typeSpec!;
      _package?.addType(_typeSpec!);
    }

    _resId = (_resId & 0xFF000000) | (_typeSpec!.getId() << 16);

    final typeFlags = _in.readUnsignedByte();
    _in.skipShort(); // reserved
    final entryCount = _in.readInt();
    final entriesStart = _in.readInt();

    final flags = await _readConfigFlags();
    _type = _package?.getOrCreateConfig(flags);

    final isOffset16 = (typeFlags & kTableTypeFlagOffset16) != 0;
    final isSparse = (typeFlags & kTableTypeFlagSparse) != 0;

    // Read entry offsets
    final entryOffsets = <int, int>{};

    if (isSparse) {
      // Sparse entries: Java Apktool always reads a ushort for the offset value and multiplies by 4.
      // Match this behavior for fidelity.
      for (int i = 0; i < entryCount; i++) {
        final idx = _in.readUnsignedShort();
        final rawOffsetVal = _in
            .readUnsignedShort(); // Always read ushort for offset value

        // Check for NO_ENTRY based on 16-bit representation
        if (rawOffsetVal != kNoEntryOffset16) {
          entryOffsets[idx] =
              rawOffsetVal * 4; // Always multiply by 4, like Java
        }
      }
    } else {
      // Dense entries
      for (int i = 0; i < entryCount; i++) {
        final rawOffset = isOffset16 ? _in.readUnsignedShort() : _in.readInt();
        final isNoEntry = isOffset16
            ? (rawOffset == kNoEntryOffset16)
            : (rawOffset == -1 || rawOffset == kNoEntry);

        if (!isNoEntry) {
          final actualOffset = rawOffset * (isOffset16 ? 4 : 1);
          entryOffsets[i] = actualOffset;
        }
      }
    }

    // Read entries
    final entriesStartPos = _header!.startPosition + entriesStart;

    // If no entries to read, skip
    if (entryOffsets.isEmpty) {
      // print(
      //   'DEBUG _readTableType: No entries to read for type ${_typeSpec?.getName()}',
      // );
    } else {
      // For the first entry, check if we're already at the right position
      var lastPos = _in.position();

      for (final entry in entryOffsets.entries) {
        final targetPos = entriesStartPos + entry.value;

        // Only jump if we need to move forward or significantly backward
        if (targetPos != lastPos) {
          _in.jumpTo(targetPos);
        }

        await _readEntry(entry.key);
        lastPos = _in.position();
      }
    }

    // Ensure we're positioned at the end of the chunk
    final currentPos = _in.position();
    if (currentPos < chunkEnd) {
      _in.jumpTo(chunkEnd);
    } else if (currentPos > chunkEnd) {
      // If we've only overshot by 1-3 bytes, it might be padding
      if (currentPos - chunkEnd < 4) {
        // Don't try to jump backwards for small overshoots
        // print('Ignoring small overshoot, likely padding');
      } else {
        // For larger overshoots, this is a real problem
        _in.jumpTo(chunkEnd);
      }
    }
  }

  Future<void> _readEntry(int entryId) async {
    _in.readUnsignedShort(); // Entry size
    final flags = _in.readUnsignedShort();
    final keyIndex = _in.readInt();

    if (keyIndex == -1 || _specNames == null) {
      return;
    }

    final key = _specNames!.getString(keyIndex);
    if (key == null) return;

    final resId = ResID((_resId & 0xFFFF0000) | entryId);

    // Get or create ResResSpec
    ResResSpec? spec;
    try {
      spec = _package?.getResSpec(resId);
    } catch (e) {
      // Create new spec
      spec = ResResSpec(resId, key, _typeSpec!);
      _package?.addResSpec(spec);
      _typeSpec!.addResSpec(spec);
    }

    ResValue? value;
    if ((flags & kEntryFlagComplex) != 0) {
      value = await _readComplexEntry();
    } else {
      value = await _readValue();
    }

    if (value != null && spec != null && _type != null) {
      final resource = ResResource(_type!, spec, value);

      // Try to add resource, but don't fail if it already exists
      try {
        _type!.addResource(resource);
        spec.addResource(resource);
      } catch (e) {
        // Resource already exists, this can happen with multiple configs
        if (e.toString().contains('Multiple resources')) {
          // print(
          //   'DEBUG: Resource already exists for ${spec.getName()} in config ${_type!.getFlags()}, skipping',
          // );
        } else {
          rethrow;
        }
      }
    }
  }

  Future<ResBagValue?> _readComplexEntry() async {
    final parentId = _in.readInt();
    final count = _in.readInt();

    final items = <int, ResScalarValue>{};

    for (int i = 0; i < count; i++) {
      final resId = _in.readInt();
      final value = await _readValue();

      if (value != null) {
        items[resId] = value;
      }
    }

    final parent = parentId != 0 ? ResReferenceValue(parentId) : null;

    // Determine bag type based on type spec
    if (_typeSpec?.getName() == ResTypeSpec.kResTypeNameArray) {
      return ResArrayValue(parent, items.values.toList());
    } else if (_typeSpec?.getName() == ResTypeSpec.kResTypeNamePlurals) {
      final pluralItems = <String, ResScalarValue>{};
      return ResPluralsValue(parent, pluralItems);
    } else {
      return ResStyleValue(parent, items);
    }
  }

  Future<ResIntBasedValue?> _readValue() async {
    final size = _in.readUnsignedShort();
    if (size < 8) {
      return null;
    }

    _in.skipByte(); // res0
    final type = _in.readUnsignedByte();
    final data = _in.readInt();

    return _createValue(type, data);
  }

  ResIntBasedValue? _createValue(int type, int data) {
    switch (type) {
      case TypedValue.TYPE_NULL:
        return null;
      case TypedValue.TYPE_STRING:
        final str = _tableStrings?.getString(data);
        if (str != null) {
          // Check if this is a file path
          if (str.startsWith('res/') ||
              str.startsWith('r/') ||
              str.startsWith('R/')) {
            return ResFileValue(str, data);
          }
          return ResStringValue(str, data);
        }
        return null;
      case TypedValue.TYPE_REFERENCE:
        return ResReferenceValue(data);
      case TypedValue.TYPE_ATTRIBUTE:
        return ResReferenceValue(data); // Attributes are references
      case TypedValue.TYPE_INT_DEC:
      case TypedValue.TYPE_INT_HEX:
        return ResIntValue(data);
      case TypedValue.TYPE_INT_BOOLEAN:
        return ResBoolValue(data != 0);
      case TypedValue.TYPE_FLOAT:
        // TODO: Convert int bits to float
        return ResIntValue(data);
      default:
        if (type >= TypedValue.TYPE_FIRST_INT &&
            type <= TypedValue.TYPE_LAST_INT) {
          return ResIntValue(data);
        }
        return ResIntValue(data); // Fallback
    }
  }

  Future<ResConfigFlags> _readConfigFlags() async {
    // Simplified - read minimal config for now
    final size = _in.readInt();
    // final startPos = _in.position(); // Not used

    if (size < 28) {
      // Skip to end of config
      _in.skipBytes(size - 4);
      return ResConfigFlags.createDefault();
    }

    // Read basic config fields
    final mcc = _in.readUnsignedShort();
    final mnc = _in.readUnsignedShort();

    final languageBytes = _in.readBytes(2);
    final regionBytes = _in.readBytes(2);

    // Parse as null-terminated C strings
    String language = '';
    for (int i = 0; i < 2; i++) {
      if (languageBytes[i] == 0) break;
      language += String.fromCharCode(languageBytes[i]);
    }

    String region = '';
    for (int i = 0; i < 2; i++) {
      if (regionBytes[i] == 0) break;
      region += String.fromCharCode(regionBytes[i]);
    }

    final orientation = _in.readUnsignedByte();
    final touchscreen = _in.readUnsignedByte();
    final density = _in.readUnsignedShort();

    final bytesRead = 16; // 2+2+2+2+1+1+2 = 12, but we already read size (4)
    final remaining = size - bytesRead;

    if (remaining > 0) {
      _in.skipBytes(remaining); // Skip remaining config bytes
    }

    return ResConfigFlags(
      mcc: mcc,
      mnc: mnc,
      language: language.isEmpty ? null : language, // Pass null if empty
      region: region.isEmpty ? null : region, // Pass null if empty
      orientation: orientation,
      touchscreen: touchscreen,
      density: density,
    );
  }
}

// Data class to hold decoded ARSC data
class ARSCData {
  final List<ResPackage> packages;

  ARSCData(this.packages);

  ResPackage? getMainPackage() {
    return packages.isNotEmpty ? packages.first : null;
  }
}
