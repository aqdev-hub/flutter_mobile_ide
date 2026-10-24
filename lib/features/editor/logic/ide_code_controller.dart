import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

import '../../../core/theme/app_theme.dart';
import '../../preview/logic/problems_analyzer.dart';
import 'dart_syntax_analyzer.dart';
import 'squiggles.dart';

/// [CodeController] يرسم تسطيرًا أحمر متعرّجًا تحت أخطاء صياغة Dart في موضعها
/// الدقيق، إضافةً إلى أيقونات الهامش الأصلية للمكتبة.
///
/// التسطير يعتمد على آخر نتيجة لـ[DartSyntaxAnalyzer] (الذي تستدعيه المكتبة
/// نفسها بعد 500ms من التوقف عن الكتابة). وإن تغيّر النص بعد ذلك تُزاح
/// المواضع تلقائيًا ([remapSquiggles]) فلا يقفز التسطير أو يختفي أثناء الكتابة.
///
/// لا يمسّ النص ولا المؤشر: التسطير نمط عرض فقط.
class IdeCodeController extends CodeController {
  IdeCodeController({super.text, super.language, super.analyzer});

  List<SquiggleRange> _semanticRanges = const [];
  String _semanticText = '';
  bool _disposed = false;

  /// يستقبل نتيجة التحقق الدلالي (من [ProblemsNotifier]) مع النص الذي حُسبت
  /// عليه، ليُرسم تسطير تحت مواضعها الدقيقة. أخطاء الصياغة لا تدخل هنا — يرسمها
  /// [DartSyntaxAnalyzer] بنفسه.
  void setSemanticProblems(List<ProblemItem> problems, String analyzedText) {
    final ranges = <SquiggleRange>[];
    for (final problem in problems) {
      if (problem.category != ProblemCategory.semantic) continue;
      final offset = problem.offset;
      if (offset == null) continue;
      final visible = visibleRange(analyzedText, offset, problem.length ?? 0);
      if (visible == null) continue;
      ranges.add(SquiggleRange(visible.$1, visible.$2, _colorFor(problem.severity)));
    }
    if (_sameRanges(ranges, _semanticRanges) && analyzedText == _semanticText) return;
    _semanticRanges = ranges;
    _semanticText = analyzedText;
    if (!_disposed) notifyListeners();
  }

  static Color _colorFor(ProblemSeverity severity) => switch (severity) {
        ProblemSeverity.error => IdeColors.stopRed,
        ProblemSeverity.warning => IdeColors.warningYellow,
        ProblemSeverity.info => IdeColors.accentBlue,
      };

  static bool _sameRanges(List<SquiggleRange> a, List<SquiggleRange> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].start != b[i].start || a[i].end != b[i].end || a[i].color != b[i].color) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    bool? withComposing,
  }) {
    final base = super.buildTextSpan(context: context, style: style, withComposing: withComposing);

    final currentText = fullText;
    // إن كان هناك نص مخفي (طيّ/أقسام مسماة) فإزاحات النص المرئي تختلف عن الكاملة؛
    // لا نرسم تسطيرًا خاطئًا — الهامش يبقى صحيحًا في كل الأحوال.
    if (text.length != currentText.length) return base;

    final ranges = <SquiggleRange>[];

    final a = analyzer;
    if (a is DartSyntaxAnalyzer && a.lastDiagnostics.isNotEmpty) {
      final analyzed = a.lastText;
      final syntax = <SquiggleRange>[];
      for (final d in a.lastDiagnostics) {
        final visible = visibleRange(analyzed, d.offset, d.length);
        if (visible == null) continue;
        syntax.add(SquiggleRange(visible.$1, visible.$2, IdeColors.stopRed));
      }
      ranges.addAll(remapSquiggles(syntax, analyzed, currentText));
    }

    if (_semanticRanges.isNotEmpty) {
      ranges.addAll(remapSquiggles(_semanticRanges, _semanticText, currentText));
    }

    return applySquiggles(base, ranges);
  }
}
