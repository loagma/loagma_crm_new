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
/// Deliberately holds no location: punching in and out is location-free.
class OpenVisit {
  final String accountId;
  final DateTime visitInAt;
  // Only used to name the account in the "visit out first" message on other
  // screens — not required, and absent on entries written before this field
  // existed (fromJson tolerates that).
  final String? accountName;

  const OpenVisit({
    required this.accountId,
    required this.visitInAt,
    this.accountName,
  });

  Map<String, dynamic> toJson() => {
        'account_id':   accountId,
        // Stored as UTC so a device timezone change can't retroactively move
        // the punch-in and corrupt the elapsed time.
        'visit_in_at':  visitInAt.toUtc().toIso8601String(),
        'account_name': accountName,
      };

  static OpenVisit? fromJson(Map<String, dynamic> j) {
    final id = (j['account_id'] ?? '').toString();
    final at = DateTime.tryParse((j['visit_in_at'] ?? '').toString());
    if (id.isEmpty || at == null) return null;
    final name = (j['account_name'] as String?)?.trim();
    return OpenVisit(
      accountId: id,
      visitInAt: at.toLocal(),
      accountName: (name == null || name.isEmpty) ? null : name,
    );
  }
}

class OpenVisitStore {
  static const _prefix = 'open_visit_';
  static String _key(String accountId) => '$_prefix$accountId';

  static OpenVisit? _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return OpenVisit.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  static Future<OpenVisit?> load(String accountId) async {
    if (accountId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(accountId));
    if (raw == null || raw.isEmpty) return null;
    final visit = _decode(raw);
    if (visit == null) {
      // Unreadable entry would otherwise wedge this account permanently.
      await prefs.remove(_key(accountId));
    }
    return visit;
  }

  /// A shop visit is a single-lane thing — a salesman can't be mid-visit at
  /// two customers at once. Scans every account with an open visit still on
  /// disk (there should be at most one, but a crash before Visit Out or a
  /// state left over from before this check existed could leave a stray one)
  /// and returns the first found other than [excludingAccountId], so the
  /// caller can block starting a new visit until that one is closed out.
  static Future<OpenVisit?> findOtherOpen(String excludingAccountId) async {
    final prefs = await SharedPreferences.getInstance();
    final excludeKey = _key(excludingAccountId);
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix) || key == excludeKey) continue;
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) continue;
      final visit = _decode(raw);
      if (visit != null) return visit;
      await prefs.remove(key); // unreadable — drop it rather than wedge every check
    }
    return null;
  }

  static Future<void> save(OpenVisit visit) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(visit.accountId), jsonEncode(visit.toJson()));
  }

  static Future<void> clear(String accountId) async {
    if (accountId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(accountId));
  }
}
