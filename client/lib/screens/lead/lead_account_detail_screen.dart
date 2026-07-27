import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_config.dart';
import '../../services/api_service.dart';
import '../../services/user_service.dart';
import '../../widgets/hover_image_preview.dart';
import 'lead_approval_actions.dart';

class LeadAccountDetailScreen extends StatefulWidget {
  final String id;
  final Map<String, dynamic>? initialData;

  const LeadAccountDetailScreen({super.key, required this.id, this.initialData});

  @override
  State<LeadAccountDetailScreen> createState() => _LeadAccountDetailScreenState();
}

class _LeadAccountDetailScreenState extends State<LeadAccountDetailScreen> {
  static const gold      = Color(0xFFD7BE69);
  static const goldLight = Color(0xFFFFF8EE);

  Map<String, dynamic>? _data;
  bool _loadingData    = false;
  bool _deletingRecord = false;
  bool _acting         = false;

  bool get _canReview {
    final role = (UserService.currentRole ?? '').toLowerCase().trim();
    return role == 'admin' || role == 'teleadmin';
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialData != null) {
      _data = widget.initialData;
    } else {
      _fetchDetail();
    }
  }

  Future<void> _fetchDetail() async {
    setState(() => _loadingData = true);
    final result = await ApiService.getLeadAccount(widget.id);
    if (mounted) setState(() { _data = result; _loadingData = false; });
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Delete Lead Account', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(
          'Delete "${_data?['businessName'] ?? 'this record'}"? This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deletingRecord = true);
    final ok = await ApiService.deleteLeadAccount(widget.id);
    if (!mounted) return;

    setState(() => _deletingRecord = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lead account deleted')),
      );
      context.pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete — please try again')),
      );
    }
  }

  Future<void> _approve() async {
    if (_data == null || _acting) return;
    setState(() => _acting = true);
    final ok = await confirmApproveLead(context, widget.id, businessName: _data?['businessName']?.toString() ?? '');
    if (!mounted) return;
    setState(() => _acting = false);
    if (ok) _fetchDetail();
  }

  Future<void> _reject() async {
    if (_data == null || _acting) return;
    setState(() => _acting = true);
    final ok = await confirmRejectLead(context, widget.id, businessName: _data?['businessName']?.toString() ?? '');
    if (!mounted) return;
    setState(() => _acting = false);
    if (ok) _fetchDetail();
  }

  Future<void> _openEdit() async {
    if (_data == null) return;
    final updated = await context.push('/lead-accounts/${widget.id}/edit', extra: _data);
    if (updated == true && mounted) {
      _fetchDetail();
    }
  }

  // ── Build helpers ────────────────────────────────────────────────────────────

  Widget _sectionHeader(IconData icon, String title) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(
      color: goldLight,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(children: [
      Icon(icon, size: 18, color: gold),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: gold)),
    ]),
  );

  Widget _row(String label, String? value, {IconData? icon}) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: Colors.grey.shade400),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 13, color: Colors.black87, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
  );

  Color _stageColor(String? stage) {
    switch ((stage ?? '').toLowerCase()) {
      case 'customer':    return Colors.green;
      case 'qualified':   return Colors.blue;
      case 'opportunity': return Colors.indigo;
      case 'prospect':    return Colors.orange;
      case 'lead':        return Colors.amber.shade700;
      case 'churned':     return Colors.red;
      default:            return Colors.grey;
    }
  }

  // ── Main build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(_data?['businessName'] as String? ?? 'Lead Account'),
        backgroundColor: gold,
        foregroundColor: Colors.white,
        actions: [
          if (!_deletingRecord) ...[
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              tooltip: 'Edit',
              onPressed: _data != null ? _openEdit : null,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Delete',
              onPressed: _data != null ? _delete : null,
            ),
          ],
          const SizedBox(width: 4),
        ],
      ),
      body: _loadingData
          ? const Center(child: CircularProgressIndicator(color: gold))
          : _data == null
              ? _errorState()
              : _buildBody(_data!),
    );
  }

  Widget _errorState() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.error_outline_rounded, size: 48, color: Colors.grey.shade300),
      const SizedBox(height: 12),
      const Text('Could not load lead account', style: TextStyle(color: Colors.grey)),
      const SizedBox(height: 12),
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.white),
        onPressed: _fetchDetail,
        child: const Text('Retry'),
      ),
    ]),
  );

  Widget _buildBody(Map<String, dynamic> d) {
    final bizName    = d['businessName']  as String? ?? '—';
    final code       = d['accountCode']   as String? ?? '';
    final person     = d['personName']    as String? ?? '—';
    final contact    = d['contactNumber'] as String? ?? '—';
    final bizType    = d['businessType']  as String?;
    final bizSize    = d['businessSize']  as String?;
    final custStage  = d['customerStage'] as String?;
    final funnelStage = d['funnelStage'] as String?;
    final gst        = d['gstNumber']     as String?;
    final pan        = d['panCard']       as String?;
    final isActive   = d['isActive']      as bool? ?? true;
    final isApproved = d['isApproved']    as bool? ?? false;
    final approvalStatus = d['approval_status'] as String? ?? (isApproved ? 'approved' : 'pending');
    final pincode    = d['pincode']       as String?;
    final country    = d['country']       as String?;
    final state      = d['state']         as String?;
    final district   = d['district']      as String?;
    final city       = d['city']          as String?;
    final area       = d['area']          as String?;
    final address    = d['address']       as String?;
    final lat        = d['latitude'];
    final lng        = d['longitude'];
    final shopImg    = d['shopImage']     as String?;
    final ownerImg   = d['ownerImage']    as String?;
    final vNotes     = d['verificationNotes'] as String?;
    final rNotes     = d['rejectionNotes']    as String?;

    final shopImgUrl  = _resolveImageUrl(shopImg);
    final ownerImgUrl = _resolveImageUrl(ownerImg);
    final hasShopImg  = shopImgUrl != null;
    final hasOwnerImg = ownerImgUrl != null;

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // ── Header card ──────────────────────────────────────────
              Card(
                color: Colors.white,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                bizName,
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.black87),
                              ),
                              if (code.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(code, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ],
                            ]),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isActive ? Colors.green.shade50 : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isActive ? 'Active' : 'Inactive',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isActive ? Colors.green.shade700 : Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        const Icon(Icons.person_outline_rounded, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(person, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                        const SizedBox(width: 12),
                        const Icon(Icons.phone_outlined, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(contact, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                      ]),
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        if (bizType  != null) _chip(bizType,  Colors.blueGrey),
                        if (bizSize  != null) _chip(bizSize,  Colors.teal),
                        if (custStage != null) _chip(custStage, _stageColor(custStage)),
                        if (funnelStage != null) _chip(funnelStage, Colors.indigo.shade300),
                        _chip(
                          switch (approvalStatus) {
                            'approved' => 'Approved',
                            'rejected' => 'Rejected',
                            _ => 'Pending Approval',
                          },
                          switch (approvalStatus) {
                            'approved' => Colors.green,
                            'rejected' => Colors.red,
                            _ => Colors.orange,
                          },
                        ),
                      ]),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Business details ─────────────────────────────────────
              Card(
                color: Colors.white,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader(Icons.business_rounded, 'Business Details'),
                      _row('GST Number',   gst, icon: Icons.receipt_long_rounded),
                      _row('PAN Card',     pan, icon: Icons.credit_card_rounded),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Location ─────────────────────────────────────────────
              Card(
                color: Colors.white,
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader(Icons.location_on_rounded, 'Location'),
                      _row('Pincode',  pincode,  icon: Icons.pin_drop_outlined),
                      _row('Area',     area,     icon: Icons.home_rounded),
                      _row('City',     city,     icon: Icons.apartment_rounded),
                      _row('District', district, icon: Icons.location_city_rounded),
                      _row('State',    state,    icon: Icons.map_rounded),
                      _row('Country',  country,  icon: Icons.public_rounded),
                      _row('Address',  address,  icon: Icons.location_on_outlined),
                      if (lat != null && lng != null)
                        _row(
                          'Coordinates',
                          '${(lat as num).toStringAsFixed(6)}, ${(lng as num).toStringAsFixed(6)}',
                          icon: Icons.my_location_rounded,
                        ),
                    ],
                  ),
                ),
              ),

              // ── Images ───────────────────────────────────────────────
              if (hasShopImg || hasOwnerImg) ...[
                const SizedBox(height: 12),
                Card(
                  color: Colors.white,
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader(Icons.photo_library_rounded, 'Images'),
                        Row(children: [
                          if (hasShopImg) _imageTile('Shop', shopImgUrl),
                          if (hasShopImg && hasOwnerImg) const SizedBox(width: 10),
                          if (hasOwnerImg) _imageTile('Owner', ownerImgUrl),
                        ]),
                      ],
                    ),
                  ),
                ),
              ],

              // ── Notes ────────────────────────────────────────────────
              if (vNotes != null || rNotes != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: Colors.white,
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader(Icons.notes_rounded, 'Approval Notes'),
                        _row('Verification', vNotes, icon: Icons.verified_outlined),
                        _row('Rejection',    rNotes, icon: Icons.cancel_outlined),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // ── Review buttons (admin/teleadmin, pending leads only) ───
              if (_canReview && approvalStatus == 'pending') ...[
                Row(children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: _acting ? null : _reject,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: kApprovalRed,
                          side: const BorderSide(color: kApprovalRed),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton.icon(
                        onPressed: _acting ? null : _approve,
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Approve'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kApprovalGreen,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 10),
              ],

              // ── Action buttons ────────────────────────────────────────
              Row(children: [
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _data != null ? _openEdit : null,
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: const Text('Edit'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: gold,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: _deletingRecord ? null : _delete,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: const Text('Delete'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ]),

              const SizedBox(height: 20),
            ],
          ),
        ),
        if (_deletingRecord)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x33000000),
              child: Center(child: CircularProgressIndicator(color: gold)),
            ),
          ),
      ],
    );
  }

  String? _resolveImageUrl(String? raw) {
    final v = (raw ?? '').trim();
    if (v.isEmpty) return null;
    if (v.startsWith('http')) return v;
    if (v.startsWith('/')) return '${ApiConfig.baseUrl}$v';
    return null;
  }

  Widget _imageTile(String label, String? url) {
    final resolvedUrl = url ?? '';
    final tile = ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: Image.network(
        resolvedUrl,
        height: 110,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          height: 110,
          color: Colors.grey.shade100,
          child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
        ),
      ),
    );

    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          resolvedUrl.isNotEmpty ? HoverImagePreview(imageUrl: resolvedUrl, previewSize: 280, child: tile) : tile,
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ],
      ),
    );
  }
}
