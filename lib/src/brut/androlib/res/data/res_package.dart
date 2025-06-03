library brut_androlib_res_data;

import 'res_table.dart';
import 'res_id.dart';
import 'res_res_spec.dart';
import 'res_config_flags.dart';
import 'res_type.dart';
import 'res_type_spec.dart';
import 'value/res_value.dart';

class ResPackage {
  final ResTable _resTable;
  final int _id;
  final String _name;
  final Map<ResID, ResResSpec> _resSpecs = {};
  final Map<ResConfigFlags, ResType> _configs = {};
  final Map<String, ResTypeSpec> _types = {};
  final Set<ResID> _synthesizedRes = {};

  ResPackage(this._resTable, this._id, this._name);

  ResTable getResTable() => _resTable;

  int getId() => _id;

  String getName() => _name;

  List<ResResSpec> listResSpecs() {
    return _resSpecs.values.toList();
  }

  bool hasResSpec(ResID resId) {
    return _resSpecs.containsKey(resId);
  }

  ResResSpec getResSpec(ResID resId) {
    final spec = _resSpecs[resId];
    if (spec == null) {
      throw Exception('Undefined resource spec: $resId');
    }
    return spec;
  }

  int getResSpecCount() {
    return _resSpecs.length;
  }

  ResType getOrCreateConfig(ResConfigFlags flags) {
    return _configs.putIfAbsent(flags, () => ResType(flags));
  }

  ResTypeSpec getType(String typeName) {
    final type = _types[typeName];
    if (type == null) {
      throw Exception('Undefined type: $typeName');
    }
    return type;
  }

  void addResSpec(ResResSpec spec) {
    if (_resSpecs.containsKey(spec.getId())) {
      throw Exception('Multiple resource specs: $spec');
    }
    _resSpecs[spec.getId()] = spec;
  }

  void addType(ResTypeSpec type) {
    if (_types.containsKey(type.getName())) {
      print('Warning: Multiple types detected! $type ignored!');
    } else {
      _types[type.getName()] = type;
    }
  }

  bool isSynthesized(ResID resId) {
    return _synthesizedRes.contains(resId);
  }

  void addSynthesizedRes(ResID resId) {
    _synthesizedRes.add(resId);
  }

  // TODO: Add getValueFactory() when ResValueFactory is implemented
}
