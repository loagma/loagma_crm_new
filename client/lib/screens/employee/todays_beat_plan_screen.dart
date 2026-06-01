import 'package:flutter/material.dart';

class TodaysBeatPlanScreen extends StatefulWidget {
  const TodaysBeatPlanScreen({super.key});

  @override
  State<TodaysBeatPlanScreen> createState() => _TodaysBeatPlanScreenState();
}

class _TodaysBeatPlanScreenState extends State<TodaysBeatPlanScreen> {
  static const _gold = Color(0xFFD7BE69);

  static const _customers = [
    {'code': '00026040073', 'name': 'Elite Kirana Store',      'salesman': 'Siddharth Jain', 'address': 'Chirag Ali Lane',           'area': 'Abids',        'pin': '500001', 'phone': '9848101015', 'day': 'Monday', 'freq': 'WEEKLY'},
    {'code': '00026040069', 'name': 'Ganesh Kirana Emporium',  'salesman': 'Ganesh Ram',      'address': 'Boggulkunta Cross Road',     'area': 'Abids',        'pin': '500001', 'phone': '9848101011', 'day': 'Monday', 'freq': 'WEEKLY'},
    {'code': '00026040064', 'name': 'Metro Kirana Mart',       'salesman': 'Prakash Jha',     'address': 'Jagdish Market Area',        'area': 'Abids',        'pin': '500001', 'phone': '9848101006', 'day': 'Monday', 'freq': 'WEEKLY'},
    {'code': '00026040058', 'name': 'Laxmi General Store',     'salesman': 'Ramesh Kumar',    'address': 'MG Road, Near Bus Stand',    'area': 'Abids',        'pin': '500001', 'phone': '9848101002', 'day': 'Monday', 'freq': 'WEEKLY'},
    {'code': '00026040055', 'name': 'Shri Balaji Provisions',  'salesman': 'Suresh Verma',    'address': 'Sultan Bazar, Shop 12',      'area': 'Sultan Bazar', 'pin': '500095', 'phone': '9848101008', 'day': 'Monday', 'freq': 'BI-WEEKLY'},
    {'code': '00026040051', 'name': 'New India Mart',          'salesman': 'Vijay Singh',     'address': 'Nampally Station Road',      'area': 'Nampally',     'pin': '500001', 'phone': '9848101014', 'day': 'Monday', 'freq': 'WEEKLY'},
    {'code': '00026040047', 'name': 'Hari Om Superstore',      'salesman': 'Deepak Rao',      'address': 'Near Charminar Gate',        'area': 'Charminar',    'pin': '500002', 'phone': '9848101020', 'day': 'Monday', 'freq': 'WEEKLY'},
    {'code': '00026040043', 'name': 'Radha Swami Grocers',     'salesman': 'Ankit Sharma',    'address': 'Laad Bazaar Lane 3',         'area': 'Charminar',    'pin': '500002', 'phone': '9848101033', 'day': 'Monday', 'freq': 'MONTHLY'},
    {'code': '00026040039', 'name': 'Sunrise Daily Needs',     'salesman': 'Kiran Patel',     'address': 'Secunderabad Main Road',     'area': 'Secunderabad', 'pin': '500003', 'phone': '9848101041', 'day': 'Monday', 'freq': 'WEEKLY'},
    {'code': '00026040035', 'name': 'Mahalaxmi Kirana',        'salesman': 'Suman Desai',     'address': 'Old MLA Quarters, Block B',  'area': 'Begumpet',     'pin': '500016', 'phone': '9848101050', 'day': 'Monday', 'freq': 'WEEKLY'},
    {'code': '00026040031', 'name': 'Bharat Super Mart',       'salesman': 'Arun Nair',       'address': 'Himayat Nagar Cross Road',   'area': 'Himayat Nagar','pin': '500029', 'phone': '9848101062', 'day': 'Monday', 'freq': 'WEEKLY'},
    {'code': '00026040027', 'name': 'City Provisions Centre',  'salesman': 'Nilesh Joshi',    'address': 'Ameerpet, Shop 7',           'area': 'Ameerpet',     'pin': '500016', 'phone': '9848101077', 'day': 'Monday', 'freq': 'BI-WEEKLY'},
    {'code': '00026040022', 'name': 'Sai Baba Store',          'salesman': 'Mohan Pillai',    'address': 'SR Nagar, 2nd Lane',         'area': 'SR Nagar',     'pin': '500038', 'phone': '9848101090', 'day': 'Monday', 'freq': 'WEEKLY'},
  ];

  String get _todayLabel {
    final now = DateTime.now();
    const dayNames = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];
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
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: () {}),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
        children: [
          // Summary card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('Today Beat Plan',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text(_todayLabel,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _Chip(label: 'Total Planned: ${_customers.length}', color: const Color(0xFF1976D2)),
                    const SizedBox(width: 8),
                    _Chip(label: 'Shown: ${_customers.length}', color: const Color(0xFF43A047)),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.map_outlined, size: 13),
                      label: const Text('Show in Map', style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.blueGrey,
                        side: BorderSide(color: Colors.blueGrey.shade400),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Customer cards
          ...List.generate(_customers.length, (i) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _CustomerCard(c: _customers[i]),
          )),
        ],
      ),
    );
  }
}

// ── Customer Card ─────────────────────────────────────────────────────────────

class _CustomerCard extends StatelessWidget {
  final Map<String, String> c;
  const _CustomerCard({required this.c});

  static const _gold   = Color(0xFFD7BE69);
  static const _cardBg = Color(0xFFFFF0EE);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFD8D2)),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Code + day/freq chips
          Row(
            children: [
              Text(c['code']!,
                  style: const TextStyle(fontSize: 11, color: Colors.grey, letterSpacing: 0.5)),
              const Spacer(),
              _Tag(label: c['day']!, bg: Colors.grey.shade300, fg: Colors.black54),
              const SizedBox(width: 6),
              _Tag(label: c['freq']!, bg: const Color(0xFFE8F5E9), fg: const Color(0xFF2E7D32)),
            ],
          ),
          const SizedBox(height: 6),
          // Store name + salesman + proceed
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(c['name']!,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(c['salesman']!,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    decoration: BoxDecoration(
                      color: _gold,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Proceed',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Address : ${c['address']}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 2),
          Text('Main area : ${c['area']}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          Text('PIN : ${c['pin']}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          const SizedBox(height: 10),
          // Phone + action buttons
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.phone_rounded, size: 13, color: Colors.grey.shade600),
                    const SizedBox(width: 5),
                    Text(c['phone']!,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const Spacer(),
              _ActionBtn(icon: Icons.visibility_outlined, color: Colors.grey.shade600),
              const SizedBox(width: 6),
              _ActionBtn(icon: Icons.call_rounded,        color: Colors.grey.shade600),
              const SizedBox(width: 6),
              _ActionBtn(icon: Icons.chat_rounded,        color: const Color(0xFF25D366)),
              const SizedBox(width: 6),
              _ActionBtn(icon: Icons.map_rounded,         color: const Color(0xFF1565C0)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color bg, fg;
  const _Tag({required this.label, required this.bg, required this.fg});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: fg)),
      );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _ActionBtn({required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: color),
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
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );
}
