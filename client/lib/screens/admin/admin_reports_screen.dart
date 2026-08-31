import 'package:flutter/material.dart';

import '../../widgets/coming_soon_view.dart';

/// Admin → Reports. Placeholder until the reporting feature is built.
class AdminReportsScreen extends StatelessWidget {
  const AdminReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonScreen(
      title: 'Reports',
      icon: Icons.bar_chart_rounded,
      message: 'Sales, calls, attendance and lead reports will appear here.',
    );
  }
}
