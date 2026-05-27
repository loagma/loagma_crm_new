import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';

class AttendanceManageScreen extends StatefulWidget {
  const AttendanceManageScreen({super.key});

  @override
  State<AttendanceManageScreen> createState() => _AttendanceManageScreenState();
}

class _AttendanceManageScreenState extends State<AttendanceManageScreen> {
  static const _gold = Color(0xFFD7BE69);

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();

  List<Map<String, dynamic>> _items = [];
  int _page = 1;
  bool _isLoading = false;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadPage();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_hasMore || _isLoading) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 100) {
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    if (_isLoading) return;
    _isLoading = true;
    final q = _searchController.text.trim();
    try {
      final result = await ApiService.getEmployees(
        q: q.isEmpty ? null : q,
        page: _page,
        perPage: 20,
      );
      if (mounted) {
        setState(() {
          _error = null;
          if (_page == 1) {
            _items = result;
          } else {
            _items.addAll(result);
          }
          _isLoading = false;
          _page++;
          _hasMore = result.length >= 20;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Unable to connect to server';
          _isLoading = false;
          _hasMore = false;
        });
      }
    }
  }

  void _refresh() {
    setState(() {
      _items.clear();
      _page = 1;
      _hasMore = true;
    });
    _loadPage();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Management'),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!,
                        style: const TextStyle(color: Colors.red)),
                  ),
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search by name, role, or mobile',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) {
                    _page = 1;
                    _hasMore = true;
                    _items.clear();
                    _loadPage();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _refresh(),
              child: _items.isEmpty && !_isLoading
                  ? const Center(child: Text('No employees found'))
                  : ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      itemCount: _items.length + (_hasMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        if (index >= _items.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 12),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final emp = _items[index];
                        final name = emp['name'] as String? ?? 'Unknown';
                        final role = emp['role'] as String? ?? '';
                        final mobile =
                            emp['mobile'] as String? ?? '';

                        return Card(
                          color: Colors.white,
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: _gold.withValues(alpha: 0.15),
                              child: const Icon(Icons.person,
                                  color: _gold),
                            ),
                            title: Text(name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                                role.isNotEmpty ? '$role • $mobile' : mobile),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => context.push(
                              '/attendance-manage/$mobile',
                              extra: emp,
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
