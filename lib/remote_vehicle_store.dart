import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'vehicle.dart';
import 'vehicle_api.dart';

String newRequestId() =>
    base64UrlEncode(List.generate(24, (_) => Random.secure().nextInt(256)));

class _ReadOperation {
  final done = Completer<void>();
}

typedef _Command = ({
  String requestId,
  bool enabled,
  CommandScenario scenario,
  int baselineRevision,
});

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
  final Map<String, _Command> _unresolved = {};
  final Map<String, CommandResult> _results = {};
  Map<String, CommandResult> get results => Map.unmodifiable(_results);
  final Set<String> _checking = {};
  final Set<String> _sending = {};
  final Set<String> _syncing = {};
  bool isSynchronizing(String id) => _syncing.contains(id);
  Timer? _timer;
  bool _disposed = false;
  _ReadOperation? _listRead;
  final Map<String, _ReadOperation> _detailReads = {};
  String? _listError;
  final Map<String, String> _detailErrors = {};
  bool get loading => _listRead != null;
  String? get error => _listError;
  bool loadingFor(String id) => loading || _detailReads.containsKey(id);
  String? errorFor(String id) => _detailErrors[id] ?? _listError;
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
  String? requestIdFor(String id) => _unresolved[id]?.requestId;
  bool isSending(String id) => _sending.contains(id);
  bool isChecking(String id) => _checking.contains(id);
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _accept(Vehicle incoming) {
    final index = _vehicles.indexWhere((v) => v.id == incoming.id);
    if (index < 0) {
      _vehicles.add(incoming);
    } else if (incoming.revision > _vehicles[index].revision) {
      _vehicles[index] = incoming;
    }
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    final active = _listRead;
    if (active != null) return active.done.future;
    final operation = _ReadOperation();
    // Register before notifying: listeners can synchronously request refresh.
    _listRead = operation;
    unawaited(_load(operation));
    return operation.done.future;
  }

  Future<void> _load(_ReadOperation operation) async {
    final confirmations = {
      for (final id in _syncing) id: _unresolved[id]?.requestId,
    };
    try {
      _changed();
      if (_disposed || !identical(_listRead, operation)) return;
      final incoming = await api.list();
      if (_disposed || !identical(_listRead, operation)) return;
      for (final v in incoming) {
        _accept(v);
      }
      for (final v in incoming) {
        final command = _unresolved[v.id];
        if (command != null &&
            _syncing.contains(v.id) &&
            confirmations[v.id] == command.requestId &&
            v.revision > command.baselineRevision &&
            v.revision >= vehicle(v.id)!.revision) {
          _syncing.remove(v.id);
          _unresolved.remove(v.id);
        }
      }
      _listError = null;
    } catch (e) {
      if (!_disposed && identical(_listRead, operation)) {
        _listError = '서버 조회 실패: $e';
      }
    } finally {
      if (!_disposed && identical(_listRead, operation)) {
        _listRead = null;
        _changed();
      }
      operation.done.complete();
    }
  }

  Future<void> loadDetail(String id) {
    if (_disposed) return Future.value();
    final active = _detailReads[id];
    if (active != null) return active.done.future;
    final operation = _ReadOperation();
    _detailReads[id] = operation;
    unawaited(_loadDetail(id, operation));
    return operation.done.future;
  }

  Future<void> _loadDetail(String id, _ReadOperation operation) async {
    try {
      _changed();
      if (_disposed || !identical(_detailReads[id], operation)) return;
      final incoming = await api.detail(id);
      if (_disposed || !identical(_detailReads[id], operation)) return;
      _accept(incoming);
      _detailErrors.remove(id);
    } catch (e) {
      if (!_disposed && identical(_detailReads[id], operation)) {
        _detailErrors[id] = '상세 조회 실패: $e';
      }
    } finally {
      if (!_disposed && identical(_detailReads[id], operation)) {
        _detailReads.remove(id);
        _changed();
      }
      operation.done.complete();
    }
  }

  @override
  void start() {
    if (_disposed || _timer != null) return;
    _timer = Timer.periodic(pollInterval, (_) => unawaited(refresh()));
    unawaited(refresh());
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
    _listRead = null;
    _detailReads.clear();
    _changed();
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
    _unresolved[id] = (
      requestId: requestId,
      enabled: enabled,
      scenario: scenario,
      baselineRevision: current.revision,
    );
    _sending.add(id);
    _results.remove(id);
    _changed();
    if (_disposed) return CommandResult.unknown;
    var result = CommandResult.unknown;
    try {
      result = await api.command(requestId, id, enabled, scenario);
    } on ApiException catch (e) {
      // These responses explicitly reject admission; 5xx/transport errors do not.
      if (e.rejected) result = CommandResult.failure;
    } catch (_) {
      /* Delivery or completion is unknown. Never automatically POST again. */
    }
    if (_disposed) return result;
    _sending.remove(id);
    _results[id] = result;
    if (result == CommandResult.success) {
      _syncing.add(id);
    } else if (result != CommandResult.unknown) {
      _unresolved.remove(id);
    }
    _changed();
    if (result == CommandResult.success) await _refreshAfterCommand();
    return result;
  }

  Future<CommandResult> checkCommand(String id) async {
    final command = _unresolved[id];
    if (_disposed ||
        command == null ||
        _sending.contains(id) ||
        _syncing.contains(id) ||
        !_checking.add(id)) {
      return CommandResult.busy;
    }
    _changed();
    if (_disposed) return CommandResult.unknown;
    var result = CommandResult.unknown;
    try {
      result = await api.commandStatus(
        command.requestId,
        vehicleId: id,
        enabled: command.enabled,
        scenario: command.scenario,
      );
    } catch (_) {
      /* Keep blocked, including 404 after server restart. */
    }
    if (_disposed) return result;
    _checking.remove(id);
    _results[id] = result;
    if (result == CommandResult.success) {
      _syncing.add(id);
    } else if (result != CommandResult.unknown) {
      _unresolved.remove(id);
    }
    _changed();
    if (result == CommandResult.success) await _refreshAfterCommand();
    return result;
  }

  Future<void> _refreshAfterCommand() {
    if (_disposed) return Future.value();
    // A read started before completion cannot confirm the command effect.
    _listRead = null;
    return refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    api.client.close();
    super.dispose();
  }
}
