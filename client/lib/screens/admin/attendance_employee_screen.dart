import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/api_config.dart';

Future<void> _openMapsUrl(double lat, double lng) async {
  final uri = Uri.parse('https://maps.google.com/?q=$lat,$lng');
  if (await canLaunchUrl(uri)) launchUrl(uri);
}

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
  static const _gold   = Color(0xFFD7BE69);
  static const _green  = Color(0xFF43A047);
  static const _red    = Color(0xFFE53935);
  static const _orange = Color(0xFFF59E0B);
  static const _blue   = Color(0xFF1E88E5);

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
      final dt   = DateTime.parse(raw).toLocal();
      final h12  = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final min  = dt.minute.toString().padLeft(2, '0');
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
    if (mins == null || mins == 0) return '—';
    final h = mins ~/ 60;
    final m = mins % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved': return _blue;
      case 'rejected': return _red;
      case 'pending':  return _orange;
      default:         return _green;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved': return 'Approved';
      case 'rejected': return 'Rejected';
      case 'pending':  return 'Pending';
      default:         return 'On Time';
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
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _refresh, child: const Text('Retry')),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: _records.isEmpty && !_isLoading
                  ? const Center(child: Text('No attendance records yet'))
                  : ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(12),
                      itemCount: _records.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        if (index >= _records.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        return _AttendanceCard(
                          record: _records[index],
                          onApprove:   () => _approve(_records[index]),
                          onReject:    () => _reject(_records[index]),
                          formatTime:  _formatTime,
                          formatDate:  _formatDate,
                          fmtMinutes:  _fmtMinutes,
                          statusColor: _statusColor,
                          statusLabel: _statusLabel,
                        );
                      },
                    ),
            ),
    );
  }
}

// ─── Card ────────────────────────────────────────────────────────────────────

class _AttendanceCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final String Function(String?) formatTime;
  final String Function(String?) formatDate;
  final String Function(int?)    fmtMinutes;
  final Color  Function(String)  statusColor;
  final String Function(String)  statusLabel;

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

  static const _orange = Color(0xFFF59E0B);
  static const _red    = Color(0xFFE53935);
  static const _green  = Color(0xFF43A047);

  @override
  Widget build(BuildContext context) {
    final r           = record;
    final status      = r['status']       as String? ?? 'on_time';
    final isLate      = r['is_late']      == true;
    final isEarlyOut  = r['is_early_out'] == true;
    final isPending   = status == 'pending';
    final lateReason  = r['late_reason']       as String?;
    final earlyReason = r['early_out_reason']  as String?;
    final adminNotes  = r['admin_notes']       as String?;
    final workMins    = r['total_work_minutes']  as int?;
    final breakMins   = r['total_break_minutes'] as int?;
    final inPhoto     = r['punch_in_photo']  as String?;
    final outPhoto    = r['punch_out_photo'] as String?;
    final inLoc       = r['punch_in_location']  as Map?;
    final outLoc      = r['punch_out_location'] as Map?;
    final breaks      = r['break_details']  as List?;

    final sColor = statusColor(status);

    return Card(
      color: Colors.white,
      elevation: 1.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isPending
              ? _orange.withValues(alpha: 0.5)
              : sColor.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Header: date + status ──────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 14, color: Colors.black45),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    formatDate(r['date'] as String?),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: sColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    statusLabel(status),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: sColor),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1, color: Color(0xFFEEEEEE)),
            const SizedBox(height: 12),

            // ── Punch In ───────────────────────────────────────────────────
            _PunchRow(
              icon: Icons.login_rounded,
              label: 'Punch In',
              time: formatTime(r['punch_in_time'] as String?),
              flagText: isLate ? 'LATE' : null,
              flagColor: _red,
              location: inLoc,
            ),

            const SizedBox(height: 10),

            // ── Punch Out ──────────────────────────────────────────────────
            _PunchRow(
              icon: Icons.logout_rounded,
              label: 'Punch Out',
              time: formatTime(r['punch_out_time'] as String?),
              flagText: isEarlyOut ? 'EARLY OUT' : null,
              flagColor: _orange,
              location: outLoc,
            ),

            // ── Work / Break summary ───────────────────────────────────────
            if (workMins != null && workMins > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  _SummaryChip(
                    icon: Icons.timer_outlined,
                    label: 'Work',
                    value: fmtMinutes(workMins),
                    color: _green,
                  ),
                  const SizedBox(width: 8),
                  if (breakMins != null && breakMins > 0)
                    _SummaryChip(
                      icon: Icons.local_cafe_outlined,
                      label: 'Break',
                      value: fmtMinutes(breakMins),
                      color: _orange,
                    ),
                ],
              ),
            ],

            // ── Reasons ────────────────────────────────────────────────────
            if (isLate && lateReason != null && lateReason.isNotEmpty) ...[
              const SizedBox(height: 10),
              _ReasonBanner(
                icon: Icons.access_time,
                label: 'Late Reason',
                text: lateReason,
                color: _red,
              ),
            ],
            if (isEarlyOut && earlyReason != null && earlyReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ReasonBanner(
                icon: Icons.exit_to_app_rounded,
                label: 'Early-Out Reason',
                text: earlyReason,
                color: _orange,
              ),
            ],
            if (adminNotes != null && adminNotes.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ReasonBanner(
                icon: Icons.admin_panel_settings_outlined,
                label: 'Admin Note',
                text: adminNotes,
                color: const Color(0xFF1E88E5),
              ),
            ],

            // ── Photos ─────────────────────────────────────────────────────
            if (inPhoto != null || outPhoto != null) ...[
              const SizedBox(height: 12),
              const Text('Photos',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54)),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (inPhoto != null)
                    Expanded(
                      child: _PhotoThumb(
                        label: 'Punch In',
                        url: ApiConfig.baseUrl + inPhoto,
                      ),
                    ),
                  if (inPhoto != null && outPhoto != null)
                    const SizedBox(width: 8),
                  if (outPhoto != null)
                    Expanded(
                      child: _PhotoThumb(
                        label: 'Punch Out',
                        url: ApiConfig.baseUrl + outPhoto,
                      ),
                    ),
                ],
              ),
            ],

            // ── Break details ──────────────────────────────────────────────
            if (breaks != null && breaks.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Break Details',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54)),
              const SizedBox(height: 6),
              ...breaks.map((b) {
                final bm = b as Map;
                final type  = (bm['type']  as String? ?? '').toUpperCase();
                final start = _fmtBreakTime(bm['start'] as String?);
                final end   = _fmtBreakTime(bm['end']   as String?);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _orange.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(type,
                            style: const TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: _orange)),
                      ),
                      const SizedBox(width: 8),
                      Text('$start → ${end ?? "ongoing"}',
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black87)),
                    ],
                  ),
                );
              }),
            ],

            // ── Approve / Reject ───────────────────────────────────────────
            if (isPending) ...[
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
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Reject',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      onPressed: onReject,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Approve',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      onPressed: onApprove,
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

  static String? _fmtBreakTime(String? raw) {
    if (raw == null) return null;
    try {
      final dt   = DateTime.parse(raw).toLocal();
      final h12  = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final min  = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour < 12 ? 'AM' : 'PM';
      return '$h12:$min $ampm';
    } catch (_) {
      return raw;
    }
  }
}

// ─── Punch row with location ──────────────────────────────────────────────────

class _PunchRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   time;
  final String?  flagText;
  final Color    flagColor;
  final Map?     location;

  const _PunchRow({
    required this.icon,
    required this.label,
    required this.time,
    required this.flagColor,
    this.flagText,
    this.location,
  });

  @override
  Widget build(BuildContext context) {
    final hasLoc = location != null &&
        location!['lat'] != null &&
        location!['lng'] != null;
    final lat = hasLoc ? (location!['lat'] as num).toDouble() : 0.0;
    final lng = hasLoc ? (location!['lng'] as num).toDouble() : 0.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: flagText != null
                ? flagColor.withValues(alpha: 0.1)
                : const Color(0xFF43A047).withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon,
              size: 18,
              color: flagText != null ? flagColor : const Color(0xFF43A047)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(label,
                      style: const TextStyle(
                          fontSize: 11, color: Colors.black54)),
                  if (flagText != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: flagColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(flagText!,
                          style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: flagColor)),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(time,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              if (hasLoc) ...[
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _openMapsUrl(lat, lng),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined,
                          size: 13, color: Color(0xFF1E88E5)),
                      const SizedBox(width: 3),
                      Text(
                        '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF1E88E5),
                            decoration: TextDecoration.underline),
                      ),
                      const SizedBox(width: 3),
                      const Icon(Icons.open_in_new,
                          size: 11, color: Color(0xFF1E88E5)),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 3),
                const Text('No location',
                    style: TextStyle(fontSize: 11, color: Colors.black38)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Summary chip (work / break) ─────────────────────────────────────────────

class _SummaryChip extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  final Color    color;

  const _SummaryChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 9, color: color, fontWeight: FontWeight.w500)),
              Text(value,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Reason banner ────────────────────────────────────────────────────────────

class _ReasonBanner extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   text;
  final Color    color;

  const _ReasonBanner({
    required this.icon,
    required this.label,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: color)),
                const SizedBox(height: 2),
                Text(text,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black87)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Photo thumbnail ──────────────────────────────────────────────────────────

class _PhotoThumb extends StatelessWidget {
  final String label;
  final String url;

  const _PhotoThumb({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(8)),
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (ctx, e, s) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Image unavailable',
                        style: TextStyle(color: Colors.grey)),
                  ),
                ),
              ),
              TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close')),
            ],
          ),
        ),
      ),
      child: Column(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              width: double.infinity,
              height: 90,
              fit: BoxFit.cover,
              errorBuilder: (ctx, e, s) => Container(
                width: double.infinity,
                height: 90,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image_outlined,
                        color: Colors.grey, size: 28),
                    SizedBox(height: 4),
                    Text('No image',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: Colors.black54)),
        ],
      ),
    );
  }
}
