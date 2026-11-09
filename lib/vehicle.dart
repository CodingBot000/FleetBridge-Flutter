import 'dart:async';

import 'package:flutter/foundation.dart';

enum VehicleStatus { driving, idle, offline }

enum CommandScenario { success, failure, timeout }

enum CommandResult { success, failure, timeout, busy }

@immutable
class Vehicle {
  const Vehicle({
    required this.id,
    required this.name,
    required this.model,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.battery,
    required this.updatedAt,
    this.refrigerationOn = false,
    this.revision = 0,
  });
  final String id, name, model;
  final double latitude, longitude;
  final VehicleStatus status;
  final int battery, revision;
  final DateTime updatedAt;
  final bool refrigerationOn;
  Vehicle copyWith({
    double? latitude,
    double? longitude,
    VehicleStatus? status,
    int? battery,
    DateTime? updatedAt,
    bool? refrigerationOn,
    int? revision,
  }) => Vehicle(
    id: id,
    name: name,
    model: model,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    status: status ?? this.status,
    battery: battery ?? this.battery,
    updatedAt: updatedAt ?? this.updatedAt,
    refrigerationOn: refrigerationOn ?? this.refrigerationOn,
    revision: revision ?? this.revision,
  );
}

class VehicleRepository extends ChangeNotifier {
  VehicleRepository({
    DateTime Function()? clock,
    Future<void> Function(Duration)? delay,
  }) : _clock = clock ?? DateTime.now,
       _delay = delay ?? Future<void>.delayed {
    final now = _clock();
    _vehicles = List.generate(10, (i) {
      final n = i + 1;
      return Vehicle(
        id: 'vehicle-$n',
        name: '차량 $n',
        model: 'Fleet Model $n',
        latitude: 37.55 + n * .003,
        longitude: 126.96 + n * .003,
        status: VehicleStatus.values[i % 3],
        battery: 95 - n * 3,
        updatedAt: now,
      );
    });
  }
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _delay;
  late List<Vehicle> _vehicles;
  final Set<String> _pending = {};
  Timer? _timer;
  bool _disposed = false;
  List<Vehicle> get vehicles => List.unmodifiable(_vehicles);
  bool get isRunning => _timer != null;
  bool isPending(String id) => _pending.contains(id);
  Vehicle? vehicle(String id) {
    for (final v in _vehicles) {
      if (v.id == id) return v;
    }
    return null;
  }

  void start() {
    if (!_disposed) {
      _timer ??= Timer.periodic(const Duration(seconds: 5), (_) => advance());
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  bool apply(Vehicle incoming) {
    final i = _vehicles.indexWhere((v) => v.id == incoming.id);
    if (i < 0 || incoming.revision <= _vehicles[i].revision || _disposed) {
      return false;
    }
    _vehicles[i] = incoming;
    notifyListeners();
    return true;
  }

  void advance() {
    if (_disposed) return;
    final now = _clock();
    _vehicles = _vehicles.map((v) {
      if (v.status == VehicleStatus.offline) return v;
      final revision = v.revision + 1;
      return v.copyWith(
        latitude: v.latitude + (v.status == VehicleStatus.driving ? .0001 : 0),
        longitude:
            v.longitude + (v.status == VehicleStatus.driving ? .0001 : 0),
        updatedAt: now,
        revision: revision,
        status: revision % 6 == 0
            ? (v.status == VehicleStatus.driving
                  ? VehicleStatus.idle
                  : VehicleStatus.driving)
            : v.status,
        battery: revision % 12 == 0 && v.battery > 0
            ? v.battery - 1
            : v.battery,
      );
    }).toList();
    notifyListeners();
  }

  Future<CommandResult> setRefrigeration(
    String id,
    bool enabled,
    CommandScenario scenario,
  ) async {
    final current = vehicle(id);
    if (_disposed ||
        current == null ||
        current.status == VehicleStatus.offline) {
      return CommandResult.failure;
    }
    if (!_pending.add(id)) return CommandResult.busy;
    notifyListeners();
    try {
      await _delay(
        Duration(seconds: scenario == CommandScenario.timeout ? 3 : 1),
      );
      if (_disposed) return CommandResult.failure;
      final latest = vehicle(id);
      if (scenario == CommandScenario.timeout) return CommandResult.timeout;
      if (scenario == CommandScenario.failure ||
          latest == null ||
          latest.status == VehicleStatus.offline) {
        return CommandResult.failure;
      }
      apply(
        latest.copyWith(
          refrigerationOn: enabled,
          revision: latest.revision + 1,
        ),
      );
      return CommandResult.success;
    } finally {
      _pending.remove(id);
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }
}
