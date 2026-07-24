import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../services/api_service.dart';
import '../../utils/distance_format.dart';

/// Admin: static single-day route map (Phase 5 history).
///
/// One fetch on open, NO polling. Contiguous runs draw solid; a jump across
/// a >5-min tracking gap draws DASHED — that stretch was not recorded and is
/// excluded from the distance total (see RouteDistance server-side).
///
/// Road snapping: when the server cached an OSRM-matched geometry for a
/// closed day (`snapped: true`), each solid run draws the snapped shape
/// instead of the raw zig-zag. Dashes across gaps ALWAYS stay raw straight
/// lines — an interruption is never beautified — and the distance figure is
/// always computed from raw points, never the snapped line.
class RouteViewScreen extends StatefulWidget {
  final String mobile;
  final String name;
  final String date; // yyyy-mm-dd

  const RouteViewScreen({
    super.key,
    required this.mobile,
    required this.name,
    required this.date,
  });

  @override
  State<RouteViewScreen> createState() => _RouteViewScreenState();
}

class _RouteViewScreenState extends State<RouteViewScreen> {
  static const _gold = Color(0xFFD7BE69);
  static const _routeColor = Color(0xFF2F6FED);
  // Darker shade of the route blue, drawn as an outline under the main line.
  static const _routeOutline = Color(0xFF1C4CB3);
  static const _gapRule = Duration(minutes: 5); // = RouteDistance::GAP_MINUTES

  bool _loading = true;
  String? _error;

  final List<List<LatLng>> _segments = []; // contiguous recorded runs (raw)
  // Per-raw-segment OSRM geometry (null entry = that run failed to snap).
  final List<List<LatLng>?> _snappedSegs = [];
  bool _snapped = false;
  LatLng? _startPin;
  LatLng? _endPin;
  int _pointCount = 0;
  num? _distanceKm;
  bool _hasGaps = false;
  bool _autoClosed = false;
  bool _isActive = false;
  String? _punchIn;
  String? _punchOut;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final res = await ApiService.getRouteHistory(
        mobile: widget.mobile, date: widget.date);
    if (!mounted) return;

    if (res == null || res['success'] != true) {
      setState(() {
        _loading = false;
        _error = 'Could not load route';
      });
      return;
    }

    final data = res['data'] as Map<String, dynamic>;
    final points = (data['points'] as List).cast<Map<String, dynamic>>();

    final segments = <List<LatLng>>[];
    var current = <LatLng>[];
    DateTime? prevAt;

    for (final p in points) {
      final pt = LatLng(
        (p['lat'] as num).toDouble(),
        (p['lng'] as num).toDouble(),
      );
      final at = DateTime.tryParse(p['recorded_at'] as String? ?? '');

      if (prevAt != null &&
          at != null &&
          at.difference(prevAt) > _gapRule &&
          current.isNotEmpty) {
        segments.add(current);
        current = <LatLng>[pt];
      } else {
        current.add(pt);
      }
      if (at != null) prevAt = at;
    }
    if (current.isNotEmpty) segments.add(current);

    // Server-side OSRM geometry, one entry per contiguous run (same >5-min
    // split rule on both sides). Length mismatch → distrust it entirely.
    final snappedRaw = data['snapped_segments'];
    var snappedSegs = <List<LatLng>?>[];
    if (data['snapped'] == true &&
        snappedRaw is List &&
        snappedRaw.length == segments.length) {
      snappedSegs = snappedRaw.map<List<LatLng>?>((seg) {
        if (seg is! List) return null;
        final pts = <LatLng>[];
        for (final c in seg) {
          if (c is List && c.length >= 2) {
            pts.add(LatLng((c[0] as num).toDouble(), (c[1] as num).toDouble()));
          }
        }
        return pts.length >= 2 ? pts : null;
      }).toList();
    }

    LatLng? pinOf(dynamic raw) => raw is Map && raw['lat'] != null
        ? LatLng((raw['lat'] as num).toDouble(), (raw['lng'] as num).toDouble())
        : null;

    setState(() {
      _loading = false;
      _error = null;
      _segments
        ..clear()
        ..addAll(segments);
      _snappedSegs
        ..clear()
        ..addAll(snappedSegs);
      _snapped = snappedSegs.any((s) => s != null);
      _pointCount = points.length;
      _startPin = pinOf(data['start']) ??
          (segments.isNotEmpty ? segments.first.first : null);
      _endPin = pinOf(data['end']) ??
          (segments.isNotEmpty ? segments.last.last : null);
      _distanceKm = data['total_distance_km'] as num?;
      _hasGaps = data['has_gaps'] == true;
      _autoClosed = data['auto_closed'] == true;
      _isActive = data['is_active'] == true;
      _punchIn = data['punch_in_time'] as String?;
      _punchOut = data['punch_out_time'] as String?;
    });
  }

  String _fmtTime(String? raw) {
    final d = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    if (d == null) return '—';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String get _duration {
    final inAt = _punchIn == null ? null : DateTime.tryParse(_punchIn!);
    final outAt = _punchOut == null ? null : DateTime.tryParse(_punchOut!);
    if (inAt == null) return '—';
    if (outAt == null) return 'ongoing';
    final d = outAt.difference(inAt);
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        title: Text('${widget.name} — ${widget.date}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _gold));
    }
    if (_error != null) {
      return Center(
          child:
              Text(_error!, style: TextStyle(color: Colors.grey.shade600)));
    }

    final allPoints = _segments.expand((s) => s).toList();
    if (allPoints.isEmpty && _startPin == null) {
      return Center(
        child: Text('No route recorded on this day',
            style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
      );
    }

    return Stack(
      children: [
        _map(allPoints),
        Positioned(left: 0, right: 0, bottom: 0, child: _summaryCard()),
      ],
    );
  }

  Widget _map(List<LatLng> allPoints) {
    final fitPoints = [
      ...allPoints,
      if (_startPin != null) _startPin!,
      if (_endPin != null) _endPin!,
    ];

    return FlutterMap(
      options: MapOptions(
        initialCameraFit: fitPoints.length >= 2
            ? CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(fitPoints),
                padding: const EdgeInsets.fromLTRB(40, 40, 40, 180),
              )
            : CameraFit.bounds(
                bounds: LatLngBounds(
                  LatLng(fitPoints.first.latitude - 0.005,
                      fitPoints.first.longitude - 0.005),
                  LatLng(fitPoints.first.latitude + 0.005,
                      fitPoints.first.longitude + 0.005),
                ),
              ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.client',
        ),
        PolylineLayer(polylines: _routePolylines()),
        MarkerLayer(markers: [
          if (_startPin != null)
            Marker(
              point: _startPin!,
              width: 36,
              height: 36,
              child: const Icon(Icons.trip_origin,
                  color: Color(0xFF2F9E57), size: 28),
            ),
          if (_endPin != null)
            Marker(
              point: _endPin!,
              width: 40,
              height: 40,
              child: const Icon(Icons.location_on,
                  color: Colors.redAccent, size: 34),
            ),
        ]),
      ],
    );
  }

  /// Dashed connectors first, solid runs on top. Each solid run prefers its
  /// snapped geometry; dashes bridge the DISPLAYED segment ends so they stay
  /// attached whether a run rendered raw or snapped. Dashed styling itself is
  /// untouched — gaps stay visibly honest.
  List<Polyline> _routePolylines() {
    final displaySegs = <List<LatLng>>[
      for (var i = 0; i < _segments.length; i++)
        (i < _snappedSegs.length ? _snappedSegs[i] : null) ?? _segments[i],
    ];

    return [
      for (var i = 0; i + 1 < displaySegs.length; i++)
        Polyline(
          points: [displaySegs[i].last, displaySegs[i + 1].first],
          strokeWidth: 3,
          color: _routeColor.withValues(alpha: 0.6),
          pattern: StrokePattern.dashed(segments: const [10, 8]),
        ),
      for (final seg in displaySegs)
        if (seg.length >= 2)
          Polyline(
            points: seg,
            strokeWidth: 5,
            color: _routeColor,
            borderStrokeWidth: 2.5,
            borderColor: _routeOutline,
            strokeCap: StrokeCap.round,
            strokeJoin: StrokeJoin.round,
          ),
    ];
  }

  Widget _summaryCard() {
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  formatDistance(_distanceKm, hasGaps: _hasGaps),
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                if (_autoClosed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('auto-closed',
                        style: TextStyle(
                            fontSize: 10, color: Colors.orange.shade900)),
                  ),
                if (_isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2F9E57),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('LIVE',
                        style:
                            TextStyle(fontSize: 10, color: Colors.white)),
                  ),
                if (_snapped) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('road-snapped',
                        style: TextStyle(
                            fontSize: 10, color: Colors.blue.shade800)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'In ${_fmtTime(_punchIn)} · Out ${_fmtTime(_punchOut)} · '
              '$_duration · $_pointCount points',
              style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
            ),
            if (_hasGaps) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 15, color: Colors.orange.shade800),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      kGapWarningText,
                      style: TextStyle(
                          fontSize: 11.5, color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
