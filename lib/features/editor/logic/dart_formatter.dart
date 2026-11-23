import 'dart:math' as math;

import 'dart_lexical.dart';

class FormatResult {
  final String text;
  final bool changed;
  final String? error;
  const FormatResult(this.text, this.changed, this.error);
}

/// منسِّق Dart **معجمي** (لا يحلّل الكود دلاليًا) — يعمل على أي نص Dart حتى
/// لو خرج عن المجموعة الجزئية التي يفهمها مُفسِّر المعاينة، ولا يرفض الكود
/// أبدًا.
///
/// **ما يفعله**:
///  - إعادة حساب المسافة البادئة (2 مسافة لكل مستوى) من هيكل الأقواس
///    `() [] {}`، مع إزاحة إضافية (4) لأسطر الاستمرار (سلاسل `.method()`،
///    `? :`، `&&`/`||`، وما بعد `=`/`+`/`=>` في نهاية السطر) و2 للـcascade.
///  - مسافة واحدة بعد الفاصلة، وإزالة المسافات قبل `, ; ) ]` وبعد `( [`،
///    ودمج المسافات المتعددة داخل السطر، ومسافة بعد if/for/while/switch/catch،
///    ومسافة قبل `{`، ومسافة حول `=` المفردة، ومسافة بعد `name:` للمعاملات
///    المُسمّاة.
///  - إزالة المسافات الزائدة في نهاية الأسطر، ودمج الأسطر الفارغة المتتالية،
///    وسطر جديد واحد في النهاية.
///
/// **ما لا يفعله (حدود صريحة)**: لا يقصّ الأسطر الطويلة، لا يضبط المسافات
/// حول العمليات `+ - * / < > == &&`، لا يُزيح أجسام `case` داخل switch.
///
/// **ضمان السلامة**: يتغيّر **المسافات والأسطر الفارغة فقط** — بعد التنسيق
/// تُقارَن سلسلة المحارف غير البيضاء قبل/بعد، وإن اختلفت بأي حرف يُلغى
/// التنسيق ويُعاد النص الأصلي كما هو مع رسالة خطأ. النصوص الحرفية
/// (بما فيها متعددة الأسطر) والتعليقات لا تُلمَس أبدًا.
class DartFormatter {
  DartFormatter._();

  static final RegExp _ws = RegExp(r'\s+');
  static final RegExp _named = RegExp(r'[(,{\[]\s*[A-Za-z_$][\w$]*$');
  static final RegExp _identOnly = RegExp(r'^[A-Za-z_$][\w$]*$');

  static FormatResult format(String source) {
    try {
      final formatted = _formatCore(source);
      if (source.replaceAll(_ws, '') != formatted.replaceAll(_ws, '')) {
        return FormatResult(
          source,
          false,
          'أُلغي التنسيق: فحص السلامة اكتشف اختلافًا في المحارف غير البيضاء (لم يتغيّر شيء).',
        );
      }
      return FormatResult(formatted, formatted != source, null);
    } catch (e) {
      return FormatResult(source, false, 'تعذّر التنسيق: $e');
    }
  }

  /// يحوّل موضع مؤشر في النص الأصلي إلى موضعه المكافئ في النص المنسَّق
  /// (بعدّ المحارف غير البيضاء قبل المؤشر، لأن التنسيق لا يغيّرها).
  static int mapOffset(String original, String formatted, int offset) {
    final end = math.min(math.max(offset, 0), original.length);
    var count = 0;
    for (var i = 0; i < end; i++) {
      if (!_isWs(original[i])) count++;
    }
    if (count == 0) return 0;
    var seen = 0;
    for (var i = 0; i < formatted.length; i++) {
      if (!_isWs(formatted[i])) {
        seen++;
        if (seen == count) return i + 1;
      }
    }
    return formatted.length;
  }

  static bool _isWs(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';

  static String _tail(List<String> out, int count) {
    final from = math.max(0, out.length - count);
    return out.sublist(from).join();
  }

  static bool _endsWithWord(String tail, List<String> words) {
    for (final w in words) {
      if (tail.endsWith(w)) {
        if (tail.length == w.length) return true;
        final p = tail[tail.length - w.length - 1];
        if (!DartLexical.isIdChar(p) && p != '.') return true;
      }
    }
    return false;
  }

  static bool _isAlnumUnderscore(String c) {
    if (c.length != 1) return false;
    final u = c.codeUnitAt(0);
    return (u >= 48 && u <= 57) || (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || u == 95;
  }

  static String _formatCore(String src) {
    final s = src.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final n = s.length;
    final kind = DartLexical.scan(s);

    final starts = <int>[0];
    for (var i = 0; i < n; i++) {
      if (s[i] == '\n') starts.add(i + 1);
    }

    final outLines = <String>[];
    final stack = <int>[]; // مستوى إزاحة السطر الذي فتح كل قوس
    var prevEnd = '';
    var prevBlank = true;

    for (var li = 0; li < starts.length; li++) {
      final ls = starts[li];
      if (ls >= n && li == starts.length - 1) break;
      var le = s.indexOf('\n', ls);
      if (le == -1) le = n;

      final verbatim = ls > 0 && kind[ls - 1] != 0;
      final endsInside = le < n && kind[le] != 0;

      if (verbatim) {
        // سطر يبدأ داخل نص/تعليق متعدد الأسطر — يُترك حرفيًا.
        outLines.add(s.substring(ls, le));
        prevBlank = false;
        final vlevel = stack.isNotEmpty ? stack.last + 1 : 0;
        for (var jx = ls; jx < le; jx++) {
          if (kind[jx] == 0) {
            final ch = s[jx];
            if (ch == '(' || ch == '[' || ch == '{') {
              stack.add(vlevel);
            } else if (ch == ')' || ch == ']' || ch == '}') {
              if (stack.isNotEmpty) stack.removeLast();
            }
          }
        }
        var jv = le - 1;
        while (jv >= ls && (kind[jv] == 2 || (kind[jv] == 0 && (s[jv] == ' ' || s[jv] == '\t')))) {
          jv--;
        }
        if (jv >= ls && kind[jv] == 0) {
          prevEnd = s.substring(math.max(ls, jv - 1), jv + 1);
        } else if (jv >= ls && kind[jv] == 1) {
          prevEnd = '"';
        }
        continue;
      }

      var lp = ls;
      while (lp < le && kind[lp] == 0 && (s[lp] == ' ' || s[lp] == '\t')) {
        lp++;
      }
      if (lp >= le) {
        if (!prevBlank) {
          outLines.add('');
          prevBlank = true;
        }
        continue;
      }

      // أقواس الإغلاق في بداية السطر
      var lead = 0;
      var q = lp;
      while (q < le && kind[q] == 0 && (s[q] == ')' || s[q] == ']' || s[q] == '}')) {
        lead++;
        q++;
      }
      final popped = <int>[];
      for (var k = 0; k < lead; k++) {
        if (stack.isNotEmpty) popped.add(stack.removeLast());
      }
      final levels = popped.isNotEmpty ? popped.first : (stack.isNotEmpty ? stack.last + 1 : 0);

      final first = s[lp];
      final second = lp + 1 < le ? s[lp + 1] : '';
      var cont = false;
      var cascade = false;
      if (lead == 0 && kind[lp] == 0) {
        if (first == '.' && second != '.') {
          cont = true;
        } else if (first == '.' && second == '.' && !s.startsWith('...', lp)) {
          cont = true;
          cascade = true;
        } else if (first == '?' || (first == ':' && (second == ' ' || second == ''))) {
          cont = true;
        } else if (s.startsWith('&&', lp) ||
            s.startsWith('||', lp) ||
            first == '+' ||
            first == '*' ||
            first == '%' ||
            s.startsWith('==', lp) ||
            s.startsWith('!=', lp)) {
          cont = true;
        }
      }
      if (!cont && lead == 0 && prevEnd.isNotEmpty) {
        final last = prevEnd[prevEnd.length - 1];
        if (('=+*/%?'.contains(last) && prevEnd != '++' && prevEnd != '--') ||
            prevEnd == '&&' ||
            prevEnd == '||' ||
            prevEnd == '??' ||
            prevEnd == '=>') {
          cont = true;
        }
      }
      if (!cont && lead == 0 && kind[lp] == 1 && prevEnd == '"') {
        cont = true;
      }
      final extra = cont ? (cascade ? 1 : 2) : 0;

      // آلة المسافات داخل السطر
      final out = <String>[];
      var j = lp;
      while (j < le) {
        final ch = s[j];
        final k = kind[j];
        if (k != 0) {
          out.add(ch);
          j++;
          continue;
        }
        if (ch == ' ' || ch == '\t') {
          var m = j;
          while (m < le && kind[m] == 0 && (s[m] == ' ' || s[m] == '\t')) {
            m++;
          }
          if (m >= le) {
            if (endsInside) out.add(s.substring(j, m));
            j = m;
            continue;
          }
          final nxt = s[m];
          final nk = kind[m];
          final prev = out.isNotEmpty ? out.last : '';
          if (nk == 0 && (nxt == ',' || nxt == ';')) {
            // لا مسافة قبل الفاصلة/الفاصلة المنقوطة
          } else if (nk == 0 && (nxt == ')' || nxt == ']')) {
            // لا مسافة قبل قوس الإغلاق
          } else if ((prev == '(' || prev == '[') && nk != 2) {
            // لا مسافة بعد قوس الفتح
          } else {
            out.add(' ');
          }
          j = m;
          continue;
        }
        if (ch == ',') {
          out.add(',');
          if (j + 1 < le) {
            final nx = s[j + 1];
            final nkk = kind[j + 1];
            if (!(nkk == 0 && (nx == ' ' || nx == '\t' || nx == ')' || nx == ']' || nx == '}'))) {
              out.add(' ');
            }
          }
          j++;
          continue;
        }
        if (ch == '(') {
          if (_endsWithWord(_tail(out, 10), const ['if', 'for', 'while', 'switch', 'catch'])) {
            out.add(' ');
          }
          out.add('(');
          j++;
          continue;
        }
        if (ch == '{') {
          if (out.isNotEmpty && out.last == ')') {
            out.add(' ');
          } else if (out.isNotEmpty && _isAlnumUnderscore(out.last) && kind[j - 1] == 0) {
            out.add(' ');
          }
          out.add('{');
          j++;
          continue;
        }
        if (ch == ':') {
          out.add(':');
          if (j + 1 < le) {
            final nx = s[j + 1];
            final nkk = kind[j + 1];
            if (!(nkk == 0 && (nx == ' ' || nx == '\t' || nx == ':'))) {
              final tail = out.length > 1
                  ? out.sublist(math.max(0, out.length - 60), out.length - 1).join()
                  : '';
              final atStart = _identOnly.hasMatch(tail) &&
                  prevEnd.isNotEmpty &&
                  '(,{['.contains(prevEnd[prevEnd.length - 1]);
              if (_named.hasMatch(tail) || atStart) out.add(' ');
            }
          }
          j++;
          continue;
        }
        if (ch == '=') {
          final nx = j + 1 < le ? s[j + 1] : '';
          final pv = out.isNotEmpty ? out.last : '';
          if (nx == '=' || nx == '>' || (pv.length == 1 && '!<>=+-*/%&|^~?'.contains(pv))) {
            out.add('=');
            j++;
            continue;
          }
          if (pv.isNotEmpty && pv != ' ' && pv != '(' && pv != '[') out.add(' ');
          out.add('=');
          if (j + 1 < le && !(kind[j + 1] == 0 && (nx == ' ' || nx == '\t'))) out.add(' ');
          j++;
          continue;
        }
        if ((ch == 'e' || ch == 'c' || ch == 'f') && out.isNotEmpty && out.last == '}') {
          for (final w in const ['else', 'catch', 'finally']) {
            if (s.startsWith(w, j) && !(j + w.length < le && DartLexical.isIdChar(s[j + w.length]))) {
              out.add(' ');
              break;
            }
          }
        }
        out.add(ch);
        j++;
      }

      var text = out.join();
      if (!endsInside) text = text.trimRight();
      final lineLevel = levels + extra;
      outLines.add('${'  ' * lineLevel}$text');
      prevBlank = false;

      for (var jj = q; jj < le; jj++) {
        if (kind[jj] == 0) {
          final ch = s[jj];
          if (ch == '(' || ch == '[' || ch == '{') {
            stack.add(lineLevel);
          } else if (ch == ')' || ch == ']' || ch == '}') {
            if (stack.isNotEmpty) stack.removeLast();
          }
        }
      }

      var je = le - 1;
      while (je >= lp && (kind[je] == 2 || (kind[je] == 0 && (s[je] == ' ' || s[je] == '\t')))) {
        je--;
      }
      if (je >= lp && kind[je] == 0) {
        prevEnd = s.substring(math.max(lp, je - 1), je + 1);
      } else if (je >= lp && kind[je] == 1) {
        prevEnd = '"';
      }
    }

    while (outLines.isNotEmpty && outLines.last.isEmpty) {
      outLines.removeLast();
    }
    if (outLines.isEmpty) return '';
    return '${outLines.join('\n')}\n';
  }
}
