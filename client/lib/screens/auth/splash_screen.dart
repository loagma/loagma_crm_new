import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../services/user_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _navigateAfterDelay();
  }

  Future<void> _navigateAfterDelay() async {
    // Show splash for 2 seconds
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    // Determine where to navigate based on login state
    if (UserService.isLoggedIn) {
      final role = UserService.currentRole;
      if (role != null && role.isNotEmpty) {
        context.go('/dashboard/$role');
      } else {
        context.go('/no-role');
      }
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Image.asset(
              'assets/logo1.png',
              width: 120,
              height: 120,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 24),
            // CRM Text
            const Text(
              'CRM',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Color(0xFFD7BE69),
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
