import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../widgets/account_map_screen.dart';
import 'telecaller_mock_data.dart';

/// Worklist — Customers-style list (mockup): search, filter chips, and rich
/// cards (avatar, name, company · city, stage/temperature/priority pills, a
/// stage-progress ring, and a Last-contact / Next-follow-up / Revenue footer).
/// Tapping a card opens the rich profile. Stage, last-contact and next-follow-up
/// are real (from `/api/telecaller/worklist`); temperature, priority and the
/// ring are derived from stage; revenue is a placeholder pending an orders table.
class TelecallerWorklistScreen extends StatefulWidget {
  const TelecallerWorklistScreen({super.key});

  @override
  State<TelecallerWorklistScreen> createState() => _TelecallerWorklistScreenState();
}

class _TelecallerWorklistScreenState extends State<TelecallerWorklistScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  // account_id's scheduled in the beat plan for today.
  Set<String> _todayIds = {};
  // account_id's with a follow-up due today or overdue.
  Set<String> _followUpIds = {};
  // account_id's that the telecaller has called in this session.
  final Set<String> _calledToday = {};
  String _filter = 'all';
  String _search = '';
  final _searchCtrl = TextEditingController();

  // (key, label)
  static const _filters = <(String, String)>[
    ('all', 'All'),
    ('follow_up', 'Follow-up due'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final worklistF   = ApiService.getTelecallerWorklist();
    final todayF      = ApiService.getTodayBeatPlan();
    final callbacksF  = ApiService.getTelecallerCallbacks();
    final items       = await worklistF;
    final todayRes    = await todayF;
    final callbacks   = await callbacksF;
    if (!mounted) return;

    final now       = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);

    final todayIds    = <String>{};
    final followUpIds = <String>{};
    final merged = [...items];
    final byId   = {for (final w in items) '${w['account_id']}': w};

    // Beat plan — accounts scheduled for today.
    final todayRaw = todayRes['data'];
    if (todayRaw is List) {
      for (final t in todayRaw) {
        if (t is! Map) continue;
        final acc = t['account'];
        if (acc is! Map) continue;
        final id = '${acc['id']}';
        if (id.isEmpty || id == 'null') continue;
        todayIds.add(id);
        if (!byId.containsKey(id)) {
          final biz    = '${acc['businessName'] ?? ''}'.trim();
          final person = '${acc['personName']   ?? ''}'.trim();
          final item = {
            'account_id':     id,
            'account_type':   '${t['account_type'] ?? 'lead'}',
            'name':           biz.isNotEmpty ? biz : (person.isNotEmpty ? person : 'Unknown'),
            'business_name':  biz,
            'person_name':    person,
            'phone':          '${acc['contactNumber'] ?? ''}',
            'area':           '${acc['area'] ?? ''}',
            'city':           '${acc['city'] ?? acc['area'] ?? ''}',
            'pincode':        '${acc['pincode'] ?? ''}',
            'stage':          '${acc['customerStage'] ?? 'lead'}',
            'label':          kLabelNotCalled,
            'last_contact':   null,
            'next_follow_up': null,
            'latitude':       acc['latitude'],
            'longitude':      acc['longitude'],
          };
          merged.add(item);
          byId[id] = item;
        }
      }
    }

    // Follow-ups — accounts with a due/overdue follow-up regardless of beat plan.
    for (final cb in callbacks) {
      final id    = '${cb['account_id'] ?? ''}';
      if (id.isEmpty || id == 'null') continue;
      final fuStr = '${cb['follow_up_date'] ?? ''}';
      if (fuStr.isEmpty || fuStr == 'null') continue;
      final fuDate = DateTime.tryParse(fuStr);
      if (fuDate == null) continue;
      if (!DateTime(fuDate.year, fuDate.month, fuDate.day).isAfter(todayDate)) {
        followUpIds.add(id);
        // Add to list only if not already present from worklist or beat plan.
        if (!byId.containsKey(id)) {
          final item = {
            'account_id':     id,
            'account_type':   '${cb['account_type'] ?? 'lead'}',
            'name':           '${cb['name'] ?? 'Unknown'}',
            'business_name':  '',
            'person_name':    '${cb['name'] ?? ''}',
            'phone':          '${cb['phone'] ?? ''}',
            'area':           '${cb['area'] ?? ''}',
            'city':           '${cb['area'] ?? ''}',
            'pincode':        '',
            'stage':          '${cb['stage'] ?? 'lead'}',
            'label':          kLabelFollowUp,
            'last_contact':   null,
            'next_follow_up': fuStr,
          };
          merged.add(item);
          byId[id] = item;
        }
      }
    }

    // Also mark worklist items that have a due follow-up (even if not in beat plan).
    for (final w in merged) {
      final id    = '${w['account_id']}';
      final fuStr = '${w['next_follow_up'] ?? ''}';
      if (fuStr.isEmpty || fuStr == 'null') continue;
      final fuDate = DateTime.tryParse(fuStr);
      if (fuDate == null) continue;
      if (!DateTime(fuDate.year, fuDate.month, fuDate.day).isAfter(todayDate)) {
        followUpIds.add(id);
      }
    }

    setState(() {
      _items       = merged;
      _todayIds    = todayIds;
      _followUpIds = followUpIds;
      _loading     = false;
    });

  }

  // Silent background refresh — same data logic as _load() but no spinner.
  Future<void> _backgroundSync() async {
    final worklistF  = ApiService.getTelecallerWorklist();
    final todayF     = ApiService.getTodayBeatPlan();
    final callbacksF = ApiService.getTelecallerCallbacks();
    final items      = await worklistF;
    final todayRes   = await todayF;
    final callbacks  = await callbacksF;
    if (!mounted) return;

    final now       = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final todayIds    = <String>{};
    final followUpIds = <String>{};
    final merged = [...items];
    final byId   = {for (final w in items) '${w['account_id']}': w};

    final todayRaw = todayRes['data'];
    if (todayRaw is List) {
      for (final t in todayRaw) {
        if (t is! Map) continue;
        final acc = t['account'];
        if (acc is! Map) continue;
        final id = '${acc['id']}';
        if (id.isEmpty || id == 'null') continue;
        todayIds.add(id);
        if (!byId.containsKey(id)) {
          final biz    = '${acc['businessName'] ?? ''}'.trim();
          final person = '${acc['personName']   ?? ''}'.trim();
          final item = {
            'account_id':     id,
            'account_type':   '${t['account_type'] ?? 'lead'}',
            'name':           biz.isNotEmpty ? biz : (person.isNotEmpty ? person : 'Unknown'),
            'business_name':  biz,
            'person_name':    person,
            'phone':          '${acc['contactNumber'] ?? ''}',
            'area':           '${acc['area'] ?? ''}',
            'city':           '${acc['city'] ?? acc['area'] ?? ''}',
            'pincode':        '${acc['pincode'] ?? ''}',
            'stage':          '${acc['customerStage'] ?? 'lead'}',
            'label':          kLabelNotCalled,
            'last_contact':   null,
            'next_follow_up': null,
            'latitude':       acc['latitude'],
            'longitude':      acc['longitude'],
          };
          merged.add(item);
          byId[id] = item;
        }
      }
    }

    for (final cb in callbacks) {
      final id    = '${cb['account_id'] ?? ''}';
      if (id.isEmpty || id == 'null') continue;
      final fuStr = '${cb['follow_up_date'] ?? ''}';
      if (fuStr.isEmpty || fuStr == 'null') continue;
      final fuDate = DateTime.tryParse(fuStr);
      if (fuDate == null) continue;
      if (!DateTime(fuDate.year, fuDate.month, fuDate.day).isAfter(todayDate)) {
        followUpIds.add(id);
        if (!byId.containsKey(id)) {
          final item = {
            'account_id':     id,
            'account_type':   '${cb['account_type'] ?? 'lead'}',
            'name':           '${cb['name'] ?? 'Unknown'}',
            'business_name':  '',
            'person_name':    '${cb['name'] ?? ''}',
            'phone':          '${cb['phone'] ?? ''}',
            'area':           '${cb['area'] ?? ''}',
            'city':           '${cb['area'] ?? ''}',
            'pincode':        '',
            'stage':          '${cb['stage'] ?? 'lead'}',
            'label':          kLabelFollowUp,
            'last_contact':   null,
            'next_follow_up': fuStr,
          };
          merged.add(item);
          byId[id] = item;
        }
      }
    }

    for (final w in merged) {
      final id    = '${w['account_id']}';
      final fuStr = '${w['next_follow_up'] ?? ''}';
      if (fuStr.isEmpty || fuStr == 'null') continue;
      final fuDate = DateTime.tryParse(fuStr);
      if (fuDate == null) continue;
      if (!DateTime(fuDate.year, fuDate.month, fuDate.day).isAfter(todayDate)) {
        followUpIds.add(id);
      }
    }

    setState(() {
      _items       = merged;
      _todayIds    = todayIds;
      _followUpIds = followUpIds;
    });
  }

  // Immediately update a single item's follow-up date and pill without an API round-trip.
  void _onFollowUpScheduled(String accountId, String date) {
    final now       = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final fuDate    = DateTime.tryParse(date);

    final idx = _items.indexWhere((w) => '${w['account_id']}' == accountId);
    if (idx != -1) {
      _items[idx] = {..._items[idx], 'next_follow_up': date};
    }

    if (fuDate != null &&
        !DateTime(fuDate.year, fuDate.month, fuDate.day).isAfter(todayDate)) {
      _followUpIds.add(accountId);
      _todayIds.add(accountId);
    }

    setState(() {});
  }

  // Today = in beat plan for today OR has a follow-up due/overdue today.
  bool _isToday(Map<String, dynamic> w) {
    final id = '${w['account_id']}';
    return _todayIds.contains(id) || _followUpIds.contains(id);
  }

  // ── Filtering ───────────────────────────────────────────────────────────────
  bool _matchesFilter(Map<String, dynamic> w) {
    final stage = '${w['stage'] ?? ''}';
    switch (_filter) {
      case 'follow_up':
        return _followUpIds.contains('${w['account_id']}');
      case 'hot':
        return tempForStage(stage).text == 'Hot';
      case 'high_value':
        return stageProgress(stage) >= 70;
      case 'repeat':
        return stage.toLowerCase() == 'customer';
      default:
        return true;
    }
  }

  bool _matchesSearch(Map<String, dynamic> w) {
    if (_search.isEmpty) return true;
    final q = _search.toLowerCase();
    final hay = [
      w['name'], w['business_name'], w['person_name'], w['city'], w['area'], w['phone'],
    ].map((e) => '${e ?? ''}'.toLowerCase()).join(' ');
    return hay.contains(q);
  }

  List<Map<String, dynamic>> get _visible {
    final list = _items.where(_isToday).where(_matchesFilter).where(_matchesSearch).toList();
    // Sort order: follow-up due (0) → beat-plan only (1) → called-today (2).
    int rank(Map<String, dynamic> w) {
      final id = '${w['account_id']}';
      if (_calledToday.contains(id)) return 2;
      if (_followUpIds.contains(id)) return 0;
      return 1;
    }
    list.sort((a, b) => rank(a) - rank(b));
    return list;
  }

  int _countFor(String key) {
    final old = _filter;
    _filter = key;
    final n = _items.where(_isToday).where(_matchesFilter).where(_matchesSearch).length;
    _filter = old;
    return n;
  }

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _call(String phone) async => _launch('tel:$phone');

  Future<void> _whatsapp(String phone) async {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    final number = digits.length == 10 ? '91$digits' : digits;
    _launch('https://wa.me/$number');
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kGold,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Today Worklist', style: TextStyle(fontWeight: FontWeight.w700)),
            Text('${_items.where(_isToday).length} today', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: Colors.white70)),
          ],
        ),
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : Column(
              children: [
                _searchBar(),
                _chips(),
                Expanded(
                  child: visible.isEmpty
                      ? Center(
                          child: Text(
                            _items.where(_isToday).isEmpty
                                ? 'No accounts scheduled for today'
                                : 'No accounts match this filter',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 2, 12, 24),
                            itemCount: visible.length,
                            itemBuilder: (_, i) => _card(visible[i]),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  // ── Search ──────────────────────────────────────────────────────────────────
  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 20, color: Colors.grey.shade400),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _search = v),
                decoration: const InputDecoration(
                  hintText: 'Search name, company, city…',
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 13),
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
            if (_search.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchCtrl.clear();
                  setState(() => _search = '');
                },
                child: Icon(Icons.close_rounded, size: 18, color: Colors.grey.shade400),
              ),
          ],
        ),
      ),
    );
  }

  // ── Chips ───────────────────────────────────────────────────────────────────
  Widget _chips() {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final f in _filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setState(() => _filter = f.$1),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  decoration: BoxDecoration(
                    color: _filter == f.$1 ? kGold : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _filter == f.$1 ? kGold : const Color(0xFFE7E7E7), width: 1.4),
                  ),
                  child: Text(
                    '${f.$2} (${_countFor(f.$1)})',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _filter == f.$1 ? Colors.white : const Color(0xFF5A6472),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Card ────────────────────────────────────────────────────────────────────
  // Ported from employee/todays_beat_plan_screen.dart's _CustomerCard layout
  // (tag row → title/owner row → detail lines → footer of phone + quick
  // actions) so both screens share the same card language. Beat Plan's
  // account-code/frequency/address fields aren't present on a worklist item,
  // so those slots are dropped; the stage/priority/follow-up pills and the
  // Last contact / Next follow-up / Revenue footer are worklist-specific and
  // kept since removing them would lose real CRM info Beat Plan doesn't have.
  Widget _card(Map<String, dynamic> w) {
    final name = '${w['name'] ?? 'Unknown'}';
    final business = '${w['business_name'] ?? ''}'.trim();
    final person = '${w['person_name'] ?? ''}'.trim();
    final city = '${w['city'] ?? w['area'] ?? ''}'.trim();
    final area = '${w['area'] ?? ''}'.trim();
    final pincode = '${w['pincode'] ?? ''}'.trim();
    final address = '${w['address'] ?? ''}'.trim();
    final addresses = ((w['addresses'] as List?) ?? [])
        .map((a) => (a is Map ? a['address'] : a)?.toString() ?? '')
        .where((a) => a.isNotEmpty)
        .toList();
    final phone = '${w['phone'] ?? ''}'.trim();
    final lat = _toDouble(w['latitude']);
    final lng = _toDouble(w['longitude']);
    final accountType = '${w['account_type'] ?? 'lead'}';
    final stage = '${w['stage'] ?? ''}';
    final st = stageStyle(stage);
    final prio = priorityForStage(stage);
    final accountId    = '${w['account_id']}';
    final wasCalled    = _calledToday.contains(accountId);
    final isFollowUp   = _followUpIds.contains(accountId);
    // Shop / business name on top (dark); owner name goes beside it, like
    // Beat Plan's name+person row, instead of stacked underneath.
    final title = business.isNotEmpty ? business : (person.isNotEmpty ? person : name);
    final owner = (person.isNotEmpty && person != title) ? person : '';

    // Matches employee/todays_beat_plan_screen.dart's card treatment: a
    // tinted background + full colored border instead of a plain white card
    // with a thin left accent stripe — green once called today, soft
    // pink/red while still needing a call, mirroring that screen's
    // visited-vs-pending states.
    final cardBg     = wasCalled ? const Color(0xFFF0FFF4) : const Color(0xFFFFF0EE);
    final cardBorder = wasCalled ? const Color(0xFFC8E6C9) : const Color(0xFFFFD8D2);

    return Container(
      margin: const EdgeInsets.only(bottom: 11),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cardBorder),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: InkWell(
        onTap: () => _openProfile(w),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 13, 13, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top tag row — account type + called/follow-up status, same
              // slot Beat Plan uses for account type + frequency/visited.
              Row(
                children: [
                  const Spacer(),
                  _tag(
                    accountType.toUpperCase(),
                    bg: accountType == 'customer' ? const Color(0xFFE3F2FD) : const Color(0xFFFFF3E0),
                    fg: accountType == 'customer' ? const Color(0xFF1976D2) : const Color(0xFFF57C00),
                  ),
                  const SizedBox(width: 6),
                  if (wasCalled)
                    _tag('✓ Called', bg: const Color(0xFFE8F5E9), fg: const Color(0xFF2E7D32))
                  else if (isFollowUp)
                    _tag('Follow-up due', bg: const Color(0xFFFFEBEE), fg: const Color(0xFFE53935)),
                ],
              ),
              const SizedBox(height: 6),
              // Name + owner row — matches Beat Plan's name+person layout
              // (business name expanded on the left, owner right-aligned)
              // instead of stacking owner into a subtitle line underneath.
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                if (owner.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(owner, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ]),
              const SizedBox(height: 7),
              Wrap(spacing: 5, runSpacing: 5, children: [
                _stagePill(st),
                _pill(prio.text, prio.color),
              ]),
              if (addresses.length > 1) ...[
                const SizedBox(height: 6),
                ...addresses.asMap().entries.map((e) => Text(
                      'Address ${e.key + 1} : ${e.value}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    )),
              ] else if (address.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Address : $address', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
              if (city.isNotEmpty || area.isNotEmpty || pincode.isNotEmpty) ...[
                const SizedBox(height: 6),
                if (city.isNotEmpty && city != area)
                  Text('City : $city', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                if (area.isNotEmpty)
                  Text('Main area : $area', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                if (pincode.isNotEmpty)
                  Text('PIN : $pincode', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              ],
              const Divider(height: 20, color: Color(0xFFF0F0F0)),
              Row(
                children: [
                  _foot('Last contact', _fmtDate('${w['last_contact'] ?? ''}'), Colors.black87),
                  _foot('Next follow-up', _fmtDate('${w['next_follow_up'] ?? ''}'),
                      '${w['next_follow_up'] ?? ''}'.isNotEmpty ? kGoldDark : Colors.black87),
                  _foot('Revenue', '₹0', Colors.black87, end: true),
                ],
              ),
              const SizedBox(height: 10),
              // Phone chip + quick actions — same footer pattern as Beat
              // Plan's card, now including its view/map buttons too.
              Row(
                children: [
                  if (phone.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.phone_rounded, size: 13, color: Colors.grey.shade600),
                        const SizedBox(width: 5),
                        Text(phone, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  const Spacer(),
                  _actionBtn(Icon(Icons.visibility_outlined, size: 18, color: Colors.grey.shade600), Colors.grey.shade600, () => _openProfile(w)),
                  if (phone.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    _actionBtn(Icon(Icons.call_rounded, size: 18, color: Colors.grey.shade600), Colors.grey.shade600, () => _call(phone)),
                    const SizedBox(width: 6),
                    _actionBtn(const FaIcon(FontAwesomeIcons.whatsapp, size: 18, color: Color(0xFF25D366)), const Color(0xFF25D366), () => _whatsapp(phone)),
                  ],
                  if (lat != null && lng != null) ...[
                    const SizedBox(width: 6),
                    _actionBtn(
                      const Icon(Icons.map_rounded, size: 18, color: Color(0xFF1565C0)),
                      const Color(0xFF1565C0),
                      () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AccountMapScreen(
                            title: title,
                            // AccountMapScreen reads businessName/personName/
                            // contactNumber/address — remap from this item's
                            // own key names rather than spreading `w` as-is.
                            accounts: [{
                              'businessName':  title,
                              'personName':    owner,
                              'contactNumber': phone,
                              'address':       address.isNotEmpty
                                  ? address
                                  : [area, pincode].where((s) => s.isNotEmpty).join(', '),
                              'addresses':     addresses,
                              'latitude':      lat,
                              'longitude':     lng,
                              '_type':         accountType,
                            }],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String label, {required Color bg, required Color fg}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
      );

  Widget _actionBtn(Widget icon, Color color, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36, height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: icon,
        ),
      );

  Widget _foot(String label, String value, Color color, {bool end = false}) => Expanded(
        child: Column(
          crossAxisAlignment: end ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade400, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      );

  Widget _stagePill(({String text, Color color}) st) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: st.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(color: st.color, shape: BoxShape.circle)),
            const SizedBox(width: 5),
            Text(st.text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: st.color)),
          ],
        ),
      );

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );


  String _fmtDate(String? iso) {
    if (iso == null || iso.isEmpty || iso == 'null') return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${months[d.month - 1]}';
  }

  Future<void> _pushProfile(Map<String, dynamic> w) async {
    final accountId = '${w['account_id']}';
    await context.push('/telecaller/profile', extra: {
      'account': {
        'id': w['account_id'],
        'account_id': w['account_id'],
        'businessName': w['business_name'] ?? w['name'],
        'name': w['name'],
        'personName': w['person_name'],
        'contactNumber': w['phone'],
        'phone': w['phone'],
        'area': w['area'],
        'city': w['city'],
        'pincode': w['pincode'],
        'customerStage': w['stage'],
        'label': w['label'],
      },
      'accountType': '${w['account_type'] ?? 'lead'}',
      'onCalled':            () => setState(() => _calledToday.add(accountId)),
      'onFollowUpScheduled': (String date) => _onFollowUpScheduled(accountId, date),
    });
    // User navigated back — silently sync to pick up outcome/follow-up changes.
    if (mounted) _backgroundSync();
  }

  Future<void> _openProfile(Map<String, dynamic> w) async {
    final accountId = '${w['account_id']}';
    if (_calledToday.contains(accountId)) {
      final name = '${w['business_name'] ?? w['name'] ?? 'this customer'}'.trim();
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(
            children: const [
              Icon(Icons.check_circle_rounded, color: Color(0xFF2F9E57), size: 22),
              SizedBox(width: 8),
              Text('Already Called', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
          content: Text(
            'You already called $name today. Do you want to call again?',
            style: const TextStyle(fontSize: 14),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey.shade600,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Skip'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _pushProfile(w); // async, fire-and-forget is fine here
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kGold,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Call Again'),
            ),
          ],
        ),
      );
      return;
    }
    _pushProfile(w);
  }
}
