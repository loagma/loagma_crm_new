import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// Shows one GPS point on an in-app map — used wherever the app previously
// deep-linked out to Google Maps for a single location (employee/staff
// coordinates, attendance punch location, etc). No external redirect.
class SingleLocationMapScreen extends StatelessWidget {
  final String title;
  final String? subtitle;
  final double latitude;
  final double longitude;

  const SingleLocationMapScreen({
    super.key,
    required this.title,
    this.subtitle,
    required this.latitude,
    required this.longitude,
  });

  static const _gold = Color(0xFFD7BE69);

  @override
  Widget build(BuildContext context) {
    final point = LatLng(latitude, longitude);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(title),
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: point,
              initialZoom: 16,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
                scrollWheelVelocity: 0.005,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.client',
              ),
              MarkerLayer(markers: [
                Marker(
                  point: point,
                  width: 40,
                  height: 40,
                  alignment: Alignment.topCenter,
                  child: const Icon(Icons.location_on_rounded, size: 38, color: _gold),
                ),
              ]),
            ],
          ),
          Positioned(
            left: 10, right: 10, bottom: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(subtitle!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  Text('${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
