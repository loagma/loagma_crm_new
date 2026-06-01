import 'package:flutter/material.dart';

class AllBeatPlanScreen extends StatefulWidget {
  const AllBeatPlanScreen({super.key});

  @override
  State<AllBeatPlanScreen> createState() => _AllBeatPlanScreenState();
}

class _AllBeatPlanScreenState extends State<AllBeatPlanScreen> {
  static const _gold = Color(0xFFD7BE69);

  static const _days = [
    {'day': 'Mon', 'date': '01/06/2026', 'status': 'Planned', 'accounts': 13},
    {'day': 'Tue', 'date': '02/06/2026', 'status': 'Planned', 'accounts': 21},
    {'day': 'Wed', 'date': '03/06/2026', 'status': 'Planned', 'accounts': 14},
    {'day': 'Thu', 'date': '04/06/2026', 'status': 'Planned', 'accounts': 17},
    {'day': 'Fri', 'date': '05/06/2026', 'status': 'Planned', 'accounts': 13},
    {'day': 'Sat', 'date': '06/06/2026', 'status': 'Planned', 'accounts': 12},
    {'day': 'Sun', 'date': '07/06/2026', 'status': 'Planned', 'accounts': 22},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('All Beat Plan'),
        backgroundColor: _gold,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () {}),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // Summary card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEEEEEE)),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text('All Beat Plan',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ),
                      Text('01/06/2026 – 07/06/2026',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Flexible(child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: const [
                          _Chip(label: 'Total: 49',    color: _gold),
                          _Chip(label: 'Planned: 47',  color: Color(0xFF43A047)),
                          _Chip(label: 'Remaining: 2', color: Color(0xFFEF5350)),
                        ],
                      )),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.map_outlined, size: 13),
                        label: const Text('Show All in Map', style: TextStyle(fontSize: 10)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blueGrey,
                          side: BorderSide(color: Colors.blueGrey.shade400),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Day grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.4,
              ),
              itemCount: _days.length,
              itemBuilder: (_, i) {
                final d = _days[i];
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFEEEEEE)),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(d['day'] as String,
                          style: const TextStyle(
                              fontSize: 20, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(d['date'] as String,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                      const Spacer(),
                      Text(d['status'] as String,
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF43A047),
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text('Accounts: ${d['accounts']}',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500)),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      );
}
