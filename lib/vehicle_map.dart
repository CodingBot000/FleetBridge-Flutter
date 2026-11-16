import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'vehicle.dart';

// The map element owns one provider for exactly the TileLayer lifetime. A lazy
// detail list may dispose/recreate the whole map while the detail route survives.
class VehicleMap extends StatefulWidget {
  const VehicleMap({
    super.key,
    required this.vehicle,
    required this.enabled,
    required this.onError,
    this.tileProviderFactory,
  });
  final Vehicle vehicle;
  final bool enabled;
  final VoidCallback onError;
  final TileProvider Function()? tileProviderFactory;
  @override
  State<VehicleMap> createState() => _VehicleMapState();
}

class _VehicleMapState extends State<VehicleMap> {
  late final TileProvider provider =
      widget.tileProviderFactory?.call() ??
      NetworkTileProvider(
        headers: {
          'User-Agent': 'FleetBridgeFlutter/1.1 (+https://github.com/CodingBot000/FleetBridge-Flutter)',
        },
      );
  @override
  Widget build(BuildContext context) => FlutterMap(
    options: MapOptions(
      initialCenter: LatLng(widget.vehicle.latitude, widget.vehicle.longitude),
      initialZoom: 13,
    ),
    children: [
      if (widget.enabled)
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          tileProvider: provider,
          userAgentPackageName: 'com.codingbot000.fleetbridge_flutter',
          errorTileCallback: (_, error, stack) {
            if (mounted) widget.onError();
          },
        ),
      MarkerLayer(
        markers: [
          Marker(
            point: LatLng(widget.vehicle.latitude, widget.vehicle.longitude),
            child: const Icon(Icons.location_on, color: Colors.red, size: 36),
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
  );
}
