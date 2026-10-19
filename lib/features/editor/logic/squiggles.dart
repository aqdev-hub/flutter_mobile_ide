import 'package:flutter/material.dart';

/// مدى نصي (إزاحات محارف داخل نص المحرر) يُرسَم تحته تسطير متعرّج.
class SquiggleRange {
  final int start;
  final int end;
  final Color color;
  const SquiggleRange(this.start, this.end, this.color);
}

/// يُحوِّل إزاحات تشخيصات حُسبت على [analyzedText] إلى إزاحات صالحة على
/// [currentText] (الذي تغيّر منذ التحليل بسبب الكتابة)، بدل إخفاء التسطير أو
/// رسمه في مكان خاطئ أثناء الكتابة:
/// - ما يقع قبل المنطقة المعدَّلة يبقى كما هو.
/// - ما يقع بعدها يُزاح بفرق الطول.
/// - ما يتقاطع مع المنطقة المعدَّلة يُحذف حتى يصل تحليل جديد.
List<SquiggleRange> remapSquiggles(
  List<SquiggleRange> ranges,
  String analyzedText,
  String currentText,
) {
  if (ranges.isEmpty) return const [];
  if (identical(analyzedText, currentText) || analyzedText == currentText) return ranges;

  final oldLen = analyzedText.length;
  final newLen = currentText.length;
  final minLen = oldLen < newLen ? oldLen : newLen;

  var prefix = 0;
  while (prefix < minLen && analyzedText.codeUnitAt(prefix) == currentText.codeUnitAt(prefix)) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < minLen - prefix &&
      analyzedText.codeUnitAt(oldLen - 1 - suffix) == currentText.codeUnitAt(newLen - 1 - suffix)) {
    suffix++;
  }

  final oldEditEnd = oldLen - suffix; // نهاية المنطقة المعدَّلة في النص القديم
  final delta = newLen - oldLen;
  final result = <SquiggleRange>[];
  for (final r in ranges) {
    if (r.end <= prefix) {
      result.add(r);
    } else if (r.start >= oldEditEnd) {
      result.add(SquiggleRange(r.start + delta, r.end + delta, r.color));
    }
  }
  return result;
}

/// يوسّع المدى الصفري الطول (رمز ناقص مثل فاصلة منقوطة منسيّة) إلى محرف واحد
/// ليكون مرئيًا: المحرف عند الموضع إن لم يكن سطرًا جديدًا، وإلا السابق له.
/// يُرجع null إن تعذّر (نص فارغ أو الموضع محاط بأسطر جديدة).
(int, int)? visibleRange(String text, int offset, int length) {
  if (offset < 0 || offset > text.length) return null;
  final end = offset + length;
  if (length > 0) return (offset, end > text.length ? text.length : end);
  if (offset < text.length && text[offset] != '\n' && text[offset] != '\r') return (offset, offset + 1);
  if (offset > 0 && text[offset - 1] != '\n' && text[offset - 1] != '\r') return (offset - 1, offset);
  return null;
}

/// يطبّق تسطيرًا متعرّجًا على شجرة [TextSpan] ناتجة عن المحرر دون تغيير نصها
/// (التسطير خاصية نمط فقط، فلا تتغيّر إزاحات المؤشر والتحديد).
///
/// [ranges] بإزاحات نص المحرر المرئي بالكامل. تُقسَّم الأجزاء النصية عند حدود
/// المدى فقط، وبقية الشجرة (ألوان التلوين النحوي) تبقى كما هي.
TextSpan applySquiggles(TextSpan root, List<SquiggleRange> ranges) {
  if (ranges.isEmpty) return root;
  final sorted = [...ranges]..sort((a, b) => a.start.compareTo(b.start));
  var offset = 0;

  TextStyle styleFor(Color color) => TextStyle(
        decoration: TextDecoration.underline,
        decorationStyle: TextDecorationStyle.wavy,
        decorationColor: color,
        decorationThickness: 1.6,
      );

  List<InlineSpan> pieces(String text, int base) {
    final out = <InlineSpan>[];
    var cursor = 0;
    for (final r in sorted) {
      final from = (r.start - base).clamp(0, text.length);
      final to = (r.end - base).clamp(0, text.length);
      if (to <= from || to <= cursor) continue;
      final startAt = from < cursor ? cursor : from;
      if (startAt > cursor) out.add(TextSpan(text: text.substring(cursor, startAt)));
      out.add(TextSpan(text: text.substring(startAt, to), style: styleFor(r.color)));
      cursor = to;
    }
    if (cursor < text.length) out.add(TextSpan(text: text.substring(cursor)));
    return out;
  }

  bool intersects(int from, int to) {
    for (final r in sorted) {
      if (r.start < to && r.end > from) return true;
    }
    return false;
  }

  TextSpan walk(TextSpan span) {
    final text = span.text;
    final textStart = offset;
    if (text != null) offset += text.length;

    final children = span.children;
    List<InlineSpan>? newChildren;
    if (children != null) {
      newChildren = [for (final c in children) c is TextSpan ? walk(c) : c];
    }

    final needsSplit = text != null && text.isNotEmpty && intersects(textStart, textStart + text.length);
    if (!needsSplit && newChildren == null) return span;

    return TextSpan(
      text: needsSplit ? null : text,
      children: [
        if (needsSplit) ...pieces(text!, textStart),
        ...?newChildren,
      ],
      style: span.style,
      recognizer: span.recognizer,
      mouseCursor: span.mouseCursor,
      onEnter: span.onEnter,
      onExit: span.onExit,
      semanticsLabel: span.semanticsLabel,
      locale: span.locale,
      spellOut: span.spellOut,
    );
  }

  return walk(root);
}
