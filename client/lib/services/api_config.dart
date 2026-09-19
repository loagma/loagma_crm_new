// lib/config/api_config.dart
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;

/// Centralized API Configuration
/// Toggle between local and production backend.
class ApiConfig {
  /// Set to false for local development, true for production (Render).
  /// To switch: change to `true` for prod, `false` for local
  static const bool useProduction = false;

  /// Optional override for local testing, for example: 
  /// `--dart-define=API_BASE_URL=http://192.168.1.10:8000`
  static const String _baseUrlOverride =
      String.fromEnvironment('API_BASE_URL', defaultValue: '');

  /// Laravel backend port (default: 8000)
  static const int _laravelPort = 8000;

  /// Production API URL (Render hosting)
  static const String _productionUrl = 'https://loagma-crm-new-1.onrender.com';

  static String get baseUrl {
    if (_baseUrlOverride.isNotEmpty) {
      return _baseUrlOverride;
    }

    if (useProduction) {
      return _productionUrl;
    }

    if (kIsWeb) return 'http://localhost:$_laravelPort';

    try {
      if (Platform.isAndroid) {
        // Android Studio emulator reaches the host machine via 10.0.2.2
        // (maps to the host's 127.0.0.1). For a physical device, use the
        // machine's LAN IP instead, e.g. http://192.168.1.10:$_laravelPort
        return 'http://10.0.2.2:$_laravelPort';
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
