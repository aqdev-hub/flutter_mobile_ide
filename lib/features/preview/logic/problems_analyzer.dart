import 'class_extractor.dart';
import 'syntax_diagnostics.dart';

enum ProblemSeverity { error, warning, info }

/// مصدر المشكلة — يفرّق بين "كودك فيه خطأ" و"المعاينة لا تفهم كودك":
/// - [syntax]: خطأ صياغة أكّده محلل Dart الرسمي (خطأ حقيقي في الكود).
/// - [preview]: الصياغة سليمة لكن المُفسِّر الخاص بالمعاينة لا يدعمها بعد
///   (قيد في المعاينة، وليس خطأً في الكود).
enum ProblemCategory { syntax, preview }

/// مشكلة واحدة جاهزة للعرض في تبويب Problems: أي ملف، أي سطر/عمود، ورسالة
/// بالعربية.
class ProblemItem {
  final String filePath;
  final String fileName;
  final int? line;
  final int? column;
  final int? offset;
  final int? length;
  final String message;

  /// تفصيل إضافي (مثل الرسالة الأصلية من المحلل) يُعرَض بخط صغير.
  final String? detail;
  final ProblemSeverity severity;
  final ProblemCategory category;

  const ProblemItem({
    required this.filePath,
    required this.fileName,
    this.line,
    this.column,
    this.offset,
    this.length,
    required this.message,
    this.detail,
    this.severity = ProblemSeverity.error,
    this.category = ProblemCategory.syntax,
  });
}

/// يحلّل محتوى ملف Dart واحد ويُنتج قائمة مشاكل بطبقتين:
///
/// 1. **الصياغة** عبر محلل Dart الرسمي ([SyntaxDiagnostics]) — مواضع دقيقة
///    (سطر/عمود). إن وُجدت أخطاء صياغة تُعرض وحدها (أخطاء حقيقية)، ولا تُعرض
///    معها أخطاء استخراج المعاينة، لأنها غالبًا مجرد نتيجة لنفس الخطأ.
/// 2. **قدرة المعاينة**: إن كانت الصياغة سليمة رسميًا لكن استخراج المعاينة
///    ([ClassExtractor]) فشل، فهذا قيد في المُفسِّر الحالي لا خطأ في كودك،
///    ويُعرض كتحذير بهذا التوصيف.
///
/// **حد صريح**: ما زال لا يوجد حلّ دلالي (أنواع، أسماء غير معرَّفة، استيرادات،
/// وسائط مسمّاة) — راجع الخطوات التالية في خطة العمل.
class ProblemsAnalyzer {
  ProblemsAnalyzer._();

  static List<ProblemItem> analyzeDartFile(String path, String fileName, String content) {
    final problems = <ProblemItem>[];

    // --- الطبقة 1: صياغة Dart الرسمية ---
    var officialParserRan = false;
    try {
      final syntax = SyntaxDiagnostics.analyze(content);
      officialParserRan = true;
      if (syntax.isNotEmpty) {
        return [
          for (final d in syntax)
            ProblemItem(
              filePath: path,
              fileName: fileName,
              line: d.line,
              column: d.column,
              offset: d.offset,
              length: d.length,
              message: d.message,
              detail: d.originalMessage,
              severity: ProblemSeverity.error,
              category: ProblemCategory.syntax,
            ),
        ];
      }
    } catch (e) {
      problems.add(ProblemItem(
        filePath: path,
        fileName: fileName,
        message: 'تعذّر تشغيل محلل Dart الرسمي على هذا الملف: $e',
        severity: ProblemSeverity.info,
        category: ProblemCategory.preview,
      ));
    }

    // --- الطبقة 2: قدرة المعاينة ---
    final extractor = ClassExtractor(content, fileName: fileName);
    try {
      extractor.extractAll();
    } catch (e) {
      problems.add(ProblemItem(
        filePath: path,
        fileName: fileName,
        message: 'خطأ عام أثناء تحليل الملف للمعاينة: $e',
        severity: officialParserRan ? ProblemSeverity.warning : ProblemSeverity.error,
        category: ProblemCategory.preview,
      ));
    }
    for (final issue in extractor.issues) {
      problems.add(ProblemItem(
        filePath: path,
        fileName: fileName,
        line: issue.line,
        message: officialParserRan
            ? 'المعاينة لا تدعم هذا الكود بعد (الصياغة سليمة وفق محلل Dart الرسمي): ${issue.message}'
            : issue.message,
        severity: officialParserRan ? ProblemSeverity.warning : ProblemSeverity.error,
        category: ProblemCategory.preview,
      ));
    }

    if (fileName == 'main.dart' && !RegExp(r'runApp\s*\(').hasMatch(content)) {
      problems.add(ProblemItem(
        filePath: path,
        fileName: fileName,
        message: 'لم يتم العثور على استدعاء runApp() داخل main.dart — لن يعمل زر التشغيل على هذا الملف',
        severity: ProblemSeverity.warning,
        category: ProblemCategory.preview,
      ));
    }

    return problems;
  }
}
