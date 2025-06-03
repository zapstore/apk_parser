library;

abstract class ResValue {
  // Base class for all resource values
}

abstract class ResScalarValue extends ResValue {
  // Base class for scalar values
}

abstract class ResIntBasedValue extends ResScalarValue {
  int getRawIntValue();
}

class ResStringValue extends ResIntBasedValue {
  final String value;
  final int rawValue;

  ResStringValue(this.value, this.rawValue);

  @override
  int getRawIntValue() => rawValue;

  @override
  String toString() => value;
}

class ResReferenceValue extends ResIntBasedValue {
  final int referenceId;
  final String? referenceString; // Optional resolved reference
  // TODO: Add package reference when circular dependencies are resolved

  ResReferenceValue(this.referenceId, [this.referenceString]);

  @override
  int getRawIntValue() => referenceId;

  @override
  String toString() {
    if (referenceString != null) {
      return referenceString!;
    }
    // Format as @0x7f050001 or similar
    return '@0x${referenceId.toRadixString(16).padLeft(8, '0')}';
  }
}

class ResIntValue extends ResIntBasedValue {
  final int value;

  ResIntValue(this.value);

  @override
  int getRawIntValue() => value;

  @override
  String toString() => value.toString();
}

class ResBoolValue extends ResIntBasedValue {
  final bool value;

  ResBoolValue(this.value);

  @override
  int getRawIntValue() => value ? 1 : 0;

  @override
  String toString() => value.toString();
}

class ResFileValue extends ResIntBasedValue {
  final String path;
  final int rawValue;

  ResFileValue(this.path, this.rawValue);

  @override
  int getRawIntValue() => rawValue;

  @override
  String toString() => path;
}

// Complex value types
class ResBagValue extends ResValue {
  final ResReferenceValue? parent;

  ResBagValue(this.parent);
}

class ResArrayValue extends ResBagValue {
  final List<ResScalarValue> items;

  ResArrayValue(super.parent, this.items);
}

class ResStyleValue extends ResBagValue {
  final Map<int, ResScalarValue> items;

  ResStyleValue(super.parent, this.items);
}

class ResPluralsValue extends ResBagValue {
  final Map<String, ResScalarValue> items;

  ResPluralsValue(super.parent, this.items);
}
