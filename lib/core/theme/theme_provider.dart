import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _themeModeKey = 'theme_mode';

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.dark) {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_themeModeKey);

      switch (saved) {
        case 'light':
          state = ThemeMode.light;
          break;
        case 'system':
          state = ThemeMode.system;
          break;
        case 'dark':
        default:
          state = ThemeMode.dark;
      }
    } catch (e) {
      print('테마 로드 오류: $e');
    }
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;

    try {
      final prefs = await SharedPreferences.getInstance();
      String value;
      switch (mode) {
        case ThemeMode.light:
          value = 'light';
          break;
        case ThemeMode.system:
          value = 'system';
          break;
        case ThemeMode.dark:
        default:
          value = 'dark';
      }
      await prefs.setString(_themeModeKey, value);
    } catch (e) {
      print('테마 저장 오류: $e');
    }
  }

  Future<void> toggle() async {
    final newMode =
        state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setTheme(newMode);
  }
}

final themeProvider =
    StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) {
  return ThemeNotifier();
});