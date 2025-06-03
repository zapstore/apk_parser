library;

import 'res_id.dart';
import 'res_type_spec.dart';
import 'res_resource.dart';
import 'res_config_flags.dart';

class ResResSpec {
  final ResID _id;
  final String _name;
  final ResTypeSpec _type;
  final Map<ResConfigFlags, ResResource> _resources = {};

  ResResSpec(this._id, this._name, this._type);

  ResID getId() => _id;

  String getName() => _name;

  ResTypeSpec getType() => _type;

  ResResource getDefaultResource() {
    // Return the default resource (usually the one without qualifiers)
    // For now, return the first one
    if (_resources.isEmpty) {
      throw Exception('No resources available for spec: $_name');
    }
    return _resources.values.first;
  }

  List<ResResource> listResources() {
    return _resources.values.toList();
  }

  void addResource(ResResource resource) {
    final config = resource.getConfig();
    if (_resources.containsKey(config.getFlags())) {
      throw Exception(
        'Multiple resources for spec=$_name, config=${config.getFlags()}',
      );
    }
    _resources[config.getFlags()] = resource;
  }

  @override
  String toString() => '$_type/$_name';
}
