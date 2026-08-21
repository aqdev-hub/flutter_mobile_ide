import 'dart_subset_ast.dart';
import 'dart_subset_parser.dart';
import 'class_extractor.dart';

class PreviewBuildResult {
  final Map<String, WidgetClassDef> classRegistry;
  final Expr? rootExpr;
  final String? errorMessage;

  const PreviewBuildResult({required this.classRegistry, this.rootExpr, this.errorMessage});

  bool get hasError => errorMessage != null;
}

/// يجمّع كل ملفات Dart المتاحة (عادة تحت lib/) في سجلّ أصناف واحد، ثم
/// يحدّد نقطة الدخول عبر تحليل `void main() { runApp(EXPR); }` داخل
/// main.dart لاستخراج تعبير الودجت الجذري.
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
    for (final entry in dartFilesByPath.entries) {
      try {
        final defs = ClassExtractor(entry.value).extractAll();
        for (final def in defs) {
          registry[def.name] = def;
        }
      } catch (_) {
        // ملف به صياغة لا يفهمها المُستخرج بعد — يُتجاهل هذا الملف فقط
        // حتى لا يمنع بقية المشروع من المعاينة.
      }
    }

    final mainSource = dartFilesByPath[mainFilePath];
    if (mainSource == null) {
      return const PreviewBuildResult(
        classRegistry: {},
        errorMessage: 'لم يتم العثور على main.dart في المشروع الحالي.',
      );
    }

    final runAppMatch = RegExp(r'runApp\s*\(').firstMatch(mainSource);
    if (runAppMatch == null) {
      return PreviewBuildResult(
        classRegistry: registry,
        errorMessage: 'لم يتم العثور على استدعاء runApp() داخل main.dart.',
      );
    }

    final argsStart = runAppMatch.end;
    final argsEnd = _matchClosingParen(mainSource, runAppMatch.end - 1);
    if (argsEnd == -1) {
      return PreviewBuildResult(
        classRegistry: registry,
        errorMessage: 'صياغة runApp() غير مكتملة أو غير مدعومة.',
      );
    }
    final exprSource = mainSource.substring(argsStart, argsEnd);

    try {
      final rootExpr = DartSubsetParser.parseExpressionSource(exprSource);
      return PreviewBuildResult(classRegistry: registry, rootExpr: rootExpr);
    } catch (e) {
      return PreviewBuildResult(
        classRegistry: registry,
        errorMessage: 'تعذّر تحليل تعبير runApp(): $e',
      );
    }
  }

  int _matchClosingParen(String text, int openIndex) {
    var depth = 0;
    for (var i = openIndex; i < text.length; i++) {
      if (text[i] == '(') depth++;
      if (text[i] == ')') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }
}
