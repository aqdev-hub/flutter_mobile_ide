import 'class_extractor.dart';

enum ProblemSeverity { error, warning }

/// مشكلة واحدة جاهزة للعرض في تبويب Problems: أي ملف، أي سطر (تقريبي)،
/// ورسالة بالعربية.
class ProblemItem {
  final String filePath;
  final String fileName;
  final int? line;
  final String message;
  final ProblemSeverity severity;

  const ProblemItem({
    required this.filePath,
    required this.fileName,
    this.line,
    required this.message,
    this.severity = ProblemSeverity.error,
  });
}

/// يحلّل محتوى ملف Dart واحد ويُنتج قائمة مشاكل.
///
/// **حد صريح ومهم**: هذا ليس محلّل Dart رسميًا (لا يوجد `dart analyze`
/// حقيقي متاح داخل هذا التطبيق). هو يعرض بالضبط الأخطاء التي يواجهها
/// المُفسِّر الخاص بالمعاينة (`ClassExtractor`/`DartSubsetParser`) أثناء
/// فهم الكود — أي "هل هذا الملف قابل للمعاينة أم لا ولماذا"، وليس فحصًا
/// شاملًا لصحة Dart بمعزل عن حدود المُفسِّر.
class ProblemsAnalyzer {
  ProblemsAnalyzer._();

  static List<ProblemItem> analyzeDartFile(String path, String fileName, String content) {
    final problems = <ProblemItem>[];

    final extractor = ClassExtractor(content);
    try {
      extractor.extractAll();
    } catch (e) {
      problems.add(ProblemItem(filePath: path, fileName: fileName, message: 'خطأ عام أثناء تحليل الملف: $e'));
    }
    for (final issue in extractor.issues) {
      problems.add(ProblemItem(filePath: path, fileName: fileName, line: issue.line, message: issue.message));
    }

    if (fileName == 'main.dart' && !RegExp(r'runApp\s*\(').hasMatch(content)) {
      problems.add(ProblemItem(
        filePath: path,
        fileName: fileName,
        message: 'لم يتم العثور على استدعاء runApp() داخل main.dart — لن يعمل زر التشغيل على هذا الملف',
        severity: ProblemSeverity.warning,
      ));
    }

    return problems;
  }
}
