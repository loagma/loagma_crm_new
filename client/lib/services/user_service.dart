import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tracking_service.dart';

class UserService extends ChangeNotifier {
  static const _keyToken  = 'token';
  static const _keyId     = 'user_id';
  static const _keyName   = 'user_name';
  static const _keyMobile = 'user_mobile';
  static const _keyRole   = 'user_role';

  static String? _token;
  static String? _role;
  static String? _name;
  static String? _mobile;
  static int?    _id;

  static final UserService _instance = UserService._internal();

  UserService._internal();

  factory UserService() {
    return _instance;
  }

  static bool    get isLoggedIn     => _token != null && _token!.isNotEmpty;
  static String? get currentRole    => _role;
  static String? get currentName    => _name;
  static String? get currentMobile  => _mobile;
  static int?    get currentId      => _id;
  static String? get token          => _token;

  /// Call once at app startup to restore session from disk.
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token  = prefs.getString(_keyToken);
    _role   = prefs.getString(_keyRole);
    _name   = prefs.getString(_keyName);
    _mobile = prefs.getString(_keyMobile);
    _id     = prefs.getInt(_keyId);
  }

  /// Save a real session from the API verify-otp response.
  static Future<void> loginFromApi(Map<String, dynamic> response) async {
    final prefs  = await SharedPreferences.getInstance();
    // Tolerant parsing: the API may send numbers as strings (or vice versa)
    // depending on the DB driver — a hard `as` cast here made login fail.
    final data   = Map<String, dynamic>.from((response['data'] as Map?) ?? const {});
    final token  = response['token']?.toString() ?? '';
    if (token.isEmpty) {
      throw Exception('Login response did not include a token');
    }

    _token  = token;
    _role   = data['role']?.toString();
    _name   = data['name']?.toString();
    _mobile = (data['mobile'] ?? data['contactNumber'])?.toString();
    final rawId = data['id'];
    _id     = rawId is int ? rawId : int.tryParse('${rawId ?? ''}');

    await prefs.setString(_keyToken, token);
    if (_role   != null) await prefs.setString(_keyRole,   _role!);
    if (_name   != null) await prefs.setString(_keyName,   _name!);
    if (_mobile != null) await prefs.setString(_keyMobile, _mobile!);
    if (_id     != null) await prefs.setInt(_keyId,        _id!);
    
    _instance.notifyListeners();
  }

  static Future<void> logout() async {
    // Stop GPS tracking first — otherwise the foreground location service
    // keeps running (and posting pings) after the user has logged out.
    try {
      await TrackingService.stop();
    } catch (_) {
      // Never block logout on the tracking plugin.
    }

    final prefs = await SharedPreferences.getInstance();
    _token  = null;
    _role   = null;
    _name   = null;
    _mobile = null;
    _id     = null;

    await prefs.remove(_keyToken);
    await prefs.remove(_keyRole);
    await prefs.remove(_keyName);
    await prefs.remove(_keyMobile);
    await prefs.remove(_keyId);
    
    _instance.notifyListeners();
  }
}
