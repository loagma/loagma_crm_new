// lib/config/api_config.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Centralized API Configuration
/// Toggle between local and production backend.
class ApiConfig {
  /// Set to false for local development, true for production (Render).
  static const bool useProduction = false;

  /// Optional override for local testing, for example:
  /// `--dart-define=API_BASE_URL=http://192.168.1.27:8000`
  static const String _baseUrlOverride =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// Laravel backend port (default: 8000)
  static const int _laravelPort = 8000;

  static String get baseUrl {
    if (_baseUrlOverride.isNotEmpty) {
      return _baseUrlOverride;
    }

    if (useProduction) {
      return 'https://loagma-crm.onrender.com';
    }

    if (kIsWeb) return 'http://localhost:$_laravelPort';

    try {
      if (Platform.isAndroid) {
        // Physical Android devices need the machine's LAN IP.
        return 'http://192.168.1.27:$_laravelPort';
      }
      return 'http://localhost:$_laravelPort';
    } catch (_) {
      return 'http://localhost:$_laravelPort';
    }
  }

  // ---------------------------------------------------------------------------
  // Endpoints (Laravel uses /api prefix automatically)
  // ---------------------------------------------------------------------------
  static String get authUrl => '$baseUrl/api/auth';
  
}
