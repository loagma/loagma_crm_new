import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One in-progress shop visit — punched in, not yet punched out.
///
/// A visit only becomes a row in the DB on Visit Out (as an order-funnel
/// response), so before this existed an open visit lived purely in screen
/// state: navigating back destroyed it and the screen reopened as though the
/// visit had never started. Persisting it here keeps the visit — and its
/// running timer — alive across navigation and app restarts.
///
/// Visits are scoped per [role] ('salesman' | 'telecaller'): a salesman's open
/// visit must not block a telecaller from checking in and vice versa, so each
/// role gets its own single lane. Within one role there can be at most one
/// open visit at a time.
///
/// Deliberately holds no location: punching in and out is location-free.
class OpenVisit {
  final String accountId;
  final String role; // 'salesman' | 'telecaller'
  // Kept so "Go There" can reopen the visit screen with the right tabs and so
  // the eventual check-out action log is filed against the correct type.
  final String accountType; // 'lead' | 'customer'
  final DateTime visitInAt;
  // Only used to name the account in the "check out first" message on other
  // screens — not required, and absent on entries written before this field
  // existed (fromJson tolerates that).
  final String? accountName;

  const OpenVisit({
    required this.accountId,
    required this.role,
    required this.accountType,
    required this.visitInAt,
    this.accountName,
  });

  Map<String, dynamic> toJson() => {
        'account_id':   accountId,
        'role':         role,
        'account_type': accountType,
        // Stored as UTC so a device timezone change can't retroactively move
        // the punch-in and corrupt the elapsed time.
        'visit_in_at':  visitInAt.toUtc().toIso8601String(),
        'account_name': accountName,
      };

  static OpenVisit? fromJson(Map<String, dynamic> j, {String? roleFromKey}) {
    final id = (j['account_id'] ?? '').toString();
    final at = DateTime.tryParse((j['visit_in_at'] ?? '').toString());
    if (id.isEmpty || at == null) return null;
    final role = (roleFromKey ?? (j['role'] ?? '').toString()).trim();
    if (role.isEmpty) return null;
    final type = (j['account_type'] ?? '').toString().trim();
    final name = (j['account_name'] as String?)?.trim();
    return OpenVisit(
      accountId: id,
      role: role,
      accountType: type.isEmpty ? 'lead' : type,
      visitInAt: at.toLocal(),
      accountName: (name == null || name.isEmpty) ? null : name,
    );
  }
}

class OpenVisitStore {
  // Keys are 'open_visit_<role>_<accountId>'. Roles carry no underscore and
  // account ids are UUIDs (also no underscore), so the first underscore after
  // the root cleanly separates the two.
  static const _root = 'open_visit_';
  static String _rolePrefix(String role) => '$_root${role}_';
  static String _key(String role, String accountId) => '${_rolePrefix(role)}$accountId';

  static ({String role, String accountId})? _parseKey(String key) {
    if (!key.startsWith(_root)) return null;
    final rest = key.substring(_root.length);
    final i = rest.indexOf('_');
    if (i <= 0 || i == rest.length - 1) return null; // no role, or empty id
    return (role: rest.substring(0, i), accountId: rest.substring(i + 1));
  }

  static OpenVisit? _decode(String raw, {String? roleFromKey}) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return OpenVisit.fromJson(Map<String, dynamic>.from(decoded), roleFromKey: roleFromKey);
    } catch (_) {
      return null;
    }
  }

  static Future<OpenVisit?> load(String role, String accountId) async {
    if (role.isEmpty || accountId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(role, accountId));
    if (raw == null || raw.isEmpty) return null;
    final visit = _decode(raw, roleFromKey: role);
    if (visit == null) {
      // Unreadable entry would otherwise wedge this account permanently.
      await prefs.remove(_key(role, accountId));
    }
    return visit;
  }

  /// A shop visit is a single-lane thing *per role* — a salesman can't be
  /// mid-visit at two customers at once, but a telecaller's open visit is a
  /// separate lane and must not block him. Scans every account with an open
  /// visit for [role] still on disk (there should be at most one, but a crash
  /// before Visit Out or a stale state could leave a stray one) and returns
  /// the first found other than [excludingAccountId], so the caller can block
  /// starting a new visit until that one is closed out. Legacy / malformed
  /// keys (including pre-role-scoping entries) are dropped as they're seen.
  static Future<OpenVisit?> findOtherOpen(String role, String excludingAccountId) async {
    if (role.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final excludeKey = _key(role, excludingAccountId);
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_root)) continue;
      final parsed = _parseKey(key);
      if (parsed == null) {
        await prefs.remove(key); // legacy 'open_visit_<id>' or malformed — drop it
        continue;
      }
      if (parsed.role != role || key == excludeKey) continue;
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) continue;
      final visit = _decode(raw, roleFromKey: parsed.role);
      if (visit != null) return visit;
      await prefs.remove(key); // unreadable — drop it rather than wedge every check
    }
    return null;
  }

  static Future<void> save(OpenVisit visit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(visit.role, visit.accountId), jsonEncode(visit.toJson()));
  }

  static Future<void> clear(String role, String accountId) async {
    if (role.isEmpty || accountId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(role, accountId));
  }
}
