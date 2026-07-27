import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_config.dart';
import '../../services/api_service.dart';
import '../../widgets/account_map_screen.dart';
import '../../widgets/hover_image_preview.dart';

class LeadAccountListScreen extends StatefulWidget {
  const LeadAccountListScreen({super.key});

  @override
  State<LeadAccountListScreen> createState() => _LeadAccountListScreenState();
}

class _LeadAccountListScreenState extends State<LeadAccountListScreen> {
  static const gold = Color(0xFFD7BE69);

  final _searchCtrl    = TextEditingController();
  final _scrollCtrl    = ScrollController();

  final List<Map<String, dynamic>> _items = [];
  int  _page    = 1;
  bool _loading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _loadPage();
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _loading) return;
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 120) {
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    if (_loading) return;
    setState(() => _loading = true);

    final q = _searchCtrl.text.trim();
    final result = await ApiService.getLeadAccounts(
      q:       q.isEmpty ? null : q,
      page:    _page,
      perPage: 20,
    );

    if (!mounted) return;

    final raw  = result['data'];
    final list = raw is List
        ? List<Map<String, dynamic>>.from(raw.map((e) => Map<String, dynamic>.from(e as Map)))
        : <Map<String, dynamic>>[];

    setState(() {
      if (_page == 1) {
        _items
          ..clear()
          ..addAll(list);
      } else {
        _items.addAll(list);
      }
      _hasMore = list.length >= 20;
      _page++;
      _loading = false;
    });
  }

  void _refresh() {
    _page = 1;
    _hasMore = true;
    _loadPage();
  }

  void _onSearchChanged(String _) {
    _page = 1;
    _hasMore = true;
    _items.clear();
    _loadPage();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Color _stageColor(String? stage) {
    switch ((stage ?? '').toLowerCase()) {
      case 'customer':   return Colors.green;
      case 'qualified':  return Colors.blue;
      case 'opportunity': return Colors.indigo;
      case 'prospect':   return Colors.orange;
      case 'lead':       return Colors.amber.shade700;
      case 'churned':    return Colors.red;
      default:           return Colors.grey;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Lead Accounts'),
        backgroundColor: gold,
        foregroundColor: Colors.white,
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.map_rounded),
              tooltip: 'Show in Map',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AccountMapScreen(
                    title: 'Lead Accounts — Map',
                    accounts: _items
                        .map((a) => {...a, '_type': 'lead'})
                        .toList(),
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: _refresh,
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await context.push('/lead-account');
          if (created == true) _refresh();
        },
        backgroundColor: gold,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_business_rounded),
        label: const Text('New Lead'),
      ),
      body: Column(
        children: [
          // ── Search bar ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by name, contact, area, code…',
                prefixIcon: const Icon(Icons.search_rounded, color: gold),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: gold),
                ),
              ),
            ),
          ),

          // ── Count badge ──────────────────────────────────────────────
          if (_items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${_items.length} lead${_items.length == 1 ? '' : 's'}${_hasMore ? '+' : ''}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ),

          // ── List ─────────────────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              color: gold,
              onRefresh: () async => _refresh(),
              child: _items.isEmpty && !_loading
                  ? _emptyState()
                  : ListView.separated(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                      itemCount: _items.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        if (i >= _items.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator(color: gold)),
                          );
                        }
                        return _buildCard(_items[i]);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => ListView(
    children: [
      const SizedBox(height: 80),
      Icon(Icons.business_center_outlined, size: 64, color: Colors.grey.shade300),
      const SizedBox(height: 12),
      Text(
        _searchCtrl.text.isEmpty ? 'No lead accounts yet' : 'No results found',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, color: Colors.grey.shade500),
      ),
      const SizedBox(height: 6),
      Text(
        _searchCtrl.text.isEmpty ? 'Tap + to create your first lead account' : 'Try a different search term',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
      ),
    ],
  );

  Widget _buildCard(Map<String, dynamic> item) {
    final bizName   = item['businessName']  as String? ?? '—';
    final person    = item['personName']    as String? ?? '—';
    final contact   = item['contactNumber'] as String? ?? '—';
    final code      = item['accountCode']   as String? ?? '';
    final city      = item['city']          as String? ?? '';
    final area      = item['area']          as String? ?? '';
    final stage     = item['customerStage'] as String?;
    final funnel    = item['funnelStage']   as String?;
    final isActive  = item['isActive']      as bool? ?? true;
    final shopImg   = item['shopImage']     as String?;
    final ownerImg  = item['ownerImage']    as String?;
    final id        = item['id']            as String? ?? '';

    final location = [city, area].where((s) => s.isNotEmpty).join(', ');

    final shopImgUrl  = _resolveImageUrl(shopImg);
    final ownerImgUrl = _resolveImageUrl(ownerImg);

    return Card(
      color: Colors.white,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final changed = await context.push('/lead-accounts/$id', extra: item);
          if (changed == true) _refresh();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Shop image + owner avatar badge
              _leadThumb(shopImgUrl, ownerImgUrl),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name + active badge
                    Row(children: [
                      Expanded(
                        child: Text(
                          bizName,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.black87),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.green.shade50 : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          isActive ? 'Active' : 'Inactive',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: isActive ? Colors.green.shade700 : Colors.grey,
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 2),
                    // Person & contact
                    Text(
                      '$person  •  $contact',
                      style: const TextStyle(fontSize: 12, color: Colors.black54),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Stage chips
                    Row(children: [
                      if (stage != null) _chip(stage, _stageColor(stage)),
                      if (stage != null && funnel != null) const SizedBox(width: 4),
                      if (funnel != null) _chip(funnel, Colors.indigo.shade300),
                    ]),
                    if (location.isNotEmpty || code.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        if (location.isNotEmpty) ...[
                          const Icon(Icons.location_on_outlined, size: 12, color: Colors.grey),
                          const SizedBox(width: 2),
                          Expanded(
                            child: Text(
                              location,
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        if (code.isNotEmpty)
                          Text(
                            code,
                            style: const TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                      ]),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  String? _resolveImageUrl(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return null;
    if (v.startsWith('http')) return v;
    if (v.startsWith('/')) return '${ApiConfig.baseUrl}$v';
    return null;
  }

  static const double _thumbSize = 52;

  Widget _imageSquare(String? imgUrl, IconData fallbackIcon) {
    final tile = Container(
      width: _thumbSize,
      height: _thumbSize,
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8EE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7BE69).withValues(alpha: 0.4)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      clipBehavior: Clip.antiAlias,
      child: imgUrl != null
          ? Image.network(
              imgUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, e, stack) => Icon(fallbackIcon, color: gold, size: 26),
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: gold))),
            )
          : Icon(fallbackIcon, color: gold, size: 26),
    );

    return imgUrl != null ? HoverImagePreview(imageUrl: imgUrl, child: tile) : tile;
  }

  Widget _leadThumb(String? shopImgUrl, String? ownerImgUrl) {
    final shop = _imageSquare(shopImgUrl, Icons.store_rounded);

    if (ownerImgUrl == null) return shop;

    final owner = _imageSquare(ownerImgUrl, Icons.person_rounded);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [shop, const SizedBox(width: 6), owner],
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
    ),
  );
}
