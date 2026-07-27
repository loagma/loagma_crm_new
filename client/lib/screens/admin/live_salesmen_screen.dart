import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import '../../utils/distance_format.dart';

/// Admin: who is on duty right now.
///
/// Polls /api/tracking/live every 15s. Each row shows the salesman's name,
/// how long ago their last route point arrived, battery, and status dots:
/// 🟢 live (ping within 5 min), 🟠 stale (older), ⚠️ mocked GPS.
/// Tapping a row will open the live route map (Phase 4) — placeholder for now.
class LiveSalesmenScreen extends StatefulWidget {
  const LiveSalesmenScreen({super.key});

  @override
  State<LiveSalesmenScreen> createState() => _LiveSalesmenScreenState();
}

class _LiveSalesmenScreenState extends State<LiveSalesmenScreen> {
  static const _gold = Color(0xFFD7BE69);
  static const _staleAfter = Duration(minutes: 5);

  Timer? _timer;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  /// Calendar button: pick a past date, then open the date-first roster of
  /// everyone who was on duty that day.
  Future<void> _openHistory() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(today.year - 1, 1, 1),
      lastDate: today,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context)
              .colorScheme
              .copyWith(primary: _gold, onPrimary: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    if (!mounted) return;
    final date =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    context.push('/history-roster', extra: {'date': date});
  }

  Future<void> _load() async {
    final res = await ApiService.getLiveSalesmen();
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res != null && res['success'] == true) {
        _error = null;
        _items = List<Map<String, dynamic>>.from(res['data'] as List);
      } else {
        _error = 'Could not load live salesmen';
      }
    });
  }

  bool _isStale(Map<String, dynamic> item) {
    final lastPing = item['last_ping_at'] as String?;
    if (lastPing == null) return true;
    final at = DateTime.tryParse(lastPing);
    if (at == null) return true;
    return DateTime.now().difference(at.toLocal()) > _staleAfter;
  }

  String _lastSeen(Map<String, dynamic> item) {
    final lastPing = item['last_ping_at'] as String?;
    if (lastPing == null) return 'No location yet';
    final at = DateTime.tryParse(lastPing)?.toLocal();
    if (at == null) return 'No location yet';
    final diff = DateTime.now().difference(at);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    return '${diff.inHours}h ${diff.inMinutes % 60}m ago';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F6),
      appBar: AppBar(
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        title: const Text('Live Salesmen',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Route history by date',
            icon: const Icon(Icons.calendar_month),
            onPressed: _openHistory,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _gold,
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _gold));
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 160),
          Icon(Icons.cloud_off, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Center(child: Text(_error!, style: TextStyle(color: Colors.grey.shade600))),
        ],
      );
    }
    if (_items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 160),
          Icon(Icons.location_off_rounded, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Center(
            child: Text('No salesmen on duty',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
          ),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(12),
      itemCount: _items.length,
      itemBuilder: (context, i) => _row(_items[i]),
    );
  }

  Widget _row(Map<String, dynamic> item) {
    final stale = _isStale(item);
    final mocked = item['is_mock'] == true;
    final battery = item['battery'];

    return Card(
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        onTap: () {
          context.push('/live-route', extra: {
            'mobile': item['employee_mobile'],
            'name': item['name'] ?? item['employee_mobile'],
          });
        },
        leading: Stack(
          children: [
            CircleAvatar(
              backgroundColor: _gold.withOpacity(0.2),
              child: Text(
                (item['name'] as String? ?? '?').isNotEmpty
                    ? (item['name'] as String).substring(0, 1).toUpperCase()
                    : '?',
                style: const TextStyle(
                    color: Color(0xFF8A6D1F), fontWeight: FontWeight.bold),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: stale ? Colors.orange : const Color(0xFF2F9E57),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(item['name'] as String? ?? item['employee_mobile'] as String,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
            if (mocked) ...[
              const SizedBox(width: 6),
              const Tooltip(
                message: 'Mock location detected',
                child: Text('⚠️', style: TextStyle(fontSize: 14)),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${_lastSeen(item)} · 📏 ${formatDistance(item['distance_km'] as num?, hasGaps: item['has_gaps'] == true)}'
          '${item['has_gaps'] == true ? '\n$kGapWarningText' : ''}',
          style: TextStyle(
              fontSize: 12.5,
              color: stale ? Colors.orange.shade800 : Colors.grey.shade600),
        ),
        trailing: battery == null
            ? null
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    (battery as num) <= 20
                        ? Icons.battery_alert_rounded
                        : Icons.battery_std_rounded,
                    size: 18,
                    color: battery <= 20 ? Colors.red : Colors.grey.shade600,
                  ),
                  Text('$battery%',
                      style: TextStyle(
                          fontSize: 12.5, color: Colors.grey.shade700)),
                ],
              ),
      ),
    );
  }
}
