/// ثوابت عامة تُستخدم عبر أكثر من feature.
/// وُضعت هنا (بدل تكرارها) لأنها تتغيّر معًا وتخصّ التطبيق ككل لا feature واحد.
class AppConstants {
  AppConstants._();

  static const String appName = 'Flutter Mobile IDE';

  /// الملفات/المجلدات التي نخفيها افتراضيًا من الشجرة لتقليل الازدحام البصري.
  static const List<String> ignoredEntries = [
    '.git',
    '.dart_tool',
    '.idea',
    'build',
    '.gradle',
  ];

  /// امتدادات الملفات النصية التي يمكن فتحها في المحرر.
  static const List<String> editableExtensions = [
    '.dart',
    '.yaml',
    '.yml',
    '.json',
    '.md',
    '.txt',
    '.gradle',
    '.properties',
    '.xml',
    '.gitignore',
    '.lock',
  ];

  static const double sidebarWidth = 260;
  static const double minPanelHeight = 120;
}
