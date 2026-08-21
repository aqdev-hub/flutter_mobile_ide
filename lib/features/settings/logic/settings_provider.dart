import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState extends Equatable {
  final bool isDarkMode;
  final double editorFontSize;
  final bool wordWrap;
  final bool hasSeenOnboarding;
  // جديد: هوية المؤلف المستخدَمة في كل عملية commit عبر تبويب Git — تُطلب
  // من مكتبة git_on_dart إلزاميًا (GitAuthor)، ولا يوجد حاليًا أي مصدر آخر
  // لها (لا ~/.gitconfig عالمي على أندرويد بمعزل عن هذا التطبيق).
  final String gitAuthorName;
  final String gitAuthorEmail;

  const SettingsState({
    this.isDarkMode = true,
    this.editorFontSize = 14,
    this.wordWrap = false,
    this.hasSeenOnboarding = false,
    this.gitAuthorName = '',
    this.gitAuthorEmail = '',
  });

  SettingsState copyWith({
    bool? isDarkMode,
    double? editorFontSize,
    bool? wordWrap,
    bool? hasSeenOnboarding,
    String? gitAuthorName,
    String? gitAuthorEmail,
  }) {
    return SettingsState(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      editorFontSize: editorFontSize ?? this.editorFontSize,
      wordWrap: wordWrap ?? this.wordWrap,
      hasSeenOnboarding: hasSeenOnboarding ?? this.hasSeenOnboarding,
      gitAuthorName: gitAuthorName ?? this.gitAuthorName,
      gitAuthorEmail: gitAuthorEmail ?? this.gitAuthorEmail,
    );
  }

  @override
  List<Object?> get props =>
      [isDarkMode, editorFontSize, wordWrap, hasSeenOnboarding, gitAuthorName, gitAuthorEmail];
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>((ref) {
  final notifier = SettingsNotifier();
  notifier._restore();
  return notifier;
});

/// إعدادات عامة بسيطة تُحفظ محليًا عبر SharedPreferences حتى لا يفقدها
/// المستخدم عند إغلاق التطبيق. وضعناها كـ feature مستقل صغير لأنها تُقرأ
/// من عدة أماكن (المحرر، الثيم العام، تبويب Git) لكنها لا تخصّ أيًا منها بالتحديد.
class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState());

  static const _darkModeKey = 'settings.dark_mode';
  static const _fontSizeKey = 'settings.font_size';
  static const _wordWrapKey = 'settings.word_wrap';
  static const _onboardingKey = 'settings.has_seen_onboarding';
  static const _gitAuthorNameKey = 'settings.git_author_name';
  static const _gitAuthorEmailKey = 'settings.git_author_email';

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = SettingsState(
      isDarkMode: prefs.getBool(_darkModeKey) ?? true,
      editorFontSize: prefs.getDouble(_fontSizeKey) ?? 14,
      wordWrap: prefs.getBool(_wordWrapKey) ?? false,
      hasSeenOnboarding: prefs.getBool(_onboardingKey) ?? false,
      gitAuthorName: prefs.getString(_gitAuthorNameKey) ?? '',
      gitAuthorEmail: prefs.getString(_gitAuthorEmailKey) ?? '',
    );
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
