import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../../services/user_service.dart';

class NoRoleScreen extends StatelessWidget {
  const NoRoleScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Are you sure you want to logout?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('No', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                await UserService.logout();
                Fluttertoast.showToast(msg: 'Logged out successfully');
                if (context.mounted) {
                  context.go('/login');
                }
              },
              child: const Text('Yes', style: TextStyle(color: Color(0xFFD7BE69))),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFD7BE69),
      body: SafeArea(
        child: Center(
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
                  // Warning Icon
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.warning_amber_rounded,
                      size: 80,
                      color: Colors.orange.shade700,
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Title
                  const Text(
                    "Role Not Assigned",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFD7BE69),
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 20),

                  // Message
                  const Text(
                    "Your role is not assigned yet. Please contact your administrator to assign a role to your account.",
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 30),

                  // Contact Info (Optional)
                  Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: const [
                        Icon(
                          Icons.support_agent,
                          size: 40,
                          color: Color(0xFFD7BE69),
                        ),
                        SizedBox(height: 10),
                        Text(
                          "Need Help?",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          "Contact your system administrator",
                          style: TextStyle(fontSize: 14, color: Colors.black54),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Logout Button
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFD7BE69),
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () => _logout(context),
                    child: const Text(
                      "Logout",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
