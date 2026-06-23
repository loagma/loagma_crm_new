import 'package:flutter/material.dart';

/// Describes one rung of the incharge hierarchy used by the admin
/// "Incharge Assign" flow.
///
/// Hierarchy:
///   Head Incharge  → assigns →  Zonal Incharge
///   Zonal Incharge → assigns →  Area Incharge (+ Teleadmin)
///   Area Incharge  → assigns →  Salesman
///   Teleadmin      → assigns →  Telecaller
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

  /// Optional second child role assignable on the same screen (e.g. a Zonal
  /// Incharge can be assigned Area Incharges AND Teleadmins). When set, the
  /// assign screen shows two sections and saves both into the one record.
  final String? secondaryChildRole;
  final String? secondaryChildLabel;

  const InchargeLevel({
    required this.key,
    required this.parentRole,
    required this.childRole,
    required this.parentLabel,
    required this.childLabel,
    required this.description,
    required this.icon,
    required this.color,
    this.secondaryChildRole,
    this.secondaryChildLabel,
  });

  /// All child roles this level can assign (1 or 2 entries), each with its label.
  List<({String role, String label})> get childRoleList => [
        (role: childRole, label: childLabel),
        if (secondaryChildRole != null)
          (role: secondaryChildRole!, label: secondaryChildLabel ?? secondaryChildRole!),
      ];

  bool get hasMultipleChildRoles => secondaryChildRole != null;

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
    description: 'Assign area incharges and teleadmins to each zonal incharge',
    icon: Icons.hub_rounded,
    color: Color(0xFF42A5F5),
    secondaryChildRole: 'teleadmin',
    secondaryChildLabel: 'Teleadmin',
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

  static const tele = InchargeLevel(
    key: 'tele',
    parentRole: 'teleadmin',
    childRole: 'telecaller',
    parentLabel: 'Teleadmin',
    childLabel: 'Telecaller',
    description: 'Assign telecallers to each teleadmin',
    icon: Icons.headset_mic_rounded,
    color: Color(0xFF5E35B1),
  );

  static const all = [head, zonal, area, tele];

  static InchargeLevel? byKey(String? key) {
    for (final l in all) {
      if (l.key == key) return l;
    }
    return null;
  }
}

/// Normalize a role string for comparison: lowercase + strip spaces, so
/// "Teleadmin", "tele admin" and "teleadmin" all match. Mirrors role_guard.
String normalizeRole(String? r) => (r ?? '').toLowerCase().trim().replaceAll(' ', '');

/// What a Zonal Incharge is specialized for, derived from the roles of the
/// children currently assigned to it:
///   only area_incharge → sales · only teleadmin → tele · both → both.
enum ZonalSpecialty { none, sales, tele, both }

ZonalSpecialty zonalSpecialtyFromRoles(Iterable<String> childRoles) {
  var hasSales = false;
  var hasTele = false;
  for (final r in childRoles) {
    final n = normalizeRole(r);
    if (n == 'area_incharge') hasSales = true;
    if (n == 'teleadmin') hasTele = true;
  }
  if (hasSales && hasTele) return ZonalSpecialty.both;
  if (hasSales) return ZonalSpecialty.sales;
  if (hasTele) return ZonalSpecialty.tele;
  return ZonalSpecialty.none;
}

extension ZonalSpecialtyStyle on ZonalSpecialty {
  /// Short badge label, or null when there's nothing to show.
  String? get label {
    switch (this) {
      case ZonalSpecialty.sales:
        return 'Sales';
      case ZonalSpecialty.tele:
        return 'Tele';
      case ZonalSpecialty.both:
        return 'Sales + Tele';
      case ZonalSpecialty.none:
        return null;
    }
  }

  Color get color {
    switch (this) {
      case ZonalSpecialty.sales:
        return const Color(0xFF43A047); // green (salesman)
      case ZonalSpecialty.tele:
        return const Color(0xFF00838F); // teal (telecaller)
      case ZonalSpecialty.both:
        return const Color(0xFF6A1B9A); // purple
      case ZonalSpecialty.none:
        return const Color(0xFF9E9E9E);
    }
  }
}
