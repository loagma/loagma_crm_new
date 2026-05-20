import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';

class AreaPincodeScreen extends StatefulWidget {
  final Map<String, dynamic> area;

  const AreaPincodeScreen({super.key, required this.area});

  @override
  State<AreaPincodeScreen> createState() => _AreaPincodeScreenState();
}

class _AreaPincodeScreenState extends State<AreaPincodeScreen> {
  static const gold = Color(0xFFD7BE69);

  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _loading = false;
  Map<String, dynamic>? _area;

  int get _areaId => int.tryParse((widget.area['id'] ?? '').toString()) ?? 0;
  String get _areaName => ((_area ?? widget.area)['area_name'] ?? 'Area').toString();

  List<String> get _pincodes {
    final raw = (_area ?? widget.area)['pincodes'];
    if (raw is List) return raw.map((e) => e.toString()).toList();
    return <String>[];
  }

  @override
  void initState() {
    super.initState();
    _loadArea();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadArea() async {
    setState(() => _loading = true);
    final data = await ApiService.getArea(_areaId);
    if (!mounted) return;
    setState(() {
      _area = data ?? widget.area;
      _loading = false;
    });
  }

  List<String> get _filtered {
    final p = _pincodes;
    if (_query.isEmpty) return p;
    return p.where((e) => e.contains(_query)).toList();
  }

  Future<void> _showAddDialog() async {
    final ctrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Add Pincode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            decoration: InputDecoration(
              labelText: 'Pincode *',
              hintText: 'Enter 6-digit pincode',
              prefixIcon: const Icon(Icons.pin_drop_outlined, color: gold),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: gold, width: 2),
              ),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Pincode is required';
              if (!RegExp(r'^\d{6}$').hasMatch(v.trim())) return 'Enter valid 6-digit pincode';
              return null;
            },
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final res = await ApiService.addAreaPincodes(_areaId, [ctrl.text.trim()]);
              if (!mounted) return;
              if (res == null || res.containsKey('errors')) {
                final msg = res?['errors']?.toString() ?? 'Failed to add pincode';
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                return;
              }
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() => _area = res);
            },
            style: ElevatedButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.white),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showEditDialog(String oldPin) async {
    final ctrl = TextEditingController(text: oldPin);
    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Pincode'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Required';
              if (!RegExp(r'^\d{6}$').hasMatch(v.trim())) return 'Enter valid 6-digit pincode';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final res = await ApiService.updateAreaPincode(_areaId, oldPin, ctrl.text.trim());
              if (!mounted) return;
              if (res == null || res.containsKey('errors')) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to update pincode')));
                return;
              }
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() => _area = res);
            },
            style: ElevatedButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.white),
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _deletePincode(String pincode) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Pincode'),
        content: Text('Delete pincode $pincode?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await ApiService.deleteAreaPincode(_areaId, pincode);
    if (!mounted) return;
    if (!done) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to delete pincode')));
      return;
    }
    await _loadArea();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(_areaName),
        backgroundColor: gold,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: gold.withValues(alpha: 0.1),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.location_on_rounded, size: 14, color: gold),
                const SizedBox(width: 6),
                Text(
                  '$_areaName  •  ${_pincodes.length} pincode${_pincodes.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12, color: gold, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _searchCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search pincodes...',
                prefixIcon: const Icon(Icons.search_rounded, color: gold),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                isDense: true,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: gold)),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: gold))
                : filtered.isEmpty
                    ? _emptyState()
                    : RefreshIndicator(
                        onRefresh: _loadArea,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final p = filtered[i];
                            return Card(
                              color: Colors.white,
                              margin: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 1.5,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: gold.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(Icons.pin_drop_rounded, color: gold, size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        p,
                                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => _showEditDialog(p),
                                      icon: const Icon(Icons.edit_rounded, size: 18),
                                      tooltip: 'Edit',
                                    ),
                                    IconButton(
                                      onPressed: () => _deletePincode(p),
                                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                                      tooltip: 'Delete',
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDialog,
        backgroundColor: gold,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_query.isNotEmpty ? Icons.search_off_rounded : Icons.pin_drop_outlined, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(_query.isNotEmpty ? 'No results for "$_query"' : 'No pincodes yet', style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            if (_query.isEmpty) Text('Tap + to add pincode for this area', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          ],
        ),
      );
}
