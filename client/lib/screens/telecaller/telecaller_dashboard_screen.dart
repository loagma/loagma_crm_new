import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import 'telecaller_actions.dart';
import 'telecaller_mock_data.dart';

/// Live telecaller dashboard. Five sections: KPI cards · today's callbacks ·
/// charts · alerts · quick actions. All numbers come from the backend
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
        title: const Text('Live Dashboard'),
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
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
      children: [
        const _SectionTitle('Today at a glance', Icons.dashboard_rounded),
        const SizedBox(height: 10),
        _kpiGrid(kpis),
        const SizedBox(height: 22),
        _callbacksSection(),
        const SizedBox(height: 22),
        const _SectionTitle('Charts', Icons.insights_rounded),
        const SizedBox(height: 10),
        _outcomesCard(outcomes),
        const SizedBox(height: 12),
        _weekCard(week),
        const SizedBox(height: 12),
        _funnelCard(funnel),
        const SizedBox(height: 22),
        const _SectionTitle('Alerts', Icons.notifications_active_rounded),
        const SizedBox(height: 10),
        _alertsCard(kpis, target),
        const SizedBox(height: 22),
        const _SectionTitle('Quick Actions', Icons.bolt_rounded),
        const SizedBox(height: 10),
        _quickActions(context),
      ],
    );
  }

  // ── KPI cards ──────────────────────────────────────────────────────────────
  Widget _kpiGrid(Map<String, dynamic> k) {
    final cards = <({String label, String value, String sub, IconData icon, Color color})>[
      (label: 'Calls Today', value: '${k['calls_today'] ?? 0}', sub: 'total dials', icon: Icons.call_rounded, color: const Color(0xFF1E88E5)),
      (label: 'Connect Rate', value: '${k['connect_rate'] ?? 0}%', sub: 'answered', icon: Icons.podcasts_rounded, color: const Color(0xFF43A047)),
      (label: 'Conversions', value: '${k['conversions'] ?? 0}', sub: 'customers', icon: Icons.verified_rounded, color: kGoldDark),
      (label: 'Follow-ups Due', value: '${k['follow_ups_due'] ?? 0}', sub: '${k['follow_ups_overdue'] ?? 0} overdue', icon: Icons.event_repeat_rounded, color: const Color(0xFFFB8C00)),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 1.55,
      ),
      itemCount: cards.length,
      itemBuilder: (_, i) {
        final c = cards[i];
        return Container(
          decoration: _cardDeco(),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    height: 34, width: 34,
                    decoration: BoxDecoration(color: c.color.withValues(alpha: 0.14), shape: BoxShape.circle),
                    child: Icon(c.icon, size: 18, color: c.color),
                  ),
                  const Spacer(),
                  Text(c.value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: c.color)),
                ],
              ),
              const SizedBox(height: 8),
              Text(c.label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.black87)),
              Text(c.sub, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500)),
            ],
          ),
        );
      },
    );
  }

  // ── Today's callbacks (preview) ────────────────────────────────────────────
  Widget _callbacksSection() {
    final preview = _callbacks.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const _SectionTitle("Today's Callbacks", Icons.event_repeat_rounded),
            const Spacer(),
            TextButton(
              onPressed: () => context.push('/telecaller/callbacks'),
              child: const Text('View all', style: TextStyle(color: kGoldDark, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        if (preview.isEmpty)
          Container(
            decoration: _cardDeco(),
            padding: const EdgeInsets.all(16),
            child: Text('No callbacks scheduled', style: TextStyle(color: Colors.grey.shade500)),
          )
        else
          ...preview.map(_callbackRow),
      ],
    );
  }

  Widget _callbackRow(Map<String, dynamic> c) {
    final overdue = c['overdue'] == true;
    final color = overdue ? const Color(0xFFE53935) : kGoldDark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: _cardDeco(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Text('${c['follow_up_date'] ?? ''}',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: color)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${c['name'] ?? 'Unknown'}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Text('${c['area'] ?? ''}${(c['stage'] ?? '').toString().isNotEmpty ? ' · ${c['stage']}' : ''}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
              ],
            ),
          ),
          if (overdue)
            const Padding(
              padding: EdgeInsets.only(right: 6),
              child: Text('OVERDUE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Color(0xFFE53935))),
            ),
          IconButton(
            icon: const Icon(Icons.call_rounded, color: Color(0xFF43A047)),
            onPressed: () => launchPhoneCall('${c['phone'] ?? ''}'),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  // ── Charts ─────────────────────────────────────────────────────────────────
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
                  height: 130, width: 130,
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
    final colors = [const Color(0xFF1E88E5), const Color(0xFF26A69A), const Color(0xFFFB8C00), const Color(0xFF43A047)];
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

  // ── Alerts ─────────────────────────────────────────────────────────────────
  Widget _alertsCard(Map<String, dynamic> k, int target) {
    final overdue = (k['follow_ups_overdue'] as num?)?.toInt() ?? 0;
    final callsToday = (k['calls_today'] as num?)?.toInt() ?? 0;
    final progress = target == 0 ? 0.0 : (callsToday / target).clamp(0.0, 1.0);
    return Column(
      children: [
        Container(
          decoration: _cardDeco(),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                height: 38, width: 38,
                decoration: BoxDecoration(
                  color: (overdue > 0 ? const Color(0xFFE53935) : const Color(0xFF43A047)).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(overdue > 0 ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                    color: overdue > 0 ? const Color(0xFFE53935) : const Color(0xFF43A047), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  overdue > 0 ? '$overdue follow-up${overdue == 1 ? '' : 's'} overdue' : 'No overdue follow-ups',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              if (overdue > 0)
                TextButton(
                  onPressed: () => context.push('/telecaller/callbacks'),
                  child: const Text('View', style: TextStyle(color: kGoldDark, fontWeight: FontWeight.w700)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: _cardDeco(),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text("Today's Target", style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('$callsToday / $target calls', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
              const SizedBox(height: 8),
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
                callsToday >= target ? 'Target reached 🎉' : '${target - callsToday} calls to go',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Quick actions (route to EXISTING screens) ──────────────────────────────
  Widget _quickActions(BuildContext context) {
    final actions = <({String label, IconData icon, Color color, String route})>[
      (label: 'Create Lead', icon: Icons.person_add_alt_1_rounded, color: const Color(0xFF42A5F5), route: '/lead-account'),
      (label: 'Verify Accounts', icon: Icons.verified_user_rounded, color: const Color(0xFF66BB6A), route: '/verify-lead-accounts'),
      (label: 'My Area', icon: Icons.location_on_rounded, color: const Color(0xFF8C219D), route: '/my-areas'),
      (label: 'Customers', icon: Icons.assignment_ind_rounded, color: const Color(0xFF26A69A), route: '/allotted-customer-accounts'),
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 2.6,
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
                  height: 36, width: 36,
                  decoration: BoxDecoration(color: a.color.withValues(alpha: 0.14), shape: BoxShape.circle),
                  child: Icon(a.icon, size: 19, color: a.color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(a.label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.black87)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
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
