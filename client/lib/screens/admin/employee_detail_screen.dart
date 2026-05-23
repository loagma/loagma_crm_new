import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../services/api_service.dart';

class EmployeeDetailScreen extends StatefulWidget {
  final Map<String, dynamic>? employee;
  final String id;

  const EmployeeDetailScreen({super.key, this.employee, required this.id});

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  static const gold = Color(0xFFD7BE69);

  late Future<Map<String, dynamic>?> _future;

  @override
  void initState() {
    super.initState();
    // Always fetch full record from API — the list only selects a subset of
    // columns (no lat/lng/admin_id), so using list data here loses those fields.
    _future = ApiService.getEmployee(widget.id);
  }

  void _reload() => setState(() {
    _future = ApiService.getEmployee(widget.id);
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Employee Detail'),
              backgroundColor: gold,
              foregroundColor: Colors.white,
            ),
            body: const Center(child: CircularProgressIndicator(color: gold)),
          );
        }

        if (snap.hasError || snap.data == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Employee Detail'), backgroundColor: gold, foregroundColor: Colors.white),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_off_rounded, size: 60, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('Employee not found', style: TextStyle(color: Colors.grey.shade500)),
                ],
              ),
            ),
          );
        }

        final e = snap.data!;
        return _DetailView(data: e, onEdited: _reload);
      },
    );
  }
}

// ── detail view ───────────────────────────────────────────────────────────────

class _DetailView extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onEdited;

  const _DetailView({required this.data, required this.onEdited});

  static const gold     = Color(0xFFD7BE69);
  static const goldDark = Color(0xFFB89A3E);

  String _s(String key, [String fallback = '']) =>
      (data[key]?.toString().trim().isNotEmpty == true) ? data[key].toString().trim() : fallback;

  String get _name     => _s('name', 'Unknown');
  String get _role     => _s('role');
  String get _mobile   => _s('mobile', '—');
  String get _deliId   => _s('deli_id', _s('id'));
  String get _adminId  => _s('admin_id');
  String get _city     => _s('city');
  String get _state    => _s('state');
  String get _pincode  => _s('pincode');
  bool   get _isLocked => data['is_locked'] == true || data['is_locked'] == 1;
  double? get _lat     => data['lat'] != null ? double.tryParse(data['lat'].toString()) : null;
  double? get _lng     => data['lng'] != null ? double.tryParse(data['lng'].toString()) : null;

  String get _initials {
    final parts = _name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return _name.isNotEmpty ? _name[0].toUpperCase() : '?';
  }

  ({Color bg, Color text, String label}) get _roleStyle {
    switch (_role.toLowerCase()) {
      case 'admin':      return (bg: const Color(0xFFFFEBEE), text: const Color(0xFFC62828), label: 'Admin');
      case 'manager':    return (bg: const Color(0xFFE8F5E9), text: const Color(0xFF2E7D32), label: 'Manager');
      case 'salesman':   return (bg: const Color(0xFFFFF8E1), text: goldDark,                label: 'Salesman');
      case 'deli_staff': return (bg: const Color(0xFFE3F0FF), text: const Color(0xFF1565C0), label: 'Deli Staff');
      default:
        return (
          bg: const Color(0xFFF3E5F5),
          text: const Color(0xFF6A1B9A),
          label: _role.isEmpty ? 'Staff' : _role[0].toUpperCase() + _role.substring(1),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F2F5),
      appBar: AppBar(
        title: const Text('Employee Detail'),
        backgroundColor: gold,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_rounded),
            tooltip: 'Edit',
            onPressed: () async {
              final res = await context.push('/employee/edit/$_mobile', extra: data);
              if (!context.mounted) return;
              if (res == true) onEdited();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            _buildHeader(context),
            const SizedBox(height: 12),
            _buildSection('Contact', Icons.phone_outlined, [
              _row(Icons.phone_rounded,     'Mobile',      _mobile,  copyable: true),
            ]),
            const SizedBox(height: 10),
            _buildSection('Identity', Icons.badge_outlined, [
              if (_deliId.isNotEmpty)  _row(Icons.tag_rounded,                    'Employee ID', _deliId, copyable: true),
              if (_adminId.isNotEmpty) _row(Icons.admin_panel_settings_rounded,   'Admin ID',    _adminId),
            ]),
            const SizedBox(height: 10),
            _buildSection('Address', Icons.location_city_outlined, [
              if (_city.isNotEmpty)    _row(Icons.apartment_rounded,   'City',    _city),
              if (_state.isNotEmpty)   _row(Icons.map_rounded,         'State',   _state),
              if (_pincode.isNotEmpty) _row(Icons.pin_drop_rounded,    'Pincode', _pincode),
            ], emptyMsg: 'No address on record'),
            const SizedBox(height: 10),
            _buildSection('Geo Location', Icons.my_location_rounded, [
              if (_lat != null) _row(Icons.north_rounded,  'Latitude',  _lat!.toStringAsFixed(6), copyable: true),
              if (_lng != null) _row(Icons.east_rounded,   'Longitude', _lng!.toStringAsFixed(6), copyable: true),
              if (_lat != null && _lng != null)
                _mapsRow(context),
            ], emptyMsg: 'No location recorded'),
            const SizedBox(height: 10),
            _buildSection('Account', Icons.shield_outlined, [
              _statusRow(),
            ]),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  // ── header card ────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    final rs = _roleStyle;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [gold, goldDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: gold.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: Row(
        children: [
          // avatar
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.25),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 2),
            ),
            child: Center(
              child: Text(_initials, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
                if (_role.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(rs.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ],
              ],
            ),
          ),
          // lock badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _isLocked ? Colors.red.withValues(alpha: 0.9) : Colors.green.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_isLocked ? Icons.lock_rounded : Icons.lock_open_rounded, size: 12, color: Colors.white),
                const SizedBox(width: 4),
                Text(
                  _isLocked ? 'Locked' : 'Active',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── section card ───────────────────────────────────────────────────────────

  Widget _buildSection(String title, IconData icon, List<Widget> rows, {String? emptyMsg}) {
    return Card(
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: gold.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 14, color: gold),
              ),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6B6B6B), letterSpacing: 0.3)),
            ]),
            const SizedBox(height: 8),
            const Divider(height: 1),
            if (rows.isEmpty && emptyMsg != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: Colors.grey.shade400),
                  const SizedBox(width: 6),
                  Text(emptyMsg, style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                ]),
              )
            else
              ...rows,
          ],
        ),
      ),
    );
  }

  // ── detail row ─────────────────────────────────────────────────────────────

  Widget _row(IconData icon, String label, String value, {bool copyable = false}) {
    if (value.isEmpty || value == '—' && label != 'Mobile') return const _EmptyPlaceholder();
    return _DetailRow(icon: icon, label: label, value: value, copyable: copyable);
  }

  Widget _statusRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(
            _isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
            size: 18,
            color: _isLocked ? Colors.red : Colors.green,
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: Text('Status', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _isLocked ? Colors.red.shade50 : Colors.green.shade50,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _isLocked ? Colors.red.shade200 : Colors.green.shade200),
            ),
            child: Text(
              _isLocked ? 'Locked — cannot log in' : 'Active — can log in',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _isLocked ? Colors.red : Colors.green.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapsRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: GestureDetector(
        onTap: () {
          final uri = 'https://www.google.com/maps?q=$_lat,$_lng';
          Clipboard.setData(ClipboardData(text: uri));
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Maps link copied to clipboard'), duration: Duration(seconds: 2)),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFE3F0FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFBBD6F5)),
          ),
          child: Row(
            children: [
              const Icon(Icons.map_rounded, size: 16, color: Color(0xFF1565C0)),
              const SizedBox(width: 8),
              const Text('View on Google Maps', style: TextStyle(fontSize: 12, color: Color(0xFF1565C0), fontWeight: FontWeight.w600)),
              const Spacer(),
              const Icon(Icons.copy_rounded, size: 13, color: Color(0xFF1565C0)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── shared row widget ─────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool copyable;

  const _DetailRow({required this.icon, required this.label, required this.value, this.copyable = false});

  static const gold = Color(0xFFD7BE69);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Divider(height: 1, indent: 0, endIndent: 0),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: gold),
              const SizedBox(width: 12),
              SizedBox(
                width: 90,
                child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87),
                ),
              ),
              if (copyable)
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: value));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$label copied'), duration: const Duration(seconds: 1)),
                    );
                  },
                  child: Icon(Icons.copy_rounded, size: 14, color: Colors.grey.shade400),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyPlaceholder extends StatelessWidget {
  const _EmptyPlaceholder();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
