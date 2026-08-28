import 'dart_subset_ast.dart';
import 'dart_subset_parser.dart';

/// مشكلة واحدة اكتُشفت أثناء استخراج الأصناف — تغذّي تبويب "Problems" في
/// الواجهة. رقم السطر تقريبي (يُحسَب بعدّ أسطر جديد حتى موضع المشكلة)، وقد
/// يكون null إن تعذّر حسابه بدقة.
class ExtractionIssue {
  final String message;
  final int? line;
  const ExtractionIssue(this.message, {this.line});
}

/// يمسح نص Dart بحثًا عن تعريفات أصناف (class) عبر مطابقة الأقواس نصيًا،
/// بدل بناء محلّل Dart كامل للغة كلها. هذا كافٍ لاستخراج:
/// - اسم الصنف والصنف الأب (StatelessWidget / StatefulWidget / State<X>)
/// - حقول بسيطة declarations مثل `int _counter = 0;`
/// - جسم دالة build كاملًا (قائمة جُمل)
/// - دوال مساعدة أخرى مُعرَّفة داخل نفس الصنف (غير build/createState)
///
/// **تحديث**: كل خلل استخراج (كان يُسجَّل سابقًا عبر print() صامت لا يصل
/// للمستخدم إطلاقًا) يُجمَع الآن في [issues] — هذه هي القائمة التي يعرضها
/// تبويب "Problems" في الواجهة. هذا يجعل الاستخراج "شفافًا": بدل أن يختفي
/// جزء من الكود بصمت لأن الاستخراج فشل عليه، يظهر تحذير واضح بالسبب.
class ClassExtractor {
  final String source;
  // اسم الملف (وليس المسار الكامل) — يُمرَّر إلى كل WidgetClassDef مُستخرَج
  // منه، ليظهر في تنسيق موضع الخطأ الموحَّد "اسم_الملف.dart — السطر N".
  final String? fileName;
  final List<ExtractionIssue> issues = [];

  ClassExtractor(this.source, {this.fileName});

  int _lineAt(int absoluteOffset) {
    var line = 1;
    final limit = absoluteOffset.clamp(0, source.length);
    for (var i = 0; i < limit; i++) {
      if (source[i] == '\n') line++;
    }
    return line;
  }

  List<WidgetClassDef> extractAll() {
    final defs = <WidgetClassDef>[];
    final classRegex = RegExp(r'class\s+(\w+)\s+extends\s+([\w<>]+)\s*\{');
    for (final match in classRegex.allMatches(source)) {
      final name = match.group(1)!;
      final baseType = match.group(2)!;
      final bodyStart = match.end - 1; // موضع '{' الافتتاحي
      final bodyEnd = _matchClosingBrace(source, bodyStart);
      if (bodyEnd == -1) {
        issues.add(ExtractionIssue('لم يتم إيجاد قوس إغلاق مطابق للصنف "$name"', line: _lineAt(bodyStart)));
        continue;
      }
      final body = source.substring(bodyStart + 1, bodyEnd);

      try {
        final baseName = baseType.startsWith('State<') ? 'State' : baseType;
        final (buildBody, buildParseError) = _extractBuildBody(body, bodyStart, name);
        defs.add(WidgetClassDef(
          name: name,
          baseType: baseName,
          stateClassName: baseType.startsWith('State<')
              ? baseType.substring('State<'.length, baseType.length - 1)
              : _findStateClassNameInBody(body),
          // نستخدم نسخة "مُقنَّعة" من body لاستخراج الحقول فقط (تُخفي كل ما
          // هو داخل أي {} متداخل، أي أجسام الدوال) — هذا يمنع التقاط
          // متغيرات محلية معرَّفة داخل build/الدوال المساعدة كحقول حالة
          // دائمة بالخطأ.
          fields: _extractFields(_maskNestedBlocks(body), bodyStart, name),
          buildBody: buildBody,
          buildParseError: buildParseError,
          methods: _extractMethods(body, bodyStart, name),
          sourceFile: fileName,
        ));
      } catch (e) {
        // خلل في استخراج صنف واحد لا يجب أن يُسقط بقية أصناف الملف —
        // نتخطى هذا الصنف فقط مع تسجيل السبب كمشكلة ظاهرة للمستخدم.
        issues.add(ExtractionIssue('تعذّر استخراج الصنف "$name": $e', line: _lineAt(bodyStart)));
      }
    }
    return defs;
  }

  /// لأصناف StatefulWidget: نبحث داخل نص الصنف نفسه عن
  /// `createState() => _XState();` أو الصيغة بالأقواس المعقوفة، لمعرفة اسم
  /// صنف الحالة المرتبط بهذا الودجت.
  String? _findStateClassNameInBody(String classBody) {
    final regex = RegExp(r'createState\s*\(\s*\)\s*(?:=>|\{[^}]*return)\s*(\w+)\s*\(');
    return regex.firstMatch(classBody)?.group(1);
  }

  int _matchClosingBrace(String text, int openIndex) {
    var depth = 0;
    for (var i = openIndex; i < text.length; i++) {
      if (text[i] == '{') depth++;
      if (text[i] == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// يستبدل كل محتوى داخل أي `{}` متداخل (أجسام الدوال، الحلقات، الشروط...)
  /// بمسافات (مع الإبقاء على أسطر جديد لحساب أرقام الأسطر بدقة)، مُبقيًا
  /// فقط النص عند "المستوى صفر" من الصنف. يعزل استخراج الحقول تمامًا عن أي
  /// محتوى إجرائي.
  String _maskNestedBlocks(String classBody) {
    final buffer = StringBuffer();
    var depth = 0;
    for (var i = 0; i < classBody.length; i++) {
      final ch = classBody[i];
      if (ch == '{') {
        depth++;
        buffer.write(' ');
        continue;
      }
      if (ch == '}') {
        if (depth > 0) depth--;
        buffer.write(' ');
        continue;
      }
      if (depth > 0) {
        buffer.write(ch == '\n' ? '\n' : ' ');
      } else {
        buffer.write(ch);
      }
    }
    return buffer.toString();
  }

  List<FieldDecl> _extractFields(String maskedClassBody, int bodyStart, String className) {
    final fields = <FieldDecl>[];
    final fieldRegex = RegExp(
      r'(?:final\s+|var\s+)?[\w<>?]+\s+(_?\w+)\s*=\s*([^;]+);',
      multiLine: true,
    );
    for (final match in fieldRegex.allMatches(maskedClassBody)) {
      final name = match.group(1)!;
      final initSource = match.group(2)!;
      final absoluteOffset = bodyStart + 1 + match.start;
      try {
        fields.add(FieldDecl(name, DartSubsetParser.parseExpressionSource(initSource)));
      } catch (e) {
        issues.add(ExtractionIssue(
          'تعذّر تحليل تهيئة الحقل "$name" في الصنف "$className": $e',
          line: _lineAt(absoluteOffset),
        ));
      }
    }
    return fields;
  }

  /// يستخرج جسم build **كاملًا** كقائمة جُمل (يسمح بمتغيرات محلية/حلقات/
  /// شروط قبل الجملة الأخيرة return). يُعيد أيضًا رسالة الخطأ الحقيقية عند
  /// الفشل (بدل الاكتفاء بـ null) حتى تظهر للمستخدم أثناء التشغيل الفعلي،
  /// وليس فقط في تبويب Problems.
  (List<Stmt>?, String?) _extractBuildBody(String classBody, int bodyStart, String className) {
    final arrowMatch =
        RegExp(r'Widget\s+build\s*\(\s*BuildContext\s+\w+\s*\)\s*=>').firstMatch(classBody);
    if (arrowMatch != null) {
      final rest = classBody.substring(arrowMatch.end);
      final semicolon = rest.indexOf(';');
      final exprSrc = semicolon == -1 ? rest : rest.substring(0, semicolon);
      try {
        return ([ReturnStmt(DartSubsetParser.parseExpressionSource(exprSrc))], null);
      } catch (e) {
        final msg = 'تعذّر تحليل تعبير build في الصنف "$className": $e';
        issues.add(ExtractionIssue(msg, line: _lineAt(bodyStart + 1 + arrowMatch.end)));
        return (null, msg);
      }
    }

    final blockMatch =
        RegExp(r'Widget\s+build\s*\(\s*BuildContext\s+\w+\s*\)\s*\{').firstMatch(classBody);
    if (blockMatch == null) {
      // لا توجد دالة build إطلاقًا في هذا الصنف — طبيعي لأصناف StatefulWidget
      // (build موجودة في صنف State وليس هنا)، لذا لا نُسجّل هذا كمشكلة أو
      // كخطأ، فقط نُعيد (null, null) بصمت.
      return (null, null);
    }
    final start = blockMatch.end - 1;
    final end = _matchClosingBrace(classBody, start);
    if (end == -1) {
      final msg = 'قوس دالة build في الصنف "$className" غير مغلَق بشكل صحيح';
      issues.add(ExtractionIssue(msg, line: _lineAt(bodyStart + 1 + start)));
      return (null, msg);
    }
    final bodyText = classBody.substring(start + 1, end);
    try {
      return (DartSubsetParser.parseStatementsSource(bodyText), null);
    } catch (e) {
      final msg = 'تعذّر تحليل جسم build في الصنف "$className": $e';
      issues.add(ExtractionIssue(msg, line: _lineAt(bodyStart + 1 + start)));
      return (null, msg);
    }
  }

  /// يحسب عمق التداخل بالأقواس المعقوفة {} عند كل موضع في النص — يُستخدَم
  /// لتصفية مطابقات استخراج الدوال المساعدة، حتى لا نلتقط أنماطًا تُشبه
  /// تعريف دالة (مثل `setState(() {` أو `builder: (context) {`) وهي في
  /// الحقيقة إغلاقات (closures) متداخلة داخل دالة أخرى (خصوصًا build نفسها).
  List<int> _computeDepthAtEachPosition(String text) {
    final depthAt = List<int>.filled(text.length + 1, 0);
    var depth = 0;
    for (var i = 0; i < text.length; i++) {
      depthAt[i] = depth;
      if (text[i] == '{') depth++;
      if (text[i] == '}') depth = depth > 0 ? depth - 1 : 0;
    }
    depthAt[text.length] = depth;
    return depthAt;
  }

  /// يستخرج كل الدوال المُعرَّفة داخل الصنف عدا build/createState.
  ///
  /// **إصلاح جوهري**: كنا سابقًا نفحص النص الكامل غير المُقنَّع بحثًا عن نمط
  /// "اسم(معاملات) {"، وهذا كان يلتقط أي إغلاق (closure) متداخل داخل build
  /// (أشيعها: `setState(() { ... })`) ويُسجِّله خطأً كدالة مساعدة على مستوى
  /// الصنف، بحدود أقواس مُلتقَطة من موضع خاطئ تمامًا — ما كان يُفسد سجلّ
  /// الدوال بطرق غير متوقعة (ومنها على الأرجح خطأ "value غير معروف" الذي
  /// ظهر أثناء الاختبار). الآن نتحقق أن كل مطابقة تبدأ عند "المستوى صفر"
  /// من الصنف فعليًا (خارج أي {} متداخل بالفعل) قبل قبولها.
  List<MethodDef> _extractMethods(String classBody, int bodyStart, String className) {
    final methods = <MethodDef>[];
    final depthAt = _computeDepthAtEachPosition(classBody);
    final methodRegex = RegExp(
      r'(?:^|\n)[ \t]*(?:[\w<>?\[\],\s]+?)\s+(_?\w+)\s*\(([^)]*)\)\s*(\{|=>)',
      multiLine: true,
    );
    for (final match in methodRegex.allMatches(classBody)) {
      // تجاهل أي مطابقة داخل {} متداخل بالفعل — ليست تعريف دالة حقيقي على
      // مستوى الصنف، بل جزء من جسم دالة أخرى (غالبًا closure متداخل).
      if (depthAt[match.start] != 0) continue;

      final name = match.group(1)!;
      if (name == 'build' || name == 'createState') continue;

      final paramsRaw = match.group(2)!.trim();
      final isArrow = match.group(3) == '=>';
      final params = paramsRaw.isEmpty
          ? <String>[]
          : paramsRaw
              .split(',')
              .map((p) => p.trim())
              .where((p) => p.isNotEmpty)
              .map((p) => p.split(RegExp(r'\s+')).last)
              .toList();

      final absoluteOffset = bodyStart + 1 + match.start;
      try {
        List<Stmt> body;
        if (isArrow) {
          final rest = classBody.substring(match.end);
          final semicolon = rest.indexOf(';');
          final exprSrc = semicolon == -1 ? rest : rest.substring(0, semicolon);
          body = [ReturnStmt(DartSubsetParser.parseExpressionSource(exprSrc))];
        } else {
          final braceStart = match.end - 1;
          final braceEnd = _matchClosingBrace(classBody, braceStart);
          if (braceEnd == -1) {
            issues.add(ExtractionIssue(
              'قوس الدالة "$name" في الصنف "$className" غير مغلَق بشكل صحيح',
              line: _lineAt(absoluteOffset),
            ));
            continue;
          }
          final bodyText = classBody.substring(braceStart + 1, braceEnd);
          body = DartSubsetParser.parseStatementsSource(bodyText);
        }
        methods.add(MethodDef(name, params, body));
      } catch (e) {
        issues.add(ExtractionIssue(
          'تعذّر تحليل الدالة "$name" في الصنف "$className": $e',
          line: _lineAt(absoluteOffset),
        ));
      }
    }
    return methods;
  }
}
