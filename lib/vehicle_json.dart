import 'vehicle.dart';

Vehicle vehicleFromJson(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Invalid vehicle');
  }
  final id = value['id'];
  final name = value['name'];
  final model = value['model'];
  final lat = value['latitude'];
  final lng = value['longitude'];
  final battery = value['battery'];
  final revision = value['revision'];
  final refrigeration = value['refrigerationOn'];
  final updated = value['updatedAt'];
  final status = VehicleStatus.values.where((s) => s.name == value['status']);
  if (id is! String ||
      id.isEmpty ||
      name is! String ||
      model is! String ||
      lat is! num ||
      !lat.isFinite ||
      lat < -90 ||
      lat > 90 ||
      lng is! num ||
      !lng.isFinite ||
      lng < -180 ||
      lng > 180 ||
      battery is! int ||
      battery < 0 ||
      battery > 100 ||
      revision is! int ||
      revision < 0 ||
      refrigeration is! bool ||
      updated is! String ||
      DateTime.tryParse(updated) == null ||
      status.isEmpty) {
    throw const FormatException('Invalid vehicle fields');
  }
  return Vehicle(
    id: id,
    name: name,
    model: model,
    latitude: lat.toDouble(),
    longitude: lng.toDouble(),
    status: status.single,
    battery: battery,
    updatedAt: DateTime.parse(updated),
    refrigerationOn: refrigeration,
    revision: revision,
  );
}
