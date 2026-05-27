import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';

class AttendanceEmployeeScreen extends StatefulWidget {
  final String employeeMobile;
  final Map<String, dynamic>? initialEmployee;

  const AttendanceEmployeeScreen({
    super.key,
    required this.employeeMobile,
    this.initialEmployee,
  });

  @override
  State<AttendanceEmployeeScreen> createState() =>
      _AttendanceEmployeeScreenState();
}

class _AttendanceEmployeeScreenState extends State<AttendanceEmployeeScreen> {
  static const _gold    = Color(0xFFD7BE69);
  static const _green   = Color(0xFF43A047);
  static const _red     = Color(0xFFE53935);
  static const _orange  = Color(0xFFF59E0B);
  static const _blue    = Color(0xFF1E88E5);

  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _records = [];
  int  _page     = 1;
  bool _isLoading = false;
  bool _hasMore   = true;
  String? _error;

  String get _name =>
      widget.initialEmployee?['name'] as String? ?? widget.employeeMobile;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadPage();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoading) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100) {
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final res = await ApiService.adminAttendanceForEmployee(
        widget.employeeMobile,
        page: _page,
      );
      if (!mounted) return;
      final data = (res['data'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      setState(() {
        _error = null;
        if (_page == 1) {
          _records = data;
        } else {
          _records.addAll(data);
        }
        _isLoading = false;
        _page++;
        _hasMore = data.length >= 20;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load attendance records';
          _isLoading = false;
          _hasMore = false;
        });
      }
    }
  }

  void _refresh() {
    setState(() {
      _records.clear();
      _page = 1;
      _hasMore = true;
    });
    _loadPage();
  }

  Future<void> _approve(Map<String, dynamic> record) async {
    final id = record['id'] as int? ?? 0;
    final ok = await ApiService.adminAttendanceApprove(id);
    if (!mounted) return;
    if (ok) {
      Fluttertoast.showToast(msg: 'Approved');
      _refresh();
    } else {
      Fluttertoast.showToast(msg: 'Failed to approve');
    }
  }

  Future<void> _reject(Map<String, dynamic> record) async {
    final notesCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject Attendance'),
        content: TextField(
          controller: notesCtrl,
          decoration: const InputDecoration(
            labelText: 'Reason for rejection (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reject',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final id = record['id'] as int? ?? 0;
    final ok = await ApiService.adminAttendanceReject(id,
        notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim());
    if (!mounted) return;
    if (ok) {
      Fluttertoast.showToast(msg: 'Rejected');
      _refresh();
    } else {
      Fluttertoast.showToast(msg: 'Failed to reject');
    }
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months   = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  String _formatTime(String? raw) {
    if (raw == null) return '—';
    try {
      final dt  = DateTime.parse(raw).toLocal();
      final h12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final min = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour < 12 ? 'AM' : 'PM';
      return '$h12:$min $ampm';
    } catch (_) {
      return raw;
    }
  }

  String _formatDate(String? raw) {
    if (raw == null) return '—';
    try {
      final dt  = DateTime.parse(raw);
      final day = _weekdays[dt.weekday - 1];
      final mon = _months[dt.month - 1];
      return '$day, ${dt.day.toString().padLeft(2, '0')} $mon ${dt.year}';
    } catch (_) {
      return raw;
    }
  }

  String _fmtMinutes(int? mins) {
    if (mins == null) return '—';
    final h = mins ~/ 60;
    final m = mins % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':  return _blue;
      case 'rejected':  return _red;
      case 'pending':   return _orange;
      default:          return _green;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':  return 'Approved';
      case 'rejected':  return 'Rejected';
      case 'pending':   return 'Pending';
      default:          return 'On Time';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_name),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Shift Settings',
            onPressed: () => context.push(
              '/attendance-manage/${widget.employeeMobile}/settings',
              extra: widget.initialEmployee,
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _error != null && _records.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!,
                      style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  ElevatedButton(
                      onPressed: _refresh,
                      child: const Text('Retry')),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: _records.isEmpty && !_isLoading
                  ? const Center(
                      child: Text('No attendance records yet'))
                  : ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: _records.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        if (index >= _records.length) {
                          return const Padding(
                            padding:
                                EdgeInsets.symmetric(vertical: 12),
                            child: Center(
                                child: CircularProgressIndicator()),
                          );
                        }
                        return _AttendanceCard(
                          record: _records[index],
                          onApprove: () => _approve(_records[index]),
                          onReject:  () => _reject(_records[index]),
                          formatTime: _formatTime,
                          formatDate: _formatDate,
                          fmtMinutes: _fmtMinutes,
                          statusColor: _statusColor,
                          statusLabel: _statusLabel,
                        );
                      },
                    ),
            ),
    );
  }
}

// ─── Card widget ─────────────────────────────────────────────────────────────

class _AttendanceCard extends StatefulWidget {
  final Map<String, dynamic> record;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final String Function(String?) formatTime;
  final String Function(String?) formatDate;
  final String Function(int?) fmtMinutes;
  final Color Function(String) statusColor;
  final String Function(String) statusLabel;

  const _AttendanceCard({
    required this.record,
    required this.onApprove,
    required this.onReject,
    required this.formatTime,
    required this.formatDate,
    required this.fmtMinutes,
    required this.statusColor,
    required this.statusLabel,
  });

  @override
  State<_AttendanceCard> createState() => _AttendanceCardState();
}

class _AttendanceCardState extends State<_AttendanceCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r      = widget.record;
    final status = r['status'] as String? ?? 'on_time';
    final isLate       = r['is_late'] == true;
    final isEarlyOut   = r['is_early_out'] == true;
    final isPending    = status == 'pending';
    final adminNotes   = r['admin_notes'] as String?;
    final lateReason   = r['late_reason'] as String?;
    final earlyReason  = r['early_out_reason'] as String?;
    final workMins     = r['total_work_minutes'] as int?;
    final breakMins    = r['total_break_minutes'] as int?;

    final sColor = widget.statusColor(status);

    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isPending
              ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
              : Colors.transparent,
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row: date + status chip ──────────────────────────
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.formatDate(r['date'] as String?),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: sColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.statusLabel(status),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: sColor),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Punch times + work/break ─────────────────────────────────
            Row(
              children: [
                _InfoCell(
                  icon: Icons.login_rounded,
                  label: 'Punch In',
                  value: widget.formatTime(r['punch_in_time'] as String?),
                  flag: isLate ? 'LATE' : null,
                ),
                const SizedBox(width: 8),
                _InfoCell(
                  icon: Icons.logout_rounded,
                  label: 'Punch Out',
                  value: widget.formatTime(r['punch_out_time'] as String?),
                  flag: isEarlyOut ? 'EARLY' : null,
                ),
                const SizedBox(width: 8),
                _InfoCell(
                  icon: Icons.timer_outlined,
                  label: 'Work',
                  value: widget.fmtMinutes(workMins),
                ),
                const SizedBox(width: 8),
                _InfoCell(
                  icon: Icons.local_cafe_outlined,
                  label: 'Break',
                  value: widget.fmtMinutes(breakMins),
                ),
              ],
            ),

            // ── Expandable reasons ────────────────────────────────────────
            if (isLate || isEarlyOut || adminNotes != null) ...[
              const SizedBox(height: 6),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(
                  children: [
                    Text(
                      _expanded ? 'Hide details' : 'Show details',
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.blue,
                          fontWeight: FontWeight.w500),
                    ),
                    Icon(
                        _expanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 16,
                        color: Colors.blue),
                  ],
                ),
              ),
              if (_expanded) ...[
                const SizedBox(height: 6),
                if (isLate && lateReason != null)
                  _ReasonRow(
                      label: 'Late reason', value: lateReason),
                if (isEarlyOut && earlyReason != null)
                  _ReasonRow(
                      label: 'Early-out reason', value: earlyReason),
                if (adminNotes != null && adminNotes.isNotEmpty)
                  _ReasonRow(label: 'Admin note', value: adminNotes),
              ],
            ],

            // ── Approve / Reject actions ──────────────────────────────────
            if (isPending) ...[
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFE53935),
                        side: const BorderSide(color: Color(0xFFE53935)),
                      ),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Reject'),
                      onPressed: widget.onReject,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF43A047),
                        foregroundColor: Colors.white,
                      ),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Approve'),
                      onPressed: widget.onApprove,
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

class _InfoCell extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? flag;

  const _InfoCell({
    required this.icon,
    required this.label,
    required this.value,
    this.flag,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: Colors.black54),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 9, color: Colors.grey)),
          const SizedBox(height: 1),
          Text(value,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700)),
          if (flag != null)
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: const Color(0xFFE53935).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                flag!,
                style: const TextStyle(
                    fontSize: 8,
                    color: Color(0xFFE53935),
                    fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReasonRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReasonRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54)),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 11, color: Colors.black87)),
          ),
        ],
      ),
    );
  }
}
