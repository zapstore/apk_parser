library brut_androlib_res_data;

class ResID {
  final int id;

  ResID(this.id);

  int getPackageId() {
    return (id >> 24) & 0xFF;
  }

  int getTypeId() {
    return (id >> 16) & 0xFF;
  }

  int getEntryId() {
    return id & 0xFFFF;
  }

  @override
  String toString() {
    return '0x${id.toRadixString(16).padLeft(8, '0')}';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResID && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
