import 'dart:async';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_config.dart';
import '../../services/api_service.dart';
import '../../widgets/account_map_screen.dart';
import '../telecaller/telecaller_mock_data.dart' show kComplaintCategories;
import 'create_sales_order_screen.dart';

class OrderFunnelScreen extends StatefulWidget {
  final String accountId;
  final Map<String, dynamic>? account;

  const OrderFunnelScreen({
    super.key,
    required this.accountId,
    this.account,
  });

  @override
  State<OrderFunnelScreen> createState() => _OrderFunnelScreenState();
}

class _OrderFunnelScreenState extends State<OrderFunnelScreen> {
  static const _gold  = Color(0xFFD7BE69);
  static const _green = Color(0xFF43A047);

  // Fixed options for the "Notes Related To" dropdown.
  static const _relatedToOptions = [
    'Order', 'Payment', 'Complaint', 'Delivery', 'Product', 'Other',
  ];

  final ImagePicker _picker = ImagePicker();

  bool _visitedIn  = false;
  bool _visitedOut = false;

  DateTime? _visitInAt;
  Timer?    _timer;
  Duration  _elapsed = Duration.zero;

  int _tab = 1; // 0 = History, 1 = Funnel, 2 = Transaction

  // ── Funnel form state ─────────────────────────────────────────────────────
  List<Map<String, dynamic>> _funnelOptions = [];
  bool   _loadingFunnel = true;
  String? _selectedSlug;
  String? _notesRelatedTo;
  bool   _savedLocally = false;   // funnel locally confirmed (not yet in DB)
  bool   _persisting   = false;   // writing to DB on Visit Out
  bool   _uploadingImage = false;
  final List<String> _images = [];
  final TextEditingController _notesCtrl = TextEditingController();

  // ── Transaction tab state ─────────────────────────────────────────────────
  List<Map<String, dynamic>> _transactions = [];
  bool _loadingTx   = false;
  bool _txLoadedOnce = false;

  Map<String, dynamic> get _acc => widget.account ?? {};
  bool get _editable => _visitedIn && !_visitedOut;

  String? get _scheduleLabel {
    switch (_acc['frequency'] as String?) {
      case 'weekly':
        return 'WEEKLY';
      case 'monthly':
        return 'MONTHLY';
      case 'n_days':
        final n = _acc['interval_days'];
        return n == null ? 'RECURRING' : 'EVERY $n DAYS';
      default:
        return null;
    }
  }

  List<String> get _dayChips {
    if ((_acc['frequency'] as String?) == 'weekly') {
      return (_acc['days'] as List?)?.map((e) => e.toString()).toList() ?? [];
    }
    return [];
  }

  @override
  void initState() {
    super.initState();
    _loadFunnel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFunnel() async {
    final options = await ApiService.getOrderFunnels();
    if (!mounted) return;
    setState(() {
      _funnelOptions = options;
      _loadingFunnel = false;
    });
  }

  Future<void> _loadTransactions() async {
    setState(() {
      _loadingTx = true;
      _txLoadedOnce = true;
    });
    final rows = await ApiService.getOrderFunnelResponses(widget.accountId);
    if (!mounted) return;
    setState(() {
      _transactions = rows;
      _loadingTx = false;
    });
  }

  // ── Visit lifecycle ───────────────────────────────────────────────────────
  void _startVisit() {
    setState(() {
      _visitedIn = true;
      _visitInAt = DateTime.now();
      _elapsed   = Duration.zero;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _visitInAt == null) return;
      setState(() => _elapsed = DateTime.now().difference(_visitInAt!));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Visit started')),
    );
  }

  Future<void> _endVisit() async {
    // Require a funnel selection before closing the visit.
    if (_selectedSlug == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a funnel stage before Visit Out')),
      );
      return;
    }

    final outAt = DateTime.now();
    setState(() => _persisting = true);

    final result = await ApiService.saveOrderFunnelResponse(
      accountId:       widget.accountId,
      funnelSlug:      _selectedSlug!,
      accountType:     _acc['account_type'] as String?,
      beatPlanId:      _acc['beat_plan_id'] is int ? _acc['beat_plan_id'] as int : null,
      generalNotes:    _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      notesRelatedTo:  _notesRelatedTo,
      visitInAt:       _visitInAt?.toUtc().toIso8601String(),
      visitOutAt:      outAt.toUtc().toIso8601String(),
      durationSeconds: _visitInAt == null ? null : outAt.difference(_visitInAt!).inSeconds,
      images:          _images.isEmpty ? null : List<String>.from(_images),
    );

    if (!mounted) return;
    final ok = result != null && result['errors'] == null;
    setState(() {
      _persisting = false;
      if (ok) {
        _visitedOut = true;
        _timer?.cancel();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Visit completed — funnel saved' : 'Failed to save. Try again.'),
      backgroundColor: ok ? _green : Colors.red,
    ));

    // Refresh the Transaction list so the just-saved visit appears.
    if (ok) _loadTransactions();
  }

  // ── Local-only funnel save (synced to DB on Visit Out) ────────────────────
  void _saveFunnelLocal() {
    if (_selectedSlug == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a funnel stage')),
      );
      return;
    }
    setState(() => _savedLocally = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved — will sync to records on Visit Out')),
    );
  }

  // ── Images ────────────────────────────────────────────────────────────────
  Future<ImageSource?> _askImageSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_rounded),
              title: const Text('Camera'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _addImage() async {
    final source = await _askImageSource();
    if (source == null || !mounted) return;

    XFile? picked;
    try {
      picked = await _picker.pickImage(source: source, imageQuality: 80);
    } catch (e) {
      debugPrint('pickImage error: $e');
    }
    if (picked == null || !mounted) return;

    setState(() => _uploadingImage = true);
    final bytes = await picked.readAsBytes();
    final name  = picked.name.isNotEmpty ? picked.name : 'funnel.jpg';
    final path = await ApiService.uploadOrderFunnelImage(bytes, name);
    if (!mounted) return;
    setState(() {
      _uploadingImage = false;
      if (path != null && path.isNotEmpty) _images.add(path);
    });
    if (path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image upload failed')),
      );
    }
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _whatsapp(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    final n = d.length == 10 ? '91$d' : d;
    _launch('https://wa.me/$n');
  }

  Future<void> _raiseComplaint() async {
    if (!_visitedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please Visit In before raising a complaint')),
      );
      return;
    }

    String? category;
    final descCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.of(ctx).viewInsets.bottom),
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Raise Complaint', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    const Text('Category *', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: category,
                      isExpanded: true,
                      decoration: InputDecoration(
                        hintText: 'Select category',
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                      items: kComplaintCategories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)))
                          .toList(),
                      onChanged: (v) => setSheetState(() => category = v),
                    ),
                    const SizedBox(height: 14),
                    const Text('Description *', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: descCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'What went wrong?',
                        contentPadding: const EdgeInsets.all(12),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Please describe the issue' : null,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white),
                        onPressed: () {
                          if (category == null) {
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please select a category')));
                            return;
                          }
                          if (formKey.currentState?.validate() != true) return;
                          Navigator.pop(ctx, true);
                        },
                        child: const Text('Submit Complaint', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (submitted != true || !mounted) return;

    final res = await ApiService.createComplaint(
      accountId: widget.accountId,
      accountType: (_acc['account_type'] as String?) ?? 'lead',
      category: category!,
      description: descCtrl.text.trim(),
      beatPlanId: _acc['beat_plan_id'] is int ? _acc['beat_plan_id'] as int : null,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res != null ? 'Complaint raised successfully' : 'Failed to raise complaint — please try again')),
    );
  }

  // A real Sales Order can only be created for a registered customer
  // (SalesOrderController::store requires buyer_userid to match a `user`
  // row) — a lead account's id doesn't correspond to one, so the server
  // rejects it outright. Catching that here up front instead of letting
  // every attempt round-trip to a 422.
  Future<void> _takeOrder() async {
    final accountType = (_acc['account_type'] as String?) ?? 'lead';
    if (accountType != 'customer') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This is a lead account — convert it to a customer before taking an order.'),
        ),
      );
      return;
    }

    await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateSalesOrderScreen(
          buyerUserId: widget.accountId,
          shopName: (_acc['businessName'] as String?) ?? '',
          ownerName: (_acc['personName'] as String?) ?? '',
          address: (_acc['address'] as String?) ?? '',
          latitude: (_acc['latitude'] as num?)?.toDouble(),
          longitude: (_acc['longitude'] as num?)?.toDouble(),
          areaName: _acc['area'] as String?,
        ),
      ),
    );
    // The confirmation toast is shown by CreateSalesOrderScreen itself
    // before it pops — nothing else to reconcile here. (This screen's
    // "Order History" tab is a static placeholder, not a real order list,
    // so there's no local list to refresh after a successful order.)
  }

  String _fmt(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final code    = _acc['accountCode']   as String? ?? '';
    final owner   = _acc['personName']    as String? ?? '';
    final shop    = _acc['businessName']  as String? ?? '—';
    final address = _acc['address']       as String? ?? '';
    final phone   = _acc['contactNumber'] as String? ?? '';
    final lat     = _acc['latitude'];
    final lng     = _acc['longitude'];

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Order Details'),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Account card ──────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEEEEEE)),
                boxShadow: const [BoxShadow(
                    color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Code + owner (single row)
                  Row(
                    children: [
                      Text(code,
                          style: const TextStyle(
                              fontSize: 12, color: Colors.black45,
                              letterSpacing: 0.4)),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text('Owner Name : $owner',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Schedule chips + visit buttons. A weekly plan with
                  // several days selected produced enough chips to overflow
                  // a plain Row + Spacer on narrower widths — the chips now
                  // live in an Expanded Wrap so they wrap to a second line
                  // instead, while the two buttons stay pinned at the end.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (_scheduleLabel != null)
                              _Chip(label: _scheduleLabel!,
                                  bg: _green.withValues(alpha: 0.10), fg: const Color(0xFF2E7D32)),
                            ..._dayChips.map((d) => _Chip(label: d,
                                bg: Colors.grey.shade200, fg: Colors.black54)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Visit In
                      _VisitBtn(
                        label: 'Visit In',
                        active: !_visitedIn,
                        onTap: _visitedIn ? null : _startVisit,
                      ),
                      const SizedBox(width: 6),
                      // Visit Out
                      _VisitBtn(
                        label: _persisting ? 'Saving…' : 'Visit Out',
                        active: _editable && !_persisting,
                        onTap: (_editable && !_persisting) ? _endVisit : null,
                      ),
                    ],
                  ),

                  // Visit timer
                  if (_visitedIn) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(_visitedOut ? Icons.check_circle_rounded : Icons.timer_rounded,
                            size: 18, color: _visitedOut ? _green : _gold),
                        const SizedBox(width: 6),
                        Text(
                          _visitedOut
                              ? 'Visit duration ${_fmt(_elapsed)}'
                              : 'In progress · ${_fmt(_elapsed)}',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700,
                              color: _visitedOut ? _green : Colors.black87),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 10),
                  // Shop name
                  Text('Shop Name : $shop',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  if (address.isNotEmpty)
                    Text('Address : $address',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  const SizedBox(height: 12),
                  // Actions + take order
                  Row(
                    children: [
                      _ActionBtn(
                        icon: Icons.call_rounded,
                        color: _green,
                        onTap: phone.isNotEmpty ? () => _launch('tel:$phone') : null,
                      ),
                      const SizedBox(width: 10),
                      _ActionBtn(
                        faIcon: FontAwesomeIcons.whatsapp,
                        color: const Color(0xFF25D366),
                        onTap: phone.isNotEmpty ? () => _whatsapp(phone) : null,
                      ),
                      const SizedBox(width: 10),
                      _ActionBtn(
                        icon: Icons.map_rounded,
                        color: const Color(0xFF1565C0),
                        onTap: (lat != null && lng != null)
                            ? () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AccountMapScreen(
                                    title: shop,
                                    accounts: [{
                                      ..._acc,
                                      '_type': _acc['account_type'] ?? 'lead',
                                    }],
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Complaint + Take Order — separated from the contact icons
                  // above since these are full actions, not quick-dial links.
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _raiseComplaint,
                          icon: const Icon(Icons.report_problem_rounded, size: 16),
                          label: const Text('Raise Complaint',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red.shade600,
                            side: BorderSide(color: Colors.red.shade300),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _takeOrder,
                          icon: const Icon(Icons.shopping_cart_rounded, size: 16),
                          label: const Text('Take Order',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _gold,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ── Tabs row ──────────────────────────────────────────────────
            Row(
              children: [
                Expanded(child: _TabBtn(
                    label: 'Order History', active: _tab == 0,
                    onTap: () => setState(() => _tab = 0))),
                const SizedBox(width: 10),
                Expanded(child: _TabBtn(
                    label: 'Order Funnel', active: _tab == 1,
                    onTap: () => setState(() => _tab = 1))),
                const SizedBox(width: 10),
                Expanded(child: _TabBtn(
                    label: 'Transaction', active: _tab == 2,
                    onTap: () {
                      setState(() => _tab = 2);
                      if (!_txLoadedOnce) _loadTransactions();
                    })),
              ],
            ),

            const SizedBox(height: 14),

            // ── Tab content ────────────────────────────────────────────────
            if (_tab == 1)
              _buildFunnelTab()
            else if (_tab == 2)
              _buildTransactionTab()
            else
              const _PlaceholderCard(text: 'No order history yet.'),
          ],
        ),
      ),
    );
  }

  // ── Order Funnel tab ────────────────────────────────────────────────────
  Widget _buildFunnelTab() {
    final editable = _editable;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: const [BoxShadow(
            color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Order Funnel',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),

          if (!_visitedIn)
            _banner('Please click "Visit In" to start editing')
          else if (_visitedOut)
            _banner('Visit completed. This funnel has been saved.', done: true),

          if (_loadingFunnel)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_funnelOptions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('No funnel stages configured.',
                  style: TextStyle(fontSize: 13, color: Colors.black54)),
            )
          else
            _buildOptionsGrid(editable),

          const SizedBox(height: 16),
          const Text('Details',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),

          const Text('General Notes',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          TextField(
            controller: _notesCtrl,
            enabled: editable,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Enter general notes here...',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
          ),

          const SizedBox(height: 14),
          const Text('Notes Related To',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _notesRelatedTo,
            isExpanded: true,
            decoration: InputDecoration(
              hintText: 'Select',
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            items: _relatedToOptions
                .map((o) => DropdownMenuItem(
                      value: o,
                      child: Text(o, style: const TextStyle(fontSize: 13)),
                    ))
                .toList(),
            onChanged: editable ? (v) => setState(() => _notesRelatedTo = v) : null,
          ),

          const SizedBox(height: 14),
          const Text('Photos',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _buildImagesRow(editable),

          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: editable ? _saveFunnelLocal : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _savedLocally ? _green : _gold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(_savedLocally ? 'Saved ✓  (syncs on Visit Out)' : 'Save Funnel',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Transaction tab ─────────────────────────────────────────────────────
  Widget _buildTransactionTab() {
    if (_loadingTx) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_transactions.isEmpty) {
      return const _PlaceholderCard(text: 'No transactions yet.');
    }
    return Column(
      children: _transactions.map(_buildTransactionCard).toList(),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final stage   = tx['funnel_name'] as String? ?? '—';
    final related = tx['notes_related_to'] as String?;
    final notes   = tx['general_notes'] as String?;
    final dur     = tx['duration_seconds'];
    final whenRaw = (tx['visit_out_at'] ?? tx['created_at']) as String?;
    final when    = _fmtDate(whenRaw);
    final images  = (tx['images'] as List?)?.whereType<String>().toList() ?? [];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: const [BoxShadow(
            color: Colors.black12, blurRadius: 4, offset: Offset(0, 1))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(stage,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ),
              if (when != null)
                Text(when,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
            ],
          ),
          if (dur is int) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.timer_rounded, size: 15, color: _gold),
                const SizedBox(width: 5),
                Text('Duration ${_fmt(Duration(seconds: dur))}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
          if (related != null && related.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Related to: $related',
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800)),
          ],
          if (notes != null && notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(notes,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700)),
          ],
          if (images.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: images.map((p) => ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network('${ApiConfig.baseUrl}$p',
                    width: 64, height: 64, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        width: 64, height: 64, color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image_rounded,
                            color: Colors.black26))),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  String? _fmtDate(String? iso) {
    if (iso == null) return null;
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return null;
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/${dt.year} $hh:$mm';
  }

  Widget _banner(String text, {bool done = false}) {
    final c = done ? _green : _gold;
    final fg = done ? const Color(0xFF1B5E20) : const Color(0xFF9C7B1E);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(done ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
              size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600, color: fg)),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionsGrid(bool editable) {
    return Wrap(
      runSpacing: 4,
      children: _funnelOptions.map((o) {
        final slug = o['slug'] as String?;
        final name = o['name'] as String? ?? '';
        return SizedBox(
          width: (MediaQuery.of(context).size.width - 28 - 28) / 2,
          child: RadioListTile<String>(
            value: slug ?? '',
            groupValue: _selectedSlug,
            onChanged: editable
                ? (v) => setState(() => _selectedSlug = v)
                : null,
            title: Text(name, style: const TextStyle(fontSize: 13)),
            dense: true,
            contentPadding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            activeColor: _gold,
          ),
        );
      }).toList(),
    );
  }

  Widget _buildImagesRow(bool editable) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ..._images.asMap().entries.map((e) {
          final idx = e.key;
          final url = '${ApiConfig.baseUrl}${e.value}';
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(url,
                    width: 72, height: 72, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                        width: 72, height: 72, color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image_rounded,
                            color: Colors.black26))),
              ),
              if (editable)
                Positioned(
                  right: -6, top: -6,
                  child: IconButton(
                    icon: const Icon(Icons.cancel, size: 20, color: Colors.redAccent),
                    onPressed: () => setState(() => _images.removeAt(idx)),
                  ),
                ),
            ],
          );
        }),
        // Add button
        GestureDetector(
          onTap: (editable && !_uploadingImage) ? _addImage : null,
          child: Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: editable ? _gold.withValues(alpha: 0.10) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: editable ? _gold : Colors.grey.shade300,
                  style: BorderStyle.solid),
            ),
            child: _uploadingImage
                ? const Center(
                    child: SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : Icon(Icons.add_a_photo_rounded,
                    color: editable ? _gold : Colors.grey.shade400),
          ),
        ),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _PlaceholderCard extends StatelessWidget {
  final String text;
  const _PlaceholderCard({required this.text});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEEEEEE)),
        ),
        child: Center(
          child: Text(text,
              style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ),
      );
}

class _Chip extends StatelessWidget {
  final String label;
  final Color  bg, fg;
  const _Chip({required this.label, required this.bg, required this.fg});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
      );
}

class _VisitBtn extends StatelessWidget {
  final String       label;
  final bool         active;
  final VoidCallback? onTap;
  const _VisitBtn({required this.label, required this.active, this.onTap});

  static const _gold = Color(0xFFD7BE69);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: active ? _gold : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: active ? Colors.white : Colors.grey.shade600)),
        ),
      );
}

class _ActionBtn extends StatelessWidget {
  final IconData?     icon;
  final IconData?     faIcon;
  final Color         color;
  final VoidCallback? onTap;
  const _ActionBtn({this.icon, this.faIcon, required this.color, this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Center(
            child: faIcon != null
                ? FaIcon(faIcon, size: 17, color: color)
                : Icon(icon, size: 19, color: color),
          ),
        ),
      );
}

class _TabBtn extends StatelessWidget {
  final String       label;
  final bool         active;
  final VoidCallback onTap;
  const _TabBtn({required this.label, required this.active, required this.onTap});

  static const _gold = Color(0xFFD7BE69);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? _gold : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: active ? _gold : const Color(0xFFEEEEEE)),
            boxShadow: const [BoxShadow(
                color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
          ),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.w600,
                  color: active ? Colors.white : Colors.black87)),
        ),
      );
}
