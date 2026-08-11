import 'dart:convert';
import 'dart:typed_data';
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
    int attempts = 0;
    while (true) {
      attempts++;
      try {
        final response = await http
            .post(url, headers: _headers, body: jsonEncode({'mobile': mobile}))
            .timeout(const Duration(seconds: 30));
        if (response.statusCode >= 400 && response.statusCode < 500) {
          // Client error (e.g. mobile not registered) — not retryable.
          return jsonDecode(response.body) as Map<String, dynamic>;
        }
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
        if (response.statusCode >= 400 && response.statusCode < 500) {
          // Client error (e.g. invalid/expired OTP) — not retryable.
          return jsonDecode(response.body) as Map<String, dynamic>;
        }
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

    try {
      final response = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 30));
      final decoded = jsonDecode(response.body);

      if (decoded is Map && decoded.containsKey('data')) {
        final data = decoded['data'];
        if (data is List) {
          return List<Map<String, dynamic>>.from(data.map((e) => Map<String, dynamic>.from(e as Map)));
        }
      } else if (decoded is List) {
        return List<Map<String, dynamic>>.from(decoded.map((e) => Map<String, dynamic>.from(e as Map)));
      }
    } catch (e) {
      print('getEmployees failed for $uri: $e');
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
    String? createdBy,
    String? status,
  }) async {
    final params = <String, dynamic>{
      if (q != null && q.isNotEmpty) 'q': q,
      if (page != null) 'page': page.toString(),
      if (perPage != null) 'per_page': perPage.toString(),
      if (pincode != null && pincode.isNotEmpty) 'pincode': pincode,
      if (createdBy != null && createdBy.isNotEmpty) 'created_by': createdBy,
      if (status != null && status.isNotEmpty) 'status': status,
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

  /// Fetch customers from user table, optionally filtered by pincodes.
  static Future<List<Map<String, dynamic>>> getCustomers({List<String>? pincodes}) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/customers');
    var finalUri = uri;
    if (pincodes != null && pincodes.isNotEmpty) {
      final params = <String, List<String>>{'pincodes[]': pincodes};
      finalUri = uri.replace(queryParameters: params);
    }
    try {
      final response = await http.get(finalUri, headers: _authHeaders).timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final data = (decoded['data'] as List?) ?? [];
        return data.cast<Map<String, dynamic>>();
      }
      print('getCustomers status ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('getCustomers error: $e');
    }
    return [];
  }

  /// Fetch a page of orders (real `orders` table, joined with buyer/admin info).
  static Future<Map<String, dynamic>> getOrders({
    int page = 1,
    int perPage = 20,
    String? q,
    String? paymentStatus,
    String? buyerUserId,
  }) async {
    final params = <String, String>{
      'page':     page.toString(),
      'per_page': perPage.toString(),
      if (q != null && q.isNotEmpty) 'q': q,
      if (paymentStatus != null && paymentStatus.isNotEmpty) 'payment_status': paymentStatus,
      if (buyerUserId != null && buyerUserId.isNotEmpty) 'buyer_userid': buyerUserId,
    };
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/orders').replace(queryParameters: params);
    try {
      final response = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 20));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      print('getOrders status ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('getOrders error: $e');
    }
    return {'success': false, 'data': <dynamic>[]};
  }

  /// Fetch full detail (owner, driver, items) for one order.
  static Future<Map<String, dynamic>?> getOrderDetail(String orderId) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/orders/$orderId');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 20));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded['success'] == true) return decoded['data'] as Map<String, dynamic>;
      }
      print('getOrderDetail status ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('getOrderDetail error: $e');
    }
    return null;
  }

  /// Aggregated per-product purchase history for one buyer across all their orders.
  static Future<List<Map<String, dynamic>>> getOwnerProductHistory(String buyerUserId) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/orders/owner/$buyerUserId/products');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 20));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final data = (decoded['data'] as List?) ?? [];
        return data.cast<Map<String, dynamic>>();
      }
      print('getOwnerProductHistory status ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('getOwnerProductHistory error: $e');
    }
    return [];
  }

  /// Search the real product catalog (`product` table) — used to pick a
  /// genuine product_id for a Sales Order line item.
  /// Returns null (not []) on failure, so callers can tell "search failed"
  /// apart from "genuinely no matching products".
  static Future<List<Map<String, dynamic>>?> searchProducts(String q) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/products/search').replace(queryParameters: {'q': q});
    try {
      final response = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 20));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final data = (decoded['data'] as List?) ?? [];
        return data.cast<Map<String, dynamic>>();
      }
      print('searchProducts status ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('searchProducts error: $e');
    }
    return null;
  }

  /// Create a real Sales Order (draft/`pending` state — see SalesOrderController).
  /// Only works when [buyerUserId] is a real registered customer (a `user` row);
  /// returns null (with the server's message logged) otherwise.
  static Future<Map<String, dynamic>?> createSalesOrder({
    required String buyerUserId,
    required List<Map<String, dynamic>> items,
    double discount = 0,
    double deliveryCharge = 0,
    String? narration,
    String? department,
    String? areaName,
    String? timeSlot,
    String? documentDate,
    Map<String, dynamic>? deliveryInfo,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/sales-orders');
    try {
      final response = await http
          .post(
            url,
            headers: _authHeaders,
            body: jsonEncode({
              'buyer_userid':     buyerUserId,
              'items':            items,
              'discount':         discount,
              'delivery_charge':  deliveryCharge,
              if (narration != null)     'narration':     narration,
              if (department != null)    'department':    department,
              if (areaName != null)      'area_name':     areaName,
              if (timeSlot != null)      'time_slot':     timeSlot,
              if (documentDate != null)  'document_date': documentDate,
              if (deliveryInfo != null)  'delivery_info': deliveryInfo,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300 && decoded['success'] == true) {
        return decoded['data'] as Map<String, dynamic>?;
      }
      print('createSalesOrder failed: ${decoded['message'] ?? response.body}');
    } catch (e) {
      print('createSalesOrder error: $e');
    }
    return null;
  }

  /// Persist an add/edit/remove of items against an EXISTING order (server
  /// only allows this while the order is still `pending` — see
  /// SalesOrderController::updateItems). Returns the raw decoded response
  /// (not just `data`) so callers can show the server's own rejection
  /// message, e.g. when the order is already invoiced/dispatched.
  static Future<Map<String, dynamic>> updateOrderItems(String orderId, List<Map<String, dynamic>> items) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/orders/$orderId/items');
    try {
      final response = await http
          .put(url, headers: _authHeaders, body: jsonEncode({'items': items}))
          .timeout(const Duration(seconds: 20));
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      print('updateOrderItems error: $e');
      return {'success': false, 'message': 'Network error — check your connection.'};
    }
  }

  /// Non-authoritative preview of the order_id the next Sales Order would get
  /// (not reserved — the real id is assigned at create time).
  static Future<int?> getNextSalesOrderId() async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/sales-orders/next-order-id');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final data = decoded['data'] as Map<String, dynamic>?;
        return data?['next_order_id'] as int?;
      }
      print('getNextSalesOrderId status ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('getNextSalesOrderId error: $e');
    }
    return null;
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

  /// Pending-approval queue for admin/teleadmin (mirrors adminPendingList).
  static Future<Map<String, dynamic>> getPendingLeadAccounts({
    int page = 1,
    String? q,
    String? createdBy,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/lead-accounts/pending').replace(queryParameters: {
      'page': page.toString(),
      if (q != null && q.isNotEmpty) 'q': q,
      if (createdBy != null && createdBy.isNotEmpty) 'created_by': createdBy,
    });
    try {
      final response = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('getPendingLeadAccounts error: $e');
    }
    return {'success': false, 'data': <dynamic>[]};
  }

  /// Distinct creators with at least one pending lead — populates the
  /// "assigned by" filter dropdown on the pending-leads screen.
  static Future<List<Map<String, dynamic>>> getPendingLeadCreators() async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/lead-accounts/pending-creators');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final data = (decoded['data'] as List? ?? []);
        return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      print('getPendingLeadCreators error: $e');
    }
    return <Map<String, dynamic>>[];
  }

  /// Count of leads awaiting review (for badge/summary use).
  static Future<int> getPendingLeadAccountsCount() async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/lead-accounts/pending-count');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        return (decoded['count'] as int?) ?? 0;
      }
    } catch (e) {
      print('getPendingLeadAccountsCount error: $e');
    }
    return 0;
  }

  /// Approve a pending lead — converts it into a real customer server-side.
  static Future<Map<String, dynamic>?> approveLeadAccount(String id, {String? notes}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/lead-accounts/$id/approve');
    try {
      final response = await http
          .post(url, headers: _authHeaders, body: jsonEncode({'verification_notes': notes ?? ''}))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'message': _errorMessage(response)};
    } catch (e) {
      print('approveLeadAccount error: $e');
      return null;
    }
  }

  /// Reject a pending lead — rejection notes are required (the message the
  /// creator sees telling them what to fix before resubmitting).
  static Future<Map<String, dynamic>?> rejectLeadAccount(String id, {required String notes}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/lead-accounts/$id/reject');
    try {
      final response = await http
          .post(url, headers: _authHeaders, body: jsonEncode({'rejection_notes': notes}))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      return {'success': false, 'message': _errorMessage(response)};
    } catch (e) {
      print('rejectLeadAccount error: $e');
      return null;
    }
  }

  static String _errorMessage(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map && decoded['message'] != null) return decoded['message'].toString();
    } catch (_) {}
    return 'Request failed';
  }

  /// Upload lead image and return stored relative URL path (e.g. /storage/leads/..)
  /// Takes raw bytes (instead of a file path) so this works on web too, where
  /// the picked file path is a blob URL that cannot be read via dart:io.
  static Future<String?> uploadLeadImage(List<int> bytes, String filename) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/lead-accounts/upload-image');
    try {
      final req = http.MultipartRequest('POST', url)
        ..headers['Accept'] = 'application/json'
        ..headers['Authorization'] = 'Bearer ${UserService.token}'
        ..files.add(http.MultipartFile.fromBytes('image', bytes, filename: filename));

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
      print('uploadLeadImage failed for $url: $e');
    }
    return null;
  }

  // ── Call Logs ──────────────────────────────────────────────────────────────

  /// Save a post-call log entry. Returns the created record or null on error.
  static Future<Map<String, dynamic>?> createCallLog(Map<String, dynamic> body) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/call-logs');
    try {
      final response = await http
          .post(url, headers: _authHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 201) return decoded['data'] as Map<String, dynamic>?;
      print('createCallLog unexpected status ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('createCallLog failed: $e');
    }
    return null;
  }

  /// Fetch call logs for the current employee. Optionally filter by [accountId].
  static Future<List<Map<String, dynamic>>> getCallLogs({String? accountId}) async {
    var uri = Uri.parse('${ApiConfig.baseUrl}/api/call-logs');
    if (accountId != null && accountId.isNotEmpty) {
      uri = uri.replace(queryParameters: {'account_id': accountId});
    }
    try {
      final response = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return ((decoded['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      }
    } catch (e) {
      print('getCallLogs failed: $e');
    }
    return [];
  }

  /// Update a call log (reschedule follow-up date / mark callback done).
  static Future<bool> updateCallLog(int id, {String? followUpDate, bool? callbackDone}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/call-logs/$id');
    final body = <String, dynamic>{
      if (followUpDate != null) 'follow_up_date': followUpDate,
      if (callbackDone != null) 'callback_done': callbackDone,
    };
    try {
      final response = await http
          .put(url, headers: _authHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('updateCallLog failed: $e');
    }
    return false;
  }

  // ── Complaints ───────────────────────────────────────────────────────────────

  /// Raise a complaint from the salesman-visit channel. (The telecaller-call
  /// channel raises one implicitly via [createCallLog] with
  /// `call_outcome: 'complaint'` instead — one request creates both rows.)
  static Future<Map<String, dynamic>?> createComplaint({
    required String accountId,
    required String accountType,
    required String category,
    required String description,
    int? beatPlanId,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/complaints');
    try {
      final response = await http
          .post(
            url,
            headers: _authHeaders,
            body: jsonEncode({
              'account_id': accountId,
              'account_type': accountType,
              'category': category,
              'description': description,
              if (beatPlanId != null) 'beat_plan_id': beatPlanId,
            }),
          )
          .timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 201) return decoded['data'] as Map<String, dynamic>?;
      print('createComplaint unexpected status ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('createComplaint failed: $e');
    }
    return null;
  }

  /// Hierarchy-scoped complaint list. Pass [raisedBy] for a "my complaints"
  /// view (always allowed for one's own mobile); pass [assignedTo] for an
  /// "assigned to me" view (works for any role, since a complaint can be
  /// delegated down to a salesman/telecaller); omit both to see everything
  /// visible to the caller's role (admin = all, incharge-type = descendants
  /// + anything assigned to them).
  static Future<Map<String, dynamic>> getComplaints({
    int page = 1,
    String? raisedBy,
    String? assignedTo,
    String? status,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/complaints').replace(queryParameters: {
      'page': page.toString(),
      if (raisedBy != null && raisedBy.isNotEmpty) 'raised_by': raisedBy,
      if (assignedTo != null && assignedTo.isNotEmpty) 'assigned_to': assignedTo,
      if (status != null && status.isNotEmpty) 'status': status,
    });
    try {
      final response = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (e) {
      print('getComplaints failed: $e');
    }
    return {'success': false, 'data': <dynamic>[]};
  }

  /// Update a complaint's status (open/in_progress/resolved/closed), with
  /// optional resolution notes captured when moving to resolved/closed.
  static Future<bool> updateComplaintStatus(int id, {required String status, String? resolutionNotes}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/complaints/$id/status');
    try {
      final response = await http
          .put(
            url,
            headers: _authHeaders,
            body: jsonEncode({
              'status': status,
              if (resolutionNotes != null) 'resolution_notes': resolutionNotes,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('updateComplaintStatus failed: $e');
    }
    return false;
  }

  /// Assign a complaint to a staff mobile — either the caller themself
  /// ("solve it myself") or someone in the caller's own downward hierarchy.
  /// Admins may assign to anyone. Returns null with an error message on
  /// failure (e.g. target isn't in the caller's team).
  static Future<Map<String, dynamic>?> assignComplaint(int id, {required String assignedTo}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/complaints/$id/assign');
    try {
      final response = await http
          .put(url, headers: _authHeaders, body: jsonEncode({'assigned_to': assignedTo}))
          .timeout(const Duration(seconds: 15));
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) return decoded;
      return {'errors': decoded['message'] ?? 'Failed to assign complaint'};
    } catch (e) {
      print('assignComplaint failed: $e');
    }
    return null;
  }

  /// Count of open/in_progress complaints currently assigned to the caller —
  /// used to poll for a "complaint assigned to you" device notification.
  static Future<int> complaintAssignedCount() async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/complaints/assigned-count');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 10));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        return (decoded['count'] as int?) ?? 0;
      }
    } catch (e) {
      print('complaintAssignedCount failed: $e');
    }
    return 0;
  }

  /// Trigger a Knowlarity bridge call: rings the telecaller's own number,
  /// then the customer's, and connects them. Returns the created call-log
  /// record (outcome starts as 'pending' until Knowlarity's webhook lands).
  static Future<Map<String, dynamic>?> triggerKnowlarityCall({
    required String accountId,
    required String accountType,
    required String customerNumber,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/telecaller/call');
    try {
      final response = await http
          .post(
            url,
            headers: _authHeaders,
            body: jsonEncode({
              'account_id': accountId,
              'account_type': accountType,
              'customer_number': customerNumber,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded['data'] as Map<String, dynamic>?;
      }
      print('triggerKnowlarityCall unexpected status ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('triggerKnowlarityCall failed: $e');
    }
    return null;
  }

  /// Poll the live status of one cloud (Knowlarity) call — used right after
  /// [triggerKnowlarityCall] to detect when the completed webhook lands and
  /// to show the current SR/call-log data while the call is in progress.
  static Future<Map<String, dynamic>?> getCallStatus(String callLogId) =>
      _tcGetMap('call-status/$callLogId');

  // ── Telecaller dashboard + modules (live data) ─────────────────────────────

  static Future<Map<String, dynamic>?> _tcGetMap(String path) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/telecaller/$path');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 20));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        if (decoded['data'] is Map) return Map<String, dynamic>.from(decoded['data'] as Map);
      }
    } catch (e) {
      print('telecaller GET $path failed: $e');
    }
    return null;
  }

  static Future<List<Map<String, dynamic>>> _tcGetList(String path) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/telecaller/$path');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 20));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return ((decoded['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      }
    } catch (e) {
      print('telecaller GET $path failed: $e');
    }
    return [];
  }

  /// Aggregated dashboard payload (kpis, outcome_counts, week, funnel, daily_target).
  static Future<Map<String, dynamic>?> getTelecallerDashboard() => _tcGetMap('dashboard');

  /// Today's + overdue callbacks for the current telecaller.
  static Future<List<Map<String, dynamic>>> getTelecallerCallbacks() => _tcGetList('callbacks');

  /// Recent enriched call history for the current telecaller.
  static Future<List<Map<String, dynamic>>> getTelecallerCallHistory() => _tcGetList('call-history');

  /// Hierarchy-scoped call history: admin sees every telecaller, a
  /// teleadmin/incharge sees their own team (via the server's
  /// getDescendantMobiles walk). Pass [mobile] to narrow to one team member;
  /// omit it to get the whole team merged together, newest first.
  static Future<List<Map<String, dynamic>>> getTeamCallHistory({String? mobile}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/telecaller/team-call-history').replace(
      queryParameters: mobile != null ? {'mobile': mobile} : null,
    );
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 20));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        return ((decoded['data'] as List?) ?? []).cast<Map<String, dynamic>>();
      }
      print('getTeamCallHistory failed ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('getTeamCallHistory error: $e');
    }
    return [];
  }

  /// Fetches a call recording's raw audio bytes through the authenticated
  /// backend proxy - the underlying Knowlarity URL 401s without the server's
  /// own API credentials, which no player/browser can attach directly.
  static Future<Uint8List?> fetchCallRecordingBytes(int callLogId) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/telecaller/call-recording/$callLogId');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 30));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return response.bodyBytes;
      }
      print('fetchCallRecordingBytes unexpected status ${response.statusCode}');
    } catch (e) {
      print('fetchCallRecordingBytes failed: $e');
    }
    return null;
  }

  /// Direct URL for saving/downloading a call recording (opened via the OS/
  /// browser, e.g. through url_launcher) - carries the JWT as a query param
  /// since a plain URL open can't attach an Authorization header the way an
  /// authenticated fetch (fetchCallRecordingBytes) can. `download=1` tells the
  /// backend to send Content-Disposition: attachment so it saves as a file
  /// instead of trying to play inline.
  static String callRecordingDownloadUrl(int callLogId) {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/telecaller/call-recording/$callLogId').replace(
      queryParameters: {'download': '1', 'token': UserService.token},
    );
    return uri.toString();
  }

  /// Same authenticated recording URL as [callRecordingDownloadUrl] but
  /// without `download=1` - used as a fallback to open the recording in the
  /// device's own media player/browser when the in-app player can't decode
  /// it (e.g. narrowband/low-bitrate MP3 variants some platform codecs reject).
  static String callRecordingStreamUrl(int callLogId) {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/telecaller/call-recording/$callLogId').replace(
      queryParameters: {'token': UserService.token},
    );
    return uri.toString();
  }

  /// Worklist (leads + customers in my areas) with derived/custom labels.
  static Future<List<Map<String, dynamic>>> getTelecallerWorklist() => _tcGetList('worklist');

  /// Set a custom label (e.g. wrong_number, do_not_call) on an account.
  static Future<bool> setTelecallerLabel(String accountId, String accountType, String label) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/telecaller/label');
    try {
      final response = await http
          .post(url, headers: _authHeaders, body: jsonEncode({
            'account_id': accountId,
            'account_type': accountType,
            'label': label,
          }))
          .timeout(const Duration(seconds: 15));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('setTelecallerLabel failed: $e');
    }
    return false;
  }

  // ── Call scripts (per-telecaller CRUD) ─────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getCallScripts() => _tcGetList('scripts');

  static Future<bool> saveCallScript({int? id, required String title, String? stageLabel, required List<String> lines, int? sortOrder}) async {
    final base = '${ApiConfig.baseUrl}/api/telecaller/scripts';
    final url = Uri.parse(id == null ? base : '$base/$id');
    final body = jsonEncode({
      'title': title,
      if (stageLabel != null) 'stage_label': stageLabel,
      'lines': lines,
      if (sortOrder != null) 'sort_order': sortOrder,
    });
    try {
      final response = await (id == null
              ? http.post(url, headers: _authHeaders, body: body)
              : http.put(url, headers: _authHeaders, body: body))
          .timeout(const Duration(seconds: 15));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('saveCallScript failed: $e');
    }
    return false;
  }

  static Future<bool> deleteCallScript(int id) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/telecaller/scripts/$id');
    try {
      final response = await http.delete(url, headers: _authHeaders).timeout(const Duration(seconds: 15));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('deleteCallScript failed: $e');
    }
    return false;
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
    // Proxy through our backend: api.postalpincode.in has an expired TLS cert
    // and is unreachable from the Flutter web client (no dart:io, browser
    // refuses the bad cert). The server fetches it and returns a normalized
    // { country, state, district, city, areas } shape.
    final url = Uri.parse('${ApiConfig.baseUrl}/api/utils/pincode/$pincode');
    try {
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['success'] != true) return null;
      final data = decoded['data'];
      if (data is! Map) return null;

      return Map<String, dynamic>.from(data);
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
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 30));
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
      final response = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 30));
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

  /// Batch-upload GPS pings captured by TrackingService.
  /// Returns the decoded body on 2xx, {'_status': 401} on auth failure
  /// (so the caller can re-auth or shut down), null on everything else.
  static Future<Map<String, dynamic>?> postPings(
      List<Map<String, dynamic>> pings) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/tracking/ping');
    try {
      final response = await http
          .post(url, headers: _authHeaders, body: jsonEncode({'pings': pings}))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      if (response.statusCode == 401) {
        return {'_status': 401};
      }
      print('postPings failed ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('postPings error: $e');
    }
    return null;
  }

  /// Admin: currently on-duty salesmen with their latest location.
  static Future<Map<String, dynamic>?> getLiveSalesmen() async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/tracking/live');
    try {
      final response = await http
          .get(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      print('getLiveSalesmen failed ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('getLiveSalesmen error: $e');
    }
    return null;
  }

  /// Admin: a salesman's route for today. Pass [since] (last recorded_at)
  /// to fetch only newer points, so the live map appends deltas.
  static Future<Map<String, dynamic>?> getLiveRoute({
    required String mobile,
    String? since,
  }) async {
    final params = <String, String>{
      'mobile': mobile,
      if (since != null) 'since': since,
    };
    final url = Uri.parse('${ApiConfig.baseUrl}/api/tracking/live-route')
        .replace(queryParameters: params);
    try {
      final response = await http
          .get(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      print('getLiveRoute failed ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('getLiveRoute error: $e');
    }
    return null;
  }

  /// Admin: full route + summary for one salesman on one day (history).
  /// One-shot — history screens must NOT poll this.
  static Future<Map<String, dynamic>?> getRouteHistory({
    required String mobile,
    required String date, // yyyy-mm-dd
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/tracking/route')
        .replace(queryParameters: {'mobile': mobile, 'date': date});
    try {
      final response = await http
          .get(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      print('getRouteHistory failed ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('getRouteHistory error: $e');
    }
    return null;
  }

  /// Admin: everyone who was on duty on [date] (yyyy-mm-dd) with their
  /// on-duty window + distance — the date-first history roster.
  /// One-shot — the roster screen must NOT poll this.
  static Future<Map<String, dynamic>?> getRoster({
    required String date, // yyyy-mm-dd
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/tracking/roster')
        .replace(queryParameters: {'date': date});
    try {
      final response = await http
          .get(url, headers: _authHeaders)
          .timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return jsonDecode(response.body) as Map<String, dynamic>;
      }
      print('getRoster failed ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('getRoster error: $e');
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

  /// Fetch every attendance record for [employeeMobile] in a given month
  /// (no pagination) for the calendar view.
  static Future<List<Map<String, dynamic>>> adminAttendanceMonth(
    String employeeMobile,
    int year,
    int month,
  ) async {
    final mm  = month.toString().padLeft(2, '0');
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/admin/attendance/$employeeMobile')
        .replace(queryParameters: {'month': '$year-$mm'});
    try {
      final response = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 15));
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final data = (decoded['data'] as List?) ?? [];
        return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      print('adminAttendanceMonth error: $e');
    }
    return <Map<String, dynamic>>[];
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

  // ── Beat Plan ───────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getMyBeatPlans() async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/beat-plan/my-plans');
    try {
      final res = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 15));
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      print('getMyBeatPlans error: $e');
    }
    return {'success': false, 'data': <dynamic>[]};
  }

  static Future<Map<String, dynamic>?> assignBeatPlan({
    required List<String> accountIds,
    required List<String> accountTypes,  // 'lead' or 'customer' for each account
    required String frequency,           // 'weekly' | 'monthly' | 'n_days' | 'specific_dates' | 'appointment'
    List<String>? days,                  // weekly only
    int? monthDate,                      // monthly only
    List<String>? specificDates,         // specific_dates only (array of YYYY-MM-DD)
    String? appointmentDate,             // appointment only (ISO8601 datetime)
    String? weekAnchorDate,              // weekly only - anchor date for alternate weeks (YYYY-MM-DD)
    int? intervalDays,                   // n_days only
    String? startDate,                   // n_days only (YYYY-MM-DD)
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/beat-plan/assign');
    try {
      final body = <String, dynamic>{
        'account_ids':  accountIds,
        'account_types': accountTypes,
        'frequency':    frequency,
        if (days != null)         'days':          days,
        if (monthDate != null)    'month_date':    monthDate,
        if (specificDates != null) 'specific_dates': specificDates,
        if (appointmentDate != null) 'appointment_date': appointmentDate,
        if (weekAnchorDate != null) 'week_anchor_date': weekAnchorDate,
        if (intervalDays != null) 'interval_days': intervalDays,
        if (startDate != null)    'start_date':    startDate,
      };
      final res = await http.post(url, headers: _authHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      print('assignBeatPlan status ${res.statusCode}: ${res.body}');
    } catch (e) {
      print('assignBeatPlan error: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>> getTodayBeatPlan() async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/beat-plan/today');
    try {
      final res = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 30));
      final decoded = jsonDecode(res.body) as Map<String, dynamic>;
      return decoded;
    } catch (e) {
      print('getTodayBeatPlan error: $e');
    }
    return {'success': false, 'data': <dynamic>[]};
  }

  static Future<Map<String, dynamic>> getWeekBeatPlan({String? date, String? weekOf}) async {
    var uri = Uri.parse('${ApiConfig.baseUrl}/api/beat-plan/week');
    final qp = <String, String>{
      if (date != null) 'date': date,
      if (weekOf != null) 'week_of': weekOf,
    };
    if (qp.isNotEmpty) uri = uri.replace(queryParameters: qp);
    try {
      final res = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 15));
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      print('getWeekBeatPlan error: $e');
    }
    return {'success': false, 'days': <dynamic>{}};
  }

  static Future<Map<String, dynamic>> getBeatPlanStats({
    required List<int> areaIds,
    List<String>? pincodes,
  }) async {
    var uri = Uri.parse('${ApiConfig.baseUrl}/api/beat-plan/stats');
    final extra = [
      ...areaIds.map((id) => 'area_ids[]=$id'),
      if (pincodes != null) ...pincodes.map((p) => 'pincodes[]=${Uri.encodeQueryComponent(p)}'),
    ].join('&');
    if (extra.isNotEmpty) uri = Uri.parse('${uri.toString()}?$extra');
    try {
      final res = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 15));
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (e) {
      print('getBeatPlanStats error: $e');
    }
    return {'success': false, 'data': <dynamic>{}};
  }

  static Future<bool> unassignBeatPlanBulk(List<String> accountIds) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/beat-plan/unassign-bulk');
    try {
      final res = await http.post(url,
          headers: _authHeaders,
          body: jsonEncode({'account_ids': accountIds}))
          .timeout(const Duration(seconds: 15));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      print('unassignBeatPlanBulk error: $e');
    }
    return false;
  }

  static Future<bool> deleteBeatPlan(int id) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/beat-plan/$id');
    try {
      final res = await http.delete(url, headers: _authHeaders).timeout(const Duration(seconds: 12));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      print('deleteBeatPlan error: $e');
    }
    return false;
  }

  // ── Order Funnel ─────────────────────────────────────────────────────────

  /// Fetch active order funnel stages from order_funnel_crm.
  /// Returns list of {id, slug, name, sort_order}.
  static Future<List<Map<String, dynamic>>> getOrderFunnels() async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/order-funnels');
    try {
      final res = await http.get(url, headers: _authHeaders).timeout(const Duration(seconds: 12));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map && decoded['data'] is List) {
          return List<Map<String, dynamic>>.from(
            (decoded['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
        }
      }
    } catch (e) {
      print('getOrderFunnels error: $e');
    }
    return [];
  }

  /// Fetch the latest saved funnel response for an account (to prefill the form).
  static Future<Map<String, dynamic>?> getOrderFunnelResponse(String accountId) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/order-funnels/response')
        .replace(queryParameters: {'account_id': accountId});
    try {
      final res = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 12));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        if (decoded['data'] is Map) return Map<String, dynamic>.from(decoded['data'] as Map);
      }
    } catch (e) {
      print('getOrderFunnelResponse error: $e');
    }
    return null;
  }

  /// All saved order funnel responses for an account (Transaction tab).
  static Future<List<Map<String, dynamic>>> getOrderFunnelResponses(String accountId) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/api/order-funnels/responses')
        .replace(queryParameters: {'account_id': accountId});
    try {
      final res = await http.get(uri, headers: _authHeaders).timeout(const Duration(seconds: 12));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        if (decoded['data'] is List) {
          return (decoded['data'] as List)
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      }
    } catch (e) {
      print('getOrderFunnelResponses error: $e');
    }
    return [];
  }

  /// Upload a single order funnel image (raw bytes) and return its stored
  /// relative path. Bytes are used (instead of a file path) so this works on
  /// web too, where the picked file path is a blob URL that cannot be read.
  static Future<String?> uploadOrderFunnelImage(List<int> bytes, String filename) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/order-funnels/upload-image');
    try {
      final req = http.MultipartRequest('POST', url)
        ..headers['Accept'] = 'application/json'
        ..headers['Authorization'] = 'Bearer ${UserService.token}'
        ..files.add(http.MultipartFile.fromBytes('image', bytes, filename: filename));

      final streamed = await req.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['path'] != null) {
          return decoded['path'].toString();
        }
      }
      print('uploadOrderFunnelImage unexpected status ${response.statusCode}: ${response.body}');
    } catch (e) {
      print('uploadOrderFunnelImage failed for $url: $e');
    }
    return null;
  }

  /// Save an order funnel response for an account.
  static Future<Map<String, dynamic>?> saveOrderFunnelResponse({
    required String accountId,
    required String funnelSlug,
    String? accountType,
    int? beatPlanId,
    String? generalNotes,
    String? notesRelatedTo,
    String? visitInAt,
    String? visitOutAt,
    int? durationSeconds,
    List<String>? images,
  }) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/order-funnels/response');
    try {
      final body = <String, dynamic>{
        'account_id':  accountId,
        'funnel_slug': funnelSlug,
        if (accountType != null)    'account_type':     accountType,
        if (beatPlanId != null)     'beat_plan_id':     beatPlanId,
        if (generalNotes != null)   'general_notes':    generalNotes,
        if (notesRelatedTo != null) 'notes_related_to': notesRelatedTo,
        if (visitInAt != null)      'visit_in_at':      visitInAt,
        if (visitOutAt != null)     'visit_out_at':     visitOutAt,
        if (durationSeconds != null)'duration_seconds': durationSeconds,
        if (images != null)         'images':           images,
      };
      final res = await http.post(url, headers: _authHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        if (decoded['data'] is Map) return Map<String, dynamic>.from(decoded['data'] as Map);
        return decoded;
      }
      if (res.statusCode == 422) {
        final decoded = jsonDecode(res.body) as Map<String, dynamic>;
        return {'errors': decoded['errors'] ?? decoded['message'] ?? 'Validation failed'};
      }
      print('saveOrderFunnelResponse unexpected status ${res.statusCode}: ${res.body}');
    } catch (e) {
      print('saveOrderFunnelResponse error: $e');
    }
    return null;
  }

  static Future<bool> recordBeatPlanVisit(int id, {String? notes}) async {
    final url = Uri.parse('${ApiConfig.baseUrl}/api/beat-plan/$id/visit');
    try {
      final body = <String, dynamic>{
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      };
      final res = await http.post(url, headers: _authHeaders, body: jsonEncode(body))
          .timeout(const Duration(seconds: 12));
      return res.statusCode >= 200 && res.statusCode < 300;
    } catch (e) {
      print('recordBeatPlanVisit error: $e');
    }
    return false;
  }
}
