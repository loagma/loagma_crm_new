import 'package:flutter/material.dart';

/// Describes one rung of the incharge hierarchy used by the admin
/// "Incharge Assign" flow.
///
/// Hierarchy:
///   Head Incharge  → assigns →  Zonal Incharge
///   Zonal Incharge → assigns →  Area Incharge
///   Area Incharge  → assigns →  Salesman
///
/// Each `parentRole` person owns exactly one set of children (`childRole`),
/// so the existing `incharge-assign/{parentId}` API (keyed by the parent's
/// unique mobile id) works for every level without backend changes.
class InchargeLevel {
  final String key; // 'head' | 'zonal' | 'area'
  final String parentRole; // role of the people shown in the list
  final String childRole; // role of the people you select & assign
  final String parentLabel; // e.g. 'Head Incharge'
  final String childLabel; // e.g. 'Zonal Incharge'
  final String description; // shown on the picker card
  final IconData icon;
  final Color color;

  const InchargeLevel({
    required this.key,
    required this.parentRole,
    required this.childRole,
    required this.parentLabel,
    required this.childLabel,
    required this.description,
    required this.icon,
    required this.color,
  });

  String childLabelCount(int n) => '$childLabel${n == 1 ? '' : 's'}';

  static const head = InchargeLevel(
    key: 'head',
    parentRole: 'head_incharge',
    childRole: 'zonal_incharge',
    parentLabel: 'Head Incharge',
    childLabel: 'Zonal Incharge',
    description: 'Assign zonal incharges to each head incharge',
    icon: Icons.account_tree_rounded,
    color: Color(0xFFAB47BC),
  );

  static const zonal = InchargeLevel(
    key: 'zonal',
    parentRole: 'zonal_incharge',
    childRole: 'area_incharge',
    parentLabel: 'Zonal Incharge',
    childLabel: 'Area Incharge',
    description: 'Assign area incharges to each zonal incharge',
    icon: Icons.hub_rounded,
    color: Color(0xFF42A5F5),
  );

  static const area = InchargeLevel(
    key: 'area',
    parentRole: 'area_incharge',
    childRole: 'salesman',
    parentLabel: 'Area Incharge',
    childLabel: 'Salesman',
    description: 'Assign salesmen to each area incharge',
    icon: Icons.groups_rounded,
    color: Color(0xFFFF7043),
  );

  static const all = [head, zonal, area];

  static InchargeLevel? byKey(String? key) {
    for (final l in all) {
      if (l.key == key) return l;
    }
    return null;
  }
}
