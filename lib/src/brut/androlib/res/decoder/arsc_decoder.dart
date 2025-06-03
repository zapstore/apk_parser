library brut_androlib_res_decoder;

import 'dart:typed_data';
import 'package:apktool_dart/src/brut/util/ext_data_input.dart';
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

class ARSCDecoder {
  static const int ENTRY_FLAG_COMPLEX = 0x0001;
  static const int ENTRY_FLAG_PUBLIC = 0x0002;
  static const int ENTRY_FLAG_WEAK = 0x0004;
  static const int ENTRY_FLAG_COMPACT = 0x0008;

  static const int TABLE_TYPE_FLAG_SPARSE = 0x01;
  static const int TABLE_TYPE_FLAG_OFFSET16 = 0x02;

  static const int NO_ENTRY = 0xFFFFFFFF;
  static const int NO_ENTRY_OFFSET16 = 0xFFFF;

  final ExtDataInput _in;
  final ResTable _resTable;
  final bool _keepBroken;

  ARSCHeader? _header;
  StringBlock? _tableStrings;
  StringBlock? _typeNames;
  StringBlock? _specNames;
  ResPackage? _package;
  ResTypeSpec? _typeSpec;
  ResType? _type;
  int _resId = 0;
  int _typeIdOffset = 0;
  int _stringPoolCount = 0; // Track string pool count

  final Map<int, ResTypeSpec> _resTypeSpecs = {};

  ARSCDecoder(this._in, this._resTable, {bool keepBroken = false})
    : _keepBroken = keepBroken;

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
        case ARSCConstants.RES_NULL_TYPE:
          print('DEBUG: Processing RES_NULL_TYPE chunk');
          await _readUnknownChunk();
          break;
        case ARSCConstants.RES_STRING_POOL_TYPE:
          print('DEBUG: Processing RES_STRING_POOL_TYPE chunk');
          await _readStringPoolChunk();
          break;
        case ARSCConstants.RES_TABLE_TYPE:
          print('DEBUG: Processing RES_TABLE_TYPE chunk');
          await _readTableChunk();
          break;
        case ARSCConstants.RES_TABLE_PACKAGE_TYPE:
          print('DEBUG: Processing RES_TABLE_PACKAGE_TYPE chunk');
          _typeIdOffset = 0;
          final pkg = await _readTablePackage();
          if (pkg != null) {
            packages.add(pkg);
            packageMap[pkg.getId()] = pkg;
          }
          break;
        case ARSCConstants.RES_TABLE_TYPE_TYPE:
          print('DEBUG: Processing RES_TABLE_TYPE_TYPE chunk');
          await _readTableType();
          break;
        case ARSCConstants.RES_TABLE_TYPE_SPEC_TYPE:
          print('DEBUG: Processing RES_TABLE_TYPE_SPEC_TYPE chunk');
          typeSpec = await _readTableSpecType();
          if (typeSpec != null) {
            _resTypeSpecs[typeSpec.getId()] = typeSpec;
          }
          break;
        case ARSCConstants.RES_TABLE_LIBRARY_TYPE:
          print('DEBUG: Processing RES_TABLE_LIBRARY_TYPE chunk');
          await _readLibraryType();
          break;
        case ARSCConstants.RES_TABLE_OVERLAYABLE_TYPE:
          print('DEBUG: Processing RES_TABLE_OVERLAYABLE_TYPE chunk');
          await _readOverlaySpec();
          break;
        case ARSCConstants.RES_TABLE_OVERLAYABLE_POLICY_TYPE:
          print('DEBUG: Processing RES_TABLE_OVERLAYABLE_POLICY_TYPE chunk');
          await _readOverlayPolicySpec();
          break;
        case ARSCConstants.RES_TABLE_STAGED_ALIAS_TYPE:
          print('DEBUG: Processing RES_TABLE_STAGED_ALIAS_TYPE chunk');
          await _readStagedAliasSpec();
          break;
        default:
          if (_header!.type != ARSCConstants.RES_NONE_TYPE) {
            print('Unknown chunk type: 0x${_header!.type.toRadixString(16)}');
          }
          break;
      }

      // Ensure we're positioned at the end of the chunk
      if (_header!.type != ARSCConstants.RES_TABLE_PACKAGE_TYPE) {
        final expectedEndPos = _header!.endPosition;
        final currentPos = _in.position();
        if (currentPos < expectedEndPos) {
          _in.jumpTo(expectedEndPos);
        }
      }
    }

    print('DEBUG: Returning ${packages.length} packages');
    for (final pkg in packages) {
      print(
        '  Package: id=0x${pkg.getId().toRadixString(16)}, name=${pkg.getName()}, specs=${pkg.getResSpecCount()}',
      );
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
    if (header == null || header.type != ARSCConstants.RES_TABLE_TYPE) {
      throw Exception('No RES_TABLE_TYPE found');
    }
    _in.readInt(); // packageCount
  }

  Future<void> _readStringPoolChunk() async {
    // The first string pool is the global table strings
    // The next ones are package-specific (typeNames, then specNames)
    _stringPoolCount++;

    final stringBlock = await StringBlock.readWithHeader(
      _in,
      _header!.startPosition,
      _header!.headerSize,
      _header!.chunkSize,
    );

    if (_stringPoolCount == 1) {
      _tableStrings = stringBlock;
      print(
        'DEBUG: Loaded table strings with ${_tableStrings!.getCount()} strings',
      );
    } else if (_stringPoolCount == 2 && _package != null) {
      _typeNames = stringBlock;
      print('DEBUG: Loaded type names with ${_typeNames!.getCount()} strings');
    } else if (_stringPoolCount == 3 && _package != null) {
      _specNames = stringBlock;
      print('DEBUG: Loaded spec names with ${_specNames!.getCount()} strings');
    }
  }

  Future<void> _readTableChunk() async {
    _in.readInt(); // packageCount
  }

  Future<void> _readUnknownChunk() async {
    _in.jumpTo(_header!.endPosition);
  }

  Future<ResPackage?> _readTablePackage() async {
    final packageStart = _header!.startPosition;
    final packageEnd = _header!.endPosition;

    final id = _in.readInt();
    final name = _in.readNullEndedString(128);
    final typeStringsOffset = _in.readInt(); // typeStrings
    _in.skipInt(); // lastPublicType
    final keyStringsOffset = _in.readInt(); // keyStrings
    _in.skipInt(); // lastPublicKey

    print(
      'DEBUG: Package offsets - typeStrings=$typeStringsOffset, keyStrings=$keyStringsOffset',
    );

    // Check for split header size
    const splitHeaderSize = 2 + 2 + 4 + 4 + (2 * 128) + (4 * 5);
    if (_header!.headerSize == splitHeaderSize) {
      _typeIdOffset = _in.readInt();
    }

    // Jump to typeStrings position within the package
    if (typeStringsOffset > 0) {
      _in.jumpTo(packageStart + typeStringsOffset);
      _typeNames = await StringBlock.readWithChunk(_in);
      print('DEBUG: Loaded typeNames with ${_typeNames!.getCount()} strings');
    }

    // Jump to keyStrings position within the package
    if (keyStringsOffset > 0) {
      _in.jumpTo(packageStart + keyStringsOffset);
      _specNames = await StringBlock.readWithChunk(_in);
      print('DEBUG: Loaded specNames with ${_specNames!.getCount()} strings');
    }

    // After reading the string pools, position at the end of the header
    // so we can continue reading type chunks
    _in.jumpTo(packageStart + _header!.headerSize);

    var packageId = id;
    if (id == 0 && _resTable.isMainPackageLoaded()) {
      // Shared library package
      packageId = _resTable.getDynamicRefPackageId(name);
    }

    _resId = packageId << 24;
    _package = ResPackage(_resTable, packageId, name);

    print(
      'DEBUG: Created package id=0x${packageId.toRadixString(16)}, name="$name"',
    );

    return _package;
  }

  Future<void> _readLibraryType() async {
    final libraryCount = _in.readInt();

    for (int i = 0; i < libraryCount; i++) {
      final id = _in.readInt();
      final name = _in.readNullEndedString(128);
      _resTable.addDynamicRefPackage(id, name);
      print('Shared library id: $id, name: "$name"');
    }
  }

  Future<void> _readStagedAliasSpec() async {
    final count = _in.readInt();

    for (int i = 0; i < count; i++) {
      print(
        'Staged alias: 0x${_in.readInt().toRadixString(16)} -> 0x${_in.readInt().toRadixString(16)}',
      );
    }
  }

  Future<void> _readOverlaySpec() async {
    final name = _in.readNullEndedString(256);
    final actor = _in.readNullEndedString(256);
    print('Overlay name: "$name", actor: "$actor"');
  }

  Future<void> _readOverlayPolicySpec() async {
    _in.skipInt(); // policyFlags
    final count = _in.readInt();

    for (int i = 0; i < count; i++) {
      print('Skipping overlay (0x${_in.readInt().toRadixString(16)})');
    }
  }

  Future<ResTypeSpec?> _readTableSpecType() async {
    final id = _in.readUnsignedByte();
    _in.skipByte(); // reserved0
    _in.skipShort(); // reserved1
    final entryCount = _in.readInt();

    print('DEBUG _readTableSpecType: id=$id, entryCount=$entryCount');

    // Skip flags
    for (int i = 0; i < entryCount; i++) {
      _in.skipInt(); // flags
    }

    if (_typeNames == null || id == 0 || id > _typeNames!.getCount()) {
      print(
        'DEBUG _readTableSpecType: Failed - typeNames=${_typeNames?.getCount()}, id=$id',
      );
      return null;
    }

    final typeName = _typeNames!.getString(id - 1);
    if (typeName == null) {
      print('DEBUG _readTableSpecType: Failed - typeName is null for id=$id');
      return null;
    }

    _typeSpec = ResTypeSpec(typeName, id);
    _package?.addType(_typeSpec!);

    print(
      'DEBUG: Added type spec "$typeName" (id=$id) to package "${_package?.getName()}", entryCount=$entryCount',
    );

    return _typeSpec;
  }

  Future<void> _readTableType() async {
    final chunkStart = _header!.startPosition;
    final chunkEnd = _header!.endPosition;
    print('DEBUG _readTableType: start=$chunkStart, end=$chunkEnd');

    final typeId = _in.readUnsignedByte() - _typeIdOffset;

    // Get or create type spec
    if (_resTypeSpecs.containsKey(typeId)) {
      _typeSpec = _resTypeSpecs[typeId];
    } else {
      if (_typeNames == null ||
          typeId == 0 ||
          typeId > _typeNames!.getCount()) {
        print('DEBUG _readTableType: skipping - no type name for id=$typeId');
        return;
      }
      final typeName = _typeNames!.getString(typeId - 1);
      if (typeName == null) {
        print(
          'DEBUG _readTableType: skipping - type name is null for id=$typeId',
        );
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

    print(
      'DEBUG _readTableType: type=${_typeSpec?.getName()}, entryCount=$entryCount, entriesStart=$entriesStart',
    );

    final flags = await _readConfigFlags();
    _type = _package?.getOrCreateConfig(flags);

    final isOffset16 = (typeFlags & TABLE_TYPE_FLAG_OFFSET16) != 0;
    final isSparse = (typeFlags & TABLE_TYPE_FLAG_SPARSE) != 0;

    // Read entry offsets
    final entryOffsets = <int, int>{};

    if (isSparse) {
      // Sparse entries
      for (int i = 0; i < entryCount; i++) {
        final idx = _in.readUnsignedShort();
        final rawOffset = isOffset16 ? _in.readUnsignedShort() : _in.readInt();
        // For 32-bit values, check if it's NO_ENTRY (-1 when read as signed int)
        final isNoEntry = isOffset16
            ? (rawOffset == NO_ENTRY_OFFSET16)
            : (rawOffset == -1 || rawOffset == NO_ENTRY);

        if (!isNoEntry) {
          entryOffsets[idx] = rawOffset * (isOffset16 ? 4 : 1);
        }
      }
    } else {
      // Dense entries
      for (int i = 0; i < entryCount; i++) {
        final rawOffset = isOffset16 ? _in.readUnsignedShort() : _in.readInt();
        // For 32-bit values, check if it's NO_ENTRY (-1 when read as signed int)
        final isNoEntry = isOffset16
            ? (rawOffset == NO_ENTRY_OFFSET16)
            : (rawOffset == -1 || rawOffset == NO_ENTRY);

        if (!isNoEntry) {
          final actualOffset = rawOffset * (isOffset16 ? 4 : 1);
          entryOffsets[i] = actualOffset;
          if (i < 3) {
            // Debug first few entries
            print(
              'DEBUG: Entry $i offset=$rawOffset, actualOffset=$actualOffset, isOffset16=$isOffset16',
            );
          }
        } else if (i < 3) {
          print('DEBUG: Entry $i is NO_ENTRY (offset=$rawOffset)');
        }
      }
    }

    print(
      'DEBUG _readTableType: after offsets, pos=${_in.position()}, ${entryOffsets.length} entries to read',
    );

    // Read entries
    final entriesStartPos = _header!.startPosition + entriesStart;

    // If no entries to read, skip
    if (entryOffsets.isEmpty) {
      print('DEBUG _readTableType: no entries to read');
    } else {
      // For the first entry, check if we're already at the right position
      var lastPos = _in.position();

      for (final entry in entryOffsets.entries) {
        final targetPos = entriesStartPos + entry.value;

        // Only jump if we need to move forward or significantly backward
        if (targetPos != lastPos) {
          print(
            'DEBUG _readTableType: jumping from $lastPos to $targetPos for entry ${entry.key}',
          );
          _in.jumpTo(targetPos);
        }

        await _readEntry(entry.key);
        lastPos = _in.position();
      }
    }

    // Ensure we're positioned at the end of the chunk
    final currentPos = _in.position();
    print(
      'DEBUG _readTableType: chunk end check - current=$currentPos, expected=$chunkEnd, type=${_typeSpec?.getName()}',
    );
    if (currentPos < chunkEnd) {
      _in.jumpTo(chunkEnd);
    } else if (currentPos > chunkEnd) {
      print(
        'WARNING: Overshot TYPE chunk end: current=$currentPos, expected=$chunkEnd, diff=${currentPos - chunkEnd}',
      );
      // If we've only overshot by 1-3 bytes, it might be padding
      if (currentPos - chunkEnd < 4) {
        // Don't try to jump backwards for small overshoots
        print('Ignoring small overshoot, likely padding');
      } else {
        // For larger overshoots, this is a real problem
        _in.jumpTo(chunkEnd);
      }
    }
  }

  Future<void> _readEntry(int entryId) async {
    final size = _in.readUnsignedShort();
    final flags = _in.readUnsignedShort();
    final keyIndex = _in.readInt();

    if (keyIndex == -1 || _specNames == null) {
      return;
    }

    final key = _specNames!.getString(keyIndex);
    if (key == null) return;

    final resId = ResID((_resId & 0xFFFF0000) | entryId);

    // Debug logging
    if (resId.id == 0x7f100000) {
      print(
        'DEBUG: Found target resource! ID=0x${resId.id.toRadixString(16)}, key=$key, type=${_typeSpec?.getName()}',
      );
    }

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
    if ((flags & ENTRY_FLAG_COMPLEX) != 0) {
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
          print(
            'DEBUG: Resource already exists for ${spec.getName()} in config ${_type!.getFlags()}, skipping',
          );
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

      if (value != null && value is ResScalarValue) {
        items[resId] = value;
      }
    }

    final parent = parentId != 0 ? ResReferenceValue(parentId) : null;

    // Determine bag type based on type spec
    if (_typeSpec?.getName() == ResTypeSpec.RES_TYPE_NAME_ARRAY) {
      return ResArrayValue(parent, items.values.toList());
    } else if (_typeSpec?.getName() == ResTypeSpec.RES_TYPE_NAME_PLURALS) {
      final pluralItems = <String, ResScalarValue>{};
      // TODO: Map quantity IDs to strings
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

    // language = language.trim(); // Not needed after char-by-char parsing
    // region = region.trim();   // Not needed after char-by-char parsing

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
