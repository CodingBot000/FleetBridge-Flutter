import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'vehicle.dart';
import 'vehicle_json.dart';

class ApiException implements Exception {
  const ApiException(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

class VehicleApi {
  VehicleApi({
    required this.baseUrl,
    required this.client,
    this.timeout = const Duration(seconds: 2),
  }) {
    if (!['http', 'https'].contains(baseUrl.scheme) ||
        baseUrl.host.isEmpty ||
        baseUrl.hasQuery ||
        baseUrl.hasFragment) {
      throw ArgumentError('API URL must be an HTTP origin');
    }
  }
  final Uri baseUrl;
  final http.Client client;
  final Duration timeout;
  CommandResult commandResult(Object? data, String requestId) {
    if (data is! Map<String, dynamic> || data['requestId'] != requestId) {
      throw const FormatException('Mismatched command response');
    }
    return switch (data['result']) {
      'success' => CommandResult.success,
      'failure' => CommandResult.failure,
      'pending' => CommandResult.unknown,
      _ => throw const FormatException('Invalid command result'),
    };
  }

  Future<CommandResult> command(
    String requestId,
    String vehicleId,
    bool enabled,
    CommandScenario scenario,
  ) async {
    final response = await client
        .post(
          baseUrl.resolve('/commands'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'requestId': requestId,
            'vehicleId': vehicleId,
            'enabled': enabled,
            'scenario': scenario.name,
          }),
        )
        .timeout(timeout);
    if (response.statusCode != 200) {
      throw ApiException('HTTP ${response.statusCode}', response.statusCode);
    }
    return commandResult(
      jsonDecode(utf8.decode(response.bodyBytes)),
      requestId,
    );
  }

  Future<CommandResult> commandStatus(String requestId) async => commandResult(
    await get('/commands/${Uri.encodeComponent(requestId)}'),
    requestId,
  );
  Future<Object?> get(String path) async {
    final response = await client.get(baseUrl.resolve(path)).timeout(timeout);
    if (response.statusCode != 200) {
      throw ApiException('HTTP ${response.statusCode}', response.statusCode);
    }
    return jsonDecode(utf8.decode(response.bodyBytes));
  }

  Future<List<Vehicle>> list() async {
    final data = await get('/vehicles');
    if (data is! List) throw const FormatException('Invalid vehicle list');
    final vehicles = data.map(vehicleFromJson).toList();
    if (vehicles.map((v) => v.id).toSet().length != vehicles.length) {
      throw const FormatException('Duplicate vehicle IDs');
    }
    return vehicles;
  }

  Future<Vehicle> detail(String id) async {
    final v = vehicleFromJson(
      await get('/vehicles/${Uri.encodeComponent(id)}'),
    );
    if (v.id != id) throw const FormatException('Mismatched vehicle ID');
    return v;
  }
}
