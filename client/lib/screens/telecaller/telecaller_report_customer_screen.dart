import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../widgets/call_recording_player.dart';
import 'telecaller_mock_data.dart';

/// Drill-in for one customer on the new Team/Self Report table: every visit
/// in the report's date range (check-in/out + order, oldest first), then
/// Normal Call vs Cloud Call tabs (source = 'manual' vs 'knowlarity' on
/// call_log_crm) across the same range.
class TelecallerReportCustomerScreen extends StatefulWidget {
  final String accountId;
  final String accountType;
  final String name;
  final String from; // YYYY-MM-DD
  final String to;   // YYYY-MM-DD
  final String? telecallerId; // null when the telecaller is viewing their own

  const TelecallerReportCustomerScreen({
    super.key,
    required this.accountId,
    required this.accountType,
    required this.name,
    required this.from,
    required this.to,
    this.telecallerId,
  });

  @override
  State<TelecallerReportCustomerScreen> createState() => _TelecallerReportCustomerScreenState();
}

class _TelecallerReportCustomerScreenState extends State<TelecallerReportCustomerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);
  bool _loading = true;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await ApiService.getTelecallerReportCustomer(
      accountId: widget.accountId,
      accountType: widget.accountType,
      from: widget.from,
      to: widget.to,
      telecallerId: widget.telecallerId,
    );
    if (!mounted) return;
    setState(() {
      _data = (res != null && res['success'] == true) ? res['data'] as Map<String, dynamic> : null;
      _loading = false;
    });
  }

  String _fmtTime(String? iso) {
    if (iso == null || iso.isEmpty) return '--:--';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '--:--';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? "AM" : "PM"}';
  }

  // Only stamp the date when the report spans more than one day — a
  // single-day filter (Today/Yesterday) doesn't need it repeated on every row.
  String _fmtWhen(String? iso) {
    if (iso == null || iso.isEmpty) return '--';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '--';
    final time = _fmtTime(iso);
    if (widget.from == widget.to) return time;
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}  $time';
  }

  @override
  Widget build(BuildContext context) {
    final visits = ((_data?['visits'] as List?) ?? []).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
    final orders = ((_data?['orders'] as List?) ?? []).cast<Map>().map((e) => e.cast<String, dynamic>()).toList();
    final normalCalls = ((_data?['normal_calls'] as List?) ?? []).cast<Map>();
    final cloudCalls  = ((_data?['cloud_calls']  as List?) ?? []).cast<Map>();

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kGold,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: [
            Tab(text: 'Normal Call (${normalCalls.length})'),
            Tab(text: 'Cloud Call (${cloudCalls.length})'),
            Tab(text: 'Orders (${orders.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : RefreshIndicator(
              onRefresh: _load,
              child: Column(
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: visits.length > 1 ? 220 : 140),
                    child: _visitsSection(visits),
                  ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabs,
                      children: [
                        _callList(normalCalls, showRecording: false),
                        _callList(cloudCalls, showRecording: true),
                        _ordersTab(orders),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _visitsSection(List<Map<String, dynamic>> visits) {
    if (visits.isEmpty) {
      return Container(
        margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        child: const Text('No visit recorded in this period.', style: TextStyle(color: Colors.black54, fontSize: 12.5)),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      itemCount: visits.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _visitCard(visits[i]),
    );
  }

  String _fmtDuration(num? seconds) {
    if (seconds == null || seconds <= 0) return '--';
    final s = seconds.toInt();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${sec}s';
    return '${sec}s';
  }

  Widget _visitCard(Map<String, dynamic> visit) {
    final order = (visit['order'] as Map?)?.cast<String, dynamic>();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEEEEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _stat('Check-in', _fmtWhen(visit['check_in_at'] as String?), Icons.login_rounded, const Color(0xFF43A047)),
              ),
              Container(width: 1, height: 32, color: const Color(0xFFEEEEEE)),
              Expanded(
                child: _stat('Check-out', _fmtWhen(visit['check_out_at'] as String?), Icons.logout_rounded, const Color(0xFFE53935)),
              ),
              Container(width: 1, height: 32, color: const Color(0xFFEEEEEE)),
              Expanded(
                child: _stat('Duration', _fmtDuration(visit['duration_seconds'] as num?), Icons.timer_outlined, const Color(0xFF1E88E5)),
              ),
            ],
          ),
          if (order != null) ...[
            const SizedBox(height: 10),
            _orderCard(order),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10.5, color: Colors.black54)),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }

  Widget _ordersTab(List<Map<String, dynamic>> orders) {
    if (orders.isEmpty) {
      return const Center(child: Text('No orders in this period.', style: TextStyle(color: Colors.black54)));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: orders.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _orderCard(orders[i]),
    );
  }

  Widget _orderCard(Map<String, dynamic> order) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFA5D6A7)),
      ),
      child: Row(
        children: [
          const Icon(Icons.shopping_bag_rounded, color: Color(0xFF2E7D32), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Order #${order['order_id']} placed',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Color(0xFF2E7D32))),
                Text(
                  '${order['items_count'] ?? 0} item(s) • Rs. ${((order['order_total'] as num?) ?? 0).toStringAsFixed(0)} • ${order['payment_status'] ?? ''}',
                  style: const TextStyle(fontSize: 11.5, color: Colors.black54),
                ),
                if ('${order['order_datetime'] ?? ''}'.isNotEmpty)
                  Text('${order['order_datetime']}', style: const TextStyle(fontSize: 11, color: Colors.black45)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _callList(List<Map> calls, {required bool showRecording}) {
    if (calls.isEmpty) {
      return const Center(child: Text('No calls in this tab for this period.', style: TextStyle(color: Colors.black54)));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      itemCount: calls.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final c = calls[i];
        final outcome = '${c['outcome'] ?? ''}';
        final color = kOutcomeColors[outcome] ?? Colors.grey;
        final label = kOutcomeLabels[outcome] ?? outcome;
        final duration = (c['duration_seconds'] as num?)?.toInt() ?? 0;
        final callLogId = c['id'];
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFEEEEEE)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                    child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
                  ),
                  const Spacer(),
                  Text(_fmtWhen(c['called_at'] as String?), style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
                ],
              ),
              if (duration > 0) ...[
                const SizedBox(height: 6),
                Text('Duration: ${duration ~/ 60}m ${duration % 60}s', style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
              ],
              if ('${c['notes'] ?? ''}'.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('${c['notes']}', style: const TextStyle(fontSize: 12)),
              ],
              if (showRecording && callLogId != null) ...[
                const SizedBox(height: 8),
                CallRecordingPlayer(callLogId: callLogId as int, accountId: widget.accountId),
              ],
            ],
          ),
        );
      },
    );
  }
}
