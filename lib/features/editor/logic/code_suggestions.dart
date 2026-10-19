import 'dart:math' as math;
import 'dart:typed_data';

import 'dart_lexical.dart';
import 'widget_catalog.dart';

enum SuggestionKind { param, widget, value, function, constant, namespace, local, keyword, snippet }

class CodeSuggestion {
  final String label;
  final String insertText;

  /// عدد المحارف التي يُرجَع بها المؤشر من نهاية النص المُدرَج (للاستدعاءات:
  /// 1 لوضع المؤشر بين القوسين).
  final int cursorBack;
  final SuggestionKind kind;

  /// اسم المواصفة في [WidgetCatalog] لعرض المساعدة (إن وُجدت).
  final String? specName;
  final String? detail;

  const CodeSuggestion({
    required this.label,
    required this.insertText,
    required this.kind,
    this.cursorBack = 0,
    this.specName,
    this.detail,
  });
}

class SignatureHint {
  final WidgetSpec spec;
  final Set<String> used;
  const SignatureHint(this.spec, this.used);
}

class SuggestionResult {
  final List<CodeSuggestion> suggestions;
  final int replaceStart;
  final int replaceEnd;
  final SignatureHint? signature;

  const SuggestionResult(this.suggestions, this.replaceStart, this.replaceEnd, this.signature);

  static const SuggestionResult empty = SuggestionResult([], 0, 0, null);
}

class _CallContext {
  final String name; // قد يكون فارغًا إن لم يُعرَف
  final bool paramPosition;
  final Set<String> used;
  const _CallContext(this.name, this.paramPosition, this.used);
}

/// محرّك الإكمال التلقائي والتلميحات — يعمل على النص ومؤشر الكتابة فقط
/// (بلا أي اعتماد على مكتبة المحرر)، ومصدره كتالوج [WidgetCatalog] +
/// السجلّ الفعلي للثوابت في `BuiltinWidgets.staticProperties`.
///
/// **ما يقترحه**:
///  - بعد `Name.`: أعضاء الثوابت (Colors.red، Icons.add...) والمُنشئات
///    المسمّاة (ListView.builder، EdgeInsets.all، Navigator.push...).
///  - داخل `Widget(` عند موضع معامل: أسماء المعاملات المسمّاة غير
///    المستخدمة بعد (تُدرَج كـ `name: `).
///  - أثناء كتابة كلمة: أسماء الودجتس/القيم/الدوال، المساحات الثابتة، أصناف
///    الملف الحالي، كلمات من الملف، والكلمات المفتاحية، وقالبَا stless/stful.
///  - لا اقتراحات داخل النصوص الحرفية أو التعليقات.
class CodeSuggestions {
  CodeSuggestions._();

  static String? _cachedText;
  static Uint8List? _cachedKinds;

  static Uint8List _kindsFor(String text) {
    if (_cachedText != null && _cachedKinds != null && _cachedText == text) {
      return _cachedKinds!;
    }
    final k = DartLexical.scan(text);
    _cachedText = text;
    _cachedKinds = k;
    return k;
  }

  static const List<String> _keywords = [
    'class', 'extends', 'StatelessWidget', 'StatefulWidget', 'State', 'build', 'return',
    'final', 'var', 'const', 'if', 'else', 'for', 'while', 'in', 'await', 'async', 'true',
    'false', 'null', 'void', 'int', 'double', 'String', 'bool', 'List', 'Map', 'Widget',
    'BuildContext', 'super', 'this', 'break', 'continue',
  ];

  static bool _isDigit(String c) {
    final u = c.codeUnitAt(0);
    return u >= 48 && u <= 57;
  }

  static SuggestionResult compute(String text, int cursor) {
    if (cursor <= 0 || cursor > text.length) return SuggestionResult.empty;
    final kind = _kindsFor(text);
    if (kind[cursor - 1] != DartLexical.code) return SuggestionResult.empty;

    var ps = cursor;
    while (ps > 0 && DartLexical.isIdChar(text[ps - 1]) && kind[ps - 1] == DartLexical.code) {
      ps--;
    }
    final partial = text.substring(ps, cursor);
    if (partial.isNotEmpty && _isDigit(partial[0])) return SuggestionResult.empty;

    String? namespace;
    if (ps > 0 && text[ps - 1] == '.' && kind[ps - 1] == DartLexical.code) {
      final isSpreadOrCascade = ps >= 2 && text[ps - 2] == '.';
      if (!isSpreadOrCascade) {
        final ne = ps - 1;
        var nsStart = ne;
        while (nsStart > 0 && DartLexical.isIdChar(text[nsStart - 1]) && kind[nsStart - 1] == DartLexical.code) {
          nsStart--;
        }
        if (nsStart == ne) return SuggestionResult.empty;
        if (nsStart > 0 && text[nsStart - 1] == '.') return SuggestionResult.empty;
        namespace = text.substring(nsStart, ne);
      }
    }

    final call = _enclosingCall(text, kind, ps);
    final spec = call == null ? null : WidgetCatalog.lookup(call.name);
    final signature = (call != null && spec != null) ? SignatureHint(spec, call.used) : null;
    final next = cursor < text.length ? text[cursor] : '';

    final lowerPartial = partial.toLowerCase();
    int score(String label) {
      if (partial.isEmpty) return 0;
      if (label.startsWith(partial)) return 0;
      final l = label.toLowerCase();
      if (l.startsWith(lowerPartial)) return 1;
      if (partial.length >= 2 && l.contains(lowerPartial)) return 2;
      return -1;
    }

    final entries = <_Entry>[];
    final seen = <String>{};

    void add(CodeSuggestion s, int priority) {
      final sc = score(s.label);
      if (sc < 0) return;
      if (!seen.add('${s.kind.index}:${s.label}')) return;
      entries.add(_Entry(s, sc, priority));
    }

    CodeSuggestion callSuggestion(String label, String insertBase, SuggestionKind k, String? specName) {
      if (next == '(') {
        return CodeSuggestion(label: label, insertText: insertBase, kind: k, specName: specName);
      }
      return CodeSuggestion(label: label, insertText: '$insertBase()', kind: k, cursorBack: 1, specName: specName);
    }

    if (namespace != null) {
      for (final m in WidgetCatalog.staticMembers(namespace)) {
        add(
          CodeSuggestion(label: m, insertText: m, kind: SuggestionKind.constant, detail: '$namespace.$m'),
          1,
        );
      }
      for (final s in WidgetCatalog.specs) {
        if (s.isDotted && s.baseName == namespace) {
          final k = s.kind == SpecKind.function
              ? SuggestionKind.function
              : (s.kind == SpecKind.value ? SuggestionKind.value : SuggestionKind.widget);
          add(callSuggestion(s.memberName, s.memberName, k, s.name), 1);
        }
      }
      return _finish(entries, ps, cursor, signature);
    }

    // أسماء المعاملات المسمّاة داخل استدعاء ودجت معروف
    if (call != null && spec != null && call.paramPosition) {
      for (final p in spec.named) {
        if (call.used.contains(p)) continue;
        add(
          CodeSuggestion(
            label: p,
            insertText: '$p: ',
            kind: SuggestionKind.param,
            specName: spec.name,
            detail: WidgetCatalog.hintFor(p),
          ),
          0,
        );
      }
    }

    if (partial.isNotEmpty) {
      final dottedBases = <String>{};
      for (final s in WidgetCatalog.specs) {
        if (s.isDotted) {
          dottedBases.add(s.baseName);
          continue;
        }
        final k = s.kind == SpecKind.function
            ? SuggestionKind.function
            : (s.kind == SpecKind.value ? SuggestionKind.value : SuggestionKind.widget);
        add(callSuggestion(s.name, s.name, k, s.name), k == SuggestionKind.function ? 2 : 1);
      }
      for (final b in dottedBases) {
        if (WidgetCatalog.lookup(b) != null) continue; // موجود كودجت عادي أعلاه
        add(CodeSuggestion(label: b, insertText: '$b.', kind: SuggestionKind.namespace), 1);
      }
      for (final ns in WidgetCatalog.staticNamespaces()) {
        add(CodeSuggestion(label: ns, insertText: '$ns.', kind: SuggestionKind.namespace), 1);
      }

      // أصناف الملف الحالي
      final classRe = RegExp(r'\bclass\s+([A-Za-z_]\w*)');
      for (final m in classRe.allMatches(text)) {
        if (kind[m.start] != DartLexical.code) continue;
        final name = m.group(1)!;
        if (name == partial) continue;
        add(callSuggestion(name, name, SuggestionKind.widget, null), 1);
      }

      // كلمات الملف (إكمال نصّي)
      final wordRe = RegExp(r'[A-Za-z_][A-Za-z0-9_]{2,}');
      var count = 0;
      for (final m in wordRe.allMatches(text)) {
        if (count > 600) break;
        if (m.start == ps || kind[m.start] != DartLexical.code) continue;
        final w = m.group(0)!;
        if (w == partial) continue;
        count++;
        add(CodeSuggestion(label: w, insertText: w, kind: SuggestionKind.local), 3);
      }

      for (final kw in _keywords) {
        add(CodeSuggestion(label: kw, insertText: kw, kind: SuggestionKind.keyword), 4);
      }

      // قوالب
      if ('stless'.startsWith(lowerPartial) && partial.length >= 2) {
        final tail = ');\n  }\n}';
        add(
          CodeSuggestion(
            label: 'stless',
            insertText: 'class MyWidget extends StatelessWidget {\n  Widget build(BuildContext context) {\n    return Container(${tail}',
            kind: SuggestionKind.snippet,
            cursorBack: tail.length,
            detail: 'قالب StatelessWidget',
          ),
          1,
        );
      }
      if ('stful'.startsWith(lowerPartial) && partial.length >= 2) {
        final tail = ');\n  }\n}';
        add(
          CodeSuggestion(
            label: 'stful',
            insertText:
                'class MyWidget extends StatefulWidget {\n  State<MyWidget> createState() => _MyWidgetState();\n}\n\nclass _MyWidgetState extends State<MyWidget> {\n  Widget build(BuildContext context) {\n    return Container(${tail}',
            kind: SuggestionKind.snippet,
            cursorBack: tail.length,
            detail: 'قالب StatefulWidget + State',
          ),
          1,
        );
      }
    }

    return _finish(entries, ps, cursor, signature);
  }

  static SuggestionResult _finish(List<_Entry> entries, int ps, int cursor, SignatureHint? sig) {
    entries.sort((a, b) {
      if (a.score != b.score) return a.score.compareTo(b.score);
      if (a.priority != b.priority) return a.priority.compareTo(b.priority);
      final la = a.s.label.length;
      final lb = b.s.label.length;
      if (la != lb) return la.compareTo(lb);
      return a.s.label.compareTo(b.s.label);
    });
    final list = entries.take(40).map((e) => e.s).toList();
    return SuggestionResult(list, ps, cursor, sig);
  }

  /// أقرب استدعاء مفتوح يحيط بالموضع [ps]، مع تحديد هل نحن عند موضع اسم
  /// معامل، وأي المعاملات المسمّاة استُخدمت بالفعل في هذا الاستدعاء.
  static _CallContext? _enclosingCall(String text, Uint8List kind, int ps) {
    var depth = 0;
    var open = -1;
    for (var i = ps - 1; i >= 0; i--) {
      if (kind[i] != DartLexical.code) continue;
      final c = text[i];
      if (c == ')' || c == ']' || c == '}') {
        depth++;
      } else if (c == '(' || c == '[' || c == '{') {
        if (depth == 0) {
          open = i;
          break;
        }
        depth--;
      }
    }
    if (open < 0 || text[open] != '(') return null;

    var e = open;
    while (e > 0 && (text[e - 1] == ' ' || text[e - 1] == '\t')) {
      e--;
    }
    var sIdx = e;
    while (sIdx > 0 && DartLexical.isIdChar(text[sIdx - 1]) && kind[sIdx - 1] == DartLexical.code) {
      sIdx--;
    }
    var name = sIdx == e ? '' : text.substring(sIdx, e);
    if (name.isNotEmpty && sIdx > 0 && text[sIdx - 1] == '.') {
      final e2 = sIdx - 1;
      var s2 = e2;
      while (s2 > 0 && DartLexical.isIdChar(text[s2 - 1]) && kind[s2 - 1] == DartLexical.code) {
        s2--;
      }
      if (s2 < e2 && !(s2 > 0 && text[s2 - 1] == '.')) {
        name = '${text.substring(s2, e2)}.$name';
      } else {
        name = '';
      }
    }

    // هل الموضع الحالي بداية معامل جديد؟ (لا نص كود منذ آخر فاصلة/قوس)
    var d = 0;
    var segStart = open + 1;
    for (var i = open + 1; i < ps; i++) {
      if (kind[i] != DartLexical.code) continue;
      final c = text[i];
      if (c == '(' || c == '[' || c == '{') {
        d++;
      } else if (c == ')' || c == ']' || c == '}') {
        d--;
      } else if (d == 0 && c == ',') {
        segStart = i + 1;
      }
    }
    final sb = StringBuffer();
    for (var i = segStart; i < ps; i++) {
      if (kind[i] == DartLexical.code) sb.write(text[i]);
    }
    final paramPosition = sb.toString().trim().isEmpty;

    // المعاملات المسمّاة المستخدمة (خارج المقطع الجاري كتابته)
    final used = <String>{};
    final nameRe = RegExp(r'^\s*([A-Za-z_]\w*)\s*:');
    var depth2 = 0;
    var segS = open + 1;
    var closed = false;

    void flush(int segEnd) {
      if (segS <= ps && ps <= segEnd) return;
      final b = StringBuffer();
      for (var i = segS; i < segEnd; i++) {
        if (kind[i] == DartLexical.code) b.write(text[i]);
      }
      final m = nameRe.firstMatch(b.toString());
      if (m != null) used.add(m.group(1)!);
    }

    for (var i = open + 1; i < text.length; i++) {
      if (kind[i] != DartLexical.code) continue;
      final c = text[i];
      if (c == '(' || c == '[' || c == '{') {
        depth2++;
      } else if (c == ')' || c == ']' || c == '}') {
        if (depth2 == 0) {
          flush(i);
          closed = true;
          break;
        }
        depth2--;
      } else if (depth2 == 0 && c == ',') {
        flush(i);
        segS = i + 1;
      }
    }
    if (!closed) flush(text.length);

    return _CallContext(name, paramPosition, used);
  }

  /// المواصفة المناسبة لزر "المساعدة": الكلمة تحت المؤشر (أو `A.b`) إن كانت
  /// معروفة، وإلا الاستدعاء الذي يحيط بالمؤشر.
  static WidgetSpec? helpSpecAt(String text, int cursor) {
    if (text.isEmpty) return null;
    final c = math.min(math.max(cursor, 0), text.length);
    final kind = _kindsFor(text);
    var s = c;
    while (s > 0 && DartLexical.isIdChar(text[s - 1])) {
      s--;
    }
    var e = c;
    while (e < text.length && DartLexical.isIdChar(text[e])) {
      e++;
    }
    if (e > s) {
      final word = text.substring(s, e);
      if (s > 0 && text[s - 1] == '.') {
        var s2 = s - 1;
        final ne = s2;
        while (s2 > 0 && DartLexical.isIdChar(text[s2 - 1])) {
          s2--;
        }
        if (s2 < ne) {
          final dotted = WidgetCatalog.lookup('${text.substring(s2, ne)}.$word');
          if (dotted != null) return dotted;
        }
      }
      final direct = WidgetCatalog.lookup(word);
      if (direct != null) return direct;
      // الاسم قبل نقطة (مثل ListView في ListView.builder)
      if (e < text.length && text[e] == '.') {
        var e2 = e + 1;
        while (e2 < text.length && DartLexical.isIdChar(text[e2])) {
          e2++;
        }
        final dotted = WidgetCatalog.lookup('$word.${text.substring(e + 1, e2)}');
        if (dotted != null) return dotted;
      }
    }
    final call = _enclosingCall(text, kind, s);
    if (call != null && call.name.isNotEmpty) return WidgetCatalog.lookup(call.name);
    return null;
  }
}

class _Entry {
  final CodeSuggestion s;
  final int score;
  final int priority;
  const _Entry(this.s, this.score, this.priority);
}
