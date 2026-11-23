import 'package:flutter/material.dart';

/// ألوان وهوية بصرية موحّدة للـ IDE.
/// فصلناها في كلاس مستقل حتى تُستخدم نفس القيم في الثيم وفي الودجتس المخصصة
/// (مثل شريط التبويبات وشجرة الملفات) دون تكرار hex codes متفرقة في الكود.
class IdeColors {
  IdeColors._();

  // خلفيات بدرجات متدرجة تفصل المناطق (شريط علوي / شجرة / محرر / لوحة سفلية)
  static const Color darkBg = Color(0xFF1E1E1E);
  static const Color darkSurface = Color(0xFF252526);
  static const Color darkSidebar = Color(0xFF1B1B1C);
  static const Color darkTopBar = Color(0xFF2D2D30);
  static const Color darkBorder = Color(0xFF3C3C3C);
  static const Color darkActiveTab = Color(0xFF1E1E1E);
  static const Color darkInactiveTab = Color(0xFF2D2D2D);

  static const Color lightBg = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFF3F3F3);
  static const Color lightSidebar = Color(0xFFF3F3F3);
  static const Color lightTopBar = Color(0xFFE7E7E7);
  static const Color lightBorder = Color(0xFFD4D4D4);

  static const Color accentBlue = Color(0xFF007ACC); // لون التشغيل والتركيز
  static const Color runGreen = Color(0xFF3FB950);
  static const Color stopRed = Color(0xFFF14C4C);
  static const Color warningYellow = Color(0xFFCCA700);
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark => ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: IdeColors.darkBg,
        colorScheme: const ColorScheme.dark(
          primary: IdeColors.accentBlue,
          surface: IdeColors.darkSurface,
        ),
        dividerColor: IdeColors.darkBorder,
        appBarTheme: const AppBarTheme(
          backgroundColor: IdeColors.darkTopBar,
          elevation: 0,
          foregroundColor: Colors.white,
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      );

  static ThemeData get light => ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: IdeColors.lightBg,
        colorScheme: const ColorScheme.light(
          primary: IdeColors.accentBlue,
          surface: IdeColors.lightSurface,
        ),
        dividerColor: IdeColors.lightBorder,
        appBarTheme: const AppBarTheme(
          backgroundColor: IdeColors.lightTopBar,
          elevation: 0,
          foregroundColor: Colors.black,
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      );
}
