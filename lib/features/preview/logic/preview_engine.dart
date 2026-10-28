import 'analyzer_front_end.dart';
import 'class_extractor.dart';
import 'dart_subset_ast.dart';
import 'dart_subset_parser.dart';
import 'preview_flags.dart';

class PreviewBuildResult {
  final Map<String, WidgetClassDef> classRegistry;
  final Expr? rootExpr;
  final String? errorMessage;

  /// ملاحظات تشخيصية (أي محرك استُخدم ولماذا رجعنا للقديم) — تُعرض في Output.
  final List<String> notes;

  /// متغيّرات ودوال المستوى الأعلى (top-level) من كل ملفات المشروع (المحرك الجديد فقط).
  final Map<String, Expr?> globalVars;
  final Map<String, MethodDef> globalFunctions;

  const PreviewBuildResult({
    required this.classRegistry,
    this.rootExpr,
    this.errorMessage,
    this.notes = const [],
    this.globalVars = const {},
    this.globalFunctions = const {},
  });

  bool get hasError => errorMessage != null;
}

/// يجمّع كل ملفات Dart المتاحة (عادة تحت lib/) في سجلّ أصناف واحد، ثم
/// يحدّد نقطة الدخول عبر تحليل `void main() { runApp(EXPR); }` داخل
/// main.dart لاستخراج تعبير الودجت الجذري.
///
/// **واجهتان أماميتان** (راجع [kUseAnalyzerFrontEnd]):
///  1. الجديدة: محلل Dart الرسمي عبر [AnalyzerFrontEnd] (صياغة Dart القياسية).
///  2. القديمة: [ClassExtractor] + [DartSubsetParser] (regex + محلل مبسَّط).
/// تُجرَّب الجديدة أولًا لكل ملف على حدة؛ إن تعذّرت (خطأ صياغة أو بنية غير
/// مدعومة) يُستخدم القديم لهذا الملف فقط وتُسجَّل ملاحظة بالسبب.
///
/// **رجوع متعمَّد عن محرّك dart_eval**: بعد اختبار فعلي حقيقي، اكتشفنا أن
/// `flutter_eval` (الإصدار المتاح وقت هذا التطوير) يحتوي خللًا جوهريًا
/// موثَّقًا (GitHub: ethanblake4/flutter_eval discussion #9) يمنع تنفيذ أي
/// صنف مستخدم يرث من StatelessWidget/StatefulWidget — أي أنه معطوب في
/// أبسط استخدام ممكن، وليس فقط في حالات حافة نادرة. عدنا لهذا المُحلِّل
/// اليدوي لأنه مستقر ومُختبَر ولا يعتمد على مكتبة خارجية غير مستقرة.
class PreviewEngine {
  PreviewBuildResult build({
    required Map<String, String> dartFilesByPath,
    required String mainFilePath,
  }) {
    final registry = <String, WidgetClassDef>{};
    final notes = <String>[];
    final globalVars = <String, Expr?>{};
    final globalFunctions = <String, MethodDef>{};
    var modernFiles = 0;
    var legacyFiles = 0;

    for (final entry in dartFilesByPath.entries) {
      // اسم الملف فقط (بدون المسار الكامل) — يظهر في رسائل الخطأ الموحَّدة.
      final fileName = entry.key.split(RegExp(r'[\\/]')).last;
      List<WidgetClassDef>? defs;

      if (kUseAnalyzerFrontEnd) {
        try {
          final result = AnalyzerFrontEnd.extractFile(entry.value, fileName: fileName);
          if (result.usable) {
            defs = result.classes;
            globalVars.addAll(result.globalVars);
            for (final fn in result.globalFunctions) {
              globalFunctions[fn.name] = fn;
            }
            modernFiles++;
          } else {
            notes.add('$fileName: استُخدم المحرك القديم — ${result.unusableReason}');
          }
        } catch (e) {
          notes.add('$fileName: استُخدم المحرك القديم — تعذّر المحرك الجديد: $e');
        }
      }

      if (defs == null) {
        try {
          defs = ClassExtractor(entry.value, fileName: fileName).extractAll();
          legacyFiles++;
        } catch (_) {
          // ملف به صياغة لا يفهمها المُستخرج بعد — يُتجاهل هذا الملف فقط
          // حتى لا يمنع بقية المشروع من المعاينة.
          continue;
        }
      }
      for (final def in defs) {
        registry[def.name] = def;
      }
    }
    if (kUseAnalyzerFrontEnd) {
      notes.insert(0, 'المحرك: analyzer ($modernFiles ملف) / القديم ($legacyFiles ملف)');
    }

    final mainSource = dartFilesByPath[mainFilePath];
    if (mainSource == null) {
      return PreviewBuildResult(
        classRegistry: const {},
        errorMessage: 'لم يتم العثور على main.dart في المشروع الحالي.',
        notes: notes,
      );
    }

    final mainFileName = mainFilePath.split(RegExp(r'[\\/]')).last;

    if (kUseAnalyzerFrontEnd) {
      final issues = <FrontEndIssue>[];
      final root = AnalyzerFrontEnd.extractRunAppRoot(mainSource, fileName: mainFileName, issues: issues);
      if (root != null) {
        return PreviewBuildResult(
          classRegistry: registry,
          rootExpr: root,
          notes: notes,
          globalVars: globalVars,
          globalFunctions: globalFunctions,
        );
      }
      final why = issues.isEmpty ? 'لم يُعثر على runApp(...)' : issues.first.message;
      notes.add('$mainFileName: جذر التطبيق عبر المحرك القديم — $why');
    }

    // نتجاهل التعليقات (// ...) قبل البحث عن runApp — بدون هذا، أي تعليق
    // توضيحي يذكر نص "runApp(" (مثل شرح كيف يعمل هذا الاستخراج نفسه!) كان
    // يُربك المطابقة النصية البسيطة ويُنتج خطأ "صياغة runApp() غير مكتملة"
    // زائفًا، رغم أن كود المستخدم الفعلي سليم تمامًا.
    final searchableSource = _stripLineComments(mainSource);

    final runAppMatch = RegExp(r'runApp\s*\(').firstMatch(searchableSource);
    if (runAppMatch == null) {
      return PreviewBuildResult(
        classRegistry: registry,
        errorMessage: 'لم يتم العثور على استدعاء runApp() داخل main.dart.',
        notes: notes,
      );
    }

    final argsStart = runAppMatch.end;
    final argsEnd = _matchClosingParen(searchableSource, runAppMatch.end - 1);
    if (argsEnd == -1) {
      return PreviewBuildResult(
        classRegistry: registry,
        errorMessage: 'صياغة runApp() غير مكتملة أو غير مدعومة.',
        notes: notes,
      );
    }
    final exprSource = searchableSource.substring(argsStart, argsEnd);

    try {
      final rootExpr = DartSubsetParser.parseExpressionSource(
        exprSource,
        startLine: '\n'.allMatches(searchableSource.substring(0, argsStart)).length + 1,
        fileName: mainFileName,
      );
      return PreviewBuildResult(
        classRegistry: registry,
        rootExpr: rootExpr,
        notes: notes,
        globalVars: globalVars,
        globalFunctions: globalFunctions,
      );
    } catch (e) {
      return PreviewBuildResult(
        classRegistry: registry,
        errorMessage: 'تعذّر تحليل تعبير runApp(): $e',
        notes: notes,
      );
    }
  }

  /// يبحث عن القوس الختامي المطابق، متجاوزًا أي أقواس داخل تعليقات سطر
  /// واحد (`//`) أو نصوص حرفية ('...'/"...") — بدون هذا، تعليق يحتوي أي
  /// حرف `(` أو `)` كان يُفسد حساب نهاية runApp(...) الصحيحة.
  int _matchClosingParen(String text, int openIndex) {
    var depth = 0;
    var i = openIndex;
    while (i < text.length) {
      final ch = text[i];

      if (ch == '/' && i + 1 < text.length && text[i + 1] == '/') {
        while (i < text.length && text[i] != '\n') {
          i++;
        }
        continue;
      }

      if (ch == "'" || ch == '"') {
        final quote = ch;
        i++;
        while (i < text.length && text[i] != quote) {
          if (text[i] == '\\' && i + 1 < text.length) i++;
          i++;
        }
        i++; // تجاوز علامة الاقتباس الختامية
        continue;
      }

      if (ch == '(') depth++;
      if (ch == ')') {
        depth--;
        if (depth == 0) return i;
      }
      i++;
    }
    return -1;
  }

  /// يستبدل محتوى كل تعليق `// ...` بمسافات (وليس حذفه) حتى تبقى كل
  /// الأطوال والمواضع الحرفية مطابقة للنص الأصلي — بنفس أسلوب
  /// `_maskNestedBlocks` في class_extractor.dart. هذا يمنع أي قوس أو نص
  /// "runApp(" داخل تعليق توضيحي من التأثير على المطابقة النصية أدناه.
  String _stripLineComments(String source) {
    final buffer = StringBuffer();
    var i = 0;
    while (i < source.length) {
      if (source[i] == '/' && i + 1 < source.length && source[i + 1] == '/') {
        while (i < source.length && source[i] != '\n') {
          buffer.write(' ');
          i++;
        }
      } else {
        buffer.write(source[i]);
        i++;
      }
    }
    return buffer.toString();
  }
}
