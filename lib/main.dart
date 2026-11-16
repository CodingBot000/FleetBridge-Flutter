import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'vehicle.dart';
import 'remote_vehicle_store.dart';
import 'vehicle_api.dart';

import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

final repositoryProvider = Provider<VehicleStore>((ref) {
  const mode = String.fromEnvironment('FLEET_MODE', defaultValue: 'local');
  if (!['local', 'remote'].contains(mode)) {
    throw StateError('Invalid FLEET_MODE');
  }
  final VehicleStore repository;
  if (mode == 'remote') {
    const configured = String.fromEnvironment('FLEET_API_URL');
    final url = configured.isNotEmpty
        ? configured
        : (defaultTargetPlatform == TargetPlatform.android
              ? 'http://10.0.2.2:8080'
              : 'http://127.0.0.1:8080');
    repository = RemoteVehicleStore(
      VehicleApi(baseUrl: Uri.parse(url), client: http.Client()),
    );
  } else {
    repository = VehicleRepository();
  }
  repository.start();
  ref.onDispose(repository.dispose);
  return repository;
});
void main() => runApp(const ProviderScope(child: FleetApp()));

class FleetApp extends ConsumerStatefulWidget {
  const FleetApp({super.key, this.mapEnabled = true});
  final bool mapEnabled;
  @override
  ConsumerState<FleetApp> createState() => _FleetAppState();
}

class _FleetAppState extends ConsumerState<FleetApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final repo = ref.read(repositoryProvider);
    if (state == AppLifecycleState.resumed) {
      repo.start();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      repo.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'FleetBridge',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      useMaterial3: true,
    ),
    home: VehicleList(mapEnabled: widget.mapEnabled),
  );
}

String statusLabel(VehicleStatus s) => switch (s) {
  VehicleStatus.driving => '운행 중',
  VehicleStatus.idle => '대기',
  VehicleStatus.offline => '오프라인',
};

class VehicleList extends ConsumerStatefulWidget {
  const VehicleList({super.key, required this.mapEnabled});
  final bool mapEnabled;
  @override
  ConsumerState<VehicleList> createState() => _VehicleListState();
}

class _VehicleListState extends ConsumerState<VehicleList> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('차량 목록')),
      body: Column(
        children: [
          if (repo is RemoteVehicleStore)
            ListenableBuilder(
              listenable: repo,
              builder: (context, _) => RemoteStatus(store: repo),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                labelText: '차량 ID 검색',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) =>
                  setState(() => query = value.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: repo,
              builder: (context, _) {
                final vehicles = repo.vehicles
                    .where((v) => v.id.toLowerCase().contains(query))
                    .toList();
                return ListView.builder(
                  itemCount: vehicles.length,
                  itemBuilder: (context, i) {
                    final v = vehicles[i];
                    return ListTile(
                      key: ValueKey(v.id),
                      title: Text(v.name),
                      subtitle: Text(
                        '${v.id} · ${v.model} · ${statusLabel(v.status)} · 배터리 ${v.battery}%',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => VehicleDetail(
                            id: v.id,
                            mapEnabled: widget.mapEnabled,
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class VehicleDetail extends ConsumerStatefulWidget {
  const VehicleDetail({
    super.key,
    required this.id,
    this.mapEnabled = true,
    this.tileProviderFactory,
  });
  final String id;
  final bool mapEnabled;
  final TileProvider Function()? tileProviderFactory;
  @override
  ConsumerState<VehicleDetail> createState() => _VehicleDetailState();
}

class _VehicleDetailState extends ConsumerState<VehicleDetail> {
  CommandScenario scenario = CommandScenario.success;
  CommandResult? result;
  bool mapFailed = false;
  int mapAttempt = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final repo = ref.read(repositoryProvider);
      if (repo is RemoteVehicleStore) repo.loadDetail(widget.id);
    });
  }

  Future<void> send(VehicleStore repo, Vehicle v) async {
    setState(() => result = null);
    final outcome = await repo.setRefrigeration(
      v.id,
      !v.refrigerationOn,
      scenario,
    );
    if (mounted) setState(() => result = outcome);
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(repositoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('차량 상세')),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) {
          final v = repo.vehicle(widget.id);
          if (v == null) {
            return Center(
              child: Text(
                repo is RemoteVehicleStore && repo.loading
                    ? '서버 조회 중…'
                    : '차량 정보를 찾을 수 없습니다.',
              ),
            );
          }
          final pending = repo.isPending(v.id);
          final remote = repo is RemoteVehicleStore ? repo : null;
          final displayedResult = remote == null
              ? result
              : remote.results[v.id];
          final attempt = mapAttempt;
          final stale =
              DateTime.now().difference(v.updatedAt) >
              const Duration(seconds: 15);
          return ListView(
            key: const ValueKey('vehicle-detail-scroll'),
            padding: const EdgeInsets.all(20),
            children: [
              if (remote != null) RemoteStatus(store: remote),
              Text(v.name, style: Theme.of(context).textTheme.headlineMedium),
              Text(v.model),
              Text(v.id),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                children: [
                  Chip(label: Text(statusLabel(v.status))),
                  Chip(label: Text('배터리 ${v.battery}%')),
                  if (v.status == VehicleStatus.offline)
                    const Chip(label: Text('연결 끊김 (모의)'))
                  else if (stale)
                    const Chip(label: Text('갱신 지연')),
                ],
              ),
              Text('마지막 갱신 ${v.updatedAt.toLocal()}'),
              const SizedBox(height: 16),
              SizedBox(
                height: 300,
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(v.latitude, v.longitude),
                    initialZoom: 13,
                  ),
                  children: [
                    if (widget.mapEnabled)
                      TileLayer(
                        key: ValueKey(mapAttempt),
                        tileProvider: widget.tileProviderFactory?.call(),
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName:
                            'com.codingbot000.fleetbridge_flutter',
                        errorTileCallback: (tile, error, stack) {
                          if (!mapFailed) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted &&
                                  !mapFailed &&
                                  attempt == mapAttempt) {
                                setState(() => mapFailed = true);
                              }
                            });
                          }
                        },
                      ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(v.latitude, v.longitude),
                          child: const Icon(
                            Icons.location_on,
                            color: Colors.red,
                            size: 36,
                          ),
                        ),
                      ],
                    ),
                    SimpleAttributionWidget(
                      source: const Text('OpenStreetMap contributors'),
                      onTap: () => launchUrl(
                        Uri.parse('https://www.openstreetmap.org/copyright'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ],
                ),
              ),
              if (mapFailed) ...[
                const Text('지도를 불러올 수 없습니다. 네트워크 연결을 확인해 주세요.'),
                TextButton(
                  onPressed: () => setState(() {
                    mapFailed = false;
                    mapAttempt++;
                  }),
                  child: const Text('지도 다시 시도'),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                '냉동기 원격 명령 (시뮬레이션)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text('실제 차량에는 명령이 전송되지 않습니다.'),
              Text('현재: ${v.refrigerationOn ? '켜짐' : '꺼짐'}'),
              DropdownButton<CommandScenario>(
                value: scenario,
                onChanged: pending
                    ? null
                    : (value) {
                        if (value != null) setState(() => scenario = value);
                      },
                items: const [
                  DropdownMenuItem(
                    value: CommandScenario.success,
                    child: Text('성공 시나리오'),
                  ),
                  DropdownMenuItem(
                    value: CommandScenario.failure,
                    child: Text('실패 시나리오'),
                  ),
                  DropdownMenuItem(
                    value: CommandScenario.timeout,
                    child: Text('시간 초과 시나리오'),
                  ),
                ],
              ),
              FilledButton(
                onPressed: pending || v.status == VehicleStatus.offline
                    ? null
                    : () => send(repo, v),
                child: Text(
                  pending
                      ? (remote != null && !remote.isSending(v.id)
                            ? '결과 확인 필요'
                            : '처리 중…')
                      : '냉동기 전환',
                ),
              ),
              if (remote != null && pending && !remote.isSending(v.id)) ...[
                Text('요청 ID: ${remote.requestIdFor(v.id)}'),
                TextButton(
                  onPressed: remote.isChecking(v.id)
                      ? null
                      : () => remote.checkCommand(v.id),
                  child: const Text('명령 결과 조회'),
                ),
              ],
              if (displayedResult != null)
                Text(switch (displayedResult) {
                  CommandResult.success => '명령 성공',
                  CommandResult.failure => '명령 실패',
                  CommandResult.timeout => '응답 시간 초과',
                  CommandResult.busy => '명령 처리 중',
                  CommandResult.unknown => '결과 확인 필요 — 서버 처리 여부가 불명확합니다.',
                }),
            ],
          );
        },
      ),
    );
  }
}

class RemoteStatus extends StatelessWidget {
  const RemoteStatus({super.key, required this.store});
  final RemoteVehicleStore store;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Column(
      children: [
        Text(store.loading ? 'Remote · 서버 조회 중…' : 'Remote · Mock API'),
        if (store.error != null) Text(store.error!),
        if (store.error != null) const Text('표시 중인 값은 마지막으로 받은 데이터입니다.'),
        TextButton(
          onPressed: store.loading ? null : store.refresh,
          child: const Text('서버 새로고침'),
        ),
      ],
    ),
  );
}
