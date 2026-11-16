import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'vehicle.dart';
import 'vehicle_api.dart';

String newRequestId() =>
    base64UrlEncode(List.generate(24, (_) => Random.secure().nextInt(256)));

class RemoteVehicleStore extends VehicleStore {
  RemoteVehicleStore(
    this.api, {
    String Function()? requestId,
    this.pollInterval = const Duration(seconds: 5),
  }) : _requestId = requestId ?? newRequestId;
  final VehicleApi api;
  final String Function() _requestId;
  final Duration pollInterval;
  final List<Vehicle> _vehicles = [];
  final Map<String, String> _unresolved = {};
  final Map<String, CommandResult> results = {};
  final Set<String> _checking = {};
  final Set<String> _sending = {};
  Timer? _timer;
  bool _disposed = false;
  bool loading = false;
  String? error;
  int _epoch = 0;
  Future<void>? _refresh;
  @override
  List<Vehicle> get vehicles => List.unmodifiable(_vehicles);
  @override
  Vehicle? vehicle(String id) {
    for (final v in _vehicles) {
      if (v.id == id) return v;
    }
    return null;
  }

  @override
  bool isPending(String id) => _unresolved.containsKey(id);
  String? requestIdFor(String id) => _unresolved[id];
  bool isSending(String id) => _sending.contains(id);
  bool isChecking(String id) => _checking.contains(id);
  void changed() {
    if (!_disposed) notifyListeners();
  }

  void accept(Vehicle incoming) {
    final index = _vehicles.indexWhere((v) => v.id == incoming.id);
    if (index < 0) {
      _vehicles.add(incoming);
    } else if (incoming.revision > _vehicles[index].revision) {
      _vehicles[index] = incoming;
    }
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    return _refresh ??= _load().whenComplete(() => _refresh = null);
  }

  Future<void> _load() async {
    final epoch = _epoch;
    loading = true;
    changed();
    try {
      final incoming = await api.list();
      if (_disposed || epoch != _epoch) return;
      // The mock fleet has stable IDs. Never derive or simulate remote values.
      for (final v in incoming) {
        accept(v);
      }
      error = null;
    } catch (e) {
      if (!_disposed && epoch == _epoch) error = '서버 조회 실패: $e';
    } finally {
      if (!_disposed) {
        loading = false;
        changed();
      }
    }
  }

  Future<void> loadDetail(String id) async {
    final epoch = _epoch;
    try {
      final incoming = await api.detail(id);
      if (_disposed || epoch != _epoch) return;
      accept(incoming);
      error = null;
    } catch (e) {
      if (!_disposed && epoch == _epoch) error = '상세 조회 실패: $e';
    }
    changed();
  }

  @override
  void start() {
    if (_disposed || _timer != null) return;
    unawaited(refresh());
    _timer = Timer.periodic(pollInterval, (_) => unawaited(refresh()));
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
    _epoch++;
  }

  @override
  Future<CommandResult> setRefrigeration(
    String id,
    bool enabled,
    CommandScenario scenario,
  ) async {
    if (_disposed) return CommandResult.failure;
    if (isPending(id)) return CommandResult.busy;
    final current = vehicle(id);
    if (current == null || current.status == VehicleStatus.offline) {
      return CommandResult.failure;
    }
    final requestId = _requestId();
    _unresolved[id] = requestId;
    _sending.add(id);
    results.remove(id);
    changed();
    var result = CommandResult.unknown;
    try {
      result = await api.command(requestId, id, enabled, scenario);
    } on ApiException catch (e) {
      // These responses explicitly reject admission; 5xx/transport errors do not.
      if ([400, 409, 422].contains(e.status)) result = CommandResult.failure;
    } catch (_) {
      /* Delivery or completion is unknown. Never automatically POST again. */
    }
    if (_disposed) return result;
    _sending.remove(id);
    results[id] = result;
    if (result != CommandResult.unknown) _unresolved.remove(id);
    changed();
    if (result == CommandResult.success) await refresh();
    return result;
  }

  Future<CommandResult> checkCommand(String id) async {
    final requestId = _unresolved[id];
    if (_disposed ||
        requestId == null ||
        _sending.contains(id) ||
        !_checking.add(id)) {
      return CommandResult.busy;
    }
    changed();
    var result = CommandResult.unknown;
    try {
      result = await api.commandStatus(requestId);
    } catch (_) {
      /* Keep blocked, including 404 after server restart. */
    }
    if (_disposed) return result;
    _checking.remove(id);
    results[id] = result;
    if (result != CommandResult.unknown) _unresolved.remove(id);
    changed();
    if (result == CommandResult.success) await refresh();
    return result;
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    api.client.close();
    super.dispose();
  }
}
