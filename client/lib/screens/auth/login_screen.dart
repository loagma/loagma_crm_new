import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import 'package:flutter/services.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();

  bool isLoading = false;

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
                Image.asset(
                  'assets/logo1.png',
                  width: 120,
                  height: 120,
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
                  textInputAction: TextInputAction.done,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  onSubmitted: (_) {
                    if (!isLoading) handleSendOtp();
                  },
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
