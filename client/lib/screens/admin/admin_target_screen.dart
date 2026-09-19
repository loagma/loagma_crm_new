import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';

import '../../services/api_service.dart';

/// Admin -> Targets. Per-telecaller monthly call/conversion goals, backed by
/// GET/POST /api/targets. Feeds the Telecaller Performance report's
/// "scorecard vs. target" view.
class AdminTargetScreen extends StatefulWidget {
  const AdminTargetScreen({super.key});

  @override
  State<AdminTargetScreen> createState() => _AdminTargetScreenState();
}

class _AdminTargetScreenState extends State<AdminTargetScreen> {
  static const _gold = Color(0xFFD7BE69);
  static const _bg = Color(0xFFF5F5F5);

  late String _period; // 'YYYY-MM', defaults to current month
  bool _isLoading = true;
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _period = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final rows = await ApiService.getTargets(period: _period);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _isLoading = false;
    });
  }

  Future<void> _changeMonth(int deltaMonths) async {
    final parts = _period.split('-');
    var year = int.parse(parts[0]);
    var month = int.parse(parts[1]) + deltaMonths;
    while (month < 1) { month += 12; year -= 1; }
    while (month > 12) { month -= 12; year += 1; }
    setState(() => _period = '$year-${month.toString().padLeft(2, '0')}');
    await _load();
  }

  Future<void> _editTarget(Map<String, dynamic> row) async {
    final callCtrl = TextEditingController(text: '${row['call_target'] ?? 0}');
    final convCtrl = TextEditingController(text: '${row['conversion_target'] ?? 0}');
    final formKey = GlobalKey<FormState>();

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(row['name']?.toString() ?? 'Set target',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: callCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Call target', border: OutlineInputBorder(), isDense: true),
                validator: (v) => (int.tryParse(v ?? '') == null) ? 'Enter a number' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: convCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Conversion target', border: OutlineInputBorder(), isDense: true),
                validator: (v) => (int.tryParse(v ?? '') == null) ? 'Enter a number' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.white),
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;

    final res = await ApiService.saveTarget(
      telecallerId: row['telecaller_id'].toString(),
      period: _period,
      callTarget: int.parse(callCtrl.text),
      conversionTarget: int.parse(convCtrl.text),
    );
    final ok = res != null && res['success'] == true;
    if (mounted) {
      Fluttertoast.showToast(msg: ok ? 'Target saved' : (res?['message']?.toString() ?? 'Failed to save'));
      if (ok) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Targets', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: _gold,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(onPressed: () => _changeMonth(-1), icon: const Icon(Icons.chevron_left)),
                Text(_period, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                IconButton(onPressed: () => _changeMonth(1), icon: const Icon(Icons.chevron_right)),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? const Center(child: Text('No telecallers found', style: TextStyle(color: Colors.black54)))
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(12),
                          itemCount: _rows.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final row = _rows[i];
                            return Card(
                              elevation: 1,
                              margin: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              child: ListTile(
                                title: Text(row['name']?.toString() ?? row['telecaller_id'].toString(),
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                                subtitle: Text(
                                  'Calls: ${row['call_target']}   •   Conversions: ${row['conversion_target']}',
                                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                                ),
                                trailing: IconButton(
                                  icon: Icon(Icons.edit_rounded, color: _gold, size: 20),
                                  onPressed: () => _editTarget(row),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
