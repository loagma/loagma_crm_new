import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

class VerifyPincodeDetailScreen extends StatefulWidget {
  final String pincode;
  final Map<String, dynamic> initialData;

  const VerifyPincodeDetailScreen({
    super.key,
    required this.pincode,
    required this.initialData,
  });

  @override
  State<VerifyPincodeDetailScreen> createState() => _VerifyPincodeDetailScreenState();
}

class _VerifyPincodeDetailScreenState extends State<VerifyPincodeDetailScreen> {
  static const _gold   = Color(0xFFD7BE69);
  static const _bg     = Color(0xFFF5F5F5);
  static const _border = Color(0xFFEEEEEE);

  final _searchCtrl = TextEditingController();
  String _query  = '';
  String _filter = 'All'; // All / Leads / Customers

  List<Map<String, dynamic>> _leads     = [];
  List<Map<String, dynamic>> _customers = [];

  @override
  void initState() {
    super.initState();
    final raw = widget.initialData;
    final rawLeads = raw['leads'];
    final rawCusts = raw['customers'];
    _leads     = rawLeads is List ? rawLeads.cast<Map<String, dynamic>>() : [];
    _customers = rawCusts is List ? rawCusts.cast<Map<String, dynamic>>() : [];
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filtered {
    List<Map<String, dynamic>> pool;
    if (_filter == 'Leads') {
      pool = _leads;
    } else if (_filter == 'Customers') {
      pool = _customers;
    } else {
      pool = [..._leads, ..._customers];
    }

    if (_query.isEmpty) return pool;
    final q = _query.toLowerCase();
    return pool.where((a) {
      final name    = (a['businessName']  ?? '').toString().toLowerCase();
      final person  = (a['personName']    ?? '').toString().toLowerCase();
      final contact = (a['contactNumber'] ?? '').toString().toLowerCase();
      final area    = (a['area']          ?? '').toString().toLowerCase();
      return name.contains(q) || person.contains(q) || contact.contains(q) || area.contains(q);
    }).toList();
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  Future<void> _whatsapp(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final num    = digits.length == 10 ? '91$digits' : digits;
    final uri    = Uri.parse('https://wa.me/$num');
    if (await canLaunchUrl(uri)) launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final areaName = (widget.initialData['areaName'] ?? '').toString();
    final items    = _filtered;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.pincode,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            Text(
              areaName.isNotEmpty ? areaName : 'Leads & Customers',
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Search bar ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search by name, contact, area…',
                hintStyle: const TextStyle(fontSize: 13, color: Colors.black38),
                prefixIcon: const Icon(Icons.search_rounded, color: _gold, size: 20),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18, color: Colors.black38),
                        onPressed: () { _searchCtrl.clear(); setState(() => _query = ''); },
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _gold, width: 1.5),
                ),
              ),
            ),
          ),

          // ── Filter chips ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: ['All', 'Leads', 'Customers'].map((label) {
                final active = _filter == label;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _filter = label),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: active ? _gold : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: active ? _gold : _border),
                        boxShadow: active
                            ? [BoxShadow(color: _gold.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))]
                            : [],
                      ),
                      child: Text(label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: active ? Colors.white : Colors.black54,
                          )),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // ── Count ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('${items.length} result${items.length == 1 ? '' : 's'}',
                  style: const TextStyle(fontSize: 12, color: Colors.black45)),
            ),
          ),

          // ── List ────────────────────────────────────────────────────────
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline_rounded, size: 56, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        const Text('No results found',
                            style: TextStyle(fontSize: 14, color: Colors.black45)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: items.length,
                    itemBuilder: (context, i) => _AccountCard(
                      account: items[i],
                      onCall: () => _call((items[i]['contactNumber'] ?? '').toString()),
                      onWhatsApp: () => _whatsapp((items[i]['contactNumber'] ?? '').toString()),
                      onTap: () => context.push('/telecaller/call', extra: {
                        'account':     items[i],
                        'accountType': items[i]['_type'] ?? 'lead',
                      }),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Account Card ─────────────────────────────────────────────────────────────

class _AccountCard extends StatelessWidget {
  final Map<String, dynamic> account;
  final VoidCallback onTap;
  final VoidCallback onCall;
  final VoidCallback onWhatsApp;

  const _AccountCard({
    required this.account,
    required this.onTap,
    required this.onCall,
    required this.onWhatsApp,
  });

  static const _gold      = Color(0xFFD7BE69);
  static const _goldLight = Color(0xFFFFF8EE);
  static const _border    = Color(0xFFEEEEEE);
  static const _green     = Color(0xFF43A047);
  static const _whatsapp  = Color(0xFF25D366);

  static Color _stageColor(String stage) {
    switch (stage.toLowerCase()) {
      case 'customer':    return Colors.green;
      case 'qualified':   return Colors.blue;
      case 'opportunity': return Colors.indigo;
      case 'prospect':    return Colors.orange;
      case 'lead':        return Colors.amber.shade700;
      case 'churned':     return Colors.red;
      default:            return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLead     = account['_type'] == 'lead';
    final name       = (account['businessName']  ?? '').toString();
    final person     = (account['personName']    ?? '').toString();
    final contact    = (account['contactNumber'] ?? '').toString();
    final area       = (account['area']          ?? '').toString();
    final city       = (account['city']          ?? '').toString();
    final address    = (account['address']       ?? '').toString();
    final pincode    = (account['pincode']       ?? '').toString();
    final state      = (account['state']         ?? '').toString();
    final code       = (account['accountCode']   ?? '').toString();
    final custStage  = (account['customerStage'] ?? '').toString();
    final funnelStg  = (account['funnelStage']   ?? '').toString();
    final gst        = (account['gstNumber']     ?? '').toString();
    final pan        = (account['panCard']        ?? '').toString();
    final shopImg    = (account['shopImage']      ?? '').toString();
    final ownerImg   = (account['ownerImage']     ?? '').toString();
    final userType   = (account['userType']       ?? '').toString();
    final shopAddr   = (account['shopAddress']    ?? '').toString();
    final email      = (account['email']          ?? '').toString();

    // Approval status for leads
    final isApproved = account['isApproved'];
    final approved   = isApproved == true || isApproved == 1 || isApproved == '1';
    final rejected   = isApproved == false || isApproved == 0 || isApproved == '0';
    final hasNotes   = (account['verificationNotes'] ?? '').toString().isNotEmpty
                    || (account['rejectionNotes']    ?? '').toString().isNotEmpty;

    final thumbUrl = shopImg.isNotEmpty ? shopImg : (ownerImg.isNotEmpty ? ownerImg : '');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // ── Top row: name + image + approval badge ──────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name,
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black87)),
                        if (code.isNotEmpty)
                          Text('#$code', style: const TextStyle(fontSize: 11, color: Colors.black38)),
                      ],
                    ),
                  ),
                  // Thumbnail if available
                  if (thumbUrl.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 52, height: 52,
                        decoration: BoxDecoration(
                          color: _goldLight,
                          border: Border.all(color: _gold.withValues(alpha: 0.4)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Image.network(
                          thumbUrl,
                          width: 52, height: 52,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => const Icon(Icons.store_rounded, color: _gold, size: 26),
                        ),
                      ),
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 8),

              // ── Chips row ───────────────────────────────────────────────
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  // Type chip
                  if (isLead)
                    _Chip(label: 'Lead', color: _gold)
                  else
                    _Chip(label: 'Customer', color: _green),

                  // Stage chips for leads
                  if (isLead && custStage.isNotEmpty)
                    _Chip(label: custStage, color: _stageColor(custStage)),
                  if (isLead && funnelStg.isNotEmpty)
                    _Chip(label: funnelStg, color: Colors.indigo.shade300),

                  // Customer type
                  if (!isLead && userType.isNotEmpty)
                    _Chip(label: userType, color: Colors.blueGrey),

                  // Approval badge for leads
                  if (isLead)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: approved
                            ? Colors.green.withValues(alpha: 0.1)
                            : rejected
                                ? Colors.orange.withValues(alpha: 0.1)
                                : Colors.grey.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: approved
                              ? Colors.green
                              : rejected
                                  ? Colors.orange
                                  : Colors.grey,
                        ),
                      ),
                      child: Text(
                        approved ? 'Approved' : rejected ? 'Pending' : 'Pending',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: approved ? Colors.green : rejected ? Colors.orange : Colors.grey,
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 8),
              const Divider(height: 1, color: Color(0xFFF0F0F0)),
              const SizedBox(height: 8),

              // ── Detail rows ─────────────────────────────────────────────
              if (person.isNotEmpty)
                _DetailRow(icon: Icons.person_rounded, text: person),
              if (contact.isNotEmpty)
                _DetailRow(icon: Icons.phone_rounded, text: contact),
              if (area.isNotEmpty || city.isNotEmpty)
                _DetailRow(
                  icon: Icons.location_on_rounded,
                  text: [area, city].where((s) => s.isNotEmpty).join(' • '),
                ),
              if (state.isNotEmpty && !city.contains(state))
                _DetailRow(icon: Icons.map_rounded, text: '$state${pincode.isNotEmpty ? '  •  $pincode' : ''}'),
              if (address.isNotEmpty)
                _DetailRow(icon: Icons.home_rounded, text: address),
              if (!isLead && shopAddr.isNotEmpty && shopAddr != address)
                _DetailRow(icon: Icons.store_rounded, text: shopAddr),
              if (!isLead && email.isNotEmpty)
                _DetailRow(icon: Icons.email_rounded, text: email),
              if (isLead && gst.isNotEmpty)
                _DetailRow(icon: Icons.receipt_long_rounded, text: 'GST: $gst'),
              if (isLead && pan.isNotEmpty)
                _DetailRow(icon: Icons.credit_card_rounded, text: 'PAN: $pan'),
              if (isLead && hasNotes)
                _DetailRow(
                  icon: Icons.notes_rounded,
                  text: (account['verificationNotes'] ?? account['rejectionNotes'] ?? '').toString(),
                  color: Colors.indigo.shade300,
                ),

              const SizedBox(height: 8),

              // ── Action buttons ──────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // "Tap to open" hint
                  const Text('Tap card to open call screen',
                      style: TextStyle(fontSize: 10, color: Colors.black26)),
                  Row(
                    children: [
                      // Call button
                      GestureDetector(
                        onTap: contact.isNotEmpty ? onCall : null,
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                            border: Border.all(color: _green.withValues(alpha: 0.3)),
                          ),
                          child: const Icon(Icons.call_rounded, color: _green, size: 18),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // WhatsApp button
                      GestureDetector(
                        onTap: contact.isNotEmpty ? onWhatsApp : null,
                        child: Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: _whatsapp.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                            border: Border.all(color: _whatsapp.withValues(alpha: 0.3)),
                          ),
                          child: const Icon(Icons.chat_rounded, color: _whatsapp, size: 18),
                        ),
                      ),
                    ],
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

class _Chip extends StatelessWidget {
  final String label;
  final Color  color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.35)),
    ),
    child: Text(label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color)),
  );
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String   text;
  final Color?   color;
  const _DetailRow({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: color ?? Colors.black38),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 12, color: color ?? Colors.black54)),
        ),
      ],
    ),
  );
}
