import 'package:flutter/material.dart';

/// A minimal full-screen "Coming soon" placeholder used for admin features
/// whose UI/backend hasn't been built yet.
class ComingSoonScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? message;

  const ComingSoonScreen({
    super.key,
    required this.title,
    this.icon = Icons.hourglass_empty_rounded,
    this.message,
  });

  static const _gold = Color(0xFFD7BE69);
  static const _bg = Color(0xFFF5F5F5);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(title,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: _gold,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                height: 84,
                width: 84,
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: _gold),
              ),
              const SizedBox(height: 20),
              const Text(
                'Coming soon',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                message ?? 'This feature is being built.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
