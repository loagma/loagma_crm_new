import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import 'telecaller_actions.dart';
import 'telecaller_mock_data.dart';

/// Call History (live data). The telecaller's recent calls with outcome, the
/// note from last time and when — so they see the last conversation before
/// dialling again. Searchable; tap to re-call.
class TelecallerCallHistoryScreen extends StatefulWidget {
  const TelecallerCallHistoryScreen({super.key});

  @override
  State<TelecallerCallHistoryScreen> createState() => _TelecallerCallHistoryScreenState();
}

class _TelecallerCallHistoryScreenState extends State<TelecallerCallHistoryScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await ApiService.getTelecallerCallHistory();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  String _relative(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final items = q.isEmpty
        ? _items
        : _items.where((h) => '${h['name'] ?? ''}'.toLowerCase().contains(q) || '${h['phone'] ?? ''}'.contains(q)).toList();

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Call History'),
        backgroundColor: kGold,
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                hintText: 'Search by name or number…',
                prefixIcon: const Icon(Icons.search_rounded, color: kGoldDark),
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kGold)),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kGold))
                : items.isEmpty
                    ? Center(
                        child: Text(_query.isEmpty ? 'No calls logged yet' : 'No calls match "$_query"',
                            style: TextStyle(color: Colors.grey.shade500)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                          itemCount: items.length,
                          itemBuilder: (_, i) => _row(items[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> h) {
    final outcome = '${h['outcome'] ?? ''}';
    final color = kOutcomeColors[outcome] ?? Colors.grey;
    final phone = '${h['phone'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 40, width: 40,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(Icons.history_rounded, color: color, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text('${h['name'] ?? 'Unknown'}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700))),
                    Text(_relative('${h['called_at'] ?? ''}'), style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
                      child: Text(kOutcomeLabels[outcome] ?? outcome,
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
                    ),
                    const SizedBox(width: 8),
                    Text(phone, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
                if ((h['notes'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text('${h['notes']}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.call_rounded, color: Color(0xFF43A047)),
            tooltip: 'Call again',
            onPressed: () => launchPhoneCall(phone),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
