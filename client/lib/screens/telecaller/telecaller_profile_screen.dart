import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../services/api_service.dart';
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

  const TelecallerProfileScreen({
    super.key,
    required this.account,
    required this.accountType,
    this.onCalled,
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
  // Mockup-style orders. Session-local (no orders-with-amounts table yet).
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

  Widget _avatar(double size, double font) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: avatarColorFor(_id.isNotEmpty ? _id : _name), borderRadius: BorderRadius.circular(14)),
        alignment: Alignment.center,
        child: Text(initialsOf(_name), style: TextStyle(fontSize: font, fontWeight: FontWeight.w700, color: Colors.white)),
      );

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
              GestureDetector(
                onTap: _busy ? null : _openOrderSheet,
                child: const Text('+ New order', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kGoldDark)),
              ),
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
    return Container(
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
        onSave: (items, amt, status, pay) {
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
          _toast('Order created · ${money(amt)}');
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
    } else {
      _toast('Could not update');
    }
  }

  Future<void> _scheduleFollowUp(String date, String summary) async {
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
  final Future<void> Function(String date, String summary) onSchedule;
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
    final dateStr = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final bits = <String>['Follow-up [$_priority]'];
    if (_time != null) bits.add(_time!.format(context));
    final purpose = _purpose.text.trim();
    if (purpose.isNotEmpty) bits.add('— $purpose');
    widget.onSchedule(dateStr, bits.join(' '));
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
    final picked = await showTimePicker(context: context, initialTime: _time ?? const TimeOfDay(hour: 16, minute: 30));
    if (picked != null) setState(() => _time = picked);
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
class _OrderSheet extends StatefulWidget {
  final String name;
  final void Function(String items, int amount, String status, String pay) onSave;
  const _OrderSheet({required this.name, required this.onSave});

  @override
  State<_OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<_OrderSheet> {
  final _items = TextEditingController();
  final _amount = TextEditingController();
  String _pay = kPaymentOptions.first;
  String _status = 'Confirmed';

  @override
  void dispose() {
    _items.dispose();
    _amount.dispose();
    super.dispose();
  }

  OutlineInputBorder _border([Color c = const Color(0xFFE7E7E7)]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: c));

  InputDecoration _decor(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
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
          const Text('Create order', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(widget.name, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          const SizedBox(height: 16),
          _label('Products / items'),
          TextField(controller: _items, decoration: _decor('e.g. Staples + oils · 12 SKUs')),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('Order value (₹)'),
                  TextField(controller: _amount, keyboardType: TextInputType.number, decoration: _decor('0')),
                ]),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('Payment'),
                  _dropdown(_pay, kPaymentOptions, (v) => setState(() => _pay = v)),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _label('Status'),
          _dropdown(_status, kOrderStatusOptions, (v) => setState(() => _status = v)),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                final amt = int.tryParse(_amount.text.trim().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                if (amt <= 0) {
                  Fluttertoast.showToast(msg: 'Enter an order value', backgroundColor: Colors.red, textColor: Colors.white);
                  return;
                }
                final items = _items.text.trim().isEmpty ? 'Order items' : _items.text.trim();
                widget.onSave(items, amt, _status, _pay);
                Navigator.of(context).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kGold,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
              ),
              child: const Text('Create order', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropdown(String value, List<String> options, ValueChanged<String> onChanged) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFA),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFFE7E7E7)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            isDense: true,
            style: const TextStyle(fontSize: 13, color: Color(0xFF20242B), fontWeight: FontWeight.w500),
            items: options.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );
}
