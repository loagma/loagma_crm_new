import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../services/api_service.dart';
import 'telecaller_actions.dart';
import 'telecaller_mock_data.dart';

/// Worklist with labels (live data). Filter leads/customers by label and apply
/// one-tap Quick Actions (Wrong number / Do-Not-Call) which persist via
/// `POST /api/telecaller/label`. "Not called / Called today / Follow-up due"
/// are derived server-side from the call log.
class TelecallerWorklistScreen extends StatefulWidget {
  const TelecallerWorklistScreen({super.key});

  @override
  State<TelecallerWorklistScreen> createState() => _TelecallerWorklistScreenState();
}

class _TelecallerWorklistScreenState extends State<TelecallerWorklistScreen> {
  bool _loading = true;
  bool _busy = false;
  List<Map<String, dynamic>> _items = [];
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final items = await ApiService.getTelecallerWorklist();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  int _countFor(String key) =>
      key == 'all' ? _items.length : _items.where((w) => w['label'] == key).length;

  @override
  Widget build(BuildContext context) {
    final visible = _filter == 'all' ? _items : _items.where((w) => w['label'] == _filter).toList();

    final chips = <(String, String)>[
      ('all', 'All'),
      (kLabelNotCalled, kWorklistLabels[kLabelNotCalled]!.text),
      (kLabelCalledToday, kWorklistLabels[kLabelCalledToday]!.text),
      (kLabelFollowUp, kWorklistLabels[kLabelFollowUp]!.text),
      (kLabelWrongNumber, kWorklistLabels[kLabelWrongNumber]!.text),
      (kLabelDoNotCall, kWorklistLabels[kLabelDoNotCall]!.text),
    ];

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Worklist'),
        backgroundColor: kGold,
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 50,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final c in chips)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text('${c.$2} (${_countFor(c.$1)})'),
                      selected: _filter == c.$1,
                      onSelected: (_) => setState(() => _filter = c.$1),
                      selectedColor: kGold,
                      labelStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _filter == c.$1 ? Colors.white : Colors.grey.shade700),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kGold))
                : visible.isEmpty
                    ? Center(child: Text(_items.isEmpty ? 'No leads in your areas' : 'No leads in this label',
                        style: TextStyle(color: Colors.grey.shade500)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                          itemCount: visible.length,
                          itemBuilder: (_, i) => _row(visible[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> w) {
    final ls = worklistLabelStyle('${w['label'] ?? kLabelNotCalled}');
    final phone = '${w['phone'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${w['name'] ?? 'Unknown'}', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    Text('$phone${(w['area'] ?? '').toString().isNotEmpty ? ' · ${w['area']}' : ''}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: ls.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                child: Text(ls.text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: ls.color)),
              ),
            ],
          ),
          const Divider(height: 16),
          Row(
            children: [
              _action(Icons.call_rounded, 'Call', const Color(0xFF43A047), () => launchPhoneCall(phone)),
              _action(Icons.chat_rounded, 'WhatsApp', const Color(0xFF25D366), () => launchWhatsApp(phone)),
              _action(Icons.report_gmailerrorred_rounded, 'Wrong No.', const Color(0xFFE53935), () => _setLabel(w, kLabelWrongNumber)),
              _action(Icons.block_rounded, 'Do Not Call', Colors.black87, () => _setLabel(w, kLabelDoNotCall)),
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
              Icon(icon, size: 18, color: color),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 9.5, color: color, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setLabel(Map<String, dynamic> w, String label) async {
    setState(() => _busy = true);
    final ok = await ApiService.setTelecallerLabel('${w['account_id']}', '${w['account_type']}', label);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      Fluttertoast.showToast(msg: '${w['name']} → ${worklistLabelStyle(label).text}', backgroundColor: kGoldDark, textColor: Colors.white);
      _load();
    } else {
      Fluttertoast.showToast(msg: 'Could not update', backgroundColor: Colors.red, textColor: Colors.white);
    }
  }
}
