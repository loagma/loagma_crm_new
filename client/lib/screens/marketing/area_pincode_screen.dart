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
  // pincode → list of other area names that have it
  Map<String, List<String>> _otherAreas = {};

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

    // Build map of pincode → other areas that have it
    final otherAreas = <String, List<String>>{};
    try {
      final allAreas = await ApiService.getAreas(perPage: 1000);
      final areasList = (allAreas['data'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      for (final area in areasList) {
        final aid = int.tryParse((area['id'] ?? '').toString()) ?? 0;
        if (aid == _areaId) continue; // skip current area
        final areaName = (area['area_name'] ?? '').toString();
        final pins = area['pincodes'];
        if (pins is List) {
          for (final p in pins) {
            final pin = p.toString();
            otherAreas.putIfAbsent(pin, () => []).add(areaName);
          }
        }
      }
    } catch (_) {
      // if fetch fails, just leave map empty — no other areas shown
    }

    if (mounted) {
      setState(() {
        _area = data ?? widget.area;
        _otherAreas = otherAreas;
        _loading = false;
      });
    }
  }

  List<String> get _filtered {
    final p = _pincodes;
    if (_query.isEmpty) return p;
    return p.where((e) => e.contains(_query)).toList();
  }

  void _toast(String msg, {bool success = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? const Color(0xFF43A047) : Colors.red,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2),
    ));
  }

  // Returns the name of another area that already contains [pin], or null.
  Future<String?> _pincodeInOtherArea(String pin) async {
    final res = await ApiService.getAreas(perPage: 1000);
    final data = res['data'];
    if (data is! List) return null;
    for (final raw in data) {
      final a   = Map<String, dynamic>.from(raw as Map);
      final aid = int.tryParse((a['id'] ?? '').toString()) ?? 0;
      if (aid == _areaId) continue; // skip the current area
      final pins = a['pincodes'];
      if (pins is List && pins.map((e) => e.toString()).contains(pin)) {
        return (a['area_name'] ?? 'another area').toString();
      }
    }
    return null;
  }

  Future<bool?> _confirmDuplicatePincode(String pin, String otherArea) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Pincode Already Exists',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Text(
          'Pincode $pin is already assigned to "$otherArea". '
          'Do you want to add it to this area as well?',
          style: const TextStyle(fontSize: 13.5),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: gold, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Yes, add'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAddDialog() async {
    final ctrl = TextEditingController();

    // Lookup state, scoped to the dialog
    bool                  looking = false;
    Map<String, dynamic>? lookup;   // {country, state, district, city, areas}
    String?               lookupError;
    String                lastQueried = '';

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final pin     = ctrl.text.trim();
          final valid6  = RegExp(r'^\d{6}$').hasMatch(pin);
          final canAdd  = valid6 && lookup != null && !looking;

          Future<void> runLookup(String p) async {
            if (p == lastQueried) return;
            lastQueried = p;
            setLocal(() { looking = true; lookup = null; lookupError = null; });
            final res = await ApiService.lookupIndianPincode(p);
            if (!ctx.mounted) return;
            setLocal(() {
              looking = false;
              if (res == null) {
                lookupError = 'Pincode not found. Please check and try again.';
              } else {
                lookup = res;
              }
            });
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: const Text('Add Pincode',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onChanged: (v) {
                    final t = v.trim();
                    setLocal(() {
                      lookup = null;
                      lookupError = null;
                    });
                    if (RegExp(r'^\d{6}$').hasMatch(t)) runLookup(t);
                  },
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
                ),
                const SizedBox(height: 10),
                // ── Lookup feedback ────────────────────────────────────────
                if (looking)
                  const Row(children: [
                    SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: gold)),
                    SizedBox(width: 8),
                    Text('Checking pincode…',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ])
                else if (lookupError != null)
                  Row(children: [
                    const Icon(Icons.error_outline_rounded, size: 16, color: Colors.red),
                    const SizedBox(width: 6),
                    Expanded(child: Text(lookupError!,
                        style: const TextStyle(fontSize: 12, color: Colors.red))),
                  ])
                else if (lookup != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF43A047).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF43A047).withValues(alpha: 0.30)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF2E7D32)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${lookup!['city'] ?? ''}, ${lookup!['district'] ?? ''}',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700,
                                  color: Color(0xFF2E7D32)),
                            ),
                          ),
                        ]),
                        if ((lookup!['state'] ?? '').toString().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text('${lookup!['state']}, ${lookup!['country'] ?? 'India'}',
                              style: const TextStyle(fontSize: 11, color: Colors.black54)),
                        ],
                        if ((lookup!['areas'] as List?)?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 6),
                          Text('Post offices:',
                              style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Wrap(
                            spacing: 4, runSpacing: 4,
                            children: (lookup!['areas'] as List)
                                .take(6)
                                .map((a) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.grey.shade300),
                                      ),
                                      child: Text(a.toString(),
                                          style: const TextStyle(fontSize: 9.5, color: Colors.black87)),
                                    ))
                                .toList(),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
              ElevatedButton(
                onPressed: canAdd
                    ? () async {
                        // Duplicate-pincode guard: is this pincode already in
                        // another area? If so, confirm before adding here too.
                        final otherArea = await _pincodeInOtherArea(pin);
                        if (!mounted) return;
                        if (otherArea != null) {
                          final proceed = await _confirmDuplicatePincode(pin, otherArea);
                          if (proceed != true) return; // keep dialog open
                        }
                        final res = await ApiService.addAreaPincodes(_areaId, [pin]);
                        if (!mounted) return;
                        if (res == null || res.containsKey('errors')) {
                          final msg = res?['errors']?.toString() ?? 'Failed to add pincode';
                          _toast(msg, success: false);
                          return;
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                        setState(() => _area = res);
                        _toast('Pincode $pin added successfully');
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                    backgroundColor: gold, foregroundColor: Colors.white,
                    disabledBackgroundColor: gold.withValues(alpha: 0.4)),
                child: const Text('Add'),
              ),
            ],
          );
        },
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
              final newPin = ctrl.text.trim();
              final res = await ApiService.updateAreaPincode(_areaId, oldPin, newPin);
              if (!mounted) return;
              if (res == null || res.containsKey('errors')) {
                _toast('Failed to update pincode', success: false);
                return;
              }
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() => _area = res);
              _toast('Pincode updated to $newPin');
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
      _toast('Failed to delete pincode', success: false);
      return;
    }
    await _loadArea();
    _toast('Pincode $pincode deleted');
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
                            final others = _otherAreas[p] ?? [];
                            return Card(
                              color: Colors.white,
                              margin: EdgeInsets.zero,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 1.5,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
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
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Pincode',
                                                style: TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: 0.3,
                                                  color: Colors.grey.shade600,
                                                ),
                                              ),
                                              Text(
                                                p,
                                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 1),
                                              ),
                                            ],
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
                                    // "Also in" chip for other areas
                                    if (others.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: gold.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: gold.withValues(alpha: 0.3)),
                                        ),
                                        child: Text(
                                          'marketing Area: ${others.join(', ')}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF8A6D1B),
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
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
