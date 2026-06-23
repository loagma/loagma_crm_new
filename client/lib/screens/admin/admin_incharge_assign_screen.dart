import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'incharge_levels.dart';

/// Entry screen for the admin "Incharge Assign" flow.
///
/// Lets the admin pick which rung of the hierarchy to manage:
///   • Head Incharge  → assign Zonal Incharges
///   • Zonal Incharge → assign Area Incharges + Teleadmins
///   • Area Incharge  → assign Salesmen
///   • Teleadmin      → assign Telecallers
class AdminInchargeAssignScreen extends StatelessWidget {
  const AdminInchargeAssignScreen({super.key});

  static const gold = Color(0xFFD7BE69);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Incharge Assign'),
        backgroundColor: gold,
        foregroundColor: Colors.white,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text('Choose a level to manage',
                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.8))),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 24),
        children: [
          for (final level in InchargeLevel.all) ...[
            _LevelCard(
              level: level,
              onTap: () => context.push('/incharge-assign/list/${level.key}'),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  final InchargeLevel level;
  final VoidCallback onTap;

  const _LevelCard({required this.level, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      elevation: 1.5,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: level.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(level.icon, color: level.color, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(level.parentLabel,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(level.description,
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _pill(level.parentLabel, level.color),
                        Icon(Icons.arrow_forward_rounded, size: 13, color: Colors.grey.shade400),
                        for (final cr in level.childRoleList) _pill(cr.label, Colors.grey.shade600),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Text(text,
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: color)),
      );
}
