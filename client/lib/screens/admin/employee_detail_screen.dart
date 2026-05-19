import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';

class EmployeeDetailScreen extends StatelessWidget {
  final Map<String, dynamic>? employee;
  final String id;

  const EmployeeDetailScreen({super.key, this.employee, required this.id});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: employee != null ? Future.value(employee) : ApiService.getEmployee(id),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && employee == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Employee Detail'), backgroundColor: const Color(0xFFD7BE69), foregroundColor: Colors.white),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        final e        = snap.data ?? employee ?? {};
        final name     = e['name']    as String? ?? 'Unknown';
        final role     = e['role']    as String? ?? '';
        final mobile   = e['mobile']  as String? ?? '—';
        final city     = e['city']    as String? ?? '';
        final state    = e['state']   as String? ?? '';
        final pincode  = e['pincode'] as String? ?? '';
        final isLocked = e['is_locked'] == true || e['is_locked'] == 1;
        final deliId   = e['deli_id']?.toString() ?? id;
        final lat      = e['lat'];
        final lng      = e['lng'];
        final parts    = name.trim().split(RegExp(r'\s+'));
        final initials = parts.take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();

        return Scaffold(
          backgroundColor: const Color(0xFFF5F5F5),
          appBar: AppBar(
            title: Text(name),
            backgroundColor: const Color(0xFFD7BE69),
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_rounded),
                onPressed: () async {
                  final res = await context.push('/employee/edit/$id', extra: e);
                  if (!context.mounted) return;
                  if (res == true) Navigator.of(context).pop(true);
                },
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                // Header
                Card(
                  color: Colors.white,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.white,
                          child: Text(initials.isNotEmpty ? initials : '?',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFFD7BE69))),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                              if (role.isNotEmpty) Text(role, style: const TextStyle(fontSize: 13, color: Color(0xFF8A6914))),
                            ],
                          ),
                        ),
                        if (isLocked)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.lock_rounded, size: 12, color: Colors.red),
                              SizedBox(width: 4),
                              Text('Locked', style: TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600)),
                            ]),
                          ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 10),

                // All details in one card
                Card(
                  color: Colors.white,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    children: [
                      _Row(icon: Icons.phone_rounded,     label: 'Mobile',    value: mobile),
                      _Row(icon: Icons.badge_rounded,     label: 'Role',      value: role.isNotEmpty ? role : '—'),
                      _Row(icon: Icons.tag_rounded,       label: 'Employee ID', value: deliId),
                      if (city.isNotEmpty)    _Row(icon: Icons.apartment_rounded,   label: 'City',    value: city),
                      if (state.isNotEmpty)   _Row(icon: Icons.map_rounded,         label: 'State',   value: state),
                      if (pincode.isNotEmpty) _Row(icon: Icons.pin_drop_rounded,    label: 'Pincode', value: pincode),
                      if (lat != null && lng != null)
                        _Row(icon: Icons.my_location_rounded, label: 'Coords', value: '${(lat as num).toStringAsFixed(5)}, ${(lng as num).toStringAsFixed(5)}'),
                      _Row(
                        icon: isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                        label: 'Status',
                        value: isLocked ? 'Locked' : 'Active',
                        valueColor: isLocked ? Colors.red : Colors.green,
                        isLast: true,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool isLast;

  const _Row({required this.icon, required this.label, required this.value, this.valueColor, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          child: Row(
            children: [
              Icon(icon, size: 18, color: const Color(0xFFD7BE69)),
              const SizedBox(width: 12),
              SizedBox(width: 90, child: Text(label, style: const TextStyle(fontSize: 13, color: Colors.grey))),
              Expanded(
                child: Text(value,
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: valueColor ?? Colors.black87)),
              ),
            ],
          ),
        ),
        if (!isLast) const Divider(height: 1, indent: 44, endIndent: 14),
      ],
    );
  }
}
