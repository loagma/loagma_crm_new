import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
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

  /// Fetch roles from role_crm table. Returns list of {id, name, label}.
  static Future<List<Map<String, dynamic>>> getRoles() async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/masters/roles');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['data'] is List) {
          return List<Map<String, dynamic>>.from(
            (decoded['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
        }
      }
    } catch (e) {
      print('getRoles error: $e');
    }
    return [];
  }

  /// Fetch list of employees from the API.
  /// Supports optional server-side search (`q`) and pagination (`page`, `perPage`).
  /// Returns a list of employee maps.
  static Future<List<Map<String, dynamic>>> getEmployees({String? q, int? page, int? perPage}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/employees').replace(queryParameters: {
      if (q != null && q.isNotEmpty) 'q': q,
      if (page != null) 'page': page.toString(),
      if (perPage != null) 'per_page': perPage.toString(),
    });

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

  // ── Lead Accounts ─────────────────────────────────────────────────────────

  /// Fetch paginated/searched list of lead accounts.
  /// Returns {'data': [...], 'meta': {...}} or {'data': [...]}.
  static Future<Map<String, dynamic>> getLeadAccounts({
    String? q,
    int? page,
    int? perPage,
    String? pincode,
    List<String>? pincodes,
    List<int>? areaIds,
  }) async {
    final params = <String, dynamic>{
      if (q != null && q.isNotEmpty) 'q': q,
      if (page != null) 'page': page.toString(),
      if (perPage != null) 'per_page': perPage.toString(),
      if (pincode != null && pincode.isNotEmpty) 'pincode': pincode,
    };
    // Uri.replace doesn't support repeated keys — build manually for list params
    var uri = Uri.parse('${ApiConfig.baseUrl}/api/lead-accounts').replace(queryParameters: params);
    if (pincodes != null && pincodes.isNotEmpty) {
      final extra = pincodes.map((p) => 'pincodes[]=${Uri.encodeQueryComponent(p)}').join('&');
      uri = Uri.parse('${uri.toString()}&$extra');
    }
    if (areaIds != null && areaIds.isNotEmpty) {
      final extra = areaIds.map((id) => 'area_ids[]=$id').join('&');
      uri = Uri.parse('${uri.toString()}&$extra');
    }

    try {
      final response = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return decoded;
    } catch (e) {
      print('getLeadAccounts failed for $uri: $e');
      return {'success': false, 'data': <dynamic>[]};
    }
  }

  /// Fetch a single lead account by id.
  static Future<Map<String, dynamic>?> getLeadAccount(String id) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/lead-accounts/$id');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded.containsKey('data')) {
          return Map<String, dynamic>.from(decoded['data'] as Map);
        }
      }
    } catch (e) {
      print('getLeadAccount failed for $url: $e');
    }
    return null;
  }

  /// Create a new lead account. Returns the created record or an errors map on 422.
  static Future<Map<String, dynamic>?> createLeadAccount(Map<String, dynamic> body) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/lead-accounts');
    try {
      final response = await http
          .post(url, headers: _authHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
      final status = response.statusCode;

      if (status >= 200 && status < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded.containsKey('data')) {
          return Map<String, dynamic>.from(decoded['data'] as Map);
        }
        return decoded;
      }

      if (status == 422) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return {'errors': decoded['errors'] ?? decoded['message'] ?? 'Validation failed'};
      }

      print('createLeadAccount unexpected status $status: ${response.body}');
    } catch (e) {
      print('createLeadAccount failed for $url: $e');
    }
    return null;
  }

  /// Update an existing lead account. Returns updated record or errors map on 422.
  static Future<Map<String, dynamic>?> updateLeadAccount(String id, Map<String, dynamic> body) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/lead-accounts/$id');
    try {
      final response = await http
          .put(url, headers: _authHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 20));
      final status = response.statusCode;

      if (status >= 200 && status < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded.containsKey('data')) {
          return Map<String, dynamic>.from(decoded['data'] as Map);
        }
        return decoded;
      }

      if (status == 422) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return {'errors': decoded['errors'] ?? decoded['message'] ?? 'Validation failed'};
      }

      print('updateLeadAccount unexpected status $status: ${response.body}');
    } catch (e) {
      print('updateLeadAccount failed for $url: $e');
    }
    return null;
  }

  /// Check whether a contact number is already registered.
  /// Pass [excludeId] in edit mode to skip the record being updated.
  /// Returns {'exists': bool, 'data': {...}} or null on network error.
  static Future<Map<String, dynamic>?> checkLeadContactExists(
    String contactNumber, {
    String? excludeId,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/lead-accounts/check-contact').replace(
      queryParameters: {
        'contact_number': contactNumber,
        if (excludeId case final id?) 'exclude_id': id,
      },
    );
    try {
      final response = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 8));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('checkLeadContactExists failed for $uri: $e');
    }
    return null;
  }

  /// Delete a lead account by id. Returns true on success.
  static Future<bool> deleteLeadAccount(String id) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/lead-accounts/$id');
    try {
      final response = await http.delete(url, headers: _authHeaders).timeout(const Duration(seconds: 10));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('deleteLeadAccount failed for $url: $e');
      return false;
    }
  }

  /// Upload lead image and return stored relative URL path (e.g. /storage/leads/..)
  static Future<String?> uploadLeadImage(String filePath) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/lead-accounts/upload-image');
    try {
      final req = http.MultipartRequest('POST', url)
        ..headers['Accept'] = 'application/json'
        ..headers['Authorization'] = 'Bearer ${UserService.token}'
        ..files.add(await http.MultipartFile.fromPath('image', filePath));

      final streamed = await req.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['path'] != null) {
          return decoded['path'].toString();
        }
      }
      print('uploadLeadImage unexpected status ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('uploadLeadImage failed for $url (${File(filePath).path}): $e');
    }
    return null;
  }

  /// Lookup Indian pincode details using public postal API.
  /// Returns normalized shape:
  /// {
  ///   'country': 'India',
  ///   'state': '...',
  ///   'district': '...',
  ///   'city': '...',
  ///   'areas': ['...', ...],
  /// }
  static Future<Map<String, dynamic>?> lookupIndianPincode(String pincode) async {
    final url = Uri.parse('https://api.postalpincode.in/pincode/$pincode');
    try {
      // api.postalpincode.in has an expired TLS cert — bypass only for this host
      final inner = HttpClient()
        ..badCertificateCallback = (cert, host, port) => host == 'api.postalpincode.in';
      final client = IOClient(inner);
      final response = await client.get(url).timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! List || decoded.isEmpty) return null;
      final first = decoded.first;
      if (first is! Map) return null;

      // API returns Status: "Error" when pincode not found
      if ((first['Status'] ?? '').toString().toLowerCase() == 'error') return null;

      final postOfficesRaw = first['PostOffice'];
      if (postOfficesRaw is! List || postOfficesRaw.isEmpty) return null;

      final postOffices = postOfficesRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (postOffices.isEmpty) return null;
      final top = postOffices.first;

      // Helper: treat "NA", "N/A", "" as absent
      String? clean(dynamic raw) {
        final s = raw?.toString().trim() ?? '';
        if (s.isEmpty || s.toUpperCase() == 'NA' || s.toUpperCase() == 'N/A') return null;
        return s;
      }

      final areas = postOffices
          .map((e) => (e['Name'] ?? '').toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList()
        ..sort();

      // City: prefer Block → Division → District → first area name
      final city = clean(top['Block'])
          ?? clean(top['Division'])
          ?? clean(top['District'])
          ?? (areas.isNotEmpty ? areas.first : '');

      return {
        'country'  : clean(top['Country'])  ?? 'India',
        'state'    : clean(top['State'])    ?? '',
        'district' : clean(top['District']) ?? '',
        'city'     : city,
        'areas'    : areas,
      };
    } catch (e) {
      print('lookupIndianPincode failed for $url: $e');
      return null;
    }
  }

  // ── Areas (Marketing + Assign source) ─────────────────────────────────────
  static Future<Map<String, dynamic>> getAreas({String? q, int? page, int? perPage}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/areas').replace(queryParameters: {
      if (q != null && q.isNotEmpty) 'q': q,
      if (page != null) 'page': page.toString(),
      if (perPage != null) 'per_page': perPage.toString(),
    });
    try {
      final response = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 15));
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      print('getAreas failed for $uri: $e');
      return {'success': false, 'data': <dynamic>[]};
    }
  }

  static Future<Map<String, dynamic>?> getArea(int id) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/areas/$id');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 12));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded['data'] is Map) return Map<String, dynamic>.from(decoded['data'] as Map);
      }
    } catch (e) {
      print('getArea failed for $url: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> createArea(String areaName, {List<String>? pincodes}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/areas');
    try {
      final body = {
        'area_name': areaName,
        if (pincodes != null) 'pincodes': pincodes,
      };
      final response = await http.post(url, headers: _authHeaders, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded['data'] is Map) return Map<String, dynamic>.from(decoded['data'] as Map);
      }
      if (status == 422) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return {'errors': decoded['errors'] ?? decoded['message'] ?? 'Validation failed'};
      }
      print('createArea unexpected status $status: ${response.body}');
    } catch (e) {
      print('createArea failed for $url: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> updateArea(int id, {String? areaName, List<String>? pincodes}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/areas/$id');
    try {
      final body = <String, dynamic>{
        if (areaName != null) 'area_name': areaName,
        if (pincodes != null) 'pincodes': pincodes,
      };
      final response = await http.put(url, headers: _authHeaders, body: jsonEncode(body)).timeout(const Duration(seconds: 15));
      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded['data'] is Map) return Map<String, dynamic>.from(decoded['data'] as Map);
      }
      if (status == 422) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return {'errors': decoded['errors'] ?? decoded['message'] ?? 'Validation failed'};
      }
      print('updateArea unexpected status $status: ${response.body}');
    } catch (e) {
      print('updateArea failed for $url: $e');
    }
    return null;
  }

  static Future<bool> deleteArea(int id) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/areas/$id');
    try {
      final response = await http.delete(url, headers: _authHeaders).timeout(const Duration(seconds: 12));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('deleteArea failed for $url: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> addAreaPincodes(int areaId, List<String> pincodes) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/areas/$areaId/pincodes');
    try {
      final response = await http
          .post(url, headers: _authHeaders, body: jsonEncode({'pincodes': pincodes}))
          .timeout(const Duration(seconds: 15));
      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded['data'] is Map) return Map<String, dynamic>.from(decoded['data'] as Map);
      }
      if (status == 422) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return {'errors': decoded['errors'] ?? decoded['message'] ?? 'Validation failed'};
      }
      print('addAreaPincodes unexpected status $status: ${response.body}');
    } catch (e) {
      print('addAreaPincodes failed for $url: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> updateAreaPincode(int areaId, String oldPincode, String newPincode) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/areas/$areaId/pincodes/$oldPincode');
    try {
      final response = await http
          .put(url, headers: _authHeaders, body: jsonEncode({'new_pincode': newPincode}))
          .timeout(const Duration(seconds: 15));
      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded['data'] is Map) return Map<String, dynamic>.from(decoded['data'] as Map);
      }
      if (status == 422) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return {'errors': decoded['errors'] ?? decoded['message'] ?? 'Validation failed'};
      }
      print('updateAreaPincode unexpected status $status: ${response.body}');
    } catch (e) {
      print('updateAreaPincode failed for $url: $e');
    }
    return null;
  }

  static Future<bool> deleteAreaPincode(int areaId, String pincode) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/areas/$areaId/pincodes/$pincode');
    try {
      final response = await http.delete(url, headers: _authHeaders).timeout(const Duration(seconds: 12));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('deleteAreaPincode failed for $url: $e');
      return false;
    }
  }

  // ── Area Assign ───────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getAllAreaAssigns() async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/area-assign');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final data = decoded['data'];
        if (data is List) {
          return List<Map<String, dynamic>>.from(data.map((e) => Map<String, dynamic>.from(e as Map)));
        }
      }
    } catch (e) {
      print('getAllAreaAssigns failed for $url: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> getAreaAssign(String employeeId) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/area-assign/$employeeId');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 12));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('getAreaAssign failed for $url: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> saveAreaAssign(
      String employeeId, List<int> areaIds, List<String> areaNames) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/area-assign/$employeeId');
    try {
      final body = {'area_ids': areaIds, 'area_names': areaNames};
      final response = await http
          .post(url, headers: _authHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      if (status == 422) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return {'errors': decoded['errors'] ?? decoded['message'] ?? 'Validation failed'};
      }
      print('saveAreaAssign unexpected status $status: ${response.body}');
    } catch (e) {
      print('saveAreaAssign failed for $url: $e');
    }
    return null;
  }

  static Future<bool> deleteAreaAssign(String employeeId) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/area-assign/$employeeId');
    try {
      final response = await http.delete(url, headers: _authHeaders).timeout(const Duration(seconds: 12));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('deleteAreaAssign failed for $url: $e');
      return false;
    }
  }

  // ── Incharge Assign (head_incharge → incharge mapping) ───────────────────

  static Future<List<Map<String, dynamic>>> getAllInchargeAssigns() async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/incharge-assign');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final data = decoded['data'];
        if (data is List) {
          return List<Map<String, dynamic>>.from(data.map((e) => Map<String, dynamic>.from(e as Map)));
        }
      }
    } catch (e) {
      print('getAllInchargeAssigns failed: $e');
    }
    return [];
  }

  static Future<Map<String, dynamic>?> getInchargeAssign(String headInchargeId) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/incharge-assign/$headInchargeId');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 12));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('getInchargeAssign failed: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> saveInchargeAssign(
      String headInchargeId, List<int> inchargeIds, List<String> inchargeNames) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/incharge-assign/$headInchargeId');
    try {
      final body = {'incharge_ids': inchargeIds, 'incharge_names': inchargeNames};
      final response = await http
          .post(url, headers: _authHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      final status = response.statusCode;
      if (status >= 200 && status < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      if (status == 422) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return {'errors': decoded['errors'] ?? decoded['message'] ?? 'Validation failed'};
      }
    } catch (e) {
      print('saveInchargeAssign failed: $e');
    }
    return null;
  }

  static Future<bool> deleteInchargeAssign(String headInchargeId) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/incharge-assign/$headInchargeId');
    try {
      final response = await http.delete(url, headers: _authHeaders).timeout(const Duration(seconds: 12));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('deleteInchargeAssign failed: $e');
      return false;
    }
  }

  // ── Attendance (employee) ─────────────────────────────────────────────────

  static Future<String?> uploadAttendancePhoto(String filePath) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/attendance/upload-photo');
    try {
      final req = http.MultipartRequest('POST', url)
        ..headers['Accept'] = 'application/json'
        ..headers['Authorization'] = 'Bearer ${UserService.token}'
        ..files.add(await http.MultipartFile.fromPath('image', filePath));

      final streamed = await req.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['path'] != null) {
          return decoded['path'].toString();
        }
      }
      print('uploadAttendancePhoto unexpected status ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('uploadAttendancePhoto error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> attendancePunchIn({
    String? lateReason,
    String? earlyInReason,
    String? punchInPhoto,
    Map<String, dynamic>? punchInLocation,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/attendance/punch-in');
    try {
      final body = <String, dynamic>{
        if (lateReason     != null) 'late_reason':       lateReason,
        if (earlyInReason  != null) 'early_in_reason':   earlyInReason,
        if (punchInPhoto   != null) 'punch_in_photo':    punchInPhoto,
        if (punchInLocation != null) 'punch_in_location': punchInLocation,
      };
      final response = await http
          .post(url, headers: _authHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      print('attendancePunchIn failed ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('attendancePunchIn error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> attendancePunchOut({
    String? earlyReason,
    int workMinutes = 0,
    int breakMinutes = 0,
    String? punchOutPhoto,
    Map<String, dynamic>? punchOutLocation,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/attendance/punch-out');
    try {
      final body = <String, dynamic>{
        'total_work_minutes':  workMinutes,
        'total_break_minutes': breakMinutes,
        if (earlyReason != null)      'early_out_reason':    earlyReason,
        if (punchOutPhoto != null)    'punch_out_photo':     punchOutPhoto,
        if (punchOutLocation != null) 'punch_out_location':  punchOutLocation,
      };
      final response = await http
          .post(url, headers: _authHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      print('attendancePunchOut failed ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('attendancePunchOut error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> attendanceConfirmPunch({
    required String type, // 'in' | 'out'
    String? photo,
    Map<String, dynamic>? location,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/attendance/confirm-punch');
    try {
      final body = <String, dynamic>{
        'type': type,
        if (photo != null)    'photo':    photo,
        if (location != null) 'location': location,
      };
      final response = await http
          .post(url, headers: _authHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      print('attendanceConfirmPunch failed ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('attendanceConfirmPunch error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> attendanceBreak({
    required String type,
    required String action,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/attendance/break');
    try {
      final response = await http
          .post(url, headers: _authHeaders, body: jsonEncode({'type': type, 'action': action}))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      print('attendanceBreak failed ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('attendanceBreak error: $e');
    }
    return null;
  }

  /// Returns {'success', 'data': attendance_record|null, 'settings': {punch_in_time, punch_out_time, grace_minutes}}
  static Future<Map<String, dynamic>?> attendanceToday() async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/attendance/today');
    try {
      final response = await http
          .get(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('attendanceToday error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>> attendanceHistory({int page = 1}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/attendance/history')
        .replace(queryParameters: {'page': page.toString()});
    try {
      final response = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('attendanceHistory error: $e');
    }
    return {'success': false, 'data': <dynamic>[]};
  }

  // ── Attendance (admin) ────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> adminAttendanceForEmployee(
    String employeeMobile, {
    int page = 1,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/admin/attendance/$employeeMobile')
        .replace(queryParameters: {'page': page.toString()});
    try {
      final response = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('adminAttendanceForEmployee error: $e');
    }
    return {'success': false, 'data': <dynamic>[]};
  }

  static Future<bool> adminAttendanceApprove(int id, {String? notes}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/admin/attendance/$id/approve');
    try {
      final response = await http
          .post(url, headers: _authHeaders, body: jsonEncode({'admin_notes': notes ?? ''}))
          .timeout(const Duration(seconds: 15));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('adminAttendanceApprove error: $e');
      return false;
    }
  }

  static Future<bool> adminAttendanceReject(int id, {String? notes}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/admin/attendance/$id/reject');
    try {
      final response = await http
          .post(url, headers: _authHeaders, body: jsonEncode({'admin_notes': notes ?? ''}))
          .timeout(const Duration(seconds: 15));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('adminAttendanceReject error: $e');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> adminGetAttendanceSettings(String employeeMobile) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/admin/attendance/settings/$employeeMobile');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 12));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded['data'] is Map) return Map<String, dynamic>.from(decoded['data'] as Map);
      }
    } catch (e) {
      print('adminGetAttendanceSettings error: $e');
    }
    return null;
  }

  static Future<bool> adminUpdateAttendanceSettings(
    String employeeMobile, {
    required String punchIn,
    required String punchOut,
    required int graceMinutes,
    bool approvalRequired = true,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/admin/attendance/settings/$employeeMobile');
    try {
      final body = {
        'punch_in_time':     punchIn,
        'punch_out_time':    punchOut,
        'grace_minutes':     graceMinutes,
        'approval_required': approvalRequired,
      };
      final response = await http
          .put(url, headers: _authHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('adminUpdateAttendanceSettings error: $e');
      return false;
    }
  }

  static Future<int> adminPendingCount() async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/admin/attendance/pending-count');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        return (decoded['count'] as int?) ?? 0;
      }
    } catch (e) {
      print('adminPendingCount error: $e');
    }
    return 0;
  }

  static Future<Map<String, dynamic>> adminPendingList({int page = 1}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/admin/attendance/pending')
        .replace(queryParameters: {'page': page.toString()});
    try {
      final response = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('adminPendingList error: $e');
    }
    return {'success': false, 'data': <dynamic>[]};
  }
}
