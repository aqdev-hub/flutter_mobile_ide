import 'package:flutter_code_editor/flutter_code_editor.dart';

import '../../preview/logic/syntax_diagnostics.dart';

/// محلل Dart للمحرر: يربط محلل Dart الرسمي ([SyntaxDiagnostics]) بآلية
/// `CodeController.analyzer` الأصلية في flutter_code_editor، فتظهر الأخطاء في
/// هامش المحرر (أيقونة بجانب رقم السطر + نافذة بالرسالة عند النقر)، مع
/// استفادة مجانية من تأخير 500ms وتجاهل النتائج المتقادمة المدمجَين في المكتبة.
///
/// يحتفظ بآخر نتيجة (مع نصها) ليرسم [IdeCodeController] التسطير المتعرّج
/// تحت الموضع الدقيق (سطر/عمود/طول) — فالهامش يعرف السطر فقط ([Issue.line]).
class DartSyntaxAnalyzer extends AbstractAnalyzer {
  DartSyntaxAnalyzer();

  String _lastText = '';
  List<SyntaxDiagnostic> _lastDiagnostics = const [];

  /// النص الذي حُسبت عليه [lastDiagnostics].
  String get lastText => _lastText;
  List<SyntaxDiagnostic> get lastDiagnostics => _lastDiagnostics;

  @override
  Future<AnalysisResult> analyze(Code code) async {
    final text = code.text;
    List<SyntaxDiagnostic> diagnostics;
    try {
      diagnostics = SyntaxDiagnostics.analyze(text);
    } catch (_) {
      diagnostics = const [];
    }
    _lastText = text;
    _lastDiagnostics = diagnostics;

    return AnalysisResult(
      issues: [
        for (final d in diagnostics)
          Issue(
            // Issue.line يبدأ من 0 (راجع gutter في المكتبة)، وموضعنا يبدأ من 1.
            line: d.line - 1,
            message: d.message,
            type: IssueType.error,
            suggestion: d.originalMessage,
          ),
      ],
    );
  }
}
