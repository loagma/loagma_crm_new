import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/api_service.dart';

/// Admin: watch one salesman's route grow live on the map.
///
/// First load draws the full trail for today; afterwards a delta poll every
/// 8s (?since=<last recorded_at>) appends only new points. Polling stops when
/// the salesman punches out (is_active false) or the screen is disposed.
class LiveRouteScreen extends StatefulWidget {
  final String mobile;
  final String name;

  const LiveRouteScreen({super.key, required this.mobile, required this.name});

  @override
  State<LiveRouteScreen> createState() => _LiveRouteScreenState();
}

class _LiveRouteScreenState extends State<LiveRouteScreen> {
  static const _gold = Color(0xFFD7BE69);
  static const _routeColor = Color(0xFF2F6FED);

  final MapController _mapController = MapController();

  Timer? _timer;
  final List<LatLng> _points = [];
  String? _lastRecordedAt;
  LatLng? _start; // punch-in location (green pin)
  bool _isActive = true;
  bool _loading = true;
  String? _error;
  bool _followTip = true;

  @override
  void initState() {
    super.initState();
    _fetch(initial: true);
    _timer = Timer.periodic(const Duration(seconds: 8), (_) => _fetch());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  Future<void> _fetch({bool initial = false}) async {
    if (!_isActive && !initial) return;

    final res = await ApiService.getLiveRoute(
      mobile: widget.mobile,
      since: initial ? null : _lastRecordedAt,
    );
    if (!mounted) return;

    if (res == null || res['success'] != true) {
      setState(() {
        _loading = false;
        if (initial) _error = 'Could not load route';
      });
      return;
    }

    final data = res['data'] as Map<String, dynamic>;
    final incoming = (data['points'] as List).cast<Map<String, dynamic>>();

    setState(() {
      _loading = false;
      _error = null;

      final startRaw = data['start'];
      if (startRaw is Map && startRaw['lat'] != null) {
        _start = LatLng(
          (startRaw['lat'] as num).toDouble(),
          (startRaw['lng'] as num).toDouble(),
        );
      }

      for (final p in incoming) {
        _points.add(LatLng(
          (p['lat'] as num).toDouble(),
          (p['lng'] as num).toDouble(),
        ));
        _lastRecordedAt = p['recorded_at'] as String;
      }

      final wasActive = _isActive;
      _isActive = data['is_active'] == true;
      if (wasActive && !_isActive) _timer?.cancel();
    });

    if (incoming.isNotEmpty && _followTip && _points.isNotEmpty) {
      _mapController.move(_points.last, _mapController.camera.zoom);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Flexible(
              child: Text(widget.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _isActive ? const Color(0xFF2F9E57) : Colors.redAccent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_isActive ? 'LIVE' : 'ENDED',
                  style: const TextStyle(fontSize: 11, color: Colors.white)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _followTip ? 'Following position' : 'Free camera',
            icon: Icon(_followTip ? Icons.gps_fixed : Icons.gps_not_fixed),
            onPressed: () => setState(() => _followTip = !_followTip),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _gold));
    }
    if (_error != null) {
      return Center(child: Text(_error!, style: TextStyle(color: Colors.grey.shade600)));
    }
    if (_points.isEmpty && _start == null) {
      return Center(
        child: Text('No route points yet today',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
      );
    }

    final center = _points.isNotEmpty ? _points.last : _start!;

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 16,
        onPositionChanged: (camera, hasGesture) {
          if (hasGesture && _followTip) setState(() => _followTip = false);
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.client',
        ),
        if (_points.length >= 2)
          PolylineLayer(polylines: [
            Polyline(points: _points, strokeWidth: 4, color: _routeColor),
          ]),
        MarkerLayer(markers: [
          if (_start != null)
            Marker(
              point: _start!,
              width: 36,
              height: 36,
              child: const Icon(Icons.trip_origin, color: Color(0xFF2F9E57), size: 28),
            ),
          if (_points.isNotEmpty)
            Marker(
              point: _points.last,
              width: 40,
              height: 40,
              child: _isActive
                  ? const Icon(Icons.navigation_rounded, color: _routeColor, size: 32)
                  : const Icon(Icons.location_on, color: Colors.redAccent, size: 34),
            ),
        ]),
      ],
    );
  }
}
