library brut_androlib_res_data;

import 'res_type.dart';
import 'res_res_spec.dart';
import 'value/res_value.dart';

class ResResource {
  final ResType _config;
  final ResResSpec _resSpec;
  final ResValue _value;

  ResResource(this._config, this._resSpec, this._value);

  String getFilePath() {
    final qualifiers = _config.getFlags().getQualifiers();
    final typeName = _resSpec.getType().getName();

    // Type name + qualifiers form the directory name
    // If there are qualifiers, they're already prefixed with "-"
    return '$typeName$qualifiers/${_resSpec.getName()}';
  }

  ResType getConfig() => _config;

  ResResSpec getResSpec() => _resSpec;

  ResValue getValue() => _value;

  void replace(ResValue value) {
    final res = ResResource(_config, _resSpec, value);
    _config.addResource(res, overwrite: true);
    _resSpec.addResource(res);
  }

  @override
  String toString() => getFilePath();
}
