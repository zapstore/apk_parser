library brut_androlib_res_data;

import 'res_res_spec.dart';

class ResTypeSpec {
  static const String RES_TYPE_NAME_ARRAY = 'array';
  static const String RES_TYPE_NAME_ATTR = 'attr';
  static const String RES_TYPE_NAME_ATTR_PRIVATE = '^attr-private';
  static const String RES_TYPE_NAME_PLURALS = 'plurals';
  static const String RES_TYPE_NAME_STRING = 'string';
  static const String RES_TYPE_NAME_STYLES = 'style';

  final String _name;
  final int _id;
  final Map<String, ResResSpec> _resSpecs = {};

  ResTypeSpec(this._name, this._id);

  String getName() => _name;

  int getId() => _id;

  bool isString() => _name == RES_TYPE_NAME_STRING;

  ResResSpec getResSpec(String name) {
    final spec = getResSpecUnsafe(name);
    if (spec == null) {
      throw Exception('Undefined resource spec: $_name/$name');
    }
    return spec;
  }

  ResResSpec? getResSpecUnsafe(String name) {
    return _resSpecs[name];
  }

  void addResSpec(ResResSpec spec) {
    if (_resSpecs.containsKey(spec.getName())) {
      throw Exception('Multiple res specs: $_name/${spec.getName()}');
    }
    _resSpecs[spec.getName()] = spec;
  }

  @override
  String toString() => _name;
}
