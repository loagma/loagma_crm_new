import 'package:flutter/material.dart';

import '../../widgets/coming_soon_view.dart';

/// Salesman → Incharge Profile. Placeholder until the feature is built.
class InchargeProfileScreen extends StatelessWidget {
  const InchargeProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ComingSoonScreen(
      title: 'Incharge Profile',
      icon: Icons.badge_rounded,
      message: 'Your reporting incharge details and contact info will appear here.',
    );
  }
}
