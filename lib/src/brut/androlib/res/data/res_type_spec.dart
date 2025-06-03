library;

import 'res_res_spec.dart';

class ResTypeSpec {
  static const String kResTypeNameArray = "array";
  static const String kResTypeNameAttr = "attr";
  static const String kResTypeNameAttrPrivate = "^attr-private";
  static const String kResTypeNamePlurals = "plurals";
  static const String kResTypeNameString = "string";
  static const String kResTypeNameStyles = "style";

  final String _name;
  final int _id;
  final Map<String, ResResSpec> _resSpecs = {};

  ResTypeSpec(this._name, this._id);

  String getName() => _name;

  int getId() => _id;

  bool isString() => _name == kResTypeNameString;

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
