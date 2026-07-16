import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';

// Real catalog search (product table via ApiService.searchProducts) — used
// wherever a Sales Order line item needs a genuine product_id, not free text.
class ProductPickerSheet extends StatefulWidget {
  const ProductPickerSheet({super.key});

  @override
  State<ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<ProductPickerSheet> {
  static const _gold = Color(0xFFD7BE69);

  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  bool _failed = false;
  List<Map<String, dynamic>> _results = [];

  // Bumped on every new search; a response is only applied if it's still the
  // most recent one requested — guards against a slower earlier request
  // overwriting a faster later one and showing stale/wrong results.
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    final myRequestId = ++_requestId;
    setState(() { _loading = true; _failed = false; });
    final results = await ApiService.searchProducts(q);
    if (!mounted || myRequestId != _requestId) return; // a newer search superseded this one
    setState(() {
      _loading = false;
      if (results == null) {
        _failed = true;
      } else {
        _results = results;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.fromLTRB(18, 8, 18, 12 + MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 42, height: 4, margin: const EdgeInsets.only(top: 8, bottom: 16), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(3)))),
          const Text('Select Product', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: 'Search products…',
              prefixIcon: const Icon(Icons.search_rounded, color: _gold),
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFFAFAFA),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE7E7E7))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE7E7E7))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: _gold)),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _gold))
                : _failed
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.wifi_off_rounded, size: 40, color: Colors.grey.shade300),
                            const SizedBox(height: 10),
                            Text('Could not search products. Check your connection.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                            const SizedBox(height: 10),
                            ElevatedButton.icon(
                              onPressed: () => _search(_searchCtrl.text),
                              icon: const Icon(Icons.refresh_rounded, size: 16),
                              label: const Text('Retry'),
                              style: ElevatedButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.white),
                            ),
                          ],
                        ),
                      )
                    : _results.isEmpty
                    ? Center(child: Text('No products found', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)))
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final p = _results[i];
                          final name = (p['name'] ?? '').toString();
                          final hsn  = (p['hsn_code'] ?? '').toString();
                          return ListTile(
                            title: Text(name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                            subtitle: hsn.isNotEmpty ? Text('HSN: $hsn', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)) : null,
                            onTap: () => Navigator.of(context).pop(p),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
