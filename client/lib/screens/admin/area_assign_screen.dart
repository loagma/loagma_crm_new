import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AreaAssignScreen extends StatefulWidget {
  const AreaAssignScreen({super.key});

  @override
  State<AreaAssignScreen> createState() => _AreaAssignScreenState();
}

class _AreaAssignScreenState extends State<AreaAssignScreen> {
  static const gold = Color(0xFFD7BE69);

  final List<Map<String, dynamic>> _salesmen = [
    {'id': 1, 'name': 'Rahul Sharma', 'mobile': '9876543210'},
    {'id': 2, 'name': 'Priya Patel', 'mobile': '9876543211'},
    {'id': 3, 'name': 'Amit Kumar', 'mobile': '9876543212'},
    {'id': 4, 'name': 'Sneha Gupta', 'mobile': '9876543213'},
    {'id': 5, 'name': 'Vikas Singh', 'mobile': '9876543214'},
  ];

  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered => _query.isEmpty
      ? _salesmen
      : _salesmen
          .where((s) =>
              (s['name'] as String).toLowerCase().contains(_query) ||
              (s['mobile'] as String).contains(_query))
          .toList();

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Area Assign'),
        backgroundColor: gold,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search salesman by name or mobile…',
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
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: Colors.grey.shade200)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: gold)),
              ),
            ),
          ),

          // Hint
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Icon(Icons.info_outline_rounded, size: 13, color: Colors.grey.shade400),
                const SizedBox(width: 6),
                Text(
                  'Double-tap a salesman to assign areas',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                ),
              ],
            ),
          ),

          // List
          Expanded(
            child: filtered.isEmpty
                ? _emptyState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final s = filtered[i];
                      return _SalesmanCard(
                        salesman: s,
                        onDoubleTap: () =>
                            context.push('/area-assign/${s['id']}', extra: s),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _query.isNotEmpty
                  ? Icons.search_off_rounded
                  : Icons.person_off_rounded,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              _query.isNotEmpty ? 'No results for "$_query"' : 'No salesmen found',
              style: TextStyle(fontSize: 15, color: Colors.grey.shade500),
            ),
          ],
        ),
      );
}

class _SalesmanCard extends StatelessWidget {
  final Map<String, dynamic> salesman;
  final VoidCallback onDoubleTap;

  const _SalesmanCard({required this.salesman, required this.onDoubleTap});

  static const gold = Color(0xFFD7BE69);

  String get _initials {
    final name = (salesman['name'] as String).trim();
    final parts = name.split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: onDoubleTap,
      child: Card(
        color: Colors.white,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 1.5,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: gold.withValues(alpha: 0.15),
                child: Text(
                  _initials,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: gold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      salesman['name'] as String,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${salesman['mobile']}  •  Double-tap to assign areas',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  color: Colors.grey, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
