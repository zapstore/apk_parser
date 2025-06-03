library brut_androlib_res_data;

import 'res_config_flags.dart';
import 'res_res_spec.dart';
import 'res_resource.dart';

class ResType {
  final ResConfigFlags _flags;
  final Map<ResResSpec, ResResource> _resources = {};

  ResType(this._flags);

  ResResource getResource(ResResSpec spec) {
    final res = _resources[spec];
    if (res == null) {
      throw Exception('Undefined resource: spec=$spec, config=$this');
    }
    return res;
  }

  ResConfigFlags getFlags() => _flags;

  void addResource(ResResource res, {bool overwrite = false}) {
    final spec = res.getResSpec();
    if (_resources.containsKey(spec) && !overwrite) {
      throw Exception('Multiple resources: spec=$spec, config=$this');
    }
    _resources[spec] = res;
  }

  @override
  String toString() => _flags.toString();
}
