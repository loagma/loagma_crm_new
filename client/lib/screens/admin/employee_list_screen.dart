import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';

class EmployeeListScreen extends StatefulWidget {
	const EmployeeListScreen({super.key});

	@override
	State<EmployeeListScreen> createState() => _EmployeeListScreenState();
}

class _EmployeeListScreenState extends State<EmployeeListScreen> {
	late Future<List<Map<String, dynamic>>> _future;
	final TextEditingController _searchController = TextEditingController();

	@override
	void initState() {
		super.initState();
		_scrollController.addListener(_onScroll);
		_loadPage();
	}

	void _refresh() {
		setState(() {
			_items.clear();
			_page = 1;
			_hasMore = true;
			_loadPage();
		});
	}

	final ScrollController _scrollController = ScrollController();
	List<Map<String, dynamic>> _items = [];
	int _page = 1;
	bool _isLoading = false;
	bool _hasMore = true;
	String? _error;

	@override
	void dispose() {
		_scrollController.removeListener(_onScroll);
		_scrollController.dispose();
		_searchController.dispose();
		super.dispose();
	}

	void _onScroll() {
		if (!_hasMore || _isLoading) return;
		if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 100) {
			_loadPage();
		}
	}

	Future<void> _loadPage() async {
		if (_isLoading) return;
		_isLoading = true;
		final q = _searchController.text.trim();
		try {
			final result = await ApiService.getEmployees(q: q.isEmpty ? null : q, page: _page, perPage: 20);
			if (mounted) {
				setState(() {
					_error = null;
					if (_page == 1) { _items = result; } else { _items.addAll(result); }
					_isLoading = false;
					_page += 1;
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

	@override
	Widget build(BuildContext context) {
		return Scaffold(
			appBar: AppBar(
				title: const Text('Employee List'),
				backgroundColor: const Color(0xFFD7BE69),
				foregroundColor: Colors.white,
				actions: [
					IconButton(
						icon: const Icon(Icons.person_add_alt_1_rounded),
						tooltip: 'Add Employee',
						onPressed: () async {
							final result = await context.push('/employee/create');
							if (result == true) _refresh();
						},
					),
					const SizedBox(width: 4),
				],
			),
			body: Column(
				children: [
					Padding(
						padding: const EdgeInsets.all(12.0),
						child: Column(
							children: [
								if (_error != null)
									Padding(
										padding: const EdgeInsets.only(bottom: 8),
										child: Text(_error!, style: const TextStyle(color: Colors.red)),
									),
								TextField(
									controller: _searchController,
									decoration: const InputDecoration(
										prefixIcon: Icon(Icons.search),
										hintText: 'Search employees by name, role, or mobile',
										border: OutlineInputBorder(),
										isDense: true,
									),
									onChanged: (_) async {
										_page = 1;
										_hasMore = true;
										_items.clear();
										await _loadPage();
									},
								),
							],
						),
					),

					Expanded(
						child: RefreshIndicator(
							onRefresh: () async {
								_page = 1;
								_hasMore = true;
								await _loadPage();
							},
							child: ListView.separated(
								controller: _scrollController,
								padding: const EdgeInsets.all(12),
								itemCount: _items.length + (_hasMore ? 1 : 0),
								separatorBuilder: (_, __) => const SizedBox(height: 8),
								itemBuilder: (context, index) {
									if (index >= _items.length) {
										return const Padding(
											padding: EdgeInsets.symmetric(vertical: 12.0),
											child: Center(child: CircularProgressIndicator()),
										);
									}

									final it = _items[index];
									final name = it['name'] as String? ?? it['full_name'] as String? ?? 'Unknown';
									final role = it['role'] as String? ?? '';
									final mobile = it['mobile'] as String? ?? it['contactNumber'] as String? ?? '';

									return Card(
											color: Colors.white,
										child: ListTile(
											title: Text(name),
											subtitle: Text(role.isNotEmpty ? '$role • $mobile' : mobile),
											leading: const CircleAvatar(child: Icon(Icons.person)),
											onTap: () async {
												final res = await context.push('/employee/${it['id']}', extra: it);
												if (res == true) _refresh();
											},
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
