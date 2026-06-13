import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import '../../services/user_service.dart';

class VerifyLeadAccountsScreen extends StatefulWidget {
  const VerifyLeadAccountsScreen({super.key});

  @override
  State<VerifyLeadAccountsScreen> createState() => _VerifyLeadAccountsScreenState();
}

class _VerifyLeadAccountsScreenState extends State<VerifyLeadAccountsScreen> {
  static const _gold = Color(0xFFD7BE69);
  static const _bg   = Color(0xFFF5F5F5);

  bool   _loading = true;
  String _error   = '';

  // [{pincode, areaName, leadCount, customerCount, leads, customers}]
  List<Map<String, dynamic>> _groups = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = ''; });

    final mobile = UserService.currentMobile ?? '';
    if (mobile.isEmpty) {
      setState(() { _loading = false; _error = 'Not logged in'; });
      return;
    }

    try {
      // Step 1 — assigned area IDs
      final assignRes  = await ApiService.getAreaAssign(mobile);
      final assignData = assignRes?['data'];
      final areaIds    = <int>[];
      if (assignData is Map) {
        final ids = assignData['area_ids'];
        if (ids is List) {
          for (final id in ids) {
            final n = int.tryParse(id.toString());
            if (n != null) areaIds.add(n);
          }
        }
      }

      if (areaIds.isEmpty) {
        setState(() { _loading = false; _groups = []; });
        return;
      }

      // Step 2 — pincodes from those areas, build pincode→areaName map
      final areaResults        = await Future.wait(areaIds.map(ApiService.getArea));
      final pincodes           = <String>[];
      final pincodeToAreaName  = <String, String>{};
      for (final area in areaResults) {
        if (area == null) continue;
        final areaName = (area['area_name'] ?? '').toString();
        final raw      = area['pincodes'];
        if (raw is List) {
          for (final p in raw) {
            final pin = p.toString();
            pincodes.add(pin);
            pincodeToAreaName[pin] = areaName;
          }
        }
      }

      // Step 3 — leads in these areas
      final result = await ApiService.getLeadAccounts(
        areaIds: areaIds,
        pincodes: pincodes,
        perPage: 1000,
      );
      final rawLeads = result['data'];
      final leads = rawLeads is List
          ? rawLeads.map((e) {
              final m = Map<String, dynamic>.from(e as Map);
              m['_type'] = 'lead';
              return m;
            }).toList()
          : <Map<String, dynamic>>[];

      // Step 4 — customers from user table
      final customerRaw = await ApiService.getCustomers(pincodes: pincodes);
      final customers = customerRaw.map((u) => <String, dynamic>{
        'id':            (u['userid'] ?? '').toString(),
        'businessName':  ((u['shop_name'] as String?)?.isNotEmpty == true
            ? u['shop_name']
            : (u['name'] ?? '')).toString(),
        'personName':    (u['name'] ?? '').toString(),
        'contactNumber': (u['contactno'] ?? '').toString(),
        'address':       (u['shop_address'] ?? u['address'] ?? '').toString(),
        'shopAddress':   (u['shop_address'] ?? '').toString(),
        'pincode':       (u['pincode'] ?? '').toString(),
        'city':          (u['city'] ?? '').toString(),
        'state':         (u['state'] ?? '').toString(),
        'email':         (u['email'] ?? '').toString(),
        'shopName':      (u['shop_name'] ?? '').toString(),
        'userType':      (u['user_type'] ?? '').toString(),
        'latitude':      u['latitude'],
        'longitude':     u['longitude'],
        '_type':         'customer',
      }).toList();

      // Step 5 — group by pincode
      final groupMap = <String, Map<String, dynamic>>{
        for (final p in pincodes) p: {
          'pincode':       p,
          'areaName':      pincodeToAreaName[p] ?? '',
          'leads':         <Map<String, dynamic>>[],
          'customers':     <Map<String, dynamic>>[],
        },
      };

      for (final lead in leads) {
        final pin = ((lead['pincode'] as String?) ?? '').trim();
        final key = pin.isEmpty ? 'Unknown' : pin;
        groupMap.putIfAbsent(key, () => {
          'pincode': key, 'areaName': '', 'leads': <Map<String, dynamic>>[], 'customers': <Map<String, dynamic>>[],
        });
        (groupMap[key]!['leads'] as List).add(lead);
      }
      for (final cust in customers) {
        final pin = ((cust['pincode'] as String?) ?? '').trim();
        final key = pin.isEmpty ? 'Unknown' : pin;
        groupMap.putIfAbsent(key, () => {
          'pincode': key, 'areaName': '', 'leads': <Map<String, dynamic>>[], 'customers': <Map<String, dynamic>>[],
        });
        (groupMap[key]!['customers'] as List).add(cust);
      }

      final groups = groupMap.values.map((g) {
        final lc = (g['leads']    as List).length;
        final cc = (g['customers'] as List).length;
        return <String, dynamic>{...g, 'leadCount': lc, 'customerCount': cc};
      }).toList();

      // Sort: most accounts first, then by pincode
      groups.sort((a, b) {
        final totalA = (a['leadCount'] as int) + (a['customerCount'] as int);
        final totalB = (b['leadCount'] as int) + (b['customerCount'] as int);
        final diff   = totalB.compareTo(totalA);
        return diff != 0 ? diff : (a['pincode'] as String).compareTo(b['pincode'] as String);
      });

      setState(() { _loading = false; _groups = groups; });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Verify Customers', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            Text('Tap a pincode to see contacts', style: TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _gold));
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 52, color: Colors.red.shade300),
              const SizedBox(height: 12),
              Text(_error, textAlign: TextAlign.center, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: _gold, foregroundColor: Colors.white),
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off_rounded, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            const Text('No areas assigned to you yet',
                style: TextStyle(fontSize: 15, color: Colors.black54)),
            const SizedBox(height: 6),
            const Text('Ask your admin to assign areas',
                style: TextStyle(fontSize: 12, color: Colors.black38)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _gold,
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
        itemCount: _groups.length,
        itemBuilder: (context, i) => _PincodeCard(
          group: _groups[i],
          onTap: () => context.push(
            '/verify-lead-accounts/${_groups[i]['pincode']}',
            extra: {
              'leads':     _groups[i]['leads'],
              'customers': _groups[i]['customers'],
              'areaName':  _groups[i]['areaName'],
            },
          ),
        ),
      ),
    );
  }
}

class _PincodeCard extends StatelessWidget {
  final Map<String, dynamic> group;
  final VoidCallback onTap;

  const _PincodeCard({required this.group, required this.onTap});

  static const _gold   = Color(0xFFD7BE69);
  static const _border = Color(0xFFEEEEEE);

  @override
  Widget build(BuildContext context) {
    final pincode      = group['pincode']       as String;
    final areaName     = group['areaName']       as String;
    final leadCount    = group['leadCount']      as int;
    final customerCount= group['customerCount']  as int;
    final total        = leadCount + customerCount;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(13),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Gold left accent bar
                Container(width: 4, color: _gold),
                // Card content
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    child: Row(
            children: [
              // Left: pincode + area
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pincode,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87)),
                    if (areaName.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(areaName,
                          style: const TextStyle(fontSize: 12, color: Colors.black45)),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: [
                        _CountChip(label: 'L: $leadCount', color: const Color(0xFFD7BE69)),
                        _CountChip(label: 'C: $customerCount', color: Colors.green.shade400),
                      ],
                    ),
                  ],
                ),
              ),
              // Right: total badge + chevron
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _gold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _gold.withValues(alpha: 0.4)),
                    ),
                    child: Text('$total contact${total == 1 ? '' : 's'}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFC09E3E))),
                  ),
                  const SizedBox(height: 8),
                  const Icon(Icons.chevron_right_rounded, color: Colors.black26, size: 22),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final Color color;
  const _CountChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.9))),
    );
  }
}
