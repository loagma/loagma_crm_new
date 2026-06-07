import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../services/api_service.dart';

class AttendanceSettingsScreen extends StatefulWidget {
  final String employeeMobile;
  final Map<String, dynamic>? initialEmployee;

  const AttendanceSettingsScreen({
    super.key,
    required this.employeeMobile,
    this.initialEmployee,
  });

  @override
  State<AttendanceSettingsScreen> createState() =>
      _AttendanceSettingsScreenState();
}

class _AttendanceSettingsScreenState extends State<AttendanceSettingsScreen> {
  static const _gold = Color(0xFFD7BE69);

  bool _loading = true;
  bool _saving  = false;
  String? _error;

  TimeOfDay _punchIn        = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _punchOut       = const TimeOfDay(hour: 18, minute: 0);
  bool      _approvalRequired = true;
  late final TextEditingController _graceCtrl;

  String get _name =>
      widget.initialEmployee?['name'] as String? ?? widget.employeeMobile;

  @override
  void initState() {
    super.initState();
    _graceCtrl = TextEditingController(text: '15');
    _loadSettings();
  }

  @override
  void dispose() {
    _graceCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
      _error   = null;
    });
    try {
      final data =
          await ApiService.adminGetAttendanceSettings(widget.employeeMobile);
      if (!mounted) return;
      if (data != null) {
        _punchIn          = _parseTime(data['punch_in_time']  as String?);
        _punchOut         = _parseTime(data['punch_out_time'] as String?);
        _graceCtrl.text   = (data['grace_minutes'] ?? 15).toString();
        _approvalRequired = (data['approval_required'] as bool?) ?? true;
      }
    } catch (_) {
      if (mounted) _error = 'Failed to load settings';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  TimeOfDay _parseTime(String? raw) {
    if (raw == null) return const TimeOfDay(hour: 9, minute: 0);
    try {
      final parts = raw.split(':');
      return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
    } catch (_) {
      return const TimeOfDay(hour: 9, minute: 0);
    }
  }

  String _fmtTimeOfDay(TimeOfDay t) {
    final h   = t.hour.toString().padLeft(2, '0');
    final min = t.minute.toString().padLeft(2, '0');
    return '$h:$min';
  }

  String _displayTime(TimeOfDay t) {
    final h12  = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final min  = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '$h12:$min $ampm';
  }

  Future<void> _pickTime({required bool isIn}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isIn ? _punchIn : _punchOut,
    );
    if (picked != null && mounted) {
      setState(() {
        if (isIn) {
          _punchIn = picked;
        } else {
          _punchOut = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    final graceText = _graceCtrl.text.trim();
    final grace = int.tryParse(graceText);
    if (grace == null || grace < 0 || grace > 120) {
      Fluttertoast.showToast(msg: 'Grace period must be 0–120 minutes');
      return;
    }

    setState(() => _saving = true);
    try {
      final ok = await ApiService.adminUpdateAttendanceSettings(
        widget.employeeMobile,
        punchIn:          _fmtTimeOfDay(_punchIn),
        punchOut:         _fmtTimeOfDay(_punchOut),
        graceMinutes:     grace,
        approvalRequired: _approvalRequired,
      );
      if (!mounted) return;
      if (ok) {
        Fluttertoast.showToast(msg: 'Settings saved');
        Navigator.of(context).pop(true);
      } else {
        Fluttertoast.showToast(msg: 'Failed to save settings');
      }
    } catch (e) {
      if (mounted) Fluttertoast.showToast(msg: 'Error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Shift Settings — $_name'),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!,
                          style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 12),
                      ElevatedButton(
                          onPressed: _loadSettings,
                          child: const Text('Retry')),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Set the expected punch-in/out times, grace period, and approval policy for this employee.',
                        style: TextStyle(
                            fontSize: 13, color: Colors.black54),
                      ),
                      const SizedBox(height: 28),

                      // ── Punch In time ────────────────────────────────
                      _SectionLabel(label: 'Expected Punch-In Time'),
                      const SizedBox(height: 8),
                      _TimeTile(
                        icon: Icons.login_rounded,
                        label: _displayTime(_punchIn),
                        onTap: () => _pickTime(isIn: true),
                      ),
                      const SizedBox(height: 20),

                      // ── Punch Out time ───────────────────────────────
                      _SectionLabel(label: 'Expected Punch-Out Time'),
                      const SizedBox(height: 8),
                      _TimeTile(
                        icon: Icons.logout_rounded,
                        label: _displayTime(_punchOut),
                        onTap: () => _pickTime(isIn: false),
                      ),
                      const SizedBox(height: 20),

                      // ── Grace period ─────────────────────────────────
                      _SectionLabel(label: 'Grace Period (minutes)'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _graceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'e.g. 15',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10)),
                          suffixText: 'min',
                          helperText:
                              'Punching in within this many minutes after the expected time is still considered on-time',
                        ),
                      ),
                      const SizedBox(height: 24),

                      // ── Approval required ────────────────────────────
                      _SectionLabel(label: 'Approval Settings'),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black12),
                          borderRadius: BorderRadius.circular(10),
                          color: Colors.white,
                        ),
                        child: CheckboxListTile(
                          value: _approvalRequired,
                          onChanged: (v) =>
                              setState(() => _approvalRequired = v ?? true),
                          title: const Text(
                            'Require approval for late / early punch',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            _approvalRequired
                                ? 'Late punch-in and early punch-out will need admin approval'
                                : 'Employee can punch in/out at any time without approval',
                            style: TextStyle(
                                fontSize: 11,
                                color: _approvalRequired
                                    ? Colors.black54
                                    : const Color(0xFF43A047)),
                          ),
                          activeColor: _gold,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // ── Save button ──────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _gold,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white))
                              : const Text('Save Settings',
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(label,
        style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black87));
  }
}

class _TimeTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _TimeTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black26),
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFFD7BE69), size: 22),
            const SizedBox(width: 12),
            Text(label,
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600)),
            const Spacer(),
            const Icon(Icons.access_time_rounded,
                color: Colors.black38, size: 20),
          ],
        ),
      ),
    );
  }
}
