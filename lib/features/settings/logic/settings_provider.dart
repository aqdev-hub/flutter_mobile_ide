import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState extends Equatable {
  final bool isDarkMode;
  final double editorFontSize;
  final bool wordWrap;
  final bool hasSeenOnboarding;
  // هوية المؤلف المستخدَمة في كل عملية commit عبر تبويب Git.
  final String gitAuthorName;
  final String gitAuthorEmail;
  // تنسيق ملفات dart تلقائيًا عند كل حفظ (مفعَّل افتراضيًا).
  final bool formatOnSave;
  // هل انتهى تحميل القيم المحفوظة من SharedPreferences؟ يمنع عرض قيم افتراضية
  // خاطئة (مثل شاشة الترحيب) لحظة بدء التشغيل قبل اكتمال القراءة.
  final bool isLoaded;

  const SettingsState({
    this.isDarkMode = true,
    this.editorFontSize = 14,
    this.wordWrap = false,
    this.hasSeenOnboarding = false,
    this.gitAuthorName = '',
    this.gitAuthorEmail = '',
    this.formatOnSave = true,
    this.isLoaded = false,
  });

  SettingsState copyWith({
    bool? isDarkMode,
    double? editorFontSize,
    bool? wordWrap,
    bool? hasSeenOnboarding,
    String? gitAuthorName,
    String? gitAuthorEmail,
    bool? formatOnSave,
    bool? isLoaded,
  }) {
    return SettingsState(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      editorFontSize: editorFontSize ?? this.editorFontSize,
      wordWrap: wordWrap ?? this.wordWrap,
      hasSeenOnboarding: hasSeenOnboarding ?? this.hasSeenOnboarding,
      gitAuthorName: gitAuthorName ?? this.gitAuthorName,
      gitAuthorEmail: gitAuthorEmail ?? this.gitAuthorEmail,
      formatOnSave: formatOnSave ?? this.formatOnSave,
      isLoaded: isLoaded ?? this.isLoaded,
    );
  }

  @override
  List<Object?> get props =>
      [isDarkMode, editorFontSize, wordWrap, hasSeenOnboarding, gitAuthorName, gitAuthorEmail, formatOnSave, isLoaded];
}

/// الإعدادات المحمَّلة مسبقًا قبل `runApp` (راجع main.dart). إن كانت null (مثل
/// بعض الاختبارات) يُحمِّل [SettingsNotifier] القيم بنفسه بشكل غير متزامن،
/// ويبقى `isLoaded == false` حتى اكتمال القراءة.
final initialSettingsProvider = Provider<SettingsState?>((ref) => null);

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  final initial = ref.watch(initialSettingsProvider);
  final notifier = SettingsNotifier(initial ?? const SettingsState());
  if (initial == null) notifier._restore();
  return notifier;
});

/// إعدادات عامة بسيطة تُحفظ محليًا عبر SharedPreferences حتى لا يفقدها
/// المستخدم عند إغلاق التطبيق.
class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier([super.initial = const SettingsState()]);

  static const _darkModeKey = 'settings.dark_mode';
  static const _fontSizeKey = 'settings.font_size';
  static const _wordWrapKey = 'settings.word_wrap';
  static const _onboardingKey = 'settings.has_seen_onboarding';
  static const _gitAuthorNameKey = 'settings.git_author_name';
  static const _gitAuthorEmailKey = 'settings.git_author_email';
  static const _formatOnSaveKey = 'settings.format_on_save';

  /// يقرأ القيم المحفوظة. عند أي فشل في القراءة يُرجع القيم الافتراضية (مع
  /// `isLoaded: true`) بدل تعليق التطبيق على شاشة فارغة.
  static Future<SettingsState> loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return SettingsState(
        isDarkMode: prefs.getBool(_darkModeKey) ?? true,
        editorFontSize: prefs.getDouble(_fontSizeKey) ?? 14,
        wordWrap: prefs.getBool(_wordWrapKey) ?? false,
        hasSeenOnboarding: prefs.getBool(_onboardingKey) ?? false,
        gitAuthorName: prefs.getString(_gitAuthorNameKey) ?? '',
        gitAuthorEmail: prefs.getString(_gitAuthorEmailKey) ?? '',
        formatOnSave: prefs.getBool(_formatOnSaveKey) ?? true,
        isLoaded: true,
      );
    } catch (_) {
      return const SettingsState(isLoaded: true);
    }
  }

  Future<void> _restore() async {
    final loaded = await loadFromPrefs();
    if (mounted) state = loaded;
  }

  Future<void> markOnboardingSeen() async {
    state = state.copyWith(hasSeenOnboarding: true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingKey, true);
  }

  Future<void> toggleDarkMode() async {
    state = state.copyWith(isDarkMode: !state.isDarkMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_darkModeKey, state.isDarkMode);
  }

  Future<void> setFontSize(double size) async {
    state = state.copyWith(editorFontSize: size);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontSizeKey, size);
  }

  Future<void> toggleWordWrap() async {
    state = state.copyWith(wordWrap: !state.wordWrap);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_wordWrapKey, state.wordWrap);
  }

  Future<void> toggleFormatOnSave() async {
    state = state.copyWith(formatOnSave: !state.formatOnSave);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_formatOnSaveKey, state.formatOnSave);
  }

  Future<void> setGitAuthorName(String name) async {
    state = state.copyWith(gitAuthorName: name);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_gitAuthorNameKey, name);
  }

  Future<void> setGitAuthorEmail(String email) async {
    state = state.copyWith(gitAuthorEmail: email);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_gitAuthorEmailKey, email);
  }
}
