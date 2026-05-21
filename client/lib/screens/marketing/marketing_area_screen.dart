import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';

class MarketingAreaScreen extends StatefulWidget {
  const MarketingAreaScreen({super.key});

  @override
  State<MarketingAreaScreen> createState() => _MarketingAreaScreenState();
}

class _MarketingAreaScreenState extends State<MarketingAreaScreen> {
  static const gold = Color(0xFFD7BE69);

  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  String _query = '';
  List<Map<String, dynamic>> _areas = [];

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  int _idOf(Map<String, dynamic> area) => int.tryParse((area['id'] ?? '').toString()) ?? 0;

  String _nameOf(Map<String, dynamic> area) => (area['area_name'] ?? '').toString();

  Future<void> _loadAreas() async {
    setState(() => _loading = true);
    final result = await ApiService.getAreas(q: _query.isEmpty ? null : _query);
    if (!mounted) return;
    final raw = result['data'];
    final list = raw is List
        ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
        : <Map<String, dynamic>>[];
    setState(() {
      _areas = list;
      _loading = false;
    });
  }

  void _onSearchChanged(String v) {
    _query = v.trim();
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _loadAreas);
  }

  Future<void> _showCreateOrEditDialog({Map<String, dynamic>? area}) async {
    final ctrl = TextEditingController(text: area == null ? '' : _nameOf(area));
    final formKey = GlobalKey<FormState>();
    final isEdit = area != null;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(isEdit ? 'Edit Area' : 'New Area', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Area Name *',
              prefixIcon: const Icon(Icons.location_on_outlined, color: gold),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: gold, width: 2),
              ),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Area name is required' : null,
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final name = ctrl.text.trim();
              Map<String, dynamic>? res;
              if (isEdit) {
                res = await ApiService.updateArea(_idOf(area), areaName: name);
              } else {
                res = await ApiService.createArea(name);
              }
              if (!mounted) return;
              if (res == null || res.containsKey('errors')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(isEdit ? 'Failed to update area' : 'Failed to create area')),
                );
                return;
              }
              if (ctx.mounted) Navigator.pop(ctx);
              _loadAreas();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: gold,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(isEdit ? 'Update' : 'Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteArea(Map<String, dynamic> area) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Area'),
        content: Text('Delete "${_nameOf(area)}"?'),
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

    final done = await ApiService.deleteArea(_idOf(area));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(done ? 'Area deleted' : 'Failed to delete area')),
    );
    if (done) _loadAreas();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Marketing Area'),
        backgroundColor: gold,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search areas...',
                prefixIcon: const Icon(Icons.search_rounded, color: gold),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _query = '';
                          _loadAreas();
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
                : _areas.isEmpty
                    ? _emptyState()
                    : RefreshIndicator(
                        onRefresh: _loadAreas,
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                          itemCount: _areas.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final area = _areas[i];
                            final pins = area['pincodes'] is List ? (area['pincodes'] as List).length : 0;
                            return _AreaCard(
                              area: area,
                              pincodeCount: pins,
                              onTap: () async {
                                final changed = await context.push('/marketing-area/${_idOf(area)}', extra: area);
                                if (changed == true) _loadAreas();
                              },
                              onEdit: () => _showCreateOrEditDialog(area: area),
                              onDelete: () => _deleteArea(area),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCreateOrEditDialog(),
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
            Icon(_query.isNotEmpty ? Icons.search_off_rounded : Icons.location_off_rounded, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(_query.isNotEmpty ? 'No results for "$_query"' : 'No areas yet', style: TextStyle(fontSize: 15, color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            if (_query.isEmpty) Text('Tap + to add the first area', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          ],
        ),
      );
}

class _AreaCard extends StatelessWidget {
  final Map<String, dynamic> area;
  final int pincodeCount;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _AreaCard({
    required this.area,
    required this.pincodeCount,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = (area['area_name'] ?? '').toString();
    final id = (area['id'] ?? '').toString();

    return GestureDetector(
      onTap: onTap,
      child: Card(
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 1.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFD7BE69).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.location_on_rounded, color: Color(0xFFD7BE69), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('ID: $id --- $pincodeCount pincodes ', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
