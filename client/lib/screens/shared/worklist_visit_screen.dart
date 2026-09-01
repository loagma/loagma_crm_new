import 'dart:async';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_config.dart';
import '../../services/api_service.dart';
import '../../services/open_visit_store.dart';
import '../../widgets/account_map_screen.dart';
import '../../widgets/address_picker_dialog.dart';
import '../../widgets/call_recording_player.dart';
import '../../widgets/create_sales_order_sheet.dart';
import '../../widgets/action_log_sheet.dart';
import '../telecaller/order_detail_screen.dart';
import '../telecaller/telecaller_actions.dart' show launchEmail;
import '../telecaller/telecaller_mock_data.dart'
    show kGold, kGoldDark, kBg, stageStyle, money, kComplaintCategories, kOutcomeLabels, kOutcomeColors, kOrderStatusColors;

/// Unified "work this customer" screen for BOTH salesman (Beat Plan) and
/// telecaller (Worklist). Customer Overview on top, then Check In / Check Out
/// with the role's main action, then four report tabs: Order History, Log
/// History, Call History, Account Details. Check Out opens the Action Log
/// popup (role-specific, mandatory).
class WorklistVisitScreen extends StatefulWidget {
  final String accountId;
  final Map<String, dynamic> account;
  final String role; // 'salesman' | 'telecaller'
  final String accountType; // 'lead' | 'customer'
  final int? beatPlanId;

  const WorklistVisitScreen({
    super.key,
    required this.accountId,
    required this.account,
    required this.role,
    required this.accountType,
    this.beatPlanId,
  });

  @override
  State<WorklistVisitScreen> createState() => _WorklistVisitScreenState();
}

class _WorklistVisitScreenState extends State<WorklistVisitScreen> {
  static const _green = Color(0xFF43A047);

  bool get _isSalesman => widget.role == 'salesman';
  bool get _isCustomer => widget.accountType == 'customer';
  Map<String, dynamic> get _acc => widget.account;

  // ── Check-in lifecycle ────────────────────────────────────────────────────
  bool _checkedIn = false;
  bool _checkedOut = false;
  DateTime? _checkInAt;
  double? _inLat, _inLng;
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _saving = false;

  bool get _live => _checkedIn && !_checkedOut;

  // ── Tabs ──────────────────────────────────────────────────────────────────
  int _tab = 0; // 0 Overview · 1 Orders · 2 Log · 3 Calls · 4 Account

  // ── Data ──────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _stages = [];
  Map<String, dynamic>? _lastCall; // telecaller: prefill for the Action Log popup

  List<Map<String, dynamic>> _orders = [];
  bool _loadingOrders = false, _ordersOnce = false, _ordersFailed = false;

  List<Map<String, dynamic>> _logs = [];
  bool _loadingLogs = false, _logsOnce = false;

  List<Map<String, dynamic>> _calls = [];
  bool _loadingCalls = false, _callsOnce = false;

  Map<String, dynamic>? _ledger;
  bool _ledgerIsCustomer = true;
  bool _loadingLedger = false, _ledgerOnce = false;

  @override
  void initState() {
    super.initState();
    if (_isSalesman) _loadStages();
    _restoreOpenVisit();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadStages() async {
    final s = await ApiService.getActionLogStages();
    if (mounted) setState(() => _stages = s);
  }

  Future<void> _restoreOpenVisit() async {
    final open = await OpenVisitStore.load(widget.accountId);
    if (!mounted || open == null) return;
    setState(() {
      _checkedIn = true;
      _checkInAt = open.visitInAt;
      _elapsed = DateTime.now().difference(open.visitInAt);
    });
    _startTicker();
  }

  void _startTicker() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _checkInAt == null) return;
      setState(() => _elapsed = DateTime.now().difference(_checkInAt!));
    });
  }

  // Best-effort, non-blocking — never prompts, and NEVER blocks check-out:
  // every step is hard-capped so a slow/hanging geolocator (common on web)
  // can't wedge the save. Coords are simply left null on any failure.
  Future<Position?> _bestEffortPosition() async {
    try {
      final perm = await Geolocator.checkPermission().timeout(const Duration(seconds: 3));
      if (perm != LocationPermission.always && perm != LocationPermission.whileInUse) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 6),
      ).timeout(const Duration(seconds: 7));
    } catch (_) {
      return null;
    }
  }

  // ── Check In / Check Out ─────────────────────────────────────────────────
  Future<void> _checkIn() async {
    final other = await OpenVisitStore.findOtherOpen(widget.accountId);
    if (other != null) {
      if (!mounted) return;
      final label = other.accountName?.isNotEmpty == true ? other.accountName! : 'another customer';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('You are still checked in at $label — check out there first.'),
        backgroundColor: Colors.red,
      ));
      return;
    }

    final startedAt = DateTime.now();
    setState(() {
      _checkedIn = true;
      _checkInAt = startedAt;
      _elapsed = Duration.zero;
    });
    _startTicker();
    await OpenVisitStore.save(OpenVisit(
      accountId: widget.accountId,
      visitInAt: startedAt,
      accountName: _acc['businessName'] as String? ?? _acc['name'] as String?,
    ));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checked in')));
    }
    final pos = await _bestEffortPosition();
    if (pos != null && mounted) setState(() {
      _inLat = pos.latitude;
      _inLng = pos.longitude;
    });
  }

  Future<void> _checkOut() async {
    if (!_live) return;

    // Salesman can't check out without a stage list — retry the fetch once
    // rather than dead-ending them in the popup with "No stages configured".
    if (_isSalesman && _stages.isEmpty) {
      await _loadStages();
      if (!mounted) return;
      if (_stages.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not load check-out stages — check your connection and try again.'),
          backgroundColor: Colors.red,
        ));
        return;
      }
    }

    final body = await showActionLogSheet(
      context,
      role: widget.role,
      accountType: widget.accountType,
      stages: _stages,
      callPrefill: _lastCall,
      uploadImage: ApiService.uploadActionLogImage,
    );
    if (body == null || !mounted) return; // cancelled — stay checked in

    setState(() => _saving = true);
    final outAt = DateTime.now();

    // Checkout GPS is best-effort and must never block the save — race it
    // against a short timeout and proceed with whatever we have.
    Position? pos;
    try {
      pos = await _bestEffortPosition().timeout(const Duration(seconds: 5));
    } catch (_) {
      pos = null;
    }
    if (!mounted) return;

    final fields = <String, dynamic>{
      ...body,
      'account_id': widget.accountId,
      'account_type': widget.accountType,
      if (widget.beatPlanId != null) 'beat_plan_id': widget.beatPlanId,
      if (_checkInAt != null) 'check_in_at': _checkInAt!.toUtc().toIso8601String(),
      'check_out_at': outAt.toUtc().toIso8601String(),
      if (_checkInAt != null) 'duration_seconds': outAt.difference(_checkInAt!).inSeconds,
      if (_inLat != null) 'check_in_lat': _inLat,
      if (_inLng != null) 'check_in_lng': _inLng,
      if (pos != null) 'check_out_lat': pos.latitude,
      if (pos != null) 'check_out_lng': pos.longitude,
    };

    final res = await ApiService.saveActionLog(fields);
    if (!mounted) return;
    final ok = res != null && res['errors'] == null;
    if (ok) await OpenVisitStore.clear(widget.accountId);

    setState(() {
      _saving = false;
      if (ok) {
        _checkedOut = true;
        _timer?.cancel();
      }
    });

    final err = res == null
        ? 'No response from server. Check your connection.'
        : (res['errors'] != null ? 'Save failed: ${res['errors']}' : null);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Checked out — action log saved' : (err ?? 'Could not save. Try again.')),
      backgroundColor: ok ? _green : Colors.red,
      duration: Duration(seconds: ok ? 2 : 5),
    ));

    if (ok) _loadLogs(force: true);
  }

  // ── Actions ──────────────────────────────────────────────────────────────
  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _whatsapp(String phone) {
    final d = phone.replaceAll(RegExp(r'\D'), '');
    final n = d.length == 10 ? '91$d' : d;
    _launch('https://wa.me/$n');
  }

  Future<void> _cloudCall() async {
    final phone = '${_acc['contactNumber'] ?? _acc['phone'] ?? ''}';
    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No phone number on file')));
      return;
    }
    if (!_live) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check in before calling')));
      return;
    }
    final result = await context.push<Map<String, dynamic>>('/telecaller/call', extra: {
      'account': {..._acc, 'id': widget.accountId},
      'accountType': widget.accountType,
      'returnOnFinish': true,
    });
    if (!mounted) return;
    if (result != null) setState(() => _lastCall = result);
    _loadCalls(force: true);
  }

  Future<void> _takeOrder() async {
    if (!_live) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check in before taking an order')));
      return;
    }
    final options = addressOptionsFrom(_acc);
    final deliveryAddress = await resolveDeliveryAddress(context, _acc);
    if (options.length > 1 && deliveryAddress == null) return;
    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CreateSalesOrderSheet(
        name: '${_acc['businessName'] ?? _acc['name'] ?? ''}',
        accountId: widget.accountId,
        accountType: widget.accountType,
        deliveryAddress: deliveryAddress,
        areaName: _acc['area'] as String?,
        contactNumber: '${_acc['contactNumber'] ?? _acc['phone'] ?? ''}',
        gstNumber: _acc['gstNumber'] as String?,
        accountCode: _acc['accountCode'] as String?,
        city: _acc['city'] as String?,
        state: _acc['state'] as String?,
        pincode: _acc['pincode'] as String?,
        onSave: (items, amt, status, pay, realOrderId) {
          if (!mounted) return;
          if (realOrderId != null) _loadOrders(force: true);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(realOrderId != null
                ? 'Sales order #$realOrderId created — ₹$amt'
                : 'Not saved — this account is a lead, not a registered customer yet.'),
            backgroundColor: realOrderId != null ? _green : null,
          ));
        },
      ),
    );
  }

  Future<void> _raiseComplaint() async {
    if (!_live) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Check in before raising a complaint')));
      return;
    }
    String? category;
    final descCtrl = TextEditingController();
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(18, 18, 18, 18 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Raise Complaint', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                value: category,
                isExpanded: true,
                decoration: const InputDecoration(hintText: 'Category', border: OutlineInputBorder()),
                items: kComplaintCategories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setSheet(() => category = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'What went wrong?', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white),
                  onPressed: () {
                    if (category == null || descCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Pick a category and describe it')));
                      return;
                    }
                    Navigator.pop(ctx, true);
                  },
                  child: const Text('Submit Complaint', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final res = await ApiService.createComplaint(
      accountId: widget.accountId,
      accountType: widget.accountType,
      category: category!,
      description: descCtrl.text.trim(),
      beatPlanId: widget.beatPlanId,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(res != null ? 'Complaint raised' : 'Failed to raise complaint'),
    ));
  }

  // ── Loaders ──────────────────────────────────────────────────────────────
  Future<void> _loadOrders({bool force = false}) async {
    if (!_isCustomer) {
      setState(() => _ordersOnce = true);
      return;
    }
    if (_loadingOrders || (_ordersOnce && !force)) return;
    setState(() {
      _loadingOrders = true;
      _ordersOnce = true;
      _ordersFailed = false;
    });
    final res = await ApiService.getOrders(buyerUserId: widget.accountId, perPage: 50);
    if (!mounted) return;
    final raw = res['data'];
    setState(() {
      _loadingOrders = false;
      if (res['success'] == true && raw is List) {
        _orders = raw.map((o) => Map<String, dynamic>.from(o as Map)).toList();
      } else {
        _ordersFailed = true;
      }
    });
  }

  Future<void> _loadLogs({bool force = false}) async {
    if (_loadingLogs || (_logsOnce && !force)) return;
    setState(() {
      _loadingLogs = true;
      _logsOnce = true;
    });
    final rows = await ApiService.getAccountActionLogs(widget.accountId);
    if (!mounted) return;
    setState(() {
      _logs = rows;
      _loadingLogs = false;
    });
  }

  Future<void> _loadCalls({bool force = false}) async {
    if (_loadingCalls || (_callsOnce && !force)) return;
    setState(() {
      _loadingCalls = true;
      _callsOnce = true;
    });
    final rows = await ApiService.getAccountCallHistory(widget.accountId);
    if (!mounted) return;
    setState(() {
      _calls = rows;
      _loadingCalls = false;
    });
  }

  Future<void> _loadLedger({bool force = false}) async {
    if (_loadingLedger || (_ledgerOnce && !force)) return;
    setState(() {
      _loadingLedger = true;
      _ledgerOnce = true;
    });
    final res = await ApiService.getAccountLedger(widget.accountId, accountType: widget.accountType);
    if (!mounted) return;
    setState(() {
      _loadingLedger = false;
      _ledgerIsCustomer = res['is_customer'] == true;
      _ledger = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : null;
    });
  }

  void _switchTab(int i) {
    setState(() => _tab = i);
    switch (i) {
      case 1:
        _loadOrders();
        break;
      case 2:
        _loadLogs();
        break;
      case 3:
        _loadCalls();
        break;
      case 4:
        _loadLedger();
        break;
    }
  }

  String _fmtDur(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _fmtDateTime(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '—';
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$d/$mo/${dt.year} $hh:$mm';
  }

  @override
  Widget build(BuildContext context) {
    final name = '${_acc['businessName'] ?? _acc['name'] ?? _acc['personName'] ?? '—'}';
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: Text(name, overflow: TextOverflow.ellipsis),
        backgroundColor: kGold,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: [
          _accountCard(),
          const SizedBox(height: 12),
          _tabBar(),
          const SizedBox(height: 12),
          if (_tab == 0) _overviewTab(),
          if (_tab == 1) _ordersTab(),
          if (_tab == 2) _logsTab(),
          if (_tab == 3) _callsTab(),
          if (_tab == 4) _ledgerTab(),
        ],
      ),
    );
  }

  // ── Account + check-in card ──────────────────────────────────────────────
  Widget _accountCard() {
    final code = '${_acc['accountCode'] ?? ''}';
    final person = '${_acc['personName'] ?? _acc['person_name'] ?? ''}';
    final phone = '${_acc['contactNumber'] ?? _acc['phone'] ?? ''}';
    final address = '${_acc['address'] ?? ''}';
    final email = '${_acc['email'] ?? ''}';
    final lat = _acc['latitude'], lng = _acc['longitude'];
    final st = stageStyle('${_acc['customerStage'] ?? widget.accountType}');

    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (code.isNotEmpty)
                Text(code, style: const TextStyle(fontSize: 11, color: Colors.grey, letterSpacing: .4)),
              const Spacer(),
              _pill(st.text, st.color),
            ],
          ),
          const SizedBox(height: 4),
          // Name + compact Check In / Check Out on the same row.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_acc['businessName'] ?? _acc['name'] ?? '—'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    if (person.isNotEmpty)
                      Text(person, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _smallBtn('Check In', active: !_checkedIn, onTap: _checkedIn ? null : _checkIn),
              const SizedBox(width: 6),
              _smallBtn(_saving ? 'Saving…' : 'Check Out',
                  active: _live && !_saving, onTap: (_live && !_saving) ? _checkOut : null),
            ],
          ),
          if (address.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(address, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
          if (_checkedIn) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(_checkedOut ? Icons.check_circle_rounded : Icons.timer_rounded,
                    size: 16, color: _checkedOut ? _green : kGold),
                const SizedBox(width: 6),
                Text(
                  _checkedOut ? 'Checked out · ${_fmtDur(_elapsed)}' : 'On visit · ${_fmtDur(_elapsed)}',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _checkedOut ? _green : Colors.black87),
                ),
              ],
            ),
          ],

          const SizedBox(height: 12),
          // Quick contact row
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _act(Icons.call_rounded, _green, phone.isEmpty ? null : () => _launch('tel:$phone')),
              _act(Icons.ring_volume_rounded, const Color(0xFF8E24AA), phone.isEmpty ? null : _cloudCall),
              _actFa(FontAwesomeIcons.whatsapp, const Color(0xFF25D366), phone.isEmpty ? null : () => _whatsapp(phone)),
              _act(Icons.mail_rounded, const Color(0xFF3B6FD4), email.isEmpty ? null : () => launchEmail(email, subject: '${_acc['businessName'] ?? ''}')),
              _act(Icons.map_rounded, const Color(0xFF1565C0), (lat != null && lng != null)
                  ? () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => AccountMapScreen(title: '${_acc['businessName'] ?? ''}', accounts: [
                        {..._acc, '_type': widget.accountType},
                      ])))
                  : null),
            ],
          ),
          const SizedBox(height: 10),
          // Main actions
          Row(
            children: [
              if (_isSalesman)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _live ? _takeOrder : null,
                    icon: const Icon(Icons.shopping_cart_rounded, size: 16),
                    label: const Text('Take Order', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kGold,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: kGold.withValues(alpha: 0.35),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                )
              else
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _live ? _cloudCall : null,
                    icon: const Icon(Icons.ring_volume_rounded, size: 16),
                    label: const Text('Cloud Call', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8E24AA),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF8E24AA).withValues(alpha: 0.35),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _live ? _raiseComplaint : null,
                  icon: const Icon(Icons.report_problem_rounded, size: 16),
                  label: const Text('Complaint', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade600,
                    side: BorderSide(color: _live ? Colors.red.shade300 : Colors.grey.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
          if (!_live) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, size: 13, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _checkedOut
                        ? 'Visit closed — actions are locked.'
                        : 'Check in to take an order, call, or raise a complaint.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Customer Overview tab ───────────────────────────────────────────────
  Widget _overviewTab() {
    return Column(
      children: [
        _card(_infoGrid('Basic information', [
          ('Phone', '${_acc['contactNumber'] ?? _acc['phone'] ?? '—'}'),
          ('Email', '${_acc['email'] ?? '—'}'),
          ('Address', '${_acc['address'] ?? '—'}'),
          ('City', '${_acc['city'] ?? _acc['area'] ?? '—'}'),
          ('Pincode', '${_acc['pincode'] ?? '—'}'),
          ('GST', '${_acc['gstNumber'] ?? '—'}'),
          ('PAN', '${_acc['panCard'] ?? '—'}'),
          ('Type', '${_acc['businessType'] ?? '—'}'),
        ])),
        _card(_infoGrid('Sales information', [
          ('Account code', '${_acc['accountCode'] ?? '—'}'),
          ('Stage', '${_acc['customerStage'] ?? widget.accountType}'),
          ('Funnel', '${_acc['funnelStage'] ?? '—'}'),
          ('Assigned to', '${_acc['assignedToId'] ?? '—'}'),
          ('Created', '${_acc['createdAt'] ?? '—'}'),
        ])),
      ],
    );
  }

  Widget _infoGrid(String title, List<(String, String)> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.black87)),
        const SizedBox(height: 8),
        Wrap(
          runSpacing: 10,
          children: rows.map((r) {
            final w = (MediaQuery.of(context).size.width - 24 - 28) / 2 - 1;
            return SizedBox(
              width: r.$1 == 'Address' ? double.infinity : w,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.$1.toUpperCase(),
                      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: .5, color: Colors.grey.shade400)),
                  const SizedBox(height: 2),
                  Text(r.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF20242B))),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Tab bar ──────────────────────────────────────────────────────────────
  Widget _tabBar() {
    const labels = ['Overview', 'Order History', 'Log History', 'Call History', 'Account'];
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) => GestureDetector(
          onTap: () => _switchTab(i),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _tab == i ? kGold : Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _tab == i ? kGold : const Color(0xFFEEEEEE)),
            ),
            child: Text(labels[i],
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _tab == i ? Colors.white : Colors.grey.shade600)),
          ),
        ),
      ),
    );
  }

  // ── Order History tab ────────────────────────────────────────────────────
  Widget _ordersTab() {
    if (!_isCustomer) {
      return _placeholder('No order history — this account is a lead, not a registered customer.');
    }
    if (_loadingOrders) return _loader();
    if (_ordersFailed) {
      return _card(Column(children: [
        const Text('Could not load order history.'),
        const SizedBox(height: 8),
        ElevatedButton(onPressed: () => _loadOrders(force: true), child: const Text('Retry')),
      ]));
    }
    if (_orders.isEmpty) return _placeholder('No orders yet for this customer.');
    return Column(children: _orders.map(_orderCard).toList());
  }

  Widget _orderCard(Map<String, dynamic> o) {
    final orderId = o['order_id']?.toString();
    final state = '${o['order_state'] ?? ''}';
    final pay = '${o['payment_status'] ?? ''}';
    final total = (o['order_total'] as num?)?.toDouble() ?? 0;
    final when = '${o['order_datetime'] ?? ''}';
    final items = ((o['items'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final sc = kOrderStatusColors[_titleCase(state)] ?? const Color(0xFF5A6472);

    return GestureDetector(
      onTap: orderId == null
          ? null
          : () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: orderId)));
              if (mounted) _loadOrders(force: true);
            },
      child: _card(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Order #$orderId', style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800))),
              Text('₹${total.round()}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
          if (when.isNotEmpty) Text(when, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          if (items.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...items.map((it) => Text(
                  '• ${it['name'] ?? 'Item'}${(it['pack_size'] ?? '').toString().isEmpty ? '' : ' (${it['pack_size']})'}  ×${(it['quantity'] as num?)?.toInt() ?? 0}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                )),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (state.isNotEmpty) _pill(_titleCase(state), sc),
            if (pay.isNotEmpty) _pill(_titleCase(pay), const Color(0xFF5A6472)),
          ]),
        ],
      )),
    );
  }

  // ── Log History tab ──────────────────────────────────────────────────────
  Widget _logsTab() {
    if (_loadingLogs) return _loader();
    if (_logs.isEmpty) return _placeholder('No visit / call logs yet for this customer.');
    return Column(children: _logs.map(_logCard).toList());
  }

  Widget _logCard(Map<String, dynamic> l) {
    final role = '${l['role'] ?? ''}';
    final staff = '${l['staff_name'] ?? ''}';
    final outcome = '${l['outcome_name'] ?? l['call_outcome'] ?? ''}';
    final inAt = _fmtDateTime('${l['check_in_at'] ?? ''}');
    final outAt = _fmtDateTime('${l['check_out_at'] ?? ''}');
    final dur = l['duration_seconds'];
    final notes = '${l['conversation_notes'] ?? l['general_notes'] ?? ''}'.trim();
    final discussion = '${l['discussion_points'] ?? ''}'.trim();
    final market = '${l['market_note'] ?? ''}'.trim();
    final pay = l['payment_collected'];
    final fu = '${l['follow_up_date'] ?? ''}';
    final images = ((l['images'] as List?) ?? []).whereType<String>().toList();

    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _pill(role == 'telecaller' ? 'TELECALLER' : 'SALESMAN',
                role == 'telecaller' ? const Color(0xFF00838F) : _green),
            const SizedBox(width: 6),
            if (outcome.isNotEmpty) Expanded(child: Text(_titleCase(outcome), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
          ],
        ),
        const SizedBox(height: 6),
        _kv('Staff', staff),
        _kv('Check-in', inAt),
        _kv('Check-out', outAt),
        if (dur is int && dur > 0) _kv('Duration', _fmtDur(Duration(seconds: dur))),
        if (l['is_invalid_call'] == true) _kv('Invalid call', 'Yes'),
        if (l['call_status'] != null && '${l['call_status']}'.isNotEmpty) _kv('Call status', '${l['call_status']}'),
        if (pay != null && (pay as num) > 0) _kv('Payment collected', '₹$pay ${l['payment_mode'] ?? ''}'),
        if (fu.isNotEmpty && fu != 'null') _kv('Follow-up', fu),
        if (notes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(notes, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800)),
        ],
        if (discussion.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Discussion: $discussion', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
        if (market.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Market: $market', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ],
        if (images.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: images
                .map((p) => ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network('${ApiConfig.baseUrl}$p',
                          width: 60, height: 60, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(width: 60, height: 60, color: Colors.grey.shade200)),
                    ))
                .toList(),
          ),
        ],
      ],
    ));
  }

  // ── Call History tab ─────────────────────────────────────────────────────
  Widget _callsTab() {
    if (_loadingCalls) return _loader();
    if (_calls.isEmpty) return _placeholder('No calls logged for this customer.');
    return Column(children: _calls.map(_callCard).toList());
  }

  Widget _callCard(Map<String, dynamic> c) {
    final outcome = '${c['outcome'] ?? ''}';
    final color = kOutcomeColors[outcome] ?? const Color(0xFF5A6472);
    final label = kOutcomeLabels[outcome] ?? _titleCase(outcome);
    final dur = (c['duration_seconds'] as num?)?.toInt() ?? 0;
    final hasRec = c['has_recording'] == true;
    final id = (c['id'] as num?)?.toInt();

    return _card(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
            const Spacer(),
            Text(_fmtDateTime('${c['called_at'] ?? ''}'), style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
          ],
        ),
        const SizedBox(height: 4),
        _kv('Staff', '${c['staff_name'] ?? ''}'),
        _kv('Source', '${c['source'] ?? 'manual'}'),
        if (dur > 0) _kv('Talk time', _fmtDur(Duration(seconds: dur))),
        if ('${c['notes'] ?? ''}'.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('${c['notes']}', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade800)),
        ],
        if (hasRec && id != null) ...[
          const SizedBox(height: 8),
          CallRecordingPlayer(callLogId: id, accountId: widget.accountId, accentColor: kGoldDark),
        ],
      ],
    ));
  }

  // ── Account Details tab ──────────────────────────────────────────────────
  Widget _ledgerTab() {
    if (_loadingLedger) return _loader();
    if (!_ledgerIsCustomer) return _placeholder('Not a customer yet — no account/billing data.');
    final d = _ledger;
    if (d == null) return _placeholder('No billing data for this customer.');

    final aging = Map<String, dynamic>.from(d['aging'] as Map? ?? {});
    final invoices = ((d['invoices'] as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

    return Column(
      children: [
        _card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Outstanding', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('₹${(d['outstanding'] as num?)?.round() ?? 0}',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFFC0584C))),
            const SizedBox(height: 12),
            Row(
              children: [
                _miniStat('Lifetime', money((d['lifetime_value'] as num?)?.round() ?? 0)),
                _miniStat('Orders', '${d['order_count'] ?? 0}'),
                _miniStat('Avg', money((d['avg_order_value'] as num?)?.round() ?? 0)),
              ],
            ),
            const SizedBox(height: 8),
            _kv('First order', _fmtDateTime('${d['first_order_at'] ?? ''}')),
            _kv('Last order', _fmtDateTime('${d['last_order_at'] ?? ''}')),
          ],
        )),
        _card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Aging (unpaid balance)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Row(
              children: [
                _miniStat('0–30d', money((aging['d0_30'] as num?)?.round() ?? 0)),
                _miniStat('31–60d', money((aging['d31_60'] as num?)?.round() ?? 0)),
                _miniStat('60d+', money((aging['d60_plus'] as num?)?.round() ?? 0)),
              ],
            ),
          ],
        )),
        if (invoices.isNotEmpty)
          _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Statement', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              ...invoices.map((inv) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('#${inv['order_id']}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                              Text(_fmtDateTime('${inv['date'] ?? ''}'), style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('₹${(inv['total'] as num?)?.round() ?? 0}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                            Text('bal ₹${(inv['balance'] as num?)?.round() ?? 0}',
                                style: TextStyle(fontSize: 10.5, color: ((inv['balance'] as num?) ?? 0) > 0 ? const Color(0xFFC0584C) : Colors.grey.shade500)),
                          ],
                        ),
                      ],
                    ),
                  )),
            ],
          )),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Text('Figures are estimated from order records.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
        ),
      ],
    );
  }

  // ── Small shared widgets ─────────────────────────────────────────────────
  Widget _card(Widget child) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEEEEEE)),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: child,
      );

  Widget _placeholder(String t) => _card(Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(t, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.black54)),
        ),
      ));

  Widget _loader() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: kGold)),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 96, child: Text(k, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500, fontWeight: FontWeight.w600))),
            Expanded(child: Text(v, style: const TextStyle(fontSize: 12.5))),
          ],
        ),
      );

  Widget _miniStat(String t, String v) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(color: const Color(0xFFF3F3F5), borderRadius: BorderRadius.circular(12)),
          child: Column(
            children: [
              FittedBox(child: Text(v, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800))),
              const SizedBox(height: 2),
              Text(t, style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500)),
            ],
          ),
        ),
      );

  Widget _pill(String t, Color c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: c)),
      );

  Widget _smallBtn(String label, {required bool active, VoidCallback? onTap}) => GestureDetector(
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: active ? kGold : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: active ? Colors.white : Colors.grey.shade600)),
        ),
      );

  Widget _act(IconData icon, Color c, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: c.withValues(alpha: onTap == null ? 0.05 : 0.12), shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: onTap == null ? Colors.grey.shade400 : c),
        ),
      );

  Widget _actFa(IconData icon, Color c, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.withValues(alpha: onTap == null ? 0.05 : 0.12), shape: BoxShape.circle),
          child: FaIcon(icon, size: 16, color: onTap == null ? Colors.grey.shade400 : c),
        ),
      );

  String _titleCase(String s) => s.isEmpty
      ? s
      : s.split(RegExp(r'[_\s]+')).map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
}
