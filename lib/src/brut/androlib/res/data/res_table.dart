library;

import 'dart:async';
import 'dart:typed_data';

import 'res_package.dart';
import '../decoder/arsc_decoder.dart';
import '../../../directory/ext_file.dart';
import '../../../util/ext_data_input_stream.dart';
import 'res_id.dart';
import 'res_res_spec.dart';
import 'value/res_value.dart';

class ResTable {
  final Map<int, ResPackage> _packagesById = <int, ResPackage>{};
  final Map<String, ResPackage> _packagesByName = <String, ResPackage>{};

  ResPackage? _mainPackage;

  ResTable();

  bool isMainPackageLoaded() => _mainPackage != null;

  ResPackage getMainPackage() {
    if (_mainPackage == null) {
      throw Exception('Main package has not been loaded');
    }
    return _mainPackage!;
  }

  Future<void> loadMainPackage(String apkPath) async {
    // print('Loading resource table from $apkPath...');

    final apkFile = ExtFile(apkPath);
    final apkDirectory = await apkFile.getDirectory();

    try {
      final resourceStream = await apkDirectory.getFileInput('resources.arsc');

      // Read all data into memory - resources.arsc is typically a few MB
      final chunks = <List<int>>[];
      int totalSize = 0;

      await for (final chunk in resourceStream.asStream()) {
        chunks.add(chunk);
        totalSize += chunk.length;
      }

      // Combine chunks into single buffer
      final buffer = Uint8List(totalSize);
      int offset = 0;
      for (final chunk in chunks) {
        buffer.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }

      // Create decoder and parse
      final input = ExtDataInputStream(buffer);
      final decoder = ARSCDecoder(input, this);

      try {
        final arscData = await decoder.decode();

        // Register the packages
        for (final pkg in arscData.packages) {
          _registerPackage(pkg);
          if (_mainPackage == null && pkg.getId() == 0x7F) {
            _mainPackage = pkg;
          }
        }

        if (_mainPackage == null && arscData.packages.isNotEmpty) {
          _mainPackage = arscData.packages.first;
        }

        if (_mainPackage == null) {
          throw Exception('No packages found in resources.arsc');
        }

        // print(
        //   'Loaded ${arscData.packages.length} package(s) from resources.arsc',
        // );

        // Debug print package contents
        for (final _ in arscData.packages) {
          // print(
          //   'Package: id=0x${package.getId().toRadixString(16)}, name=${package.getName()}, specs=${package.getResSpecCount()}',
          // );
        }
      } catch (e) {
        // print('Error decoding resources.arsc: $e');
        // Re-throw to let the caller handle it
        rethrow;
      }
    } catch (e) {
      // print('Warning: Could not load resource table: $e');
      // Don't rethrow - let manifest decoding continue
    } finally {
      await apkDirectory.close();
      await apkFile.close();
    }
  }

  void _registerPackage(ResPackage pkg) {
    final id = pkg.getId();
    if (_packagesById.containsKey(id)) {
      throw Exception('Multiple packages: id=$id');
    }
    final name = pkg.getName();
    if (_packagesByName.containsKey(name)) {
      throw Exception('Multiple packages: name=$name');
    }

    _packagesById[id] = pkg;
    _packagesByName[name] = pkg;
  }

  ResPackage getCurrentPackage() {
    if (_mainPackage == null) {
      // if no main package, we directly get "android" instead
      return getPackageById(1);
    }
    return _mainPackage!;
  }

  ResPackage getPackageByName(String name) {
    final pkg = _packagesByName[name];
    if (pkg == null) {
      throw Exception('Undefined package: name=$name');
    }
    return pkg;
  }

  ResPackage getPackageById(int id) {
    var pkg = _packagesById[id];
    if (pkg == null) {
      throw Exception('Undefined package: id=$id');
    }
    return pkg;
  }

  ResResSpec getResSpec(int resId) {
    if (resId >> 24 == 0) {
      // The package ID is 0x00. That means that a shared library is accessing its own
      // local resource, so we fix up this resource with the calling package ID.
      resId = (resId & 0xFFFFFF) | (_mainPackage!.getId() << 24);
    }
    return getResSpecFromId(ResID(resId));
  }

  ResResSpec getResSpecFromId(ResID resId) {
    return getPackageById(resId.getPackageId()).getResSpec(resId);
  }

  ResValue getValue(String pkg, String type, String name) {
    return getPackageByName(
      pkg,
    ).getType(type).getResSpec(name).getDefaultResource().getValue();
  }

  void addDynamicRefPackage(int pkgId, String pkgName) {
    // Implementation of addDynamicRefPackage method
  }

  int getDynamicRefPackageId(String pkgName) {
    // Implementation of getDynamicRefPackageId method
    return 0;
  }

  String? resolveReference(int resId) {
    try {
      if (resId == 0) {
        return null;
      }

      final resIdObj = ResID(resId);
      final packageId = resIdObj.getPackageId();

      // Try to get the package
      ResPackage? pkg;
      try {
        pkg = getPackageById(packageId);
      } catch (e) {
        return null;
      }

      // Try to get the resource spec
      try {
        final spec = pkg.getResSpec(resIdObj);
        final typeSpec = spec.getType();

        // Format: @type/name
        final result = '@${typeSpec.getName()}/${spec.getName()}';
        return result;
      } catch (e) {
        return null;
      }
    } catch (e) {
      return null;
    }
  }
}
