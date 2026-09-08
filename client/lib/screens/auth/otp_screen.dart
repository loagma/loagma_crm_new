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
  static const int _otpLength = 4;
  final List<TextEditingController> _digitControllers =
      List.generate(_otpLength, (_) => TextEditingController());
  final List<FocusNode> _digitFocusNodes =
      List.generate(_otpLength, (_) => FocusNode());
  final List<FocusNode> _keyFocusNodes =
      List.generate(_otpLength, (_) => FocusNode());
  bool _isLoading = false;

  String get _otp => _digitControllers.map((c) => c.text).join();
  int _resendSeconds = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _digitFocusNodes.first.requestFocus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in _digitControllers) {
      c.dispose();
    }
    for (final f in _digitFocusNodes) {
      f.dispose();
    }
    for (final f in _keyFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _onDigitChanged(int index, String value) {
    if (value.length > 1) {
      // Handle paste / autofill of the whole code
      final digits = value.replaceAll(RegExp(r'[^\d]'), '');
      for (int i = 0; i < _otpLength; i++) {
        _digitControllers[i].text = i < digits.length ? digits[i] : '';
      }
      final next =
          digits.length >= _otpLength ? _otpLength - 1 : digits.length;
      _digitFocusNodes[next].requestFocus();
      setState(() {});
      if (_otp.length == _otpLength) _verifyOtp();
      return;
    }

    if (value.isNotEmpty && index < _otpLength - 1) {
      _digitFocusNodes[index + 1].requestFocus();
    } else if (value.isEmpty && index > 0) {
      _digitFocusNodes[index - 1].requestFocus();
    }
    setState(() {});
    if (_otp.length == _otpLength) _verifyOtp();
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
        for (final c in _digitControllers) {
          c.clear();
        }
        _digitFocusNodes.first.requestFocus();
        setState(() {});
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
    final otp = _otp.trim();
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_otpLength, (i) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: SizedBox(
                        width: 60,
                        child: KeyboardListener(
                          focusNode: _keyFocusNodes[i],
                          onKeyEvent: (event) {
                            if (event is KeyDownEvent &&
                                event.logicalKey ==
                                    LogicalKeyboardKey.backspace &&
                                _digitControllers[i].text.isEmpty &&
                                i > 0) {
                              _digitControllers[i - 1].clear();
                              _digitFocusNodes[i - 1].requestFocus();
                              setState(() {});
                            }
                          },
                          child: TextField(
                            controller: _digitControllers[i],
                            focusNode: _digitFocusNodes[i],
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            obscureText: true,
                            obscuringCharacter: '•',
                            maxLength: 1,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                            style: const TextStyle(
                              fontSize: 40,
                              height: 1.0,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFD7BE69),
                            ),
                            decoration: InputDecoration(
                              counterText: '',
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onChanged: (v) => _onDigitChanged(i, v),
                            onSubmitted: (_) => _verifyOtp(),
                          ),
                        ),
                      ),
                    );
                  }),
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
