import 'package:flutter/material.dart';

import '../services/api_config.dart';
import 'single_location_map_screen.dart';

/// One day's attendance record, rendered read-only: status header, punch
/// in/out cells (time + late/early flag + tappable location), work/break
/// chips, late / early-in / early-out / admin-note reason rows, punch photos
/// (tap to zoom), and break chips.
///
/// Extracted verbatim from admin/attendance_employee_screen.dart so both that
/// screen and the Team Report drill-in render an attendance day identically.
/// The card is purely presentational — it carries no approve/reject actions.
///
/// [record] is the raw attendance row (server shape from
/// AttendanceController::adminEmployeeAttendance / TeamReportController::employee):
/// `date, status, is_late, is_early_out, is_early_in, total_work_minutes,
/// total_break_minutes, punch_in_time, punch_out_time, punch_in_photo,
/// punch_out_photo, punch_in_location {lat,lng}, punch_out_location,
/// break_details[], late_reason, early_out_reason, early_in_reason, admin_notes`.
class AttendanceDayCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final String Function(String?) fmtDate;
  final String Function(String?) fmtTime;
  final String Function(int?) fmtMins;

  const AttendanceDayCard({
    super.key,
    required this.record,
    required this.fmtDate,
    required this.fmtTime,
    required this.fmtMins,
  });

  static const _green  = Color(0xFF43A047);
  static const _red    = Color(0xFFE53935);
  static const _orange = Color(0xFFF59E0B);
  static const _blue   = Color(0xFF1E88E5);
  static const _teal   = Color(0xFF00ACC1);

  Color _statusColor(String s) => switch (s) {
    'approved' => _blue,
    'rejected' => _red,
    'pending'  => _orange,
    'early_in' => _teal,
    _          => _green,
  };

  String _statusLabel(String s) => switch (s) {
    'approved' => 'Approved',
    'rejected' => 'Rejected',
    'pending'  => 'Pending',
    'early_in' => 'Early In',
    _          => 'On Time',
  };

  IconData _statusIcon(String s) => switch (s) {
    'approved' => Icons.check_circle_outline,
    'rejected' => Icons.cancel_outlined,
    'pending'  => Icons.hourglass_empty_rounded,
    'early_in' => Icons.alarm_rounded,
    _          => Icons.check_circle_outline,
  };

  @override
  Widget build(BuildContext context) {
    final r          = record;
    final status     = (r['status'] as String?) ?? 'on_time';
    final isLate     = r['is_late']      == true;
    final isEarly    = r['is_early_out'] == true;
    final isEarlyIn  = r['is_early_in']  == true;
    final workMins   = (r['total_work_minutes']  as num?)?.toInt();
    final breakMins  = (r['total_break_minutes'] as num?)?.toInt();
    final inPhoto    = r['punch_in_photo']  as String?;
    final outPhoto   = r['punch_out_photo'] as String?;
    final inLoc      = r['punch_in_location']  as Map?;
    final outLoc     = r['punch_out_location'] as Map?;
    final breaks     = r['break_details']  as List?;
    final lateReason    = r['late_reason']       as String?;
    final earlyReason   = r['early_out_reason']  as String?;
    final earlyInReason = r['early_in_reason']   as String?;
    final adminNotes    = r['admin_notes']        as String?;

    final sc = _statusColor(status);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sc.withValues(alpha: 0.18), width: 1),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 4, offset: const Offset(0, 1)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Header ─────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: sc.withValues(alpha: 0.06),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_rounded, size: 13, color: sc),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    fmtDate(r['date'] as String?),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: Colors.black87),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: sc.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_statusIcon(status), size: 11, color: sc),
                      const SizedBox(width: 3),
                      Text(_statusLabel(status),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: sc)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Body ───────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // ── Punch In / Out side by side ──────────────────────────────
                Row(
                  children: [
                    Expanded(child: _PunchCell(
                      icon: Icons.login_rounded,
                      label: 'Punch In',
                      time: fmtTime(r['punch_in_time'] as String?),
                      flag: isLate ? 'LATE' : (isEarlyIn ? 'EARLY' : null),
                      flagColor: isLate ? _red : _teal,
                      location: inLoc,
                    )),
                    Container(width: 1, height: 56, color: const Color(0xFFEEEEEE)),
                    Expanded(child: _PunchCell(
                      icon: Icons.logout_rounded,
                      label: 'Punch Out',
                      time: fmtTime(r['punch_out_time'] as String?),
                      flag: isEarly ? 'EARLY' : null,
                      flagColor: _orange,
                      location: outLoc,
                    )),
                  ],
                ),

                // ── Work / Break chips ────────────────────────────────────────
                if ((workMins ?? 0) > 0) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFF0F0F0)),
                  const SizedBox(height: 8),
                  Row(children: [
                    _Chip(Icons.timer_outlined, fmtMins(workMins), _green, 'Work'),
                    if ((breakMins ?? 0) > 0) ...[
                      const SizedBox(width: 8),
                      _Chip(Icons.local_cafe_outlined, fmtMins(breakMins), _orange, 'Break'),
                    ],
                  ]),
                ],

                // ── Reasons ──────────────────────────────────────────────────
                if (isLate && (lateReason?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 8),
                  _ReasonRow(Icons.schedule_rounded, 'Late reason', lateReason!, _red),
                ],
                if (isEarlyIn && (earlyInReason?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 6),
                  _ReasonRow(Icons.alarm_rounded, 'Early-in reason', earlyInReason!, _teal),
                ],
                if (isEarly && (earlyReason?.isNotEmpty ?? false)) ...[
                  const SizedBox(height: 6),
                  _ReasonRow(Icons.exit_to_app_rounded, 'Early-out reason', earlyReason!, _orange),
                ],
                if (adminNotes?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 6),
                  _ReasonRow(Icons.admin_panel_settings_outlined, 'Admin note', adminNotes!, _blue),
                ],

                // ── Photos ────────────────────────────────────────────────────
                if (inPhoto != null || outPhoto != null) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFF0F0F0)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (inPhoto != null)
                        Expanded(child: _PhotoThumb('In', ApiConfig.baseUrl + inPhoto)),
                      if (inPhoto != null && outPhoto != null)
                        const SizedBox(width: 6),
                      if (outPhoto != null)
                        Expanded(child: _PhotoThumb('Out', ApiConfig.baseUrl + outPhoto)),
                    ],
                  ),
                ],

                // ── Breaks ────────────────────────────────────────────────────
                if (breaks != null && breaks.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1, color: Color(0xFFF0F0F0)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: breaks.map((b) {
                      final bm    = b as Map;
                      final type  = (bm['type'] as String? ?? '').toUpperCase();
                      final start = _fmtBreak(bm['start'] as String?);
                      final end   = _fmtBreak(bm['end']   as String?);
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: _orange.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: _orange.withValues(alpha: 0.22)),
                        ),
                        child: Text(
                          '$type  $start → ${end ?? "ongoing"}',
                          style: const TextStyle(fontSize: 10, color: Color(0xFFF59E0B),
                              fontWeight: FontWeight.w600),
                        ),
                      );
                    }).toList(),
                  ),
                ],

              ],
            ),
          ),
        ],
      ),
    );
  }

  static String? _fmtBreak(String? raw) {
    if (raw == null) return null;
    try {
      final d = DateTime.parse(raw).toLocal();
      final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
      return '$h:${d.minute.toString().padLeft(2,'0')} ${d.hour<12?"AM":"PM"}';
    } catch (_) { return raw; }
  }
}

void _openMaps(BuildContext context, double lat, double lng, {String? title}) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => SingleLocationMapScreen(
        title: title ?? 'Location',
        latitude: lat,
        longitude: lng,
      ),
    ),
  );
}

// ─── Punch cell ───────────────────────────────────────────────────────────────

class _PunchCell extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   time;
  final String?  flag;
  final Color    flagColor;
  final Map?     location;

  const _PunchCell({
    required this.icon,
    required this.label,
    required this.time,
    required this.flagColor,
    this.flag,
    this.location,
  });

  @override
  Widget build(BuildContext context) {
    final hasLoc  = location?['lat'] != null && location?['lng'] != null;
    final lat     = hasLoc ? (location!['lat'] as num).toDouble() : 0.0;
    final lng     = hasLoc ? (location!['lng'] as num).toDouble() : 0.0;
    final iColor  = flag != null ? flagColor : const Color(0xFF43A047);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 12, color: iColor),
              const SizedBox(width: 4),
              Text(label,
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600, color: iColor)),
              if (flag != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: flagColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(flag!,
                      style: TextStyle(
                          fontSize: 8, fontWeight: FontWeight.w800, color: flagColor)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 3),
          // Time
          Text(time,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          // Location
          if (hasLoc)
            GestureDetector(
              onTap: () => _openMaps(context, lat, lng, title: '$label — $time'),
              child: Text.rich(
                TextSpan(children: [
                  const WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.location_on_rounded, size: 10,
                        color: Color(0xFF1E88E5)),
                  ),
                  TextSpan(
                    text: ' ${lat.toStringAsFixed(3)}, ${lng.toStringAsFixed(3)}',
                    style: const TextStyle(
                        fontSize: 9,
                        color: Color(0xFF1E88E5),
                        decoration: TextDecoration.underline),
                  ),
                ]),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            )
          else
            const Text('No location',
                style: TextStyle(fontSize: 9, color: Colors.black38)),
        ],
      ),
    );
  }
}

// ─── Work / Break chip ────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final IconData icon;
  final String   value;
  final Color    color;
  final String   label;

  const _Chip(this.icon, this.value, this.color, this.label);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w500)),
              Text(value,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Reason row ───────────────────────────────────────────────────────────────

class _ReasonRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   text;
  final Color    color;

  const _ReasonRow(this.icon, this.label, this.text, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 11, color: color),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '$label: ',
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, color: color),
              ),
              TextSpan(
                text: text,
                style: const TextStyle(fontSize: 10, color: Colors.black87),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}

// ─── Photo thumbnail ──────────────────────────────────────────────────────────

class _PhotoThumb extends StatelessWidget {
  final String label;
  final String url;

  const _PhotoThumb(this.label, this.url);

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
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text('$label Photo',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(8)),
                child: Image.network(url,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, e, st) => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Image unavailable',
                            style: TextStyle(color: Colors.grey)))),
              ),
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close')),
            ],
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            Image.network(url,
                width: double.infinity,
                height: 64,
                fit: BoxFit.cover,
                errorBuilder: (ctx, e, st) => Container(
                    width: double.infinity,
                    height: 64,
                    color: Colors.grey.shade100,
                    child: const Icon(Icons.broken_image_outlined,
                        color: Colors.grey, size: 22))),
            Positioned(
              bottom: 0, left: 0, right: 0,
              child: Container(
                color: Colors.black38,
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w600,
                        color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
