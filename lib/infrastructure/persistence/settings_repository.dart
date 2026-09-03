import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../application/settings/app_settings.dart';
import '../../core/logging/app_logger.dart';

class SettingsRepository {
  static const _key = 'driveguard.settings.v1';

  Future<AppSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const AppSettings();
      return AppSettings.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      AppLogger.instance.error(
        'SettingsRepository',
        'Failed to load settings, using defaults',
        e,
      );
      return const AppSettings();
    }
  }

  Future<void> save(AppSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(settings.toJson()));
    } catch (e) {
      AppLogger.instance.error(
        'SettingsRepository',
        'Failed to save settings',
        e,
      );
    }
  }
}
