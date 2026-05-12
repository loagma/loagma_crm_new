import 'package:shared_preferences/shared_preferences.dart';

class UserService {
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
    final data   = response['data'] as Map<String, dynamic>;
    final token  = response['token'] as String;

    _token  = token;
    _role   = data['role']   as String?;
    _name   = data['name']   as String?;
    _mobile = (data['mobile'] ?? data['contactNumber']) as String?;
    _id     = data['id']     as int?;

    await prefs.setString(_keyToken, token);
    if (_role   != null) await prefs.setString(_keyRole,   _role!);
    if (_name   != null) await prefs.setString(_keyName,   _name!);
    if (_mobile != null) await prefs.setString(_keyMobile, _mobile!);
    if (_id     != null) await prefs.setInt(_keyId,        _id!);
  }

  /// Dev-mode only: create a fake session without a real token.
  static Future<void> login({
    required String role,
    required String contactNumber,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _role   = role;
    _mobile = contactNumber;
    _token  = 'dev_token';

    await prefs.setString(_keyToken,  'dev_token');
    await prefs.setString(_keyRole,   role);
    await prefs.setString(_keyMobile, contactNumber);
  }

  static Future<void> logout() async {
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
  }
}
