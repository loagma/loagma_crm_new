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

  static Future<Map<String, dynamic>> sendOtp(String mobile) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/auth/send-otp');
    final response = await http
        .post(url, headers: _headers, body: jsonEncode({'mobile': mobile}))
        .timeout(const Duration(seconds: 15));
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifyOtp(
      String mobile, String otp) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/auth/verify-otp');
    final response = await http
        .post(url,
            headers: _headers,
            body: jsonEncode({'mobile': mobile, 'otp': otp}))
        .timeout(const Duration(seconds: 15));
    return jsonDecode(response.body) as Map<String, dynamic>;
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
}
