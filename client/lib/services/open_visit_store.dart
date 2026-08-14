import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One in-progress shop visit — punched in, not yet punched out.
///
/// A visit only becomes a row in the DB on Visit Out (as an order-funnel
/// response), so before this existed an open visit lived purely in screen
/// state: navigating back destroyed it and the screen reopened as though the
/// visit had never started. Persisting it here keeps the visit — and its
/// running timer — alive across navigation and app restarts.
class OpenVisit {
  final String accountId;
  final DateTime visitInAt;

  /// Salesman's own position at Visit In, used as the geofence anchor. Null
  /// when the fix wasn't available — the visit still opens, it just can't be
  /// auto-closed on distance.
  final double? lat;
  final double? lng;

  const OpenVisit({
    required this.accountId,
    required this.visitInAt,
    this.lat,
    this.lng,
  });

  Map<String, dynamic> toJson() => {
        'account_id':  accountId,
        // Stored as UTC so a device timezone change can't retroactively move
        // the punch-in and corrupt the elapsed time.
        'visit_in_at': visitInAt.toUtc().toIso8601String(),
        'lat':         lat,
        'lng':         lng,
      };

  static OpenVisit? fromJson(Map<String, dynamic> j) {
    final id = (j['account_id'] ?? '').toString();
    final at = DateTime.tryParse((j['visit_in_at'] ?? '').toString());
    if (id.isEmpty || at == null) return null;
    return OpenVisit(
      accountId: id,
      visitInAt: at.toLocal(),
      lat: (j['lat'] as num?)?.toDouble(),
      lng: (j['lng'] as num?)?.toDouble(),
    );
  }
}

class OpenVisitStore {
  static String _key(String accountId) => 'open_visit_$accountId';

  static Future<OpenVisit?> load(String accountId) async {
    if (accountId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(accountId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return OpenVisit.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      // Unreadable entry would otherwise wedge this account permanently.
      await prefs.remove(_key(accountId));
      return null;
    }
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
