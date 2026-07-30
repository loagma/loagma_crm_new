import 'package:url_launcher/url_launcher.dart';

/// Shared launch helpers for the telecaller modules. Mirrors the existing
/// pattern in telecaller_call_screen.dart (tel: dialer + wa.me WhatsApp).

Future<void> launchPhoneCall(String phone) async {
  final p = phone.trim();
  if (p.isEmpty) return;
  final uri = Uri.parse('tel:$p');
  if (await canLaunchUrl(uri)) await launchUrl(uri);
}

Future<void> launchWhatsApp(String phone) async {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return;
  final num = digits.length == 10 ? '91$digits' : digits;
  final uri = Uri.parse('https://wa.me/$num');
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

Future<void> launchEmail(String email, {String subject = ''}) async {
  final e = email.trim();
  if (e.isEmpty) return;
  final uri = Uri(
    scheme: 'mailto',
    path: e,
    query: subject.isEmpty ? null : 'subject=${Uri.encodeComponent(subject)}',
  );
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// "95s" -> "1m 35s"; plain seconds under a minute pass through as-is.
String formatCallDuration(int seconds) {
  if (seconds <= 0) return '0s';
  if (seconds < 60) return '${seconds}s';
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return s == 0 ? '${m}m' : '${m}m ${s}s';
}
