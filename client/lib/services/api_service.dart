import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'user_service.dart';

class ApiService {
  static Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };

  static Map<String, String> get _authHeaders => {
        ..._headers,
        'Authorization': 'Bearer ${UserService.token}',
      };

  // Indicates whether last employees fetch used mocked fallback data
  static bool usedMockEmployees = false;

  static Future<Map<String, dynamic>> sendOtp(String mobile) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/auth/send-otp');
    int attempts = 0;
    while (true) {
      attempts++;
      try {
        final response = await http
            .post(url, headers: _headers, body: jsonEncode({'mobile': mobile}))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return jsonDecode(response.body) as Map<String, dynamic>;
        }
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      } catch (e) {
        // Log and retry a few times before failing
        print('sendOtp attempt $attempts failed for $url: $e');
        if (attempts >= 3) rethrow;
        await Future.delayed(Duration(seconds: 2 * attempts));
      }
    }
  }

  static Future<Map<String, dynamic>> verifyOtp(
      String mobile, String otp) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/auth/verify-otp');
    int attempts = 0;
    while (true) {
      attempts++;
      try {
        final response = await http
            .post(url,
                headers: _headers,
                body: jsonEncode({'mobile': mobile, 'otp': otp}))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return jsonDecode(response.body) as Map<String, dynamic>;
        }
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      } catch (e) {
        print('verifyOtp attempt $attempts failed for $url: $e');
        if (attempts >= 3) rethrow;
        await Future.delayed(Duration(seconds: 2 * attempts));
      }
    }
  }

  static Future<Map<String, dynamic>> me() async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/auth/me');
    final response = await http
        .get(url, headers: _authHeaders)
        .timeout(const Duration(seconds: 15));
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<void> logout() async {
    try {
      final url = Uri.parse('${ApiConfig.baseUrl}/api/auth/logout');
      final response = await http
          .post(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 10));
      // Log response for debugging
      print('Logout response status: ${response.statusCode}');
      print('Logout response body: ${response.body}');
    } catch (e) {
      print('Logout API error: $e');
      // Continue with local logout even if API fails (user might have expired token)
    }
  }

  /// Fetch list of employees from the API.
  /// Supports optional server-side search (`q`) and pagination (`page`, `perPage`).
  /// Returns a list of employee maps.
  static Future<List<Map<String, dynamic>>> getEmployees({String? q, int? page, int? perPage}) async {
    usedMockEmployees = false;
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/employees').replace(queryParameters: {
      if (q != null && q.isNotEmpty) 'q': q,
      if (page != null) 'page': page.toString(),
      if (perPage != null) 'per_page': perPage.toString(),
    });

    try {
      final response = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(response.body);

      if (decoded is Map && decoded.containsKey('data')) {
        final data = decoded['data'];
        if (data is List) {
          return List<Map<String, dynamic>>.from(data.map((e) => Map<String, dynamic>.from(e as Map)));
        }
      } else if (decoded is List) {
        return List<Map<String, dynamic>>.from(decoded.map((e) => Map<String, dynamic>.from(e as Map)));
      }

      return <Map<String, dynamic>>[];
    } catch (e) {
      // Backend may be down or unreachable (timeout). Return mocked data so UI remains usable.
      usedMockEmployees = true;
      print('getEmployees failed for $uri: $e');

      // Sample mock employees
      return [
        {'id': '1', 'name': 'Alice Johnson', 'role': 'Admin', 'mobile': '555-0100'},
        {'id': '2', 'name': 'Bob Patel', 'role': 'Manager', 'mobile': '555-0101'},
        {'id': '3', 'name': 'Carol Singh', 'role': 'Sales', 'mobile': '555-0102'},
      ];
    }
  }

  /// Fetch a single employee by id (mobile)
  static Future<Map<String, dynamic>?> getEmployee(String id) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/employees/$id');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded.containsKey('data')) {
          return Map<String, dynamic>.from(decoded['data'] as Map);
        }
      }
    } catch (e) {
      print('getEmployee failed for $url: $e');
    }
    return null;
  }

  /// Create or update an employee record on the server.
  static Future<Map<String, dynamic>?> createEmployee(Map<String, dynamic> body) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/employees');
    try {
      final response = await http.post(url, headers: _authHeaders, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
      final status = response.statusCode;

      if (status >= 200 && status < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded.containsKey('data')) {
          return Map<String, dynamic>.from(decoded['data'] as Map);
        }
        return null;
      }

      // Validation errors (Laravel returns 422 with errors)
      if (status == 422) {
        try {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          if (decoded.containsKey('errors')) {
            return {'errors': Map<String, dynamic>.from(decoded['errors'] as Map)};
          }
        } catch (_) {}
      }

      print('createEmployee unexpected status $status: ${response.body}');
    } catch (e) {
      print('createEmployee failed for $url: $e');
    }
    return null;
  }

  /// Update an existing employee by id (mobile)
  static Future<Map<String, dynamic>?> updateEmployee(String id, Map<String, dynamic> body) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/employees/$id');
    try {
      final response = await http.put(url, headers: _authHeaders, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
      final status = response.statusCode;

      if (status >= 200 && status < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded.containsKey('data')) {
          return Map<String, dynamic>.from(decoded['data'] as Map);
        }
        return null;
      }

      if (status == 422) {
        try {
          final decoded = jsonDecode(response.body) as Map<String, dynamic>;
          if (decoded.containsKey('errors')) {
            return {'errors': Map<String, dynamic>.from(decoded['errors'] as Map)};
          }
        } catch (_) {}
      }

      print('updateEmployee unexpected status $status: ${response.body}');
    } catch (e) {
      print('updateEmployee failed for $url: $e');
    }
    return null;
  }
}
