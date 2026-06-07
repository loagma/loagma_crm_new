import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../services/api_service.dart';
import '../../services/api_config.dart';

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});

  @override
  State<AdminNotificationsScreen> createState() => _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  static const _gold = Color(0xFFD7BE69);
  static const _red  = Color(0xFFE53935);

  List<Map<String, dynamic>> _records = [];
  bool _loading = false;
  bool _hasMore = true;
  int  _page    = 1;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 100 &&
          !_loading && _hasMore) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading && _records.isNotEmpty && !refresh) return;
    if (refresh) {
      _page = 1;
      _hasMore = true;
      _records = [];
    }
    setState(() => _loading = true);
    try {
      final res = await ApiService.adminPendingList(page: _page);
      if (!mounted) return;
      final items = (res['data'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final meta = res['meta'] as Map?;
      setState(() {
        _records.addAll(items);
        _hasMore = _page < (meta?['last_page'] as int? ?? 1);
        _page++;
      });
    } catch (e) {
      if (mounted) Fluttertoast.showToast(msg: 'Failed to load: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(int id, int index) async {
    try {
      final ok = await ApiService.adminAttendanceApprove(id);
      if (!mounted) return;
      if (ok) {
        setState(() => _records.removeAt(index));
        Fluttertoast.showToast(msg: 'Approved');
      } else {
        Fluttertoast.showToast(msg: 'Failed to approve');
      }
    } catch (e) {
      if (mounted) Fluttertoast.showToast(msg: 'Error: $e');
    }
  }

  Future<void> _reject(int id, int index) async {
    final notesCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Attendance',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: notesCtrl,
          decoration: const InputDecoration(
            hintText: 'Admin notes (optional)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final ok = await ApiService.adminAttendanceReject(id, notes: notesCtrl.text.trim());
      if (!mounted) return;
      if (ok) {
        setState(() => _records.removeAt(index));
        Fluttertoast.showToast(msg: 'Rejected');
      } else {
        Fluttertoast.showToast(msg: 'Failed to reject');
      }
    } catch (e) {
      if (mounted) Fluttertoast.showToast(msg: 'Error: $e');
    }
  }

  String _fmtDate(String? raw) {
    if (raw == null) return '—';
    try {
      final d = DateTime.parse(raw);
      const wk = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      const mo = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${wk[d.weekday - 1]}, ${d.day} ${mo[d.month - 1]} ${d.year}';
    } catch (_) {
      return raw;
    }
  }

  String _fmtTime(String? raw) {
    if (raw == null) return '—';
    try {
      final d = DateTime.parse(raw).toLocal();
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      final m = d.minute.toString().padLeft(2, '0');
      return '$h:$m ${d.hour < 12 ? "AM" : "PM"}';
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        title: const Text('Pending Approvals',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _load(refresh: true),
          ),
        ],
      ),
      body: _loading && _records.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : !_loading && _records.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 56, color: Color(0xFF43A047)),
                      SizedBox(height: 12),
                      Text('No pending approvals',
                          style: TextStyle(fontSize: 16, color: Colors.black54,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                )
              : ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(14),
              itemCount: _records.length + (_loading || _hasMore ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == _records.length) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final r = _records[i];
                return _PendingCard(
                  record: r,
                  baseUrl: ApiConfig.baseUrl,
                  fmtDate: _fmtDate,
                  fmtTime: _fmtTime,
                  onApprove: () => _approve(r['id'] as int, i),
                  onReject:  () => _reject(r['id'] as int, i),
                );
              },
            ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final String baseUrl;
  final String Function(String?) fmtDate;
  final String Function(String?) fmtTime;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PendingCard({
    required this.record,
    required this.baseUrl,
    required this.fmtDate,
    required this.fmtTime,
    required this.onApprove,
    required this.onReject,
  });

  static const _orange = Color(0xFFF59E0B);
  static const _green  = Color(0xFF43A047);
  static const _red    = Color(0xFFE53935);

  @override
  Widget build(BuildContext context) {
    final emp      = record['employee'] as Map?;
    final empName  = emp?['name']  as String? ?? record['employee_mobile'] as String? ?? '—';
    final empRole  = emp?['role']  as String? ?? '';
    final isLate   = record['is_late']     == true;
    final isEarly  = record['is_early_out'] == true;
    final reason   = isLate
        ? (record['late_reason']     as String?)
        : (record['early_out_reason'] as String?);

    return Card(
      color: Colors.white,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _orange.withValues(alpha: 0.4), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(empName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 14)),
                      if (empRole.isNotEmpty)
                        Text(empRole,
                            style: const TextStyle(fontSize: 11, color: Colors.black54)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: _orange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isLate ? 'Late Punch-In' : isEarly ? 'Early Punch-Out' : 'Pending',
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                        color: _orange),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(fmtDate(record['date'] as String?),
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.login_rounded, size: 14, color: Colors.black45),
                const SizedBox(width: 4),
                Text('In: ${fmtTime(record['punch_in_time'] as String?)}',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 16),
                const Icon(Icons.logout_rounded, size: 14, color: Colors.black45),
                const SizedBox(width: 4),
                Text('Out: ${fmtTime(record['punch_out_time'] as String?)}',
                    style: const TextStyle(fontSize: 12)),
              ],
            ),
            if (reason != null && reason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline, size: 14, color: _orange),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(reason,
                        style: const TextStyle(fontSize: 11, color: Colors.black54)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _red,
                      side: const BorderSide(color: _red),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Reject', style: TextStyle(fontWeight: FontWeight.w600)),
                    onPressed: onReject,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Approve', style: TextStyle(fontWeight: FontWeight.w600)),
                    onPressed: onApprove,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
