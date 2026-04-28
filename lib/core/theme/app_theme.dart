import 'package:flutter/material.dart';

class AppTheme {
  // 다크 테마 색상
  static const Color _darkBg           = Color(0xFF080810);
  static const Color _darkBgCard       = Color(0xFF0F0F1F);
  static const Color _darkBorder       = Color(0xFF1E1B3A);
  static const Color _darkTextMain     = Color(0xFFE2E8F0);
  static const Color _darkTextSub      = Color(0xFF64748B);
  static const Color _darkTextMuted    = Color(0xFF334155);

  // 라이트 테마 색상
  static const Color _lightBg          = Color(0xFFFFFFFF);
  static const Color _lightBgCard      = Color(0xFFF5F5F7);
  static const Color _lightBorder      = Color(0xFFE4E4E7);
  static const Color _lightTextMain    = Color(0xFF18181B);
  static const Color _lightTextSub     = Color(0xFF71717A);
  static const Color _lightTextMuted   = Color(0xFFA1A1AA);

  // 공통 색상 (항상 동일)
  static const Color primary      = Color(0xFF7C3AED);
  static const Color primaryLight = Color(0xFFA78BFA);
  static const Color error        = Color(0xFFEF4444);
  static const Color success      = Color(0xFF10B981);

  // 현재 테마 상태
  static bool _isDark = true;

  static void setDark(bool isDark) {
    _isDark = isDark;
  }

  // 동적 색상 getter
  static Color get bg         => _isDark ? _darkBg         : _lightBg;
  static Color get bgCard     => _isDark ? _darkBgCard     : _lightBgCard;
  static Color get border     => _isDark ? _darkBorder     : _lightBorder;
  static Color get textMain   => _isDark ? _darkTextMain   : _lightTextMain;
  static Color get textSub    => _isDark ? _darkTextSub    : _lightTextSub;
  static Color get textMuted  => _isDark ? _darkTextMuted  : _lightTextMuted;

  // 다크 테마
  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: _darkBg,
    colorScheme: const ColorScheme.dark(
      primary: primary,
      secondary: primaryLight,
      surface: _darkBgCard,
      error: error,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _darkBg,
      foregroundColor: _darkTextMain,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: _darkTextMain,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: _darkTextMain,
        side: const BorderSide(color: _darkBorder),
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _darkBgCard,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _darkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _darkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      hintStyle: const TextStyle(color: _darkTextSub, fontSize: 14),
    ),
    dividerColor: _darkBorder,
    dividerTheme: const DividerThemeData(color: _darkBorder, thickness: 1),
    // ✨ 전역 SnackBar 테마 - 다크
    snackBarTheme: SnackBarThemeData(
      backgroundColor: _darkBgCard,
      contentTextStyle: const TextStyle(
        color: _darkTextMain,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _darkBorder),
      ),
      elevation: 6,
      actionTextColor: primaryLight,
    ),
    // 팝업 메뉴
    popupMenuTheme: PopupMenuThemeData(
      color: _darkBgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: const TextStyle(
        color: _darkTextMain,
        fontSize: 14,
      ),
    ),
    // 다이얼로그
    dialogTheme: DialogThemeData(
      backgroundColor: _darkBgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      titleTextStyle: const TextStyle(
        color: _darkTextMain,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: const TextStyle(
        color: _darkTextSub,
        fontSize: 14,
      ),
    ),
    // 바텀 시트
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: _darkBgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
  );

  // 라이트 테마
  static ThemeData get light => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: _lightBg,
    colorScheme: const ColorScheme.light(
      primary: primary,
      secondary: primaryLight,
      surface: _lightBgCard,
      error: error,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _lightBg,
      foregroundColor: _lightTextMain,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TextStyle(
        color: _lightTextMain,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: _lightBgCard,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _lightBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _lightBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 1.5),
      ),
      hintStyle: const TextStyle(color: _lightTextSub, fontSize: 14),
    ),
    dividerColor: _lightBorder,
    dividerTheme: const DividerThemeData(color: _lightBorder, thickness: 1),
    // ✨ 전역 SnackBar 테마 - 라이트
    snackBarTheme: SnackBarThemeData(
      backgroundColor: _lightBgCard,
      contentTextStyle: const TextStyle(
        color: _lightTextMain,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _lightBorder),
      ),
      elevation: 6,
      actionTextColor: primary,
    ),
    // 팝업 메뉴
    popupMenuTheme: PopupMenuThemeData(
      color: _lightBgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: const TextStyle(
        color: _lightTextMain,
        fontSize: 14,
      ),
    ),
    // 다이얼로그
    dialogTheme: DialogThemeData(
      backgroundColor: _lightBgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      titleTextStyle: const TextStyle(
        color: _lightTextMain,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
      contentTextStyle: const TextStyle(
        color: _lightTextSub,
        fontSize: 14,
      ),
    ),
    // 바텀 시트
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: _lightBgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
  );
}