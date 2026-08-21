import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_shell.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/view/onboarding_screen.dart';
import 'features/settings/logic/settings_provider.dart';

void main() {
  runApp(const ProviderScope(child: FlutterMobileIdeApp()));
}

class FlutterMobileIdeApp extends ConsumerWidget {
  const FlutterMobileIdeApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = ref.watch(settingsProvider.select((s) => s.isDarkMode));

    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: const _AppRoot(),
    );
  }
}

/// يقرر أول شاشة تظهر للمستخدم: شاشة الترحيب في أول تشغيل فقط، ثم بيئة
/// العمل الرئيسية (AppShell) في كل مرة لاحقة — حالة يُحفظ مصدرها في
/// [settingsProvider] عبر SharedPreferences.
class _AppRoot extends ConsumerWidget {
  const _AppRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasSeenOnboarding = ref.watch(settingsProvider.select((s) => s.hasSeenOnboarding));
    return hasSeenOnboarding ? const AppShell() : const OnboardingScreen();
  }
}
