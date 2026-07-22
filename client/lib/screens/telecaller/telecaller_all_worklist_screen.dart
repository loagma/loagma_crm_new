import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import 'telecaller_mock_data.dart';

/// All Worklist — current-week (Mon–Sun) overview. Shows one tile per
/// weekday with that day's account count; tapping a tile opens
/// `TelecallerWorklistDayScreen` for that specific date. Mirrors the
/// day-grid → day-detail navigation `AllBeatPlanScreen`/`BeatPlanDayScreen`
/// already use for the employee/salesman beat plan.
class TelecallerAllWorklistScreen extends StatefulWidget {
  const TelecallerAllWorklistScreen({super.key});

  @override
  State<TelecallerAllWorklistScreen> createState() => _TelecallerAllWorklistScreenState();
}

class _TelecallerAllWorklistScreenState extends State<TelecallerAllWorklistScreen> {
  static const _dayKeys   = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  static const _dayLabels = {'mon': 'Mon', 'tue': 'Tue', 'wed': 'Wed', 'thu': 'Thu', 'fri': 'Fri', 'sat': 'Sat', 'sun': 'Sun'};

  bool _loading = true;
  Map<String, DateTime> _weekDates = {};
  Map<String, int> _dayCounts = {};
  int _weekTotal = 0; // unique accounts across the whole week

  // 0 = current week, -1 = previous week, +1 = next week, etc.
  int _weekOffset = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, DateTime> _currentWeekDates() {
    final now    = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1))
        .add(Duration(days: 7 * _weekOffset));
    return {for (var i = 0; i < _dayKeys.length; i++) _dayKeys[i]: monday.add(Duration(days: i))};
  }

  void _changeWeek(int delta) {
    setState(() => _weekOffset += delta);
    _load();
  }

  // Jump straight to the week containing `picked`, instead of stepping
  // through `_changeWeek` one week at a time.
  void _goToDate(DateTime picked) {
    final now         = DateTime.now();
    final todayMonday  = DateTime(now.year, now.month, now.day).subtract(Duration(days: now.weekday - 1));
    final pickedMonday = DateTime(picked.year, picked.month, picked.day).subtract(Duration(days: picked.weekday - 1));
    final weeks = pickedMonday.difference(todayMonday).inDays ~/ 7;

    setState(() => _weekOffset = weeks);
    _load();
  }

  Future<void> _pickFromCalendar() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _weekDates[_dayKeys[now.weekday - 1]] ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
      helpText: 'Go to date',
    );
    if (picked != null) _goToDate(picked);
  }

  // Parses an 8-digit DDMMYYYY string (e.g. "07062016" → 7 June 2016).
  // Returns null for anything that isn't a real calendar date.
  DateTime? _parseDdMmYyyy(String digits) {
    if (digits.length != 8) return null;
    final day   = int.tryParse(digits.substring(0, 2));
    final month = int.tryParse(digits.substring(2, 4));
    final year  = int.tryParse(digits.substring(4, 8));
    if (day == null || month == null || year == null) return null;
    if (month < 1 || month > 12) return null;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    if (day < 1 || day > daysInMonth) return null;
    return DateTime(year, month, day);
  }

  // "Go to date" — type DDMMYYYY directly, or fall back to the native
  // calendar picker if that's easier.
  Future<void> _goToDateDialog() async {
    final ctrl = TextEditingController();
    String? error;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Go to date', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(8),
                ],
                decoration: InputDecoration(
                  hintText: 'DDMMYYYY',
                  errorText: error,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (error != null) setDialogState(() => error = null);
                },
              ),
              const SizedBox(height: 6),
              Text('e.g. 07062016 = 7 June 2016', style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500)),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _pickFromCalendar();
                },
                icon: const Icon(Icons.calendar_month_rounded, size: 16),
                label: const Text('Pick from calendar', style: TextStyle(fontSize: 12.5)),
              ),
            ],
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancel', style: TextStyle(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: () {
                final parsed = _parseDdMmYyyy(ctrl.text.trim());
                if (parsed == null) {
                  setDialogState(() => error = 'Enter a valid date as DDMMYYYY');
                  return;
                }
                Navigator.of(ctx).pop();
                _goToDate(parsed);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kGold,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Go'),
            ),
          ],
        ),
      ),
    );
  }

  String get _weekLabel => switch (_weekOffset) {
        0 => 'This week',
        -1 => 'Last week',
        1 => 'Next week',
        < 0 => '${-_weekOffset} weeks ago',
        _ => 'In $_weekOffset weeks',
      };

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _loading = true);
    final weekDates = _currentWeekDates();
    final results = await Future.wait(
      _dayKeys.map((k) => ApiService.getWeekBeatPlan(date: _isoDate(weekDates[k]!))),
    );
    if (!mounted) return;

    final dayCounts   = <String, int>{};
    final uniqueIds   = <String>{};
    for (var i = 0; i < _dayKeys.length; i++) {
      final res = results[i];
      final raw = res['data'];
      var count = 0;
      if (res['success'] == true && raw is List) {
        for (final t in raw) {
          if (t is! Map) continue;
          final acc = t['account'];
          if (acc is! Map || acc['id'] == null) continue;
          uniqueIds.add('${acc['id']}');
          count++;
        }
      }
      dayCounts[_dayKeys[i]] = count;
    }

    setState(() {
      _weekDates  = weekDates;
      _dayCounts  = dayCounts;
      _weekTotal  = uniqueIds.length;
      _loading    = false;
    });
  }

  String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final todayKey = _dayKeys[DateTime.now().weekday - 1];
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text('All Worklist', style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: kGold,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.calendar_month_rounded), tooltip: 'Go to date', onPressed: _goToDateDialog),
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kGold))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  // Week switcher — Previous / label / Next
                  Row(
                    children: [
                      _weekNavBtn(Icons.chevron_left_rounded, () => _changeWeek(-1)),
                      Expanded(
                        child: Column(
                          children: [
                            Text(_weekLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                            if (_weekDates.isNotEmpty)
                              Text(
                                '${_formatDate(_weekDates['mon']!)} – ${_formatDate(_weekDates['sun']!)}',
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                              ),
                            if (_weekOffset != 0) ...[
                              const SizedBox(height: 5),
                              GestureDetector(
                                onTap: () {
                                  setState(() => _weekOffset = 0);
                                  _load();
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: kGold.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: const [
                                      Icon(Icons.today_rounded, size: 12, color: kGoldDark),
                                      SizedBox(width: 4),
                                      Text('Today', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: kGoldDark)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      _weekNavBtn(Icons.chevron_right_rounded, () => _changeWeek(1)),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Summary card
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFEEEEEE)),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text('Accounts scheduled this week',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: kGold.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text('$_weekTotal accounts',
                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: kGoldDark)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Day grid — tap opens that day's worklist
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.4,
                    ),
                    itemCount: _dayKeys.length,
                    itemBuilder: (_, i) {
                      final key   = _dayKeys[i];
                      final date  = _weekDates[key];
                      final count = _dayCounts[key] ?? 0;
                      final isToday = _weekOffset == 0 && key == todayKey;
                      return GestureDetector(
                        onTap: date == null
                            ? null
                            : () => context.push(
                                '/telecaller/worklist/day?date=${_isoDate(date)}&label=${_dayLabels[key]}',
                              ),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: isToday ? kGold : const Color(0xFFEEEEEE), width: isToday ? 1.6 : 1),
                            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Text(_dayLabels[key] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                                if (isToday) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                    decoration: BoxDecoration(color: kGold.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                                    child: const Text('Today', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: kGoldDark)),
                                  ),
                                ],
                              ]),
                              const SizedBox(height: 2),
                              Text(date == null ? '' : _formatDate(date), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                              const Spacer(),
                              Text(
                                count > 0 ? 'Scheduled' : 'No accounts',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: count > 0 ? const Color(0xFF43A047) : Colors.grey,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text('Accounts: $count', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _weekNavBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36, height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: const Color(0xFFEEEEEE)),
            boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Icon(icon, color: kGoldDark, size: 22),
        ),
      );
}
