import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

import '../../../core/theme/app_theme.dart';
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

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    bool? withComposing,
  }) {
    final base = super.buildTextSpan(context: context, style: style, withComposing: withComposing);

    final a = analyzer;
    if (a is! DartSyntaxAnalyzer || a.lastDiagnostics.isEmpty) return base;

    final currentText = fullText;
    // إن كان هناك نص مخفي (طيّ/أقسام مسماة) فإزاحات النص المرئي تختلف عن الكاملة؛
    // لا نرسم تسطيرًا خاطئًا — الهامش يبقى صحيحًا في كل الأحوال.
    if (text.length != currentText.length) return base;

    final analyzed = a.lastText;
    final ranges = <SquiggleRange>[];
    for (final d in a.lastDiagnostics) {
      final visible = visibleRange(analyzed, d.offset, d.length);
      if (visible == null) continue;
      ranges.add(SquiggleRange(visible.$1, visible.$2, IdeColors.stopRed));
    }
    final mapped = remapSquiggles(ranges, analyzed, currentText);
    return applySquiggles(base, mapped);
  }
}
