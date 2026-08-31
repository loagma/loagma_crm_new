import 'package:flutter/material.dart';

import '../../widgets/coming_soon_view.dart';

/// Admin → Targets. Placeholder until the targets feature is built.
class AdminTargetScreen extends StatelessWidget {
  const AdminTargetScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonScreen(
      title: 'Targets',
      icon: Icons.flag_rounded,
      message: 'Set monthly goals and track achievement per team member here.',
    );
  }
}
