import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../services/api_service.dart';
import 'telecaller_actions.dart';
import 'telecaller_mock_data.dart';

/// Today's + overdue callbacks (live data). Each row can Call, WhatsApp,
/// Snooze (reschedule the follow-up date) or mark Done — both persisted via
/// `PUT /api/call-logs/{id}`.
class TelecallerCallbacksScreen extends StatefulWidget {
  const TelecallerCallbacksScreen({super.key});

  @override
  State<TelecallerCallbacksScreen> createState() => _TelecallerCallbacksScreenState();
}

class _TelecallerCallbacksScreenState extends State<TelecallerCallbacksScreen> {
  bool _loading = true;
  bool _busy = false;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await ApiService.getTelecallerCallbacks();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final overdue = _items.where((c) => c['overdue'] == true).toList();
    final upcoming = _items.where((c) => c['overdue'] != true).toList();

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text("Today's Callbacks"),
        backgroundColor: kGold,
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
                children: [
                  _summary(overdue.length, upcoming.length),
                  if (overdue.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _header('Overdue', overdue.length, const Color(0xFFE53935)),
                    ...overdue.map(_row),
                  ],
                  if (upcoming.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _header('Upcoming', upcoming.length, kGoldDark),
                    ...upcoming.map(_row),
                  ],
                  if (_items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: Center(child: Text('No callbacks scheduled', style: TextStyle(color: Colors.grey.shade500, fontSize: 15))),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _summary(int overdue, int upcoming) {
    Widget cell(String label, int v, Color c) => Expanded(
          child: Column(
            children: [
              Text('$v', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: c)),
              Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        );
    return Container(
      decoration: _cardDeco(),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(children: [
        cell('Overdue', overdue, const Color(0xFFE53935)),
        cell('Upcoming', upcoming, kGoldDark),
        cell('Total', overdue + upcoming, const Color(0xFF1E88E5)),
      ]),
    );
  }

  Widget _header(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
      child: Row(children: [
        Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
          child: Text('$count', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      ]),
    );
  }

  Widget _row(Map<String, dynamic> c) {
    final overdue = c['overdue'] == true;
    final color = overdue ? const Color(0xFFE53935) : kGoldDark;
    final phone = '${c['phone'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: _cardDeco(),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Text('${c['follow_up_date'] ?? ''}',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${c['name'] ?? 'Unknown'}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    Text('$phone${(c['area'] ?? '').toString().isNotEmpty ? ' · ${c['area']}' : ''}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    if ((c['notes'] ?? '').toString().isNotEmpty)
                      Text('${c['notes']}', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10.5, color: Colors.grey.shade400)),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 16),
          Row(
            children: [
              _action(Icons.call_rounded, 'Call', const Color(0xFF43A047), () => launchPhoneCall(phone)),
              _action(Icons.chat_rounded, 'WhatsApp', const Color(0xFF25D366), () => launchWhatsApp(phone)),
              _action(Icons.snooze_rounded, 'Snooze', const Color(0xFFFB8C00), () => _snooze(c)),
              _action(Icons.check_circle_rounded, 'Done', const Color(0xFF1E88E5), () => _markDone(c)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _action(IconData icon, String label, Color color, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: _busy ? null : onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              Icon(icon, size: 19, color: color),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _snooze(Map<String, dynamic> c) async {
    final id = c['id'] as int?;
    if (id == null) return;
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Reschedule callback to',
    );
    if (picked == null) return;
    final dateStr = '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    setState(() => _busy = true);
    final ok = await ApiService.updateCallLog(id, followUpDate: dateStr);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Fluttertoast.showToast(msg: 'Rescheduled to $dateStr', backgroundColor: kGoldDark, textColor: Colors.white);
      _load();
    } else {
      Fluttertoast.showToast(msg: 'Could not reschedule', backgroundColor: Colors.red, textColor: Colors.white);
    }
  }

  Future<void> _markDone(Map<String, dynamic> c) async {
    final id = c['id'] as int?;
    if (id == null) return;
    setState(() => _busy = true);
    final ok = await ApiService.updateCallLog(id, callbackDone: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Fluttertoast.showToast(msg: 'Marked done', backgroundColor: const Color(0xFF43A047), textColor: Colors.white);
      _load();
    } else {
      Fluttertoast.showToast(msg: 'Could not update', backgroundColor: Colors.red, textColor: Colors.white);
    }
  }
}

BoxDecoration _cardDeco() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFEEEEEE)),
      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
    );
