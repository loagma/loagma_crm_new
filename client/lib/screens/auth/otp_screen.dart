import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:go_router/go_router.dart';

import '../../services/api_service.dart';
import '../../services/user_service.dart';

class OtpScreen extends StatefulWidget {
  final String contactNumber;

  const OtpScreen({super.key, required this.contactNumber});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpController = TextEditingController();
  bool _isLoading = false;
  int _resendSeconds = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() => _resendSeconds = 30);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_resendSeconds == 0) {
        t.cancel();
      } else {
        if (mounted) setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _resendOtp() async {
    if (_resendSeconds > 0) return;
    try {
      final res = await ApiService.sendOtp(widget.contactNumber);
      if (res['success'] == true) {
        Fluttertoast.showToast(
            msg: 'OTP resent', backgroundColor: Colors.green);
        _startResendTimer();
      } else {
        Fluttertoast.showToast(
            msg: res['message'] ?? 'Failed to resend',
            backgroundColor: Colors.red);
      }
    } catch (_) {
      Fluttertoast.showToast(
          msg: 'Network error', backgroundColor: Colors.red);
    }
  }

  Future<void> _verifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length < 4) {
      Fluttertoast.showToast(msg: 'Enter 4-digit OTP');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final res = await ApiService.verifyOtp(widget.contactNumber, otp);
      if (!mounted) return;

      if (res['success'] == true) {
        await UserService.loginFromApi(res);
        final role = UserService.currentRole;
        if (!mounted) return;
        if (role == null || role.isEmpty) {
          context.go('/no-role');
        } else {
          context.go('/dashboard/$role');
        }
      } else {
        Fluttertoast.showToast(
          msg: res['message'] ?? 'Invalid OTP',
          backgroundColor: Colors.red,
        );
      }
    } catch (e) {
      Fluttertoast.showToast(
          msg: 'Error: $e', backgroundColor: Colors.red);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

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
                    offset: Offset(0, 2))
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline,
                    size: 80, color: Color(0xFFD7BE69)),
                const SizedBox(height: 20),
                const Text(
                  'Enter OTP',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFD7BE69),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'OTP sent to ${widget.contactNumber}',
                  style: const TextStyle(fontSize: 14, color: Colors.black54),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(
                    fontSize: 28,
                    letterSpacing: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '- - - -',
                    hintStyle: const TextStyle(color: Colors.black26),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onSubmitted: (_) => _verifyOtp(),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD7BE69),
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _isLoading ? null : _verifyOtp,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          'Verify OTP',
                          style: TextStyle(fontSize: 16, color: Colors.white),
                        ),
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: _resendSeconds == 0 ? _resendOtp : null,
                  child: Text(
                    _resendSeconds > 0
                        ? 'Resend OTP in ${_resendSeconds}s'
                        : 'Resend OTP',
                    style: TextStyle(
                      fontSize: 14,
                      color: _resendSeconds == 0
                          ? const Color(0xFFD7BE69)
                          : Colors.grey,
                      fontWeight: _resendSeconds == 0
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text(
                    'Change Number',
                    style: TextStyle(color: Colors.grey),
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
