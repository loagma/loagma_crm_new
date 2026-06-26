import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import '../../services/user_service.dart';
import 'telecaller_actions.dart';
import 'telecaller_mock_data.dart';

/// Telecaller home — restyled to the CRM mockup: greeting, hero stat grid,
/// today's-progress card, follow-ups-due list (taps into the rich profile),
/// quick actions, then live charts under "Insights". Every number is real
/// (`/api/telecaller/dashboard` + `/callbacks`), scoped to the logged-in agent.
class TelecallerDashboardScreen extends StatefulWidget {
  const TelecallerDashboardScreen({super.key});

  @override
  State<TelecallerDashboardScreen> createState() => _TelecallerDashboardScreenState();
}

class _TelecallerDashboardScreenState extends State<TelecallerDashboardScreen> {
  bool _loading = true;
  bool _error = false;
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _callbacks = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    final results = await Future.wait([
      ApiService.getTelecallerDashboard(),
      ApiService.getTelecallerCallbacks(),
    ]);
    if (!mounted) return;
    final data = results[0] as Map<String, dynamic>?;
    setState(() {
      _data = data;
      _callbacks = (results[1] as List).cast<Map<String, dynamic>>();
      _error = data == null;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('Dashboard'),
        backgroundColor: kGold,
        foregroundColor: Colors.white,
        actions: [IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : _error
              ? _errorView()
              : RefreshIndicator(onRefresh: _load, child: _content()),
    );
  }

  Widget _errorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, size: 56, color: Colors.grey.shade300),
          const SizedBox(height: 10),
          Text('Could not load dashboard', style: TextStyle(color: Colors.grey.shade600)),
          const SizedBox(height: 10),
          OutlinedButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _content() {
    final kpis = (_data!['kpis'] as Map?)?.cast<String, dynamic>() ?? {};
    final outcomes = (_data!['outcome_counts'] as Map?)?.cast<String, dynamic>() ?? {};
    final week = (_data!['week'] as Map?)?.cast<String, dynamic>() ?? {};
    final funnel = ((_data!['funnel'] as List?) ?? []).cast<Map<String, dynamic>>();
    final target = (_data!['daily_target'] as num?)?.toInt() ?? 60;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      children: [
        _greeting(),
        const SizedBox(height: 12),
        _heroStats(kpis),
        const SizedBox(height: 12),
        _progressCard(kpis, target),
        const SizedBox(height: 14),
        _followUpsCard(),
        const SizedBox(height: 14),
        _quickActions(),
        const SizedBox(height: 18),
        const _SectionTitle('Insights', Icons.insights_rounded),
        const SizedBox(height: 10),
        _outcomesCard(outcomes),
        const SizedBox(height: 12),
        _weekCard(week),
        const SizedBox(height: 12),
        _funnelCard(funnel),
      ],
    );
  }

  // ── Greeting ────────────────────────────────────────────────────────────────
  Widget _greeting() {
    final name = UserService.currentName ?? 'there';
    final now = DateTime.now();
    final hour = now.hour;
    final part = hour < 12 ? 'Good morning' : hour < 17 ? 'Good afternoon' : 'Good evening';
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$part,', style: TextStyle(fontSize: 12.5, color: Colors.grey.shade500)),
              Text(name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(_dateLine(now), style: TextStyle(fontSize: 11.5, color: Colors.grey.shade400)),
            ],
          ),
        ),
        Container(
          height: 46,
          width: 46,
          decoration: BoxDecoration(color: avatarColorFor(name), borderRadius: BorderRadius.circular(14)),
          alignment: Alignment.center,
          child: Text(initialsOf(name), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
        ),
      ],
    );
  }

  // ── Hero stats ──────────────────────────────────────────────────────────────
  Widget _heroStats(Map<String, dynamic> k) {
    final cards = <({String label, String value, String sub, IconData icon, Color color})>[
      (label: 'Calls today', value: '${k['calls_today'] ?? 0}', sub: 'total dials', icon: Icons.call_rounded, color: const Color(0xFF2F9E57)),
      (label: 'Follow-ups due', value: '${k['follow_ups_due'] ?? 0}', sub: '${k['follow_ups_overdue'] ?? 0} overdue', icon: Icons.event_repeat_rounded, color: const Color(0xFFD98A2B)),
      (label: 'Conversions', value: '${k['conversions'] ?? 0}', sub: 'customers', icon: Icons.verified_rounded, color: const Color(0xFF7C5CD6)),
      (label: 'Connect rate', value: '${k['connect_rate'] ?? 0}%', sub: 'answered', icon: Icons.podcasts_rounded, color: const Color(0xFF3B6FD4)),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 11,
        mainAxisSpacing: 11,
        childAspectRatio: 1.5,
      ),
      itemCount: cards.length,
      itemBuilder: (_, i) {
        final c = cards[i];
        return Container(
          decoration: _cardDeco(),
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 34,
                    width: 34,
                    decoration: BoxDecoration(color: c.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
                    child: Icon(c.icon, size: 18, color: c.color),
                  ),
                  const Spacer(),
                  Text(c.value, style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: c.color)),
                ],
              ),
              const Spacer(),
              Text(c.label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.black87)),
              Text(c.sub, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
            ],
          ),
        );
      },
    );
  }

  // ── Today's progress (calls vs target) ──────────────────────────────────────
  Widget _progressCard(Map<String, dynamic> k, int target) {
    final calls = (k['calls_today'] as num?)?.toInt() ?? 0;
    final progress = target == 0 ? 0.0 : (calls / target).clamp(0.0, 1.0);
    return Container(
      decoration: _cardDeco(),
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text("Today's progress", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const Spacer(),
              Text('Target $target', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade400)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$calls', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: kGoldDark)),
              const SizedBox(width: 6),
              Text('/ $target calls', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.grey.shade200,
              valueColor: const AlwaysStoppedAnimation(kGoldDark),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            calls >= target ? 'Target reached 🎉' : '${target - calls} calls to go',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _miniBox('${k['connect_rate'] ?? 0}%', 'Connect rate'),
              const SizedBox(width: 10),
              _miniBox('${k['conversions'] ?? 0}', 'Conversions'),
              const SizedBox(width: 10),
              _miniBox('${k['follow_ups_due'] ?? 0}', 'Follow-ups'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniBox(String n, String t) => Expanded(
        child: Container(
          decoration: BoxDecoration(color: const Color(0xFFF3F3F5), borderRadius: BorderRadius.circular(13)),
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Column(
            children: [
              Text(n, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const SizedBox(height: 3),
              Text(t, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ],
          ),
        ),
      );

  // ── Follow-ups due today ────────────────────────────────────────────────────
  Widget _followUpsCard() {
    final preview = _callbacks.take(4).toList();
    return Container(
      decoration: _cardDeco(),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Row(
              children: [
                const Text('Follow-ups due today', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                const Spacer(),
                GestureDetector(
                  onTap: () => context.push('/telecaller/callbacks'),
                  child: const Text('View all', style: TextStyle(fontSize: 12, color: kGoldDark, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (preview.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(child: Text('No follow-ups due. Nice work.', style: TextStyle(color: Colors.grey.shade400, fontSize: 12.5))),
            )
          else
            ...preview.map(_callbackRow),
        ],
      ),
    );
  }

  Widget _callbackRow(Map<String, dynamic> c) {
    final overdue = c['overdue'] == true;
    final color = overdue ? const Color(0xFFC0584C) : kGoldDark;
    final name = '${c['name'] ?? 'Unknown'}';
    final stage = '${c['stage'] ?? ''}'.trim();
    final notes = '${c['notes'] ?? ''}'.trim();
    final sub = [if (stage.isNotEmpty) stageStyle(stage).text, if (notes.isNotEmpty) notes].join(' · ');
    return InkWell(
      onTap: () => _openProfile(c),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        child: Row(
          children: [
            Container(
              height: 40,
              width: 40,
              decoration: BoxDecoration(color: avatarColorFor('${c['account_id'] ?? name}'), borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: Text(initialsOf(name), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (sub.isNotEmpty)
                    Text(sub, style: TextStyle(fontSize: 11, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(overdue ? 'Overdue' : 'Today', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: color)),
                Text('${c['follow_up_date'] ?? ''}', style: TextStyle(fontSize: 9.5, color: Colors.grey.shade400)),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.call_rounded, color: Color(0xFF2F9E57)),
              onPressed: () => launchPhoneCall('${c['phone'] ?? ''}'),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  void _openProfile(Map<String, dynamic> c) {
    context.push('/telecaller/profile', extra: {
      'account': {
        'id': c['account_id'],
        'account_id': c['account_id'],
        'businessName': c['name'],
        'name': c['name'],
        'contactNumber': c['phone'],
        'phone': c['phone'],
        'area': c['area'],
        'customerStage': c['stage'],
      },
      'accountType': '${c['account_type'] ?? 'lead'}',
    });
  }

  // ── Quick actions (route to existing screens) ───────────────────────────────
  Widget _quickActions() {
    final actions = <({String label, IconData icon, Color color, String route})>[
      (label: 'Today Worklist', icon: Icons.checklist_rounded, color: kGoldDark, route: '/telecaller/worklist'),
      (label: "Today's Callbacks", icon: Icons.event_repeat_rounded, color: const Color(0xFFD98A2B), route: '/telecaller/callbacks'),
      (label: 'Create Lead', icon: Icons.person_add_alt_1_rounded, color: const Color(0xFF3B6FD4), route: '/lead-account'),
      (label: 'Verify Accounts', icon: Icons.verified_user_rounded, color: const Color(0xFF2F9E57), route: '/verify-lead-accounts'),
      (label: 'Customers', icon: Icons.assignment_ind_rounded, color: const Color(0xFF7C5CD6), route: '/allotted-customer-accounts'),
      (label: 'Call History', icon: Icons.history_rounded, color: const Color(0xFF5A6472), route: '/telecaller/call-history'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 2, bottom: 10),
          child: Text('Quick actions', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 11,
            mainAxisSpacing: 11,
            childAspectRatio: 2.7,
          ),
          itemCount: actions.length,
          itemBuilder: (_, i) {
            final a = actions[i];
            return GestureDetector(
              onTap: () => context.push(a.route),
              child: Container(
                decoration: _cardDeco(),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Container(
                      height: 36,
                      width: 36,
                      decoration: BoxDecoration(color: a.color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(11)),
                      child: Icon(a.icon, size: 19, color: a.color),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(a.label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87)),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ── Charts (Insights) ───────────────────────────────────────────────────────
  Widget _outcomesCard(Map<String, dynamic> outcomes) {
    final entries = outcomes.entries.map((e) => MapEntry(e.key, (e.value as num?)?.toInt() ?? 0)).toList();
    final total = entries.fold<int>(0, (a, b) => a + b.value);
    return Container(
      decoration: _cardDeco(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Call Outcomes (today)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 10),
          if (total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('No calls logged today', style: TextStyle(color: Colors.grey.shade500))),
            )
          else
            Row(
              children: [
                SizedBox(
                  height: 130,
                  width: 130,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 38,
                        sections: [
                          for (final e in entries.where((e) => e.value > 0))
                            PieChartSectionData(
                              value: e.value.toDouble(),
                              color: kOutcomeColors[e.key],
                              radius: 24,
                              showTitle: false,
                            ),
                        ],
                      )),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$total', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                          Text('calls', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in entries.where((e) => e.value > 0))
                        _legendRow(kOutcomeColors[e.key] ?? Colors.grey, kOutcomeLabels[e.key] ?? e.key, e.value),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _legendRow(Color color, String label, int value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12))),
          Text('$value', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _weekCard(Map<String, dynamic> week) {
    final days = ((week['days'] as List?) ?? []).map((e) => e.toString()).toList();
    final calls = ((week['calls'] as List?) ?? []).map((e) => (e as num?)?.toInt() ?? 0).toList();
    final maxRaw = calls.isEmpty ? 0 : calls.reduce((a, b) => a > b ? a : b);
    final maxY = (maxRaw == 0 ? 5 : maxRaw * 1.2).ceilToDouble();
    return Container(
      decoration: _cardDeco(),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Calls This Week', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: BarChart(BarChartData(
              maxY: maxY,
              borderData: FlBorderData(show: false),
              gridData: const FlGridData(show: true, drawVerticalLine: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= days.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(days[i], style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < calls.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: calls[i].toDouble(),
                      color: kGoldDark,
                      width: 16,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  ]),
              ],
            )),
          ),
        ],
      ),
    );
  }

  Widget _funnelCard(List<Map<String, dynamic>> funnel) {
    final colors = [const Color(0xFF3B6FD4), const Color(0xFF26A69A), const Color(0xFFD98A2B), const Color(0xFF2F9E57)];
    final maxV = funnel.isEmpty ? 1 : (funnel.first['value'] as num?)?.toInt() ?? 1;
    final denom = maxV == 0 ? 1 : maxV;
    return Container(
      decoration: _cardDeco(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Conversion Funnel', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 12),
          for (var i = 0; i < funnel.length; i++) ...[
            Row(
              children: [
                SizedBox(width: 92, child: Text('${funnel[i]['label'] ?? ''}', style: const TextStyle(fontSize: 12))),
                Expanded(
                  child: LayoutBuilder(builder: (_, c) {
                    final v = (funnel[i]['value'] as num?)?.toInt() ?? 0;
                    return Stack(
                      children: [
                        Container(height: 22, decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6))),
                        Container(
                          height: 22,
                          width: c.maxWidth * (v / denom).clamp(0.0, 1.0),
                          decoration: BoxDecoration(color: colors[i % colors.length], borderRadius: BorderRadius.circular(6)),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 8),
                          child: Text('$v', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
                        ),
                      ],
                    );
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  // ── helpers ─────────────────────────────────────────────────────────────────
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String _dateLine(DateTime d) => '${_weekdays[d.weekday - 1]} · ${d.day} ${_months[d.month - 1]} ${d.year}';
}

// ── shared bits ───────────────────────────────────────────────────────────────
BoxDecoration _cardDeco() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFEEEEEE)),
      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 3))],
    );

class _SectionTitle extends StatelessWidget {
  final String text;
  final IconData icon;
  const _SectionTitle(this.text, this.icon);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: kGoldDark),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.black87)),
      ],
    );
  }
}
