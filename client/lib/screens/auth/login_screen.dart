import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../services/api_service.dart';
import '../../services/api_config.dart';
import '../../services/user_service.dart';
import 'package:flutter/services.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  static const String _rolesEndpoint = '/masters/roles';

  bool isLoading = false;
  bool isLoadingRoles = false;
  String? _rolesLoadDebugMessage;

  bool showDevMode = kDebugMode; // Auto enabled for debug builds
  String? selectedDevRole;
  List<Map<String, dynamic>> roles = [];

  int logoTapCount = 0;
  Timer? _tapResetTimer;

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      _loadRoles();
    }
  }

  @override
  void dispose() {
    _tapResetTimer?.cancel();
    super.dispose();
  }

  // ----------------------------------------------------------------
  // DEV MODE: Tap logo 5 times to enable debug login
  // ----------------------------------------------------------------
  void _onLogoTap() {
    logoTapCount++;

    _tapResetTimer?.cancel();
    _tapResetTimer = Timer(const Duration(seconds: 3), () {
      setState(() => logoTapCount = 0);
    });

    if (logoTapCount >= 5 && !showDevMode) {
      setState(() => showDevMode = true);
      _loadRoles();

      Fluttertoast.showToast(
        msg: "Dev Mode Enabled! 🔧",
        backgroundColor: Colors.green,
      );
    }
  }

  // ----------------------------------------------------------------
  // LOAD ROLES FOR DEV MODE
  // ----------------------------------------------------------------
  Future<void> _loadRoles() async {
    setState(() {
      isLoadingRoles = true;
      _rolesLoadDebugMessage = null;
    });

    try {
      final url = Uri.parse('${ApiConfig.baseUrl}$_rolesEndpoint');
      final response = await http
          .get(url, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final roleData = data['data'];
        if (roleData is! List) {
          throw const FormatException('Invalid role payload shape');
        }

        setState(() {
          roles = List<Map<String, dynamic>>.from(roleData);
          isLoadingRoles = false;
          _rolesLoadDebugMessage = kDebugMode
              ? 'Role API OK (${response.statusCode}) $url'
              : null;
        });
      } else if (response.statusCode == 401) {
        setState(() {
          isLoadingRoles = false;
          _rolesLoadDebugMessage = kDebugMode
              ? 'Role API unauthorized (${response.statusCode}) $url'
              : null;
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Role API protected unexpectedly (401).'),
            backgroundColor: Colors.red,
          ),
        );
      } else {
        setState(() {
          isLoadingRoles = false;
          _rolesLoadDebugMessage = kDebugMode
              ? 'Role API failed (${response.statusCode}) $url'
              : null;
        });
      }
    } on TimeoutException catch (_) {
      setState(() {
        isLoadingRoles = false;
        _rolesLoadDebugMessage = kDebugMode
            ? 'Role API timeout at ${ApiConfig.baseUrl}$_rolesEndpoint'
            : null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Cannot reach backend (timeout while loading roles)."),
          backgroundColor: Colors.red,
        ),
      );
    } on FormatException catch (_) {
      setState(() {
        isLoadingRoles = false;
        _rolesLoadDebugMessage = kDebugMode
            ? 'Role API contract mismatch at ${ApiConfig.baseUrl}$_rolesEndpoint'
            : null;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Role API contract mismatch."),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      setState(() {
        isLoadingRoles = false;
        _rolesLoadDebugMessage = kDebugMode
            ? 'Role API network/error at ${ApiConfig.baseUrl}$_rolesEndpoint'
            : null;
      });
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Cannot reach backend while loading roles: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // ----------------------------------------------------------------
  // SEND OTP LOGIN
  // ----------------------------------------------------------------
  Future<void> handleSendOtp() async {
    final contactNumber = _phoneController.text.trim().replaceAll(
      RegExp(r'[^\d+]'),
      '',
    );

    if (contactNumber.isEmpty) {
      Fluttertoast.showToast(msg: "Please enter your contact number");
      return;
    }

    setState(() => isLoading = true);

    try {
      final response = await ApiService.sendOtp(contactNumber);

      if (!mounted) return;
      setState(() => isLoading = false);

      if (response['success'] == true) {
        Fluttertoast.showToast(msg: response['message'] ?? "OTP sent");

        context.push(
          '/otp',
          extra: {
            'contactNumber': contactNumber,
            'isNewUser': response['isNewUser'] ?? false,
          },
        );
      } else {
        final errorMsg = response['message'] ?? "Error";
        final isNotFound = errorMsg.toLowerCase().contains('not found') ||
                          errorMsg.toLowerCase().contains('no user') ||
                          errorMsg.toLowerCase().contains('invalid');

        Fluttertoast.showToast(
          msg: isNotFound ? "Phone number not found" : errorMsg,
          backgroundColor: Colors.red,
        );
      }
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
      Fluttertoast.showToast(
        msg: "Phone number not found",
        backgroundColor: Colors.red,
      );
    }
  }

  // ----------------------------------------------------------------
  // DEV MODE: DIRECT LOGIN WITHOUT OTP (with user lookup)
  // ----------------------------------------------------------------
  Future<void> _devModeLogin() async {
    if (selectedDevRole == null) return;

    setState(() => isLoading = true);

    try {
      // Try to find a real user with this role
      final url = Uri.parse('${ApiConfig.baseUrl}/api/user/get-all');
      final response = await http
          .get(url, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final users = List<Map<String, dynamic>>.from(data['data']);

          // Find first user with selected role
          final userWithRole = users.firstWhere(
            (user) =>
                user['role']?.toString().toLowerCase() ==
                selectedDevRole!.toLowerCase(),
            orElse: () => {},
          );

          if (userWithRole.isNotEmpty) {
            // Save real user data
            await UserService.loginFromApi({
              'success': true,
              'data': {
                'id': userWithRole['id'],
                'role': selectedDevRole,
                'contactNumber': userWithRole['contactNumber'] ?? '9999999999',
                'name': userWithRole['name'] ?? 'Dev User',
              },
              'token': 'dev_mode_token',
            });

            if (mounted) {
              Fluttertoast.showToast(
                msg: "Dev Login: ${userWithRole['name']}",
                backgroundColor: Colors.green,
              );
              context.go('/dashboard/$selectedDevRole');
            }
            return;
          }
        }
      }

      // Fallback: Create fake session if no user found
      await UserService.login(
        role: selectedDevRole!,
        contactNumber: "9999999999",
      );

      if (mounted) {
        Fluttertoast.showToast(
          msg: "Dev Mode: No real user found, using fake session",
          backgroundColor: Colors.orange,
        );
        context.go('/dashboard/$selectedDevRole');
      }
    } catch (e) {
      if (kDebugMode) print('Dev login error: $e');

      // Fallback on error
      await UserService.login(
        role: selectedDevRole!,
        contactNumber: "9999999999",
      );

      if (mounted) {
        context.go('/dashboard/$selectedDevRole');
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  // ----------------------------------------------------------------
  // UI
  // ----------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD7BE69),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(25),
          child: Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(25),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _onLogoTap,
                  child: Image.asset(
                    'assets/logo1.png',
                    width: 120,
                    height: 120,
                  ),
                ),

                const SizedBox(height: 20),
                const Text(
                  "Login",
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD7BE69),
                  ),
                ),

                const SizedBox(height: 30),

                // Phone Input
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: InputDecoration(
                    hintText: "Enter Phone Number",
                    prefixIcon: const Icon(
                      Icons.phone_android,
                      color: Color(0xFFD7BE69),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Next Button
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD7BE69),
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: isLoading ? null : handleSendOtp,
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "Next",
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                ),

                // ------------------------------------------------
                // DEV MODE SECTION
                // ------------------------------------------------
                if (showDevMode) ...[
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 10),

                  const Text(
                    'Dev Mode - Select Role',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),

                  const SizedBox(height: 10),

                  if (isLoadingRoles)
                    Column(
                      children: const [
                        CircularProgressIndicator(color: Color(0xFFD7BE69)),
                        SizedBox(height: 10),
                        Text(
                          'Loading roles...',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    )
                  else if (roles.isEmpty)
                    Column(
                      children: [
                        const Text(
                          'Failed to load roles',
                          style: TextStyle(fontSize: 14, color: Colors.red),
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton(
                          onPressed: _loadRoles,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFD7BE69),
                          ),
                          child: const Text("Retry"),
                        ),
                        if (kDebugMode && _rolesLoadDebugMessage != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            _rolesLoadDebugMessage!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ],
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue: selectedDevRole,
                      items: roles.map((role) {
                        return DropdownMenuItem<String>(
                          value: role['name'],
                          child: Text(role['name']),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() => selectedDevRole = value);
                      },
                      decoration: InputDecoration(
                        hintText: "Select a role",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),

                  const SizedBox(height: 10),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.grey[700],
                      minimumSize: const Size(double.infinity, 45),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: (selectedDevRole == null || isLoadingRoles)
                        ? null
                        : _devModeLogin,
                    child: const Text(
                      'Skip Login (Dev Mode)',
                      style: TextStyle(fontSize: 14, color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
