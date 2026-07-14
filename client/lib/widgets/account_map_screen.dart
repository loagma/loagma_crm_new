import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// Shows a set of lead/customer accounts as pins on a map: gold for leads,
// green for customers — same colour coding used across the app's account
// type chips. Reused by every screen that lists lead/customer accounts
// (allotted accounts, verify-lead pincode groups, beat plans, lead list...).
class AccountMapScreen extends StatefulWidget {
  final String title;
  final List<Map<String, dynamic>> accounts;

  const AccountMapScreen({super.key, required this.title, required this.accounts});

  @override
  State<AccountMapScreen> createState() => _AccountMapScreenState();
}

class _AccountMapScreenState extends State<AccountMapScreen> {
  static const _gold  = Color(0xFFD7BE69);
  static const _green = Color(0xFF2E7D32);

  // 'all' | 'lead' | 'customer'
  String _typeFilter = 'all';

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  // Several accounts can share the exact same coordinate (e.g. leads
  // backfilled to a shared pincode-centre point), which would otherwise stack
  // their pins perfectly on top of each other (only the topmost one
  // visible/tappable). Fan duplicates out in a small circle around the shared
  // point so every account gets its own pin, and remember the full sibling
  // group so tapping any one of them can show every account at that original
  // point — not just the pin on top.
  List<(Map<String, dynamic>, LatLng, List<Map<String, dynamic>>)> _spreadOverlaps(
      List<(Map<String, dynamic>, LatLng)> points) {
    final groups = <String, List<int>>{};
    for (var i = 0; i < points.length; i++) {
      final p = points[i].$2;
      final key = '${p.latitude.toStringAsFixed(5)},${p.longitude.toStringAsFixed(5)}';
      groups.putIfAbsent(key, () => []).add(i);
    }

    final displayPoints = List<LatLng>.from(points.map((p) => p.$2));
    const radiusDeg = 0.0006; // roughly 60-70m, enough to separate pins visually
    for (final indices in groups.values) {
      if (indices.length <= 1) continue;
      for (var j = 0; j < indices.length; j++) {
        final angle = (2 * math.pi * j) / indices.length;
        final base = points[indices[j]].$2;
        displayPoints[indices[j]] = LatLng(
          base.latitude + radiusDeg * math.cos(angle),
          base.longitude + radiusDeg * math.sin(angle),
        );
      }
    }

    return [
      for (var i = 0; i < points.length; i++)
        (
          points[i].$1,
          displayPoints[i],
          [for (final idx in groups.values.firstWhere((g) => g.contains(i))) points[idx].$1],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final allPinnedRaw = <(Map<String, dynamic>, LatLng)>[];
    for (final a in widget.accounts) {
      final lat = _toDouble(a['latitude']);
      final lng = _toDouble(a['longitude']);
      if (lat != null && lng != null) allPinnedRaw.add((a, LatLng(lat, lng)));
    }
    final allPinned = _spreadOverlaps(allPinnedRaw);

    final pinned = _typeFilter == 'all'
        ? allPinned
        : allPinned.where((p) => p.$1['_type'] == _typeFilter).toList();

    final leadCount     = allPinned.where((p) => p.$1['_type'] == 'lead').length;
    final customerCount = allPinned.where((p) => p.$1['_type'] == 'customer').length;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                _filterChip('All', 'all', allPinned.length),
                const SizedBox(width: 8),
                _filterChip('Leads', 'lead', leadCount),
                const SizedBox(width: 8),
                _filterChip('Customers', 'customer', customerCount),
              ],
            ),
          ),
          Expanded(
            child: pinned.isEmpty
                ? Center(
                    child: Text(
                      allPinned.isEmpty
                          ? 'No account here has a saved location yet'
                          : 'No ${_typeFilter == 'lead' ? 'lead' : 'customer'} location here',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                    ),
                  )
                : Stack(
                    children: [
                      FlutterMap(
                        options: MapOptions(
                          initialCameraFit: pinned.length >= 2
                              ? CameraFit.bounds(
                                  bounds: LatLngBounds.fromPoints(
                                      pinned.map((p) => p.$2).toList()),
                                  padding: const EdgeInsets.fromLTRB(40, 40, 40, 40),
                                )
                              : CameraFit.bounds(
                                  bounds: LatLngBounds(
                                    LatLng(pinned.first.$2.latitude - 0.01,
                                        pinned.first.$2.longitude - 0.01),
                                    LatLng(pinned.first.$2.latitude + 0.01,
                                        pinned.first.$2.longitude + 0.01),
                                  ),
                                ),
                          // Explicitly enable drag/pinch/mouse-wheel zoom so the
                          // map is fully interactive on both touch and desktop/web.
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
                            for (final p in pinned)
                              Marker(
                                point: p.$2,
                                width: 40,
                                height: 40,
                                // location_on's visual tip is at the bottom-center of
                                // its bounding box — anchor there so the pin actually
                                // points at the coordinate instead of centering on it.
                                alignment: Alignment.topCenter,
                                child: GestureDetector(
                                  onTap: () => p.$3.length > 1
                                      ? _showGroupSheet(context, p.$3)
                                      : _showAccountSheet(context, p.$1),
                                  child: Icon(
                                    Icons.location_on_rounded,
                                    size: 38,
                                    color: (p.$1['_type'] == 'lead') ? _gold : _green,
                                  ),
                                ),
                              ),
                          ]),
                        ],
                      ),
                      Positioned(
                        top: 10, left: 10,
                        child: _legend(),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, String value, int count) {
    final selected = _typeFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _typeFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? _gold : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _gold : Colors.grey.shade300),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _legend() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(10),
      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.location_on_rounded, size: 16, color: _gold),
        const SizedBox(width: 4),
        const Text('Lead', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(width: 10),
        const Icon(Icons.location_on_rounded, size: 16, color: _green),
        const SizedBox(width: 4),
        const Text('Customer', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    ),
  );

  void _showGroupSheet(BuildContext context, List<Map<String, dynamic>> group) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
              child: Text('${group.length} accounts at this point',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: group.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final a       = group[i];
                  final isLead  = a['_type'] == 'lead';
                  final name    = (a['businessName'] as String?) ?? '—';
                  final phone   = (a['contactNumber'] as String?) ?? '';
                  return ListTile(
                    leading: Icon(Icons.location_on_rounded,
                        color: isLead ? _gold : _green),
                    title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      [isLead ? 'Lead' : 'Customer', if (phone.isNotEmpty) phone].join(' · '),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showAccountSheet(context, a);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  void _showAccountSheet(BuildContext context, Map<String, dynamic> account) {
    final isLead  = account['_type'] == 'lead';
    final name    = (account['businessName'] as String?) ?? '—';
    final person  = (account['personName']   as String?) ?? '';
    final phone   = (account['contactNumber'] as String?) ?? '';
    final address = (account['address']      as String?) ?? '';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (isLead ? _gold : _green).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isLead ? _gold : _green),
                  ),
                  child: Text(isLead ? 'Lead' : 'Customer',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700,
                          color: isLead ? const Color(0xFFB89A3E) : _green)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            if (person.isNotEmpty && person != name)
              Text(person, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
            if (address.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(address, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
            ],
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(Icons.phone_rounded, size: 14, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(phone, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
