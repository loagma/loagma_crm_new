import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_config.dart';
import '../../services/api_service.dart';
import '../../widgets/hover_image_preview.dart';
import 'lead_approval_actions.dart';

/// Review queue for admin/teleadmin: every lead a salesman/telecaller has
/// created that hasn't been approved or rejected yet. Mirrors the shape of
/// admin_notifications_screen.dart (attendance pending-approvals).
class PendingLeadsScreen extends StatefulWidget {
  const PendingLeadsScreen({super.key});

  @override
  State<PendingLeadsScreen> createState() => _PendingLeadsScreenState();
}

class _PendingLeadsScreenState extends State<PendingLeadsScreen> {
  static const _gold = Color(0xFFD7BE69);

  List<Map<String, dynamic>> _records = [];
  bool _loading = false;
  bool _hasMore = true;
  int _page = 1;
  final _scroll = ScrollController();

  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';

  List<Map<String, dynamic>> _creators = [];
  String? _selectedCreatorMobile;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCreators();
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 100 && !_loading && _hasMore) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadCreators() async {
    final creators = await ApiService.getPendingLeadCreators();
    if (mounted) setState(() => _creators = creators);
  }

  Future<void> _load({bool refresh = false}) async {
    if (_loading && _records.isNotEmpty && !refresh) return;
    if (refresh) {
      _page = 1;
      _hasMore = true;
      _records = [];
    }
    setState(() => _loading = true);
    try {
      final res = await ApiService.getPendingLeadAccounts(
        page: _page,
        q: _query,
        createdBy: _selectedCreatorMobile,
      );
      if (!mounted) return;
      final items = (res['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final meta = res['meta'] as Map?;
      setState(() {
        _records.addAll(items);
        _hasMore = _page < (meta?['last_page'] as int? ?? 1);
        _page++;
      });
    } catch (e) {
      if (mounted) Fluttertoast.showToast(msg: 'Failed to load: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String value) {
    setState(() {}); // refresh the clear (x) button visibility immediately
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _query = value.trim();
      _load(refresh: true);
    });
  }

  void _onCreatorChanged(String? mobile) {
    setState(() => _selectedCreatorMobile = mobile);
    _load(refresh: true);
  }

  Future<void> _approve(String id, int index, String bizName) async {
    final ok = await confirmApproveLead(context, id, businessName: bizName);
    if (ok && mounted) setState(() => _records.removeAt(index));
  }

  Future<void> _reject(String id, int index, String bizName) async {
    final ok = await confirmRejectLead(context, id, businessName: bizName);
    if (ok && mounted) setState(() => _records.removeAt(index));
  }

  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search by shop, contact person or phone',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                      },
                    ),
              filled: true,
              fillColor: const Color(0xFFF5F5F5),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.person_search_rounded, size: 18, color: Colors.black45),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: _selectedCreatorMobile,
                    hint: const Text('Assigned by (all)', style: TextStyle(fontSize: 13, color: Colors.black54)),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Assigned by (all)')),
                      ..._creators.map((c) {
                        final mobile = c['mobile']?.toString() ?? '';
                        final name = c['name']?.toString() ?? mobile;
                        final role = c['role']?.toString() ?? '';
                        return DropdownMenuItem<String?>(
                          value: mobile,
                          child: Text(role.isNotEmpty ? '$name ($role)' : name, overflow: TextOverflow.ellipsis),
                        );
                      }),
                    ],
                    onChanged: _onCreatorChanged,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtersActive = _query.isNotEmpty || _selectedCreatorMobile != null;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        title: const Text('Pending Leads', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () => _load(refresh: true)),
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(),
          Expanded(
            child: _loading && _records.isEmpty
                ? const Center(child: CircularProgressIndicator(color: _gold))
                : !_loading && _records.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              filtersActive ? Icons.search_off_rounded : Icons.check_circle_outline,
                              size: 56,
                              color: filtersActive ? Colors.black26 : const Color(0xFF43A047),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              filtersActive ? 'No leads match your search/filter' : 'No leads awaiting review',
                              style: const TextStyle(fontSize: 16, color: Colors.black54, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        color: _gold,
                        onRefresh: () => _load(refresh: true),
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(14),
                          itemCount: _records.length + (_loading || _hasMore ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (i == _records.length) {
                              return const Padding(
                                padding: EdgeInsets.symmetric(vertical: 16),
                                child: Center(child: CircularProgressIndicator(color: _gold)),
                              );
                            }
                            final r = _records[i];
                            final id = '${r['id']}';
                            final bizName = r['businessName']?.toString() ?? '';
                            return _PendingLeadCard(
                              record: r,
                              onTap: () => context.push('/lead-accounts/$id', extra: r),
                              onApprove: () => _approve(id, i, bizName),
                              onReject: () => _reject(id, i, bizName),
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

class _PendingLeadCard extends StatelessWidget {
  final Map<String, dynamic> record;
  final VoidCallback onTap;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _PendingLeadCard({
    required this.record,
    required this.onTap,
    required this.onApprove,
    required this.onReject,
  });

  static const _orange = Color(0xFFF59E0B);
  static const _gold = Color(0xFFD7BE69);

  String? _resolveImageUrl(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return null;
    if (v.startsWith('http')) return v;
    if (v.startsWith('/')) return '${ApiConfig.baseUrl}$v';
    return null;
  }

  String _relative(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bizName = record['businessName']?.toString() ?? '—';
    final person = record['personName']?.toString() ?? '—';
    final contact = record['contactNumber']?.toString() ?? '—';
    final creator = record['creator'] as Map?;
    final creatorName = creator?['name']?.toString() ?? record['createdById']?.toString() ?? 'Unknown';
    final creatorRole = creator?['role']?.toString() ?? '';
    final shopUrl = _resolveImageUrl(record['shopImage'] as String?);
    final ownerUrl = _resolveImageUrl(record['ownerImage'] as String?);

    Widget thumb(String? url, IconData icon) {
      final tile = Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFFFF8EE),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _gold.withValues(alpha: 0.4)),
        ),
        clipBehavior: Clip.antiAlias,
        child: url != null
            ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => Icon(icon, color: _gold, size: 22))
            : Icon(icon, color: _gold, size: 22),
      );
      return url != null ? HoverImagePreview(imageUrl: url, child: tile) : tile;
    }

    return Card(
      color: Colors.white,
      elevation: 1,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _orange.withValues(alpha: 0.4), width: 1.5),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  thumb(shopUrl, Icons.store_rounded),
                  const SizedBox(width: 6),
                  thumb(ownerUrl, Icons.person_rounded),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(bizName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                        const SizedBox(height: 2),
                        Text('$person  •  $contact', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration:
                        BoxDecoration(color: _orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
                    child: const Text('Pending',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _orange)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.person_add_alt_1_rounded, size: 13, color: Colors.black45),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Created by $creatorName${creatorRole.isNotEmpty ? ' ($creatorRole)' : ''}',
                      style: const TextStyle(fontSize: 11.5, color: Colors.black54),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(_relative(record['createdAt']?.toString()),
                      style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kApprovalRed,
                        side: const BorderSide(color: kApprovalRed),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Reject', style: TextStyle(fontWeight: FontWeight.w600)),
                      onPressed: onReject,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kApprovalGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Approve', style: TextStyle(fontWeight: FontWeight.w600)),
                      onPressed: onApprove,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
