import 'dart:typed_data';

/// ماسح معجمي خفيف مشترك بين المنسِّق ([DartFormatter]) ومحرّك الاقتراحات:
/// يُصنِّف **كل محرف** في النص إلى: كود (0)، داخل نص حرفي (1)، أو داخل
/// تعليق (2) — بحيث لا تُعالَج أبدًا الأقواس/الفواصل/المسافات الموجودة
/// داخل النصوص والتعليقات كأنها كود.
///
/// يدعم: `//` و`/* */` (متداخلة)، النصوص بعلامة ' أو "، النصوص الثلاثية،
/// النصوص الخام r'...'، والاستيفاء `${...}` بما فيه نصوص متداخلة داخله
/// (مثل `'a ${b['x']} c'`).
class DartLexical {
  DartLexical._();

  static const int code = 0;
  static const int string = 1;
  static const int comment = 2;

  static bool isIdChar(String c) {
    if (c.isEmpty) return false;
    final u = c.codeUnitAt(0);
    return (u >= 48 && u <= 57) ||
        (u >= 65 && u <= 90) ||
        (u >= 97 && u <= 122) ||
        u == 95 ||
        u == 36;
  }

  static Uint8List scan(String s) {
    final n = s.length;
    final kind = Uint8List(n);

    int scanString(int start) {
      var i = start;
      var raw = false;
      if (s[i] == 'r' && i + 1 < n && (s[i + 1] == "'" || s[i + 1] == '"')) {
        raw = true;
        i++;
      }
      final q = s[i];
      final triple = s.startsWith(q * 3, i);
      i += triple ? 3 : 1;
      while (i < n) {
        final c = s[i];
        if (!raw && c == '\\') {
          i += 2;
          continue;
        }
        if (!raw && c == '\$' && i + 1 < n && s[i + 1] == '{') {
          i += 2;
          var depth = 1;
          while (i < n && depth > 0) {
            final ch = s[i];
            if (ch == "'" || ch == '"') {
              i = scanString(i);
            } else if (ch == 'r' &&
                i + 1 < n &&
                (s[i + 1] == "'" || s[i + 1] == '"') &&
                (i == 0 || !isIdChar(s[i - 1]))) {
              i = scanString(i);
            } else if (ch == '{') {
              depth++;
              i++;
            } else if (ch == '}') {
              depth--;
              i++;
            } else {
              i++;
            }
          }
          continue;
        }
        if (triple) {
          if (s.startsWith(q * 3, i)) {
            i += 3;
            break;
          }
        } else {
          if (c == q) {
            i++;
            break;
          }
          if (c == '\n') break;
        }
        i++;
      }
      if (i > n) i = n;
      for (var k = start; k < i; k++) {
        kind[k] = string;
      }
      return i;
    }

    var i = 0;
    while (i < n) {
      final c = s[i];
      final nx = i + 1 < n ? s[i + 1] : '';
      if (c == '/' && nx == '/') {
        var j = s.indexOf('\n', i);
        if (j == -1) j = n;
        for (var k = i; k < j; k++) {
          kind[k] = comment;
        }
        i = j;
      } else if (c == '/' && nx == '*') {
        var depth = 1;
        var j = i + 2;
        while (j < n && depth > 0) {
          if (s[j] == '/' && j + 1 < n && s[j + 1] == '*') {
            depth++;
            j += 2;
          } else if (s[j] == '*' && j + 1 < n && s[j + 1] == '/') {
            depth--;
            j += 2;
          } else {
            j++;
          }
        }
        final end = j > n ? n : j;
        for (var k = i; k < end; k++) {
          kind[k] = comment;
        }
        i = j;
      } else if (c == "'" || c == '"') {
        i = scanString(i);
      } else if (c == 'r' &&
          (nx == "'" || nx == '"') &&
          (i == 0 || !isIdChar(s[i - 1]))) {
        i = scanString(i);
      } else {
        i++;
      }
    }
    return kind;
  }
}
