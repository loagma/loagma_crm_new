import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/api_service.dart';
import '../../services/open_visit_store.dart';
import '../../widgets/account_map_screen.dart';
import '../telecaller/telecaller_mock_data.dart'
    show stageStyle, priorityForStage;

class TodaysBeatPlanScreen extends StatefulWidget {
  const TodaysBeatPlanScreen({super.key});

  @override
  State<TodaysBeatPlanScreen> createState() => _TodaysBeatPlanScreenState();
}

class _TodaysBeatPlanScreenState extends State<TodaysBeatPlanScreen> {
  static const _gold = Color(0xFFD7BE69);

  bool _loading = true;
  String _error = '';
  int _total = 0;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final res = await ApiService.getTodayBeatPlan();
      if (!mounted) return;
      if (res['success'] == true) {
        final raw = res['data'];
        final items = raw is List
            ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
            : <Map<String, dynamic>>[];
        setState(() {
          _items = items;
          _total = (res['total'] as int?) ?? items.length;
          _loading = false;
        });
      } else {
        setState(() {
          _loading = false;
          _error = 'Failed to load beat plan.';
        });
      }
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = 'Error loading beat plan.';
        });
    }
  }

  String get _todayLabel {
    final now = DateTime.now();
    const dayNames = [
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
    ];
    final d = now.day.toString().padLeft(2, '0');
    final m = now.month.toString().padLeft(2, '0');
    return '${dayNames[now.weekday % 7]} | $d/$m/${now.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('My Beat Plan'),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _gold))
          : _error.isNotEmpty
          ? Center(
              child: Text(_error, style: const TextStyle(color: Colors.red)),
            )
          : RefreshIndicator(
              onRefresh: _load,
              color: _gold,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                children: [
                  // Summary card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 6,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              'Today Beat Plan',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _todayLabel,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _Chip(
                              label: 'Total Planned: $_total',
                              color: const Color(0xFF1976D2),
                            ),
                            const SizedBox(width: 8),
                            _Chip(
                              label: 'Shown: ${_items.length}',
                              color: const Color(0xFF43A047),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: _items.isEmpty
                                  ? null
                                  : () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AccountMapScreen(
                                          title: "Today's Beat Plan — Map",
                                          accounts: _items.map((item) {
                                            final acc =
                                                Map<String, dynamic>.from(
                                                  item['account'] as Map? ?? {},
                                                );
                                            acc['_type'] =
                                                item['account_type'] ?? 'lead';
                                            return acc;
                                          }).toList(),
                                        ),
                                      ),
                                    ),
                              icon: const Icon(Icons.map_outlined, size: 13),
                              label: const Text(
                                'Show in Map',
                                style: TextStyle(fontSize: 11),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blueGrey,
                                side: BorderSide(
                                  color: Colors.blueGrey.shade400,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (_items.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 40),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.today_outlined,
                              size: 72,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 14),
                            Text(
                              'No accounts scheduled for today',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...List.generate(
                      _items.length,
                      (i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _CustomerCard(
                          item: _items[i],
                          todaysItems: _items,
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

// ── Customer card ─────────────────────────────────────────────────────────────

class _CustomerCard extends StatelessWidget {
  final Map<String, dynamic> item;
  // Every other account on today's beat plan — used only to find and jump
  // straight to the account that has an open visit, when this card is
  // blocked from starting a new one (see _openAccount below).
  final List<Map<String, dynamic>> todaysItems;
  const _CustomerCard({required this.item, required this.todaysItems});

  static const _gold = Color(0xFFD7BE69);
  static const _cardBg = Color(0xFFFFF0EE);

  Map<String, dynamic> get _account =>
      (item['account'] as Map<String, dynamic>?) ?? {};

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Map<String, dynamic> _extraFor(
    Map<String, dynamic> acc,
    Map<String, dynamic> forItem,
    String accountType,
  ) => {
    ...acc,
    'account_type': accountType,
    'beat_plan_id': forItem['beat_plan_id'],
    'frequency': forItem['frequency'],
    'days': forItem['days'],
    'month_date': forItem['month_date'],
    'interval_days': forItem['interval_days'],
  };

  // A salesman can only be mid-visit at one customer at a time. Block
  // opening a different account while another one still has an open visit,
  // and offer a straight jump to it instead of leaving them to hunt for it
  // in the list.
  Future<void> _openAccount(
    BuildContext context,
    Map<String, dynamic> acc,
    String accountType,
  ) async {
    final myId = '${acc['id'] ?? ''}';
    final other = await OpenVisitStore.findOtherOpen(myId);
    if (!context.mounted) return;

    if (other != null) {
      final otherItem = todaysItems.firstWhere(
        (it) => '${(it['account'] as Map?)?['id'] ?? ''}' == other.accountId,
        orElse: () => <String, dynamic>{},
      );
      final label = other.accountName?.isNotEmpty == true
          ? other.accountName!
          : (otherItem['account'] as Map?)?['businessName'] as String? ??
                'another customer';
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: const Text(
            'Visit already in progress',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          content: Text(
            'You have an open visit at $label. Visit Out there before starting a new visit.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK', style: TextStyle(color: Colors.grey)),
            ),
            if (otherItem.isNotEmpty)
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  final otherAcc =
                      (otherItem['account'] as Map<String, dynamic>?) ?? {};
                  final otherType =
                      otherItem['account_type'] as String? ?? 'lead';
                  context.push(
                    '/order-funnel/${other.accountId}',
                    extra: _extraFor(otherAcc, otherItem, otherType),
                  );
                },
                child: const Text('Go There'),
              ),
          ],
        ),
      );
      return;
    }

    context.push(
      '/order-funnel/$myId',
      extra: _extraFor(acc, item, accountType),
    );
  }

  String _freqLabel(String freq, List<dynamic>? days) {
    switch (freq) {
      case 'weekly':
        final d = days?.cast<dynamic>() ?? [];
        final alt = item['week_anchor_date'] != null ? ' (ALT)' : '';
        return d.isEmpty ? 'WEEKLY$alt' : '${d.join(', ').toUpperCase()}$alt';
      case 'monthly':
        final md = item['month_date'];
        return md == null ? 'MONTHLY' : 'DAY $md / MONTH';
      case 'specific_dates':
        final dates = (item['specific_dates'] as List?)?.cast<String>() ?? [];
        return dates.isEmpty
            ? 'SPECIFIC DATES'
            : 'SPECIFIC: ${dates.length} DATES';
      case 'appointment':
        final apt = item['appointment_date'] as String?;
        if (apt == null) return 'APPOINTMENT';
        try {
          final dt = DateTime.parse(apt);
          return 'APPT: ${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
        } catch (e) {
          return 'APPOINTMENT';
        }
      case 'n_days':
        final n = item['interval_days'];
        return n == null ? 'RECURRING' : 'EVERY $n DAYS';
      default:
        return freq.toUpperCase();
    }
  }

  Widget _stagePill(({String text, Color color}) st) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: st.color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: st.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          st.text,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: st.color,
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final acc = _account;
    final code = acc['accountCode'] as String? ?? '';
    final accountType = item['account_type'] as String? ?? 'lead';
    // "Customer id" (user_id) only makes sense for a customer account — a
    // lead has no user_id, just its own record id, so the code line there
    // stays code-only instead of appending a meaningless "ID: <uuid>".
    final id = '${acc['id'] ?? ''}';
    final codeLine = accountType == 'customer'
        ? [if (code.isNotEmpty) code, if (id.isNotEmpty) 'ID: $id'].join(' · ')
        : code;
    final name = acc['businessName'] as String? ?? '—';
    final person = acc['personName'] as String? ?? '';
    final phone = acc['contactNumber'] as String? ?? '';
    final address = acc['address'] as String? ?? '';
    final addresses = ((acc['addresses'] as List?) ?? [])
        .map((a) => (a is Map ? a['address'] : a)?.toString() ?? '')
        .where((a) => a.isNotEmpty)
        .toList();
    final area = acc['area'] as String? ?? '';
    final pin = acc['pincode'] as String? ?? '';
    final freq = item['frequency'] as String? ?? 'weekly';
    final days = item['days'] as List?;
    final visited = item['visited_today'] == true;
    final stage = acc['customerStage'] as String? ?? accountType;
    final st = stageStyle(stage);
    final prio = priorityForStage(stage);

    // The card body itself is inert — only the explicit Proceed button (and
    // the other action buttons, e.g. the eye/view icon below) navigate. It
    // used to also open the lead/account detail page on any tap, a second,
    // different destination from Proceed's order-funnel screen that was easy
    // to trigger by accident and made Proceed feel redundant.
    return Container(
      decoration: BoxDecoration(
        color: visited ? const Color(0xFFF0FFF4) : _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: visited ? const Color(0xFFC8E6C9) : const Color(0xFFFFD8D2),
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Code + freq chip + account type
          // A long freq label (e.g. a weekly plan with several days
          // selected, "MON, TUE, WED, THU, FRI (ALT)") plus the account-type
          // tag used to overflow a plain Row with no flexible child — on
          // narrower phones/web widths this threw a RenderFlex overflow.
          // Flexible + Wrap lets the tags wrap to a second line instead.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Text(
                  codeLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.grey,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _Tag(
                      label: accountType.toUpperCase(),
                      bg: accountType == 'customer'
                          ? const Color(0xFFE3F2FD)
                          : const Color(0xFFFFF3E0),
                      fg: accountType == 'customer'
                          ? const Color(0xFF1976D2)
                          : const Color(0xFFF57C00),
                    ),
                    if (visited)
                      _Tag(
                        label: '✓ Visited',
                        bg: const Color(0xFFE8F5E9),
                        fg: const Color(0xFF2E7D32),
                      )
                    else
                      _Tag(
                        label: _freqLabel(freq, days),
                        bg: const Color(0xFFE8F5E9),
                        fg: const Color(0xFF2E7D32),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Name + salesman + proceed
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (person.isNotEmpty)
                    Text(
                      person,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  const SizedBox(height: 6),
                  if (!visited)
                    GestureDetector(
                      onTap: () => _openAccount(context, acc, accountType),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: _gold,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Proceed',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              _stagePill(st),
              _Tag(
                label: prio.text,
                bg: prio.color.withValues(alpha: 0.12),
                fg: prio.color,
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (addresses.length > 1)
            ...addresses.asMap().entries.map(
              (e) => Text(
                'Address ${e.key + 1} : ${e.value}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            )
          else if (address.isNotEmpty)
            Text(
              'Address : $address',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          if (area.isNotEmpty)
            Text(
              'Main area : $area',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          if (pin.isNotEmpty)
            Text(
              'PIN : $pin',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          const SizedBox(height: 10),
          // Phone + actions
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.phone_rounded,
                      size: 13,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      phone,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _ActionBtn(
                icon: Icons.visibility_outlined,
                color: Colors.grey.shade600,
                onTap: () {
                  final id = '${acc['id'] ?? ''}';
                  if (id.isNotEmpty) {
                    context.push('/lead-accounts/$id', extra: acc);
                  }
                },
              ),
              const SizedBox(width: 6),
              _ActionBtn(
                icon: Icons.call_rounded,
                color: Colors.grey.shade600,
                onTap: phone.isNotEmpty ? () => _launch('tel:$phone') : null,
              ),
              const SizedBox(width: 6),
              _ActionBtn(
                color: const Color(0xFF25D366),
                onTap: phone.isNotEmpty
                    ? () {
                        final d = phone.replaceAll(RegExp(r'\D'), '');
                        final n = d.length == 10 ? '91$d' : d;
                        _launch('https://wa.me/$n');
                      }
                    : null,
                child: const FaIcon(
                  FontAwesomeIcons.whatsapp,
                  size: 18,
                  color: Color(0xFF25D366),
                ),
              ),
              const SizedBox(width: 6),
              _ActionBtn(
                icon: Icons.map_rounded,
                color: const Color(0xFF1565C0),
                onTap: (acc['latitude'] != null && acc['longitude'] != null)
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AccountMapScreen(
                            title: name,
                            accounts: [
                              {...acc, '_type': accountType},
                            ],
                          ),
                        ),
                      )
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Small helpers ─────────────────────────────────────────────────────────────

class _Tag extends StatelessWidget {
  final String label;
  final Color bg, fg;
  const _Tag({required this.label, required this.bg, required this.fg});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg),
    ),
  );
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withValues(alpha: 0.30)),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

class _ActionBtn extends StatelessWidget {
  final IconData? icon;
  final Widget? child;
  final Color color;
  final VoidCallback? onTap;
  const _ActionBtn({this.icon, this.child, required this.color, this.onTap})
    : assert(icon != null || child != null);
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: child ?? Icon(icon, size: 18, color: color),
    ),
  );
}
