import 'package:analyzer/dart/analysis/utilities.dart';

/// خطأ نحوي واحد اكتشفه محلّل Dart الرسمي (`package:analyzer`) بموضعه
/// المطلق الدقيق داخل الملف (سطر/عمود 1-based) — وليس موضعًا تقريبيًا.
class SyntaxDiagnostic {
  final int line;
  final int column;

  /// إزاحة الخطأ وطوله بالمحارف داخل النص الكامل (طول 0 = "رمز ناقص"، مثل
  /// فاصلة منقوطة منسيّة). تُستخدَم لاحقًا لرسم الخط الأحمر تحت الموضع.
  final int offset;
  final int length;

  /// اسم رمز الخطأ في المحلل بحروف صغيرة (مثل expected_token).
  final String code;

  /// الرسالة بالعربية إن عرفنا ترجمتها، وإلا الرسالة الإنجليزية الأصلية.
  final String message;

  /// الرسالة الإنجليزية الأصلية من المحلل كما هي.
  final String originalMessage;

  const SyntaxDiagnostic({
    required this.line,
    required this.column,
    required this.offset,
    required this.length,
    required this.code,
    required this.message,
    required this.originalMessage,
  });
}

/// فحص نحوي كامل لملف Dart عبر المحلل الرسمي — **تحليل نحوي فقط** (parse)،
/// دون حلّ أنواع أو استيرادات، لذلك لا يحتاج Dart SDK ولا مصادر Flutter على
/// الجهاز (وهو ما يجعله ممكنًا على الهاتف).
///
/// يكتشف ما كان يمرّ بصمت سابقًا: `{super?key}`، `bstract class`، فاصلة
/// منقوطة منسيّة، أقواس غير متوازنة، تعريفات بصياغة خاطئة... بنفس رسائل
/// وقواعد Dart الحقيقية.
///
/// **حد صريح**: لا يكتشف أخطاء الأنواع/الأسماء غير المعرَّفة/الوسائط غير
/// الموجودة (هذه تحتاج حلًّا دلاليًا — الخطوات التالية في الخطة).
class SyntaxDiagnostics {
  SyntaxDiagnostics._();

  static const int maxDiagnostics = 50;

  // ذاكرة مؤقتة صغيرة: لوحة Problems ومحلل المحرر (الخط الأحمر والهامش) يفحصان
  // النص نفسه في اللحظة نفسها تقريبًا، فلا نحلّله مرتين.
  static const int _cacheSize = 8;
  static final Map<String, List<SyntaxDiagnostic>> _cache = {};

  static List<SyntaxDiagnostic> analyze(String content) {
    final cached = _cache.remove(content);
    if (cached != null) {
      _cache[content] = cached; // يصبح الأحدث استخدامًا
      return cached;
    }
    final fresh = _analyzeUncached(content);
    _cache[content] = fresh;
    if (_cache.length > _cacheSize) _cache.remove(_cache.keys.first);
    return fresh;
  }

  static List<SyntaxDiagnostic> _analyzeUncached(String content) {
    final result = parseString(content: content, throwIfDiagnostics: false);
    final lineInfo = result.lineInfo;

    final diagnostics = <SyntaxDiagnostic>[];
    final seen = <String>{};
    for (final error in result.errors) {
      final location = lineInfo.getLocation(error.offset);
      final code = error.diagnosticCode.lowerCaseName;
      final key = '${location.lineNumber}:${location.columnNumber}:$code';
      if (!seen.add(key)) continue;
      diagnostics.add(SyntaxDiagnostic(
        line: location.lineNumber,
        column: location.columnNumber,
        offset: error.offset,
        length: error.length,
        code: code,
        message: localizeMessage(error.message),
        originalMessage: error.message,
      ));
    }
    diagnostics.sort((a, b) => a.offset.compareTo(b.offset));
    return List.unmodifiable(
      diagnostics.length > maxDiagnostics ? diagnostics.sublist(0, maxDiagnostics) : diagnostics,
    );
  }

  static final List<(RegExp, String Function(RegExpMatch))> _translations = [
    (RegExp(r"^Expected to find '(.+?)'\.?$"), (m) => "متوقَّع '${m[1]}' في هذا الموضع."),
    (RegExp(r"^Expected an identifier\.?$"), (m) => 'متوقَّع اسم (معرِّف) في هذا الموضع.'),
    (RegExp(r"^Unexpected text '(.+?)'\.?$"), (m) => "نص غير متوقَّع: '${m[1]}'."),
    (
      RegExp(r"^Can't find '(.+?)' to match '(.+?)'\.?$"),
      (m) => "لا يوجد '${m[1]}' مقابل لـ '${m[2]}' (أقواس غير متوازنة)."
    ),
    (
      RegExp(r"^Variables must be declared using the keywords"),
      (m) => "تعريف غير صحيح: يجب أن يبدأ تعريف المتغيّر بـ const أو final أو var أو اسم نوع."
    ),
    (
      RegExp(r"^Expected a declaration, but got '(.+?)'\.?$"),
      (m) => "متوقَّع تعريف (صنف أو دالة أو متغيّر) لكن وُجد '${m[1]}'."
    ),
    (
      RegExp(r"^Expected a class member, but got '(.+?)'\.?$"),
      (m) => "متوقَّع عضو صنف (حقل أو دالة أو مُنشئ) لكن وُجد '${m[1]}'."
    ),
    (RegExp(r"^Expected a string literal\.?$"), (m) => 'متوقَّع نص حرفي (بين علامتي اقتباس).'),
    (RegExp(r"^Expected an expression\.?$"), (m) => 'متوقَّع تعبير في هذا الموضع.'),
    (RegExp(r"^Expected a statement\.?$"), (m) => 'متوقَّع جملة في هذا الموضع.'),
    (RegExp(r"^Expected a type name\.?$"), (m) => 'متوقَّع اسم نوع في هذا الموضع.'),
  ];

  /// يترجم أشهر رسائل المحلل للعربية. أي رسالة لا نعرفها تُعرَض بالإنجليزية
  /// الأصلية مسبوقة بتصنيف عربي — لا نخمّن ترجمة قد تُضلّل.
  static String localizeMessage(String original) {
    final trimmed = original.trim();
    for (final (pattern, build) in _translations) {
      final match = pattern.firstMatch(trimmed);
      if (match != null) return build(match);
    }
    return 'خطأ في صياغة Dart: $trimmed';
  }
}
