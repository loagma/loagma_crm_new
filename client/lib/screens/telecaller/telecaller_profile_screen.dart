import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../services/api_service.dart';
import '../../services/notification_service.dart';
import 'order_detail_screen.dart';
import 'telecaller_actions.dart';
import 'telecaller_mock_data.dart';

/// Rich lead / customer profile for the telecaller (mockup-faithful).
///
/// Header + quick actions, then four tabs — Overview · Activity · Orders ·
/// Follow-up. Real data comes from `GET /lead-accounts/{id}` (lead detail) and
/// `GET /call-logs?account_id=…` (call history → stats, log, notes, follow-ups).
/// Outcome logging and follow-up scheduling persist via `POST /call-logs`.
/// Fields the backend doesn't have yet (lead score, revenue, orders) are shown
/// as honest placeholders so the layout reflects the intended design.
class TelecallerProfileScreen extends StatefulWidget {
  final Map<String, dynamic> account;
  final String accountType; // 'lead' | 'customer'
  final VoidCallback? onCalled; // notifies worklist when a call is initiated
  final void Function(String date)? onFollowUpScheduled; // notifies worklist with the new follow-up date

  const TelecallerProfileScreen({
    super.key,
    required this.account,
    required this.accountType,
    this.onCalled,
    this.onFollowUpScheduled,
  });

  @override
  State<TelecallerProfileScreen> createState() => _TelecallerProfileScreenState();
}

class _TelecallerProfileScreenState extends State<TelecallerProfileScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _busy = false;
  bool _callInitiated = false;
  int _tab = 0; // 0 Overview · 1 Activity · 2 Orders · 3 Follow-up

  /// Merged account detail (full lead record when available, else the row we
  /// were navigated with).
  Map<String, dynamic> _acc = {};
  List<Map<String, dynamic>> _logs = [];
  // Real orders for customers (fetched from `orders` via buyer_userid).
  // Leads have no `user` row to query real orders against, so their entries
  // here are session-local drafts only (see _OrderSheet's onSave handling).
  final List<Map<String, dynamic>> _orders = [];

  bool get _isLead => widget.accountType == 'lead';
  int get _orderTotal => _orders.fold<int>(0, (a, o) => a + ((o['amt'] as num?)?.toInt() ?? 0));
  String get _id => '${widget.account['id'] ?? widget.account['account_id'] ?? ''}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _acc = Map<String, dynamic>.from(widget.account);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _callInitiated) {
      _callInitiated = false;
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _openOutcomeSheet();
      });
    }
  }

  Future<void> _callAndLog() async {
    if (_phone.isEmpty) {
      _toast('No phone number on file');
      return;
    }
    _callInitiated = true;
    widget.onCalled?.call();
    await launchPhoneCall(_phone);
  }

  Future<void> _cloudCall() async {
    if (_phone.isEmpty) {
      _toast('No phone number on file');
      return;
    }
    _toast('Calling… your phone will ring first, then the customer.');
    final result = await ApiService.triggerKnowlarityCall(
      accountId: _id,
      accountType: widget.accountType,
      customerNumber: _phone,
    );
    if (!mounted) return;
    if (result != null) {
      _callInitiated = true;
      widget.onCalled?.call();
      _toast('Call started');
    } else {
      _toast('Could not start the call. Try again.');
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final logsF = ApiService.getCallLogs(accountId: _id);
    Map<String, dynamic>? detail;
    if (_isLead && _id.isNotEmpty) {
      detail = await ApiService.getLeadAccount(_id);
    }
    final logs = await logsF;
    if (!mounted) return;
    setState(() {
      if (detail != null) _acc = {..._acc, ...detail};
      _logs = logs;
      _loading = false;
    });
    if (!_isLead) await _loadOrders();
  }

  String _titleCase(String s) => s.isEmpty
      ? s
      : s.split(RegExp(r'[_\s]+')).map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

  Future<void> _loadOrders() async {
    if (_id.isEmpty) return;
    final res = await ApiService.getOrders(buyerUserId: _id, perPage: 50);
    if (!mounted) return;
    final raw = res['data'];
    if (raw is! List) return;
    setState(() {
      _orders
        ..clear()
        ..addAll(raw.map((o) {
          final m = Map<String, dynamic>.from(o as Map);
          return {
            'order_id': m['order_id']?.toString(),
            'inv':    'Order #${m['order_id']}',
            'date':   m['order_datetime'] ?? '',
            'items':  '${m['items_count'] ?? 0} item(s)',
            'amt':    ((m['order_total'] as num?) ?? 0).round(),
            'status': _titleCase((m['order_state'] ?? '').toString()),
            'pay':    _titleCase((m['payment_status'] ?? '').toString()),
          };
        }));
    });
  }

  // ── Derived account fields ──────────────────────────────────────────────────
  String get _name => '${_acc['businessName'] ?? _acc['name'] ?? _acc['personName'] ?? 'Unknown'}'.trim();
  String get _person => '${_acc['personName'] ?? ''}'.trim();
  String get _phone => '${_acc['contactNumber'] ?? _acc['phone'] ?? ''}'.trim();
  String get _email => '${_acc['email'] ?? ''}'.trim();
  String get _stage => '${_acc['customerStage'] ?? (_isLead ? 'lead' : 'customer')}'.trim();
  String get _code => '${_acc['accountCode'] ?? ''}'.trim();
  String get _area => [
        '${_acc['area'] ?? ''}'.trim(),
        '${_acc['city'] ?? ''}'.trim(),
      ].where((s) => s.isNotEmpty).join(', ');

  /// Honest "activity" badge derived from real call data (not an invented temp).
  ({String text, Color color}) get _activityBadge {
    if (_openFollowUp != null) return (text: 'Follow-up', color: const Color(0xFFD98A2B));
    final last = _lastCallAt;
    if (last != null && DateTime.now().difference(last).inDays <= 14) {
      return (text: 'Active', color: const Color(0xFF2F9E57));
    }
    if (_logs.isEmpty) return (text: 'New', color: const Color(0xFF3B6FD4));
    return (text: 'Dormant', color: const Color(0xFF5A6472));
  }

  // ── Call-log analytics ──────────────────────────────────────────────────────
  int _outcome(String o) => _logs.where((l) => '${l['call_outcome']}' == o).length;
  DateTime? get _lastCallAt =>
      _logs.isEmpty ? null : DateTime.tryParse('${_logs.first['called_at']}')?.toLocal();

  Map<String, dynamic>? get _openFollowUp {
    for (final l in _logs) {
      final fu = '${l['follow_up_date'] ?? ''}';
      final done = l['callback_done'] == true || l['callback_done'] == 1;
      if (fu.isNotEmpty && fu != 'null' && !done) return l;
    }
    return null;
  }

  List<Map<String, dynamic>> get _notes =>
      _logs.where((l) => '${l['notes'] ?? ''}'.trim().isNotEmpty).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kGold,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
            if (_area.isNotEmpty)
              Text(_area, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.white70)),
          ],
        ),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                children: [
                  _headerCard(),
                  const SizedBox(height: 12),
                  _tabBar(),
                  const SizedBox(height: 12),
                  if (_tab == 0) ..._overview(),
                  if (_tab == 1) ..._activity(),
                  if (_tab == 2) ..._ordersTab(),
                  if (_tab == 3) ..._followUpTab(),
                ],
              ),
            ),
    );
  }

  // ── Header + quick actions ──────────────────────────────────────────────────
  Widget _headerCard() {
    final st = stageStyle(_stage);
    final badge = _activityBadge;
    return _card(
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // _avatar(64, 24),
              // const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_code.isNotEmpty)
                      Text('#$_code', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.grey.shade400, letterSpacing: .3)),
                    Text(_name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.2)),
                    if (_person.isNotEmpty && _person != _name)
                      Text(_person, style: TextStyle(fontSize: 13.5, color: Colors.grey.shade500)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 4, children: [_pill(st.text, st.color), _pill(badge.text, badge.color)]),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _qa(const Icon(Icons.call_rounded, size: 22, color: Color(0xFF2F9E57)), 'Call', const Color(0xFF2F9E57), _callAndLog),
              _qa(const Icon(Icons.ring_volume_rounded, size: 22, color: Color(0xFF8E24AA)), 'Cloud Call', const Color(0xFF8E24AA), _cloudCall),
              _qa(const FaIcon(FontAwesomeIcons.whatsapp, size: 22, color: Color(0xFF25D366)), 'WhatsApp', const Color(0xFF25D366), () => launchWhatsApp(_phone)),
              _qa(const Icon(Icons.mail_rounded, size: 22, color: Color(0xFF3B6FD4)), 'Email', const Color(0xFF3B6FD4), _emailAction),
              _qa(Icon(Icons.shopping_bag_rounded, size: 22, color: kGoldDark), 'Order', kGoldDark, _openOrderSheet),
              _qa(const Icon(Icons.event_rounded, size: 22, color: Color(0xFFD98A2B)), 'Follow-up', const Color(0xFFD98A2B), () => setState(() => _tab = 3)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qa(Widget iconWidget, String label, Color color, VoidCallback onTap) => Expanded(
        child: InkWell(
          onTap: _busy ? null : onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                Container(
                  height: 50,
                  width: 50,
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: iconWidget,
                ),
                const SizedBox(height: 5),
                Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      );


  // ── Tab bar ─────────────────────────────────────────────────────────────────
  Widget _tabBar() {
    const tabs = ['Overview', 'Activity', 'Orders', 'Follow-up'];
    return Row(
      children: [
        for (var i = 0; i < tabs.length; i++) ...[
          Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tab = i),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: _tab == i ? kGold : Colors.white,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: _tab == i ? kGold : const Color(0xFFEEEEEE)),
                ),
                alignment: Alignment.center,
                child: Text(tabs[i],
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _tab == i ? Colors.white : Colors.grey.shade600)),
              ),
            ),
          ),
          if (i < tabs.length - 1) const SizedBox(width: 7),
        ],
      ],
    );
  }

  // ── Overview tab ────────────────────────────────────────────────────────────
  List<Widget> _overview() {
    final st = stageStyle(_stage);
    return [
      _sectionCard('Basic information', [
        _info('Phone', _phone.isEmpty ? '—' : '+91 $_phone'),
        _info('Email', _email.isEmpty ? '—' : _email),
        _info('Address', '${_acc['address'] ?? '—'}'),
        _info('City', '${_acc['city'] ?? _acc['area'] ?? '—'}'),
        _info('GST', '${_acc['gstNumber'] ?? '—'}'),
        _info('Type', '${_acc['businessType'] ?? '—'}'),
      ]),
      _sectionCard('Sales information', [
        _info('Stage', st.text),
        _info('Funnel', '${_acc['funnelStage'] ?? '—'}'),
        _info('Lead score', '—'),
        _info('Priority', _activityBadge.text),
        _info('Assigned to', '${_acc['assignedToId'] ?? '—'}'),
        _info('Approved', _acc['isApproved'] == true ? 'Yes' : 'No'),
      ]),
      _kpiCard(),
    ];
  }

  Widget _kpiCard() {
    final total = _logs.length;
    final answered = _outcome('answered');
    final connect = total == 0 ? 0 : (answered * 100 / total).round();
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle('Performance indicators'),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 9,
            mainAxisSpacing: 9,
            childAspectRatio: 1.5,
            children: [
              _kpi('$connect%', 'Connect rate', const Color(0xFF2F9E57)),
              _kpi(money(_orderTotal), 'Lifetime value', kGoldDark),
              _kpi('${_orders.length}', 'Total orders', Colors.black87),
              _kpi('$total', 'Call attempts', Colors.black87),
              _kpi('$answered', 'Answered', const Color(0xFF2F9E57)),
              _kpi(_logs.isEmpty ? '—' : _shortWhen(_lastCallAt), 'Last call', Colors.black87),
            ],
          ),
        ],
      ),
    );
  }

  // ── Activity tab ────────────────────────────────────────────────────────────
  List<Widget> _activity() {
    final total = _logs.length;
    return [
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _cardTitle('Call statistics'),
              const Spacer(),
              Text('$total attempts', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade400)),
            ]),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.15,
              children: [
                _stat('$total', 'Attempts', Colors.black87),
                _stat('${_outcome('answered')}', 'Answered', const Color(0xFF2F9E57)),
                _stat('${_outcome('no_answer')}', 'No Answer', const Color(0xFFC0584C)),
                _stat('${_outcome('busy')}', 'Busy', const Color(0xFFD98A2B)),
                _stat('${_outcome('switch_off')}', 'Switched Off', const Color(0xFF5A6472)),
                _stat('${_outcome('invalid')}', 'Invalid', const Color(0xFFC0584C)),
                _stat('${_outcome('callback')}', 'Callback', const Color(0xFF3B6FD4)),
                _stat(_logs.isEmpty ? '—' : _shortWhen(_lastCallAt), 'Last', Colors.black87),
              ],
            ),
          ],
        ),
      ),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle('Call log'),
            const SizedBox(height: 8),
            if (_logs.isEmpty)
              _emptyInline('No calls logged yet')
            else
              ..._groupedLog(),
          ],
        ),
      ),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _cardTitle('Conversation notes'),
              const Spacer(),
              Text('${_notes.length} notes', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade400)),
            ]),
            const SizedBox(height: 8),
            if (_notes.isEmpty)
              _emptyInline('No notes yet — add one when you log a call')
            else
              ..._notes.map(_noteRow),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: _busy ? null : _openOutcomeSheet,
              style: OutlinedButton.styleFrom(
                foregroundColor: kGoldDark,
                side: const BorderSide(color: kGold),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                minimumSize: const Size(double.infinity, 42),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add note with a call', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
            ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _groupedLog() {
    // Group consecutive logs by calendar day, preserving the desc order.
    final widgets = <Widget>[];
    String? lastKey;
    final today = DateTime.now();
    for (final l in _logs) {
      final d = DateTime.tryParse('${l['called_at']}')?.toLocal();
      final key = d == null ? 'unknown' : '${d.year}-${d.month}-${d.day}';
      if (key != lastKey) {
        final isToday = d != null && d.year == today.year && d.month == today.month && d.day == today.day;
        widgets.add(Padding(
          padding: EdgeInsets.only(top: lastKey == null ? 0 : 12, bottom: 6),
          child: Row(children: [
            Text(d == null ? 'Unknown date' : _dayLabel(d),
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
            if (isToday) ...[
              const SizedBox(width: 6),
              Text('· Today', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade400)),
            ],
          ]),
        ));
        lastKey = key;
      }
      widgets.add(_logRow(l));
    }
    return widgets;
  }

  Widget _logRow(Map<String, dynamic> l) {
    final o = '${l['call_outcome'] ?? ''}';
    final color = kOutcomeColors[o] ?? const Color(0xFF9A7A2F);
    final label = kOutcomeLabels[o] ?? o;
    final d = DateTime.tryParse('${l['called_at']}')?.toLocal();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            height: 28,
            width: 28,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(8)),
            child: Icon(_outcomeIcon(o), size: 15, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text(d == null ? '—' : _timeOf(d), style: TextStyle(fontSize: 10.5, color: Colors.grey.shade400)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteRow(Map<String, dynamic> l) {
    final d = DateTime.tryParse('${l['called_at']}')?.toLocal();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(11)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(kOutcomeLabels['${l['call_outcome']}'] ?? '${l['call_outcome']}',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kGoldDark)),
            const Spacer(),
            Text(d == null ? '' : _shortWhen(d), style: TextStyle(fontSize: 10.5, color: Colors.grey.shade400)),
          ]),
          const SizedBox(height: 4),
          Text('${l['notes']}', style: const TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF404650))),
        ],
      ),
    );
  }

  // ── Orders tab (mockup-style: summary + history + create-order sheet) ───────
  List<Widget> _ordersTab() {
    final count = _orders.length;
    final avg = count == 0 ? 0 : (_orderTotal / count).round();
    return [
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle('Order summary'),
            const SizedBox(height: 12),
            Row(children: [
              _miniBox('$count', 'Total orders'),
              const SizedBox(width: 10),
              _miniBox(money(_orderTotal), 'Total value'),
              const SizedBox(width: 10),
              _miniBox(count == 0 ? '—' : money(avg), 'Avg value'),
            ]),
          ],
        ),
      ),
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              _cardTitle('Order history'),
              const Spacer(),
             
            ]),
            const SizedBox(height: 8),
            if (_orders.isEmpty)
              Column(children: [
                const SizedBox(height: 6),
                Icon(Icons.shopping_bag_outlined, size: 40, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text('No orders yet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                const SizedBox(height: 4),
                Text('Create the first one below.', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade400)),
                const SizedBox(height: 8),
              ])
            else
              ..._orders.map(_orderCard),
          ],
        ),
      ),
      SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton.icon(
          onPressed: _busy ? null : _openOrderSheet,
          style: ElevatedButton.styleFrom(
            backgroundColor: kGold,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Create order', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
        ),
      ),
    ];
  }

  Widget _miniBox(String n, String t) => Expanded(
        child: Container(
          decoration: BoxDecoration(color: const Color(0xFFF3F3F5), borderRadius: BorderRadius.circular(13)),
          padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
          child: Column(
            children: [
              FittedBox(child: Text(n, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
              const SizedBox(height: 3),
              Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500)),
            ],
          ),
        ),
      );

  Widget _orderCard(Map<String, dynamic> o) {
    final amt = (o['amt'] as num?)?.toInt() ?? 0;
    final status = '${o['status'] ?? ''}';
    final pay = '${o['pay'] ?? ''}';
    final sc = kOrderStatusColors[status] ?? const Color(0xFF5A6472);
    final orderId = o['order_id'] as String?;
    return GestureDetector(
      onTap: orderId == null
          ? () => _toast('This is a local draft — no real order to open yet')
          : () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => OrderDetailScreen(orderId: orderId)),
              ),
      child: Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(color: kGold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(11)),
            child: const Icon(Icons.receipt_long_rounded, size: 18, color: kGoldDark),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${o['inv'] ?? 'Order'}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                if ('${o['items'] ?? ''}'.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text('${o['items']} · ${o['date'] ?? ''}',
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
                  ),
                const SizedBox(height: 6),
                Wrap(spacing: 5, runSpacing: 4, children: [
                  if (status.isNotEmpty) _pill(status, sc),
                  if (pay.isNotEmpty) _pill(pay, const Color(0xFF5A6472)),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(money(amt), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      ),
      ),
    );
  }

  // ── Follow-up tab ───────────────────────────────────────────────────────────
  List<Widget> _followUpTab() {
    final open = _openFollowUp;
    return [
      _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(open == null ? 'No upcoming follow-up' : 'Upcoming follow-up'),
            const SizedBox(height: 10),
            if (open == null)
              _emptyInline('Schedule the next touchpoint below')
            else
              _fupCard(open),
          ],
        ),
      ),
      _ScheduleFollowUp(busy: _busy, onSchedule: _scheduleFollowUp),
    ];
  }

  Widget _fupCard(Map<String, dynamic> l) {
    final fu = '${l['follow_up_date'] ?? ''}';
    final date = DateTime.tryParse(fu);
    final overdue = date != null && date.isBefore(DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day));
    final color = overdue ? const Color(0xFFC0584C) : kGoldDark;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: overdue ? const Color(0xFFFDF5F4) : const Color(0xFFFDFAF2),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(date == null ? fu : _dayLabel(date),
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
            const Spacer(),
            _pill(overdue ? 'Overdue' : 'Scheduled', color),
          ]),
          if ('${l['notes'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('${l['notes']}', style: const TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF404650))),
          ],
          const SizedBox(height: 10),
          Row(children: [
            ElevatedButton.icon(
              onPressed: _busy ? null : () => launchPhoneCall(_phone),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2F9E57),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.call_rounded, size: 16),
              label: const Text('Call now', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: _busy ? null : () => _markDone(l),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Mark done', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ]),
        ],
      ),
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────────────
  void _emailAction() {
    if (_email.isEmpty) {
      _toast('No email on file');
      return;
    }
    launchEmail(_email, subject: _name);
  }

  void _openOrderSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderSheet(
        name: _name,
        accountId: _id,
        accountType: widget.accountType,
        onSave: (items, amt, status, pay, realOrderId) async {
          if (realOrderId != null) {
            // Real order — refetch from the server so the list/summary
            // reflect the authoritative saved row, not a guessed local copy.
            await _loadOrders();
            _toast('Sales order #$realOrderId created · ${money(amt)}');
            return;
          }
          // Lead draft — no backend row exists to refetch, keep it local-only.
          final now = DateTime.now();
          setState(() {
            _orders.insert(0, {
              'inv': 'INV-${20601 + _orders.length}',
              'date': '${now.day} ${_months[now.month - 1]} ${now.year}',
              'items': items,
              'amt': amt,
              'status': status,
              'pay': pay,
            });
          });
          _toast('Draft saved locally · ${money(amt)}');
        },
      ),
    );
  }

  Future<void> _markDone(Map<String, dynamic> l) async {
    final id = l['id'];
    if (id is! int) return;
    setState(() => _busy = true);
    final ok = await ApiService.updateCallLog(id, callbackDone: true);
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      _toast('Follow-up marked done');
      _load();
      NotificationService.cancelFollowUpReminders(_id);
    } else {
      _toast('Could not update');
    }
  }

  Future<void> _scheduleFollowUp(String date, String summary, DateTime? followUpDateTime) async {
    setState(() => _busy = true);
    final res = await ApiService.createCallLog({
      'account_id': _id,
      'account_type': widget.accountType,
      'call_outcome': 'callback',
      'notes': summary,
      'follow_up_date': date,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (res != null) {
      _toast('Follow-up scheduled');
      _load();
      final d = DateTime.tryParse(date);
      final fuTime = followUpDateTime ??
          (d != null ? DateTime(d.year, d.month, d.day, 9, 0) : DateTime.now().add(const Duration(hours: 1)));
      NotificationService.scheduleFollowUpReminders(_id, _name, fuTime);
      widget.onFollowUpScheduled?.call(date);
    } else {
      _toast('Could not schedule');
    }
  }

  void _openOutcomeSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OutcomeSheet(
        name: _name,
        onFollowUp: () => setState(() => _tab = 3),
        onSave: (outcome, note) async {
          final res = await ApiService.createCallLog({
            'account_id': _id,
            'account_type': widget.accountType,
            'call_outcome': outcome,
            if (note.isNotEmpty) 'notes': note,
          });
          if (!mounted) return false;
          if (res != null) {
            _toast('Outcome saved · ${kOutcomeLabels[outcome] ?? outcome}');
            _load();
            NotificationService.cancelFollowUpReminders(_id);
            return true;
          }
          _toast('Could not save');
          return false;
        },
      ),
    );
  }


  // ── Small shared widgets / helpers ──────────────────────────────────────────
  void _toast(String m) => Fluttertoast.showToast(msg: m, backgroundColor: kGoldDark, textColor: Colors.white);

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEEEEE)),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: child,
      );

  Widget _sectionCard(String title, List<Widget> infos) => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _cardTitle(title),
            const SizedBox(height: 8),
            Wrap(runSpacing: 10, children: infos),
          ],
        ),
      );

  Widget _cardTitle(String t) => Text(t, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black87));

  Widget _info(String label, String value, {bool full = false}) => SizedBox(
        width: full ? double.infinity : (MediaQuery.of(context).size.width - 24 - 28) / 2 - 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: .5, color: Colors.grey.shade400)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF20242B))),
          ],
        ),
      );

  Widget _kpi(String n, String t, Color color) => Container(
        decoration: BoxDecoration(color: const Color(0xFFF3F3F5), borderRadius: BorderRadius.circular(13)),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(child: Text(n, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color))),
            const SizedBox(height: 3),
            Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, color: Colors.grey.shade500)),
          ],
        ),
      );

  Widget _stat(String n, String t, Color color) => Container(
        decoration: BoxDecoration(color: const Color(0xFFF3F3F5), borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(child: Text(n, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color))),
            const SizedBox(height: 3),
            Text(t, textAlign: TextAlign.center, style: TextStyle(fontSize: 8.5, color: Colors.grey.shade500)),
          ],
        ),
      );

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );

  Widget _emptyInline(String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Center(child: Text(t, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade400))),
      );

  IconData _outcomeIcon(String o) => switch (o) {
        'answered' => Icons.check_rounded,
        'busy' => Icons.phone_paused_rounded,
        'no_answer' => Icons.phone_missed_rounded,
        'switch_off' => Icons.power_off_rounded,
        'invalid' => Icons.error_outline_rounded,
        'callback' => Icons.schedule_rounded,
        _ => Icons.call_rounded,
      };

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String _dayLabel(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
  String _shortWhen(DateTime? d) => d == null ? '—' : '${d.day} ${_months[d.month - 1]}';
  String _timeOf(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }
}

// ── Log-outcome bottom sheet ───────────────────────────────────────────────────
class _OutcomeSheet extends StatefulWidget {
  final String name;
  final Future<bool> Function(String outcome, String note) onSave;
  final VoidCallback onFollowUp;
  const _OutcomeSheet({required this.name, required this.onSave, required this.onFollowUp});

  @override
  State<_OutcomeSheet> createState() => _OutcomeSheetState();
}

class _OutcomeSheetState extends State<_OutcomeSheet> {
  static const _outcomes = [
    ('answered', 'Answered', Color(0xFF2F9E57)),
    ('busy', 'Busy', Color(0xFFD98A2B)),
    ('no_answer', 'No Answer', Color(0xFFC0584C)),
    ('switch_off', 'Switched Off', Color(0xFF5A6472)),
    ('invalid', 'Invalid Number', Color(0xFFC0584C)),
    ('callback', 'Will Callback', Color(0xFF3B6FD4)),
  ];
  String? _sel;
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(18, 8, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 42, height: 4, margin: const EdgeInsets.only(top: 8, bottom: 16), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(3)))),
          const Text('Log call outcome', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('${widget.name} · just now', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 9,
            mainAxisSpacing: 9,
            childAspectRatio: 3.6,
            children: _outcomes.map((o) {
              final (val, label, color) = o;
              final active = _sel == val;
              return GestureDetector(
                onTap: () => setState(() => _sel = val),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  decoration: BoxDecoration(
                    color: active ? kGold.withValues(alpha: 0.14) : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: active ? kGold : const Color(0xFFE7E7E7), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 9),
                      Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600))),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Add a note for this call (optional)…',
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              filled: true,
              fillColor: const Color(0xFFFAFAFA),
              contentPadding: const EdgeInsets.all(12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE7E7E7))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE7E7E7))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kGold)),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onFollowUp();
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: kGoldDark,
              side: const BorderSide(color: kGold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
              minimumSize: const Size(double.infinity, 44),
            ),
            icon: const Icon(Icons.event_rounded, size: 17),
            label: const Text('Set Follow-up', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 50,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving
                  ? null
                  : () async {
                      if (_sel == null) {
                        Fluttertoast.showToast(msg: 'Pick an outcome first', backgroundColor: Colors.red, textColor: Colors.white);
                        return;
                      }
                      final nav = Navigator.of(context);
                      setState(() => _saving = true);
                      final ok = await widget.onSave(_sel!, _note.text.trim());
                      if (!mounted) return;
                      setState(() => _saving = false);
                      if (ok) nav.pop();
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: kGold,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
              ),
              child: _saving
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Save outcome', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Schedule-follow-up form card ────────────────────────────────────────────────
class _ScheduleFollowUp extends StatefulWidget {
  final bool busy;
  final Future<void> Function(String date, String summary, DateTime? followUpDateTime) onSchedule;
  const _ScheduleFollowUp({required this.busy, required this.onSchedule});

  @override
  State<_ScheduleFollowUp> createState() => _ScheduleFollowUpState();
}

class _ScheduleFollowUpState extends State<_ScheduleFollowUp> {
  DateTime? _date;
  TimeOfDay? _time;
  String _priority = 'Medium';
  final _purpose = TextEditingController();

  @override
  void dispose() {
    _purpose.dispose();
    super.dispose();
  }

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  Widget build(BuildContext context) {
    final dateLabel = _date == null ? 'Select date' : '${_date!.day} ${_months[_date!.month - 1]} ${_date!.year}';
    final timeLabel = _time == null ? 'Time' : _time!.format(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEEEEEE)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Schedule next', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _field('Date', dateLabel, _pickDate, Icons.calendar_today_rounded)),
            const SizedBox(width: 10),
            Expanded(child: _field('Time', timeLabel, _pickTime, Icons.schedule_rounded)),
          ]),
          const SizedBox(height: 11),
          _label('Priority'),
          const SizedBox(height: 5),
          Row(
            children: ['High', 'Medium', 'Low'].map((p) {
              final active = _priority == p;
              final c = p == 'High' ? const Color(0xFFC0584C) : p == 'Medium' ? const Color(0xFFD98A2B) : const Color(0xFF5A6472);
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(right: p == 'Low' ? 0 : 8),
                  child: GestureDetector(
                    onTap: () => setState(() => _priority = p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: active ? c.withValues(alpha: 0.12) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: active ? c : const Color(0xFFE7E7E7), width: 1.4),
                      ),
                      child: Text(p, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: active ? c : Colors.grey.shade500)),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 11),
          _label('Purpose'),
          const SizedBox(height: 5),
          TextField(
            controller: _purpose,
            decoration: InputDecoration(
              hintText: "What's the next step?",
              hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
              filled: true,
              fillColor: const Color(0xFFFAFAFA),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE7E7E7))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE7E7E7))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: kGold)),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: widget.busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: kGold,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Schedule follow-up', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  void _submit() {
    if (_date == null) {
      Fluttertoast.showToast(msg: 'Pick a date first', backgroundColor: Colors.red, textColor: Colors.white);
      return;
    }
    final d = _date!;
    final t = _time ?? const TimeOfDay(hour: 9, minute: 0);
    final followUpDateTime = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    if (followUpDateTime.isBefore(DateTime.now())) {
      Fluttertoast.showToast(msg: 'Follow-up time is in the past', backgroundColor: Colors.red, textColor: Colors.white);
      return;
    }
    final dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final bits = <String>['Follow-up [$_priority]'];
    bits.add(t.format(context));
    final purpose = _purpose.text.trim();
    if (purpose.isNotEmpty) bits.add('— $purpose');
    widget.onSchedule(dateStr, bits.join(' '), followUpDateTime);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: const ColorScheme.light(primary: kGold, onPrimary: Colors.white)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? const TimeOfDay(hour: 16, minute: 30),
    );
    if (picked == null) return;
    // Reject past times when the selected date is today
    final now = DateTime.now();
    final d = _date ?? now;
    final isToday = d.year == now.year && d.month == now.month && d.day == now.day;
    if (isToday) {
      final pickedDt = DateTime(now.year, now.month, now.day, picked.hour, picked.minute);
      if (pickedDt.isBefore(now)) {
        Fluttertoast.showToast(msg: 'Pick a future time for today', backgroundColor: Colors.red, textColor: Colors.white);
        return;
      }
    }
    setState(() => _time = picked);
  }

  Widget _label(String t) => Text(t.toUpperCase(),
      style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: .5, color: Colors.grey.shade400));

  Widget _field(String label, String value, VoidCallback onTap, IconData icon) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(label),
          const SizedBox(height: 5),
          GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: const Color(0xFFE7E7E7)),
              ),
              child: Row(children: [
                Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                Icon(icon, size: 16, color: Colors.grey.shade400),
              ]),
            ),
          ),
        ],
      );
}

// ── Create-order bottom sheet (mockup) ──────────────────────────────────────────
class _OrderLineItem {
  final product = TextEditingController();
  final qty = TextEditingController(text: '1');
  final unitPrice = TextEditingController(text: '0');
  final totalTax = TextEditingController(text: '0');
  String unit = 'PCS';
  String? productId; // real product_id once selected from search — required to submit a real order

  double get qtyNum => double.tryParse(qty.text.trim()) ?? 0;
  double get priceNum => double.tryParse(unitPrice.text.trim()) ?? 0;
  double get taxNum => double.tryParse(totalTax.text.trim()) ?? 0;
  double get productTotal => qtyNum * priceNum;
  double get grossAmount => productTotal - taxNum;

  void dispose() {
    product.dispose();
    qty.dispose();
    unitPrice.dispose();
    totalTax.dispose();
  }
}

class _OrderAddon {
  String name;
  final amount = TextEditingController(text: '0');
  _OrderAddon(this.name);

  double get amountNum => double.tryParse(amount.text.trim()) ?? 0;

  void dispose() => amount.dispose();
}

class _OrderSheet extends StatefulWidget {
  final String name;
  final String accountId;
  final String accountType; // 'lead' | 'customer'
  final void Function(String items, int amount, String status, String pay, String? realOrderId) onSave;
  const _OrderSheet({
    required this.name,
    required this.accountId,
    required this.accountType,
    required this.onSave,
  });

  @override
  State<_OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<_OrderSheet> {
  static const _units = ['PCS', 'KG', 'BOX', 'LTR', 'DOZ'];
  static const _addonNames = ['Hamali', 'Transport', 'Packing', 'Discount', 'Other'];

  int? _voucherNo; // null while loading the real preview from the server
  DateTime _documentDate = DateTime.now();
  DateTime _expectedDate = DateTime.now().add(const Duration(days: 1));
  final _narration = TextEditingController();
  bool _pricesIncludeTax = true;

  final List<_OrderLineItem> _lineItems = [_OrderLineItem()];
  final List<_OrderAddon> _addons = [];
  bool _saving = false;

  bool get _isCustomer => widget.accountType == 'customer';

  @override
  void initState() {
    super.initState();
    _loadVoucherPreview();
  }

  Future<void> _loadVoucherPreview() async {
    final next = await ApiService.getNextSalesOrderId();
    if (!mounted) return;
    setState(() => _voucherNo = next);
  }

  @override
  void dispose() {
    _narration.dispose();
    for (final i in _lineItems) {
      i.dispose();
    }
    for (final a in _addons) {
      a.dispose();
    }
    super.dispose();
  }

  String get _financialYear {
    final d = _documentDate;
    final startYear = d.month >= 4 ? d.year : d.year - 1;
    return '${(startYear % 100).toString().padLeft(2, '0')}-${((startYear + 1) % 100).toString().padLeft(2, '0')}';
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  double get _grossAmount => _lineItems.fold(0, (s, i) => s + i.grossAmount);
  double get _totalTax => _lineItems.fold(0, (s, i) => s + i.taxNum);
  double get _addonsTotal => _addons.fold(0, (s, a) => s + a.amountNum);
  double get _grandTotal => _grossAmount + _totalTax + _addonsTotal;

  OutlineInputBorder _border([Color c = const Color(0xFFE7E7E7)]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: c));

  InputDecoration _decor(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: _border(),
        enabledBorder: _border(),
        focusedBorder: _border(kGold),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 5),
        child: Text(t.toUpperCase(),
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, letterSpacing: .5, color: Colors.grey.shade400)),
      );

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(t, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: kGoldDark)),
      );

  Widget _voucherArrow(IconData icon, VoidCallback? onTap) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 34, height: 38,
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: onTap != null ? kGoldDark : Colors.grey.shade300),
        ),
      );

  Widget _sectionCard({required String title, Widget? trailing, required Widget child}) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kGold.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: _sectionTitle(title)),
              ?trailing,
            ]),
            child,
          ],
        ),
      );

  Future<void> _pickDate({required bool expected}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: expected ? _expectedDate : _documentDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => expected ? _expectedDate = picked : _documentDate = picked);
    }
  }

  Future<void> _pickProduct(_OrderLineItem item) async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ProductPickerSheet(),
    );
    if (picked != null) {
      setState(() {
        item.product.text = picked['name'] as String? ?? '';
        item.productId = picked['product_id'] as String?;
      });
    }
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    final validItems = _lineItems.where((i) => i.product.text.trim().isNotEmpty && i.qtyNum > 0).toList();
    if (validItems.isEmpty) {
      Fluttertoast.showToast(msg: 'Add at least one product', backgroundColor: Colors.red, textColor: Colors.white);
      return;
    }
    final itemsSummary = validItems.map((i) => i.product.text.trim()).join(', ');

    if (!_isCustomer) {
      // Lead — no real `user` row to attach an order to. Local draft only.
      widget.onSave(itemsSummary, _grandTotal.round(), 'Draft', 'Pending', null);
      Navigator.of(context).pop();
      return;
    }

    final missingProduct = validItems.where((i) => i.productId == null).toList();
    if (missingProduct.isNotEmpty) {
      Fluttertoast.showToast(
        msg: 'Select a real product from search for every item before saving',
        backgroundColor: Colors.red, textColor: Colors.white,
      );
      return;
    }

    setState(() => _saving = true);
    final result = await ApiService.createSalesOrder(
      buyerUserId: widget.accountId,
      items: validItems.map((i) => {
        'product_id':  i.productId,
        'quantity':    i.qtyNum,
        'item_price':  i.priceNum,
        'unit':        i.unit,
      }).toList(),
      discount: 0,
      // Addons (Hamali/Transport/Packing/etc.) are extra charges, not a discount —
      // the backend has no dedicated "charges" field yet, so fold them into
      // delivery_charge (which the order-total formula adds, matching intent).
      deliveryCharge: _addonsTotal,
      narration: _narration.text.trim().isEmpty ? null : _narration.text.trim(),
      department: null,
      areaName: null,
      timeSlot: _fmtDate(_expectedDate),
      documentDate: _isoDate(_documentDate),
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (result == null) {
      Fluttertoast.showToast(msg: 'Could not create the order. Try again.', backgroundColor: Colors.red, textColor: Colors.white);
      return;
    }

    final realOrderId = result['order_id']?.toString();
    final savedTotal = ((result['order_total'] as num?) ?? _grandTotal).round();
    widget.onSave(itemsSummary, savedTotal, 'Pending', 'Not Paid', realOrderId);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height - MediaQuery.of(context).padding.top,
      padding: EdgeInsets.fromLTRB(18, 8, 18, 18 + MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 42, height: 4, margin: const EdgeInsets.only(top: 8, bottom: 16), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(3)))),
                const Text('Create Sales Order', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(widget.name, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(height: 18),

                // ── Customer & Dates ──────────────────────────────────────────
            _sectionCard(
              title: 'Customer & Dates',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Financial Year'),
                        Container(
                          height: 46,
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFE7E7E7))),
                          child: Text(_financialYear, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Voucher No'),
                        Container(
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFE7E7E7))),
                          child: Row(children: [
                            // No real "previous voucher" to browse to here — this is always
                            // a *new* order, so only a refresh action makes sense (the preview
                            // can go stale if another order is created elsewhere meanwhile).
                            _voucherArrow(Icons.chevron_left_rounded, null),
                            Expanded(
                              child: _voucherNo == null
                                  ? const Center(
                                      child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: kGold)),
                                    )
                                  : Text('$_voucherNo',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                            ),
                            _voucherArrow(Icons.refresh_rounded, _loadVoucherPreview),
                          ]),
                        ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Document Date *'),
                        InkWell(
                          borderRadius: BorderRadius.circular(11),
                          onTap: () => _pickDate(expected: false),
                          child: Container(
                            height: 46,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFE7E7E7))),
                            child: Row(children: [
                              Expanded(child: Text(_fmtDate(_documentDate), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                              Icon(Icons.calendar_today_rounded, size: 15, color: Colors.grey.shade500),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        _label('Expected Date'),
                        InkWell(
                          borderRadius: BorderRadius.circular(11),
                          onTap: () => _pickDate(expected: true),
                          child: Container(
                            height: 46,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFE7E7E7))),
                            child: Row(children: [
                              Expanded(child: Text(_fmtDate(_expectedDate), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                              Icon(Icons.calendar_today_rounded, size: 15, color: Colors.grey.shade500),
                            ]),
                          ),
                        ),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _label('Customer'),
                  Container(
                    width: double.infinity,
                    height: 46,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFE7E7E7))),
                    child: Text(widget.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: 14),
                  _label('Narration'),
                  TextField(controller: _narration, maxLines: 2, decoration: _decor('', hint: 'Notes for this order…')),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFE7E7E7))),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Prices include tax', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                          Text('Line prices are entered tax-inclusive', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ]),
                      ),
                      Switch.adaptive(
                        value: _pricesIncludeTax,
                        activeThumbColor: kGold,
                        onChanged: (v) => setState(() => _pricesIncludeTax = v),
                      ),
                    ]),
                  ),
                ],
              ),
            ),

            // ── Product Detail ────────────────────────────────────────────
            _sectionCard(
              title: 'Product Detail',
              trailing: GestureDetector(
                onTap: () => setState(() => _lineItems.add(_OrderLineItem())),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: kGold.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: kGold.withValues(alpha: 0.4))),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.add_rounded, size: 15, color: kGoldDark),
                    SizedBox(width: 3),
                    Text('Add Item', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: kGoldDark)),
                  ]),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 6),
                  ..._lineItems.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final item = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFFCFAF3), borderRadius: BorderRadius.circular(12), border: Border.all(color: kGold.withValues(alpha: 0.3))),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text('Item ${idx + 1}  |  HSN: NA',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade600)),
                            ),
                            if (_lineItems.length > 1)
                              GestureDetector(
                                onTap: () => setState(() { item.dispose(); _lineItems.removeAt(idx); }),
                                child: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFC0584C)),
                              ),
                          ]),
                          const SizedBox(height: 10),
                          _label('Product *'),
                          InkWell(
                            borderRadius: BorderRadius.circular(11),
                            onTap: () => _pickProduct(item),
                            child: IgnorePointer(
                              child: TextField(
                                controller: item.product,
                                decoration: _decor('', hint: 'Tap to search…').copyWith(
                                  suffixIcon: Icon(Icons.search_rounded, size: 18, color: Colors.grey.shade500),
                                  suffixIconConstraints: const BoxConstraints(minWidth: 36),
                                ),
                              ),
                            ),
                          ),
                          if (item.product.text.isNotEmpty && item.productId == null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('Select a real product from search results',
                                  style: TextStyle(fontSize: 10.5, color: Colors.red.shade400)),
                            ),
                          const SizedBox(height: 12),
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                _label('Qty *'),
                                TextField(controller: item.qty, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: _decor('')),
                              ]),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                _label('Unit'),
                                Container(
                                  height: 46,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFE7E7E7))),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: item.unit,
                                      isExpanded: true,
                                      isDense: true,
                                      style: const TextStyle(fontSize: 13, color: Color(0xFF20242B), fontWeight: FontWeight.w500),
                                      items: _units.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                                      onChanged: (v) { if (v != null) setState(() => item.unit = v); },
                                    ),
                                  ),
                                ),
                              ]),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                _label('Unit Price (incl. tax) *'),
                                TextField(controller: item.unitPrice, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: _decor('')),
                              ]),
                            ),
                          ]),
                          const SizedBox(height: 12),
                          Divider(height: 1, color: kGold.withValues(alpha: 0.2)),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                _label('Gross Amount'),
                                Text(item.grossAmount.toStringAsFixed(2), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                              ]),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                _label('Total Tax'),
                                TextField(
                                  controller: item.totalTax,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  onChanged: (_) => setState(() {}),
                                  decoration: _decor(''),
                                ),
                              ]),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                _label('Product Total'),
                                Text(item.productTotal.toStringAsFixed(2), style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: kGoldDark)),
                              ]),
                            ),
                          ]),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),

            // ── Addon ──────────────────────────────────────────────────────
            _sectionCard(
              title: 'Addon',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  ..._addons.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final addon = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _label('Name'),
                            Container(
                              height: 46,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(color: const Color(0xFFFAFAFA), borderRadius: BorderRadius.circular(11), border: Border.all(color: const Color(0xFFE7E7E7))),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: addon.name,
                                  isExpanded: true,
                                  isDense: true,
                                  style: const TextStyle(fontSize: 13, color: Color(0xFF20242B), fontWeight: FontWeight.w500),
                                  items: _addonNames.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
                                  onChanged: (v) { if (v != null) setState(() => addon.name = v); },
                                ),
                              ),
                            ),
                          ]),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _label('Amount'),
                            TextField(controller: addon.amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), onChanged: (_) => setState(() {}), decoration: _decor('')),
                          ]),
                        ),
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: GestureDetector(
                            onTap: () => setState(() { addon.dispose(); _addons.removeAt(idx); }),
                            child: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFC0584C)),
                          ),
                        ),
                      ]),
                    );
                  }),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: () => setState(() => _addons.add(_OrderAddon(_addonNames.first))),
                      icon: const Icon(Icons.add_rounded, size: 15, color: kGoldDark),
                      label: const Text('Addons', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kGoldDark)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: kGold), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                    ),
                  ),
                ],
              ),
            ),

            // ── Summary ────────────────────────────────────────────────────
            _sectionCard(
              title: 'Summary',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Row(children: [
                    Text('Gross Amount', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                    const Spacer(),
                    Text(_grossAmount.toStringAsFixed(2), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 10),
                  Divider(height: 1, color: kGold.withValues(alpha: 0.2)),
                  const SizedBox(height: 10),
                  Row(children: [
                    const Text('Total', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                    const Spacer(),
                    Text('₹${_grandTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kGoldDark)),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: (_isCustomer ? const Color(0xFF2F9E57) : const Color(0xFFD98A2B)).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _isCustomer
                    ? 'This will create a real Sales Order for this customer.'
                    : 'This account is a lead, not a registered customer yet — saved as a local draft only, not a real order.',
                style: TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w600,
                  color: _isCustomer ? const Color(0xFF2F9E57) : const Color(0xFFD98A2B),
                ),
              ),
            ),
            const SizedBox(height: 14),

            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black54)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGold,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: kGold.withValues(alpha: 0.5),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                  ),
                  child: _saving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Save', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ],
            ),
          ),
          Positioned(
            top: 4, right: 0,
            child: GestureDetector(
              onTap: _saving ? null : () => Navigator.of(context).pop(),
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: Colors.grey.shade100, shape: BoxShape.circle),
                child: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Product picker (real catalog search) ───────────────────────────────────

class _ProductPickerSheet extends StatefulWidget {
  const _ProductPickerSheet();

  @override
  State<_ProductPickerSheet> createState() => _ProductPickerSheetState();
}

class _ProductPickerSheetState extends State<_ProductPickerSheet> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  List<Map<String, dynamic>> _results = [];

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    final results = await ApiService.searchProducts(q);
    if (!mounted) return;
    setState(() { _results = results; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: EdgeInsets.fromLTRB(18, 8, 18, 12 + MediaQuery.of(context).viewInsets.bottom),
      decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 42, height: 4, margin: const EdgeInsets.only(top: 8, bottom: 16), decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(3)))),
          const Text('Select Product', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            autofocus: true,
            onChanged: _onChanged,
            decoration: InputDecoration(
              hintText: 'Search products…',
              prefixIcon: const Icon(Icons.search_rounded, color: kGold),
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFFAFAFA),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE7E7E7))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: Color(0xFFE7E7E7))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: const BorderSide(color: kGold)),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: kGold))
                : _results.isEmpty
                    ? Center(child: Text('No products found', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)))
                    : ListView.separated(
                        itemCount: _results.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final p = _results[i];
                          final name = (p['name'] ?? '').toString();
                          final hsn  = (p['hsn_code'] ?? '').toString();
                          return ListTile(
                            title: Text(name, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                            subtitle: hsn.isNotEmpty ? Text('HSN: $hsn', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)) : null,
                            onTap: () => Navigator.of(context).pop(p),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
