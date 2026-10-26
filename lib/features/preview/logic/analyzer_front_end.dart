import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart' as ast;

import 'dart_subset_ast.dart';

/// واجهة المُفسِّر الأمامية المبنية على محلل Dart الرسمي (analyzer، تحليل نحوي
/// فقط): تقرأ **صياغة Dart القياسية كاملة** وتُنتج نفس عقد AST الخاصة بالمُفسِّر
/// ([dart_subset_ast.dart]) — فيبقى المُفسِّر نفسه كما هو دون تعديل.
///
/// ما يُحوَّل بالتبسيط (desugaring) إلى عقد موجودة أصلًا:
///  - `a ?? b`، `a?.b`، `a?.f()`، `a ??= b`: إلى تعبير شرطي. **يُقيَّم الطرف
///    الأيسر مرتين**، لذلك لا يُقبل إلا إن كان خاليًا من الاستدعاءات
///    (معرّف/خاصية/فهرسة/ثابت) وإلا يُرفَض بوضوح.
///  - `a!` و`x as T`: إلى `x`.
///  - `...xs` و`if (c) x` و`if (c) ...xs` داخل القوائم: إلى `for` عنصرية.
///  - `*=` و`/=` و`%=`: إلى `x = x * v`.
///  - الدوال المحلية: إلى متغير يحمل lambda.
///  - `this.x`: إلى `x` (الحقول تُحلّ بالاسم في المُفسِّر).
///  - `super.method()`: إلى لا شيء (null).
///
/// ما لا يُدعَم (يُرفَض برسالة "قيد في المعاينة" بسطره الصحيح بدل null صامت):
/// cascade (`..`)، `try/catch`، `switch`، `do-while`، `is`، تعبيرات `throw`،
/// العمليات البتّية، `++`/`--` كتعبير داخل تعبير، الكائنات العادية (غير
/// الودجتس) وحقولها/دوالها static — وهذه الأخيرة هي موضوع الدفعة التالية
/// (نموذج الكائنات).
class AnalyzerFrontEnd {
  AnalyzerFrontEnd._();

  /// يحوّل ملفًا واحدًا. لا يرمي استثناءً؛ النتيجة تصف ما حدث.
  static FrontEndFileResult extractFile(String source, {required String fileName}) {
    final parsed = parseString(content: source, throwIfDiagnostics: false);
    if (parsed.errors.isNotEmpty) {
      return FrontEndFileResult(
        classes: const [],
        issues: const [],
        hasSyntaxErrors: true,
      );
    }
    final converter = _Converter(
      fileName,
      (offset) => parsed.lineInfo.getLocation(offset).lineNumber,
    );
    for (final decl in parsed.unit.declarations) {
      if (decl is ast.ClassDeclaration) converter.classDecl(decl);
    }
    return FrontEndFileResult(
      classes: converter.classes,
      issues: converter.issues,
      hasSyntaxErrors: false,
    );
  }

  /// تعبير الودجت الجذري داخل `runApp(...)` في دالة `main`، أو null إن لم
  /// يوجد/تعذّر تحويله ([issues] يُملأ بالسبب).
  static Expr? extractRunAppRoot(String source, {required String fileName, List<FrontEndIssue>? issues}) {
    final parsed = parseString(content: source, throwIfDiagnostics: false);
    if (parsed.errors.isNotEmpty) return null;
    final converter = _Converter(
      fileName,
      (offset) => parsed.lineInfo.getLocation(offset).lineNumber,
    );
    try {
      for (final decl in parsed.unit.declarations) {
        if (decl is! ast.FunctionDeclaration || decl.name.lexeme != 'main') continue;
        final body = decl.functionExpression.body;
        final candidates = <ast.Expression>[];
        if (body is ast.ExpressionFunctionBody) {
          candidates.add(body.expression);
        } else if (body is ast.BlockFunctionBody) {
          for (final s in body.block.statements) {
            if (s is ast.ExpressionStatement) candidates.add(s.expression);
          }
        }
        for (final e in candidates) {
          final call = e is ast.AwaitExpression ? e.expression : e;
          if (call is ast.MethodInvocation && call.target == null && call.methodName.name == 'runApp') {
            final args = call.argumentList.arguments;
            if (args.isEmpty) return null;
            return converter.expr(args.first.argumentExpression);
          }
        }
      }
    } on UnsupportedConstruct catch (e) {
      issues?.add(FrontEndIssue(e.message, line: e.line, isError: true));
    }
    return null;
  }
}

class FrontEndIssue {
  final String message;
  final int? line;
  final bool isError;
  const FrontEndIssue(this.message, {this.line, this.isError = false});
}

class FrontEndFileResult {
  final List<WidgetClassDef> classes;
  final List<FrontEndIssue> issues;
  final bool hasSyntaxErrors;

  const FrontEndFileResult({
    required this.classes,
    required this.issues,
    required this.hasSyntaxErrors,
  });

  bool get hasConversionErrors => issues.any((i) => i.isError);

  /// هل يصلح هذا الملف للاعتماد عليه بدل المُستخرِج القديم؟
  bool get usable => !hasSyntaxErrors && !hasConversionErrors;

  /// سبب عدم الصلاحية (للاستعمال في ملاحظة الكونسول).
  String get unusableReason {
    if (hasSyntaxErrors) return 'خطأ صياغة (يعالجه المُستخرِج القديم)';
    final first = issues.firstWhere((i) => i.isError, orElse: () => const FrontEndIssue(''));
    return first.line == null ? first.message : '${first.message} (السطر ${first.line})';
  }
}

class UnsupportedConstruct implements Exception {
  final String message;
  final int? line;
  UnsupportedConstruct(this.message, {this.line});
  @override
  String toString() => message;
}

class _Converter {
  final String file;
  final int Function(int offset) lineOf;
  final List<WidgetClassDef> classes = [];
  final List<FrontEndIssue> issues = [];

  _Converter(this.file, this.lineOf);

  // ------------------------- أدوات عامة -------------------------

  Never _unsupported(String what, ast.AstNode node) =>
      throw UnsupportedConstruct('قيد في المعاينة: $what', line: lineOf(node.offset));

  IdentifierExpr _ident(String name, int offset) => IdentifierExpr(name)
    ..line = lineOf(offset)
    ..file = file;

  CallExpr _call(Expr callee, List<Expr> pos, Map<String, Expr> named, int offset) =>
      CallExpr(callee, pos, named)
        ..line = lineOf(offset)
        ..file = file;

  bool _isPure(Expr e) =>
      e is IdentifierExpr ||
      e is LiteralExpr ||
      (e is PropertyExpr && _isPure(e.target)) ||
      (e is IndexExpr && _isPure(e.target) && _isPure(e.index));

  Expr _requirePure(Expr e, ast.AstNode node, String op) {
    if (!_isPure(e)) {
      _unsupported('العملية $op مع تعبير يحوي استدعاءً (يُقيَّم مرتين في المُفسِّر الحالي) — ضع القيمة في متغيّر أولًا', node);
    }
    return e;
  }

  Expr _nullTest(Expr value, String op) => BinaryExpr(value, op, LiteralExpr(null));

  // ------------------------- الأصناف -------------------------

  void classDecl(ast.ClassDeclaration d) {
    final name = d.namePart.typeName.lexeme;
    final ext = d.extendsClause?.superclass;
    final superName = ext?.name.lexeme;
    final typeArgs = ext?.typeArguments?.arguments;
    final superArg = (typeArgs != null && typeArgs.isNotEmpty) ? typeArgs.first.toSource() : null;

    final isStateless = superName == 'StatelessWidget';
    final isStateful = superName == 'StatefulWidget';
    final isState = superName == 'State';
    final isWidget = isStateless || isStateful;

    final members = d.body.members;
    final fields = <FieldDecl>[];
    final methods = <MethodDef>[];
    List<Stmt>? buildBody;
    String? buildParseError;
    String? stateClassName = isState ? superArg : null;

    // معاملات المُنشئ الموضعية للودجتس (لربط الوسائط الموضعية بأسماء الحقول).
    final positionalCtorParams = <String>[];
    if (isWidget) {
      for (final m in members) {
        if (m is ast.ConstructorDeclaration && m.name == null) {
          for (final p in m.parameters.parameters) {
            final n = p.name;
            if (n == null) continue;
            if (p.isPositional) positionalCtorParams.add(n.lexeme);
            if (p.defaultClause != null) {
              issues.add(FrontEndIssue(
                'الصنف $name: القيمة الافتراضية للمعامل "${n.lexeme}" في المُنشئ لا تُطبَّق في المعاينة بعد.',
                line: lineOf(p.offset),
              ));
            }
          }
        }
      }
    }
    for (final p in positionalCtorParams) {
      fields.add(FieldDecl(p, null));
    }

    for (final m in members) {
      if (m is ast.FieldDeclaration) {
        if (m.isStatic) {
          issues.add(FrontEndIssue('الصنف $name: حقل static غير مدعوم في المعاينة بعد.', line: lineOf(m.offset)));
          continue;
        }
        for (final v in m.fields.variables) {
          final fieldName = v.name.lexeme;
          if (positionalCtorParams.contains(fieldName)) continue;
          try {
            final init = v.initializer;
            fields.add(FieldDecl(fieldName, init == null ? null : expr(init)));
          } on UnsupportedConstruct catch (e) {
            issues.add(FrontEndIssue('الصنف $name، الحقل "$fieldName": ${e.message}', line: e.line, isError: true));
          }
        }
      } else if (m is ast.MethodDeclaration) {
        final methodName = m.name.lexeme;
        if (m.isGetter || m.isSetter || m.isOperator) {
          issues.add(FrontEndIssue('الصنف $name: ${m.isGetter ? 'getter' : m.isSetter ? 'setter' : 'operator'} "$methodName" غير مدعوم في المعاينة بعد.', line: lineOf(m.offset)));
          continue;
        }
        if (m.isStatic) {
          issues.add(FrontEndIssue('الصنف $name: الدالة static "$methodName" غير مدعومة في المعاينة بعد.', line: lineOf(m.offset)));
          continue;
        }
        if (methodName == 'createState') {
          stateClassName ??= _createdStateName(m);
          continue;
        }
        final fnBody = m.body;
        if (fnBody is ast.EmptyFunctionBody) continue; // abstract

        try {
          final params = m.parameters;
          final names = <String>[];
          var hasNamed = false;
          for (final p in params?.parameters ?? const <ast.FormalParameter>[]) {
            final n = p.name;
            if (n == null) continue;
            if (p.isNamed) {
              hasNamed = true;
              continue;
            }
            names.add(n.lexeme);
          }
          if (hasNamed) {
            issues.add(FrontEndIssue('الصنف $name، الدالة "$methodName": الوسائط المسمّاة غير مدعومة في الدوال المساعدة بعد (تُهمَل عند الاستدعاء).', line: lineOf(m.offset)));
          }
          var body = _functionBody(fnBody);
          if (methodName == 'build') {
            // المُفسِّر يربط BuildContext باسم "context" دائمًا: نُضيف اسمًا بديلًا
            // إن سمّاه المستخدم بغير ذلك (مثل ctx).
            final alias = names.isNotEmpty ? names.first : null;
            if (alias != null && alias != 'context') {
              body = [
                VarDeclStmt(alias, _ident('context', m.offset))
                  ..line = lineOf(m.offset)
                  ..file = file,
                ...body,
              ];
            }
            buildBody = body;
          } else {
            methods.add(MethodDef(methodName, names, body, isAsync: fnBody.isAsynchronous));
          }
        } on UnsupportedConstruct catch (e) {
          final msg = 'الصنف $name، الدالة "$methodName": ${e.message}';
          issues.add(FrontEndIssue(msg, line: e.line, isError: true));
          if (methodName == 'build') buildParseError = msg;
        }
      }
    }

    String? baseType;
    if (isState) {
      baseType = 'State';
    } else if (isStateful) {
      baseType = 'StatefulWidget';
    } else if (isStateless) {
      baseType = 'StatelessWidget';
    } else {
      baseType = superName;
      buildParseError ??=
          'الصنف $name ليس ودجت${superName == null ? '' : ' (يرث $superName)'} — دعم الأصناف العادية '
          '(حقول/دوال/static/مُنشئات) قيد التطوير في المعاينة.';
    }

    classes.add(WidgetClassDef(
      name: name,
      baseType: baseType,
      stateClassName: stateClassName,
      fields: fields,
      buildBody: buildBody,
      buildParseError: buildParseError,
      methods: methods,
      sourceFile: file,
    ));
  }

  /// اسم صنف الحالة الذي تُعيده `createState()` (مثل `_HomeState` من
  /// `createState() => _HomeState();` أو `{ return _HomeState(); }`).
  String? _createdStateName(ast.MethodDeclaration m) {
    ast.Expression? returned;
    final b = m.body;
    if (b is ast.ExpressionFunctionBody) {
      returned = b.expression;
    } else if (b is ast.BlockFunctionBody) {
      for (final s in b.block.statements) {
        if (s is ast.ReturnStatement) {
          returned = s.expression;
          break;
        }
      }
    }
    if (returned is ast.MethodInvocation && returned.target == null) return returned.methodName.name;
    if (returned is ast.InstanceCreationExpression) return returned.constructorName.type.name.lexeme;
    return null;
  }

  // ------------------------- أجسام الدوال والجمل -------------------------

  List<Stmt> _functionBody(ast.FunctionBody body) {
    if (body is ast.ExpressionFunctionBody) {
      return [
        ReturnStmt(expr(body.expression))
          ..line = lineOf(body.expression.offset)
          ..file = file,
      ];
    }
    if (body is ast.BlockFunctionBody) return _block(body.block);
    return const [];
  }

  List<Stmt> _block(ast.Block block) => [for (final s in block.statements) ...stmt(s)];

  /// جملة أو كتلة كقائمة جُمل (جسم if/for/while).
  List<Stmt> _bodyOf(ast.Statement s) => s is ast.Block ? _block(s) : stmt(s);

  List<Stmt> stmt(ast.Statement s) {
    final out = _stmtInner(s);
    final line = lineOf(s.offset);
    for (final x in out) {
      if (x.line == 0) x.line = line;
      x.file ??= file;
    }
    return out;
  }

  List<Stmt> _stmtInner(ast.Statement s) {
    if (s is ast.Block) return _block(s);
    if (s is ast.EmptyStatement) return const [];
    if (s is ast.ExpressionStatement) return [_exprStmt(s.expression)];
    if (s is ast.ReturnStatement) {
      final e = s.expression;
      return [ReturnStmt(e == null ? null : expr(e))];
    }
    if (s is ast.VariableDeclarationStatement) {
      return [
        for (final v in s.variables.variables)
          VarDeclStmt(v.name.lexeme, v.initializer == null ? null : expr(v.initializer!)),
      ];
    }
    if (s is ast.IfStatement) {
      if (s.caseClause != null) _unsupported('if-case (مطابقة الأنماط)', s);
      final elseS = s.elseStatement;
      return [IfStmt(expr(s.expression), _bodyOf(s.thenStatement), elseS == null ? const [] : _bodyOf(elseS))];
    }
    if (s is ast.ForStatement) return [_forStatement(s)];
    if (s is ast.WhileStatement) return [WhileStmt(expr(s.condition), _bodyOf(s.body))];
    if (s is ast.BreakStatement) return [BreakStmt()];
    if (s is ast.ContinueStatement) return [ContinueStmt()];
    if (s is ast.FunctionDeclarationStatement) {
      final fn = s.functionDeclaration;
      return [VarDeclStmt(fn.name.lexeme, _lambda(fn.functionExpression))];
    }
    _unsupported('الجملة من نوع ${s.runtimeType} (مثل try/catch وswitch وdo-while)', s);
  }

  Stmt _forStatement(ast.ForStatement s) {
    if (s.awaitKeyword != null) _unsupported('await for', s);
    final parts = s.forLoopParts;
    final body = _bodyOf(s.body);
    if (parts is ast.ForEachPartsWithDeclaration) {
      return ForInStmt(parts.loopVariable.name.lexeme, expr(parts.iterable), body);
    }
    if (parts is ast.ForPartsWithDeclarations) {
      final vars = parts.variables.variables;
      if (vars.length != 1) _unsupported('أكثر من متغير في تهيئة حلقة for', s);
      final v = vars.first;
      final init = VarDeclStmt(v.name.lexeme, v.initializer == null ? null : expr(v.initializer!))
        ..line = lineOf(v.offset)
        ..file = file;
      return ForStmt(init, parts.condition == null ? null : expr(parts.condition!), _updater(parts, s), body);
    }
    if (parts is ast.ForPartsWithExpression) {
      final init = parts.initialization == null ? null : _exprStmt(parts.initialization!);
      return ForStmt(init, parts.condition == null ? null : expr(parts.condition!), _updater(parts, s), body);
    }
    _unsupported('شكل حلقة for غير مدعوم', s);
  }

  Stmt? _updater(ast.ForParts parts, ast.AstNode node) {
    final updaters = parts.updaters;
    if (updaters.isEmpty) return null;
    if (updaters.length > 1) _unsupported('أكثر من تعبير تحديث في حلقة for', node);
    return _exprStmt(updaters.first);
  }

  Stmt _exprStmt(ast.Expression e) {
    final result = _exprStmtInner(e);
    result
      ..line = lineOf(e.offset)
      ..file = file;
    return result;
  }

  Stmt _exprStmtInner(ast.Expression e) {
    if (e is ast.AssignmentExpression) return _assignment(e);
    if (e is ast.PostfixExpression && (e.operator.lexeme == '++' || e.operator.lexeme == '--')) {
      return IncDecStmt(_target(e.operand), e.operator.lexeme);
    }
    if (e is ast.PrefixExpression && (e.operator.lexeme == '++' || e.operator.lexeme == '--')) {
      return IncDecStmt(_target(e.operand), e.operator.lexeme);
    }
    return ExprStmt(expr(e));
  }

  Expr _target(ast.Expression e) {
    if (e is ast.PropertyAccess && e.target is ast.ThisExpression) return _ident(e.propertyName.name, e.offset);
    return expr(e);
  }

  Stmt _assignment(ast.AssignmentExpression e) {
    final target = _target(e.leftHandSide);
    final value = expr(e.rightHandSide);
    switch (e.operator.lexeme) {
      case '=':
      case '+=':
      case '-=':
        return AssignStmt(target, e.operator.lexeme, value);
      case '*=':
      case '/=':
      case '%=':
        _requirePure(target, e, e.operator.lexeme);
        return AssignStmt(target, '=', BinaryExpr(target, e.operator.lexeme.substring(0, 1), value));
      case '??=':
        _requirePure(target, e, '??=');
        return AssignStmt(target, '=', TernaryExpr(_nullTest(target, '!='), target, value));
    }
    _unsupported('عامل التعيين ${e.operator.lexeme}', e);
  }

  // ------------------------- التعبيرات -------------------------

  Expr expr(ast.Expression e) {
    if (e is ast.ParenthesizedExpression) return expr(e.expression);
    if (e is ast.IntegerLiteral) {
      final v = e.value;
      if (v == null) _unsupported('عدد صحيح خارج المدى', e);
      return LiteralExpr(v);
    }
    if (e is ast.DoubleLiteral) return LiteralExpr(e.value);
    if (e is ast.BooleanLiteral) return LiteralExpr(e.value);
    if (e is ast.NullLiteral) return LiteralExpr(null);
    if (e is ast.SimpleStringLiteral) return LiteralExpr(e.value);
    if (e is ast.StringInterpolation) return _interpolation([e]);
    if (e is ast.AdjacentStrings) return _interpolation(e.strings);
    if (e is ast.SimpleIdentifier) return _ident(e.name, e.offset);
    if (e is ast.PrefixedIdentifier) {
      return PropertyExpr(_ident(e.prefix.name, e.prefix.offset), e.identifier.name);
    }
    if (e is ast.PropertyAccess) return _propertyAccess(e);
    if (e is ast.MethodInvocation) return _methodInvocation(e);
    if (e is ast.InstanceCreationExpression) return _creation(e);
    if (e is ast.ListLiteral) return ListExpr(_listElements(e.elements));
    if (e is ast.SetOrMapLiteral) return _mapLiteral(e);
    if (e is ast.BinaryExpression) return _binary(e);
    if (e is ast.PrefixExpression) {
      final op = e.operator.lexeme;
      if (op == '!' || op == '-') return UnaryExpr(op, expr(e.operand));
      _unsupported('العامل الأحادي $op', e);
    }
    if (e is ast.PostfixExpression) {
      if (e.operator.lexeme == '!') return expr(e.operand);
      _unsupported('العامل ${e.operator.lexeme} داخل تعبير', e);
    }
    if (e is ast.ConditionalExpression) {
      return TernaryExpr(expr(e.condition), expr(e.thenExpression), expr(e.elseExpression));
    }
    if (e is ast.IndexExpression) {
      final target = e.target;
      if (target == null) _unsupported('فهرسة داخل cascade', e);
      final t = expr(target);
      final index = IndexExpr(t, expr(e.index));
      if (e.isNullAware) {
        _requirePure(t, e, '?[]');
        return TernaryExpr(_nullTest(t, '=='), LiteralExpr(null), index);
      }
      return index;
    }
    if (e is ast.FunctionExpression) return _lambda(e);
    if (e is ast.AwaitExpression) return AwaitExpr(expr(e.expression));
    if (e is ast.AsExpression) return expr(e.expression);
    if (e is ast.ThisExpression) _unsupported('استخدام this كقيمة', e);
    if (e is ast.CascadeExpression) _unsupported('cascade (..)', e);
    if (e is ast.IsExpression) _unsupported('is / is!', e);
    _unsupported('التعبير من نوع ${e.runtimeType}', e);
  }

  Expr _interpolation(List<ast.StringLiteral> strings) {
    final parts = <Object>[];
    void addText(String s) {
      if (s.isEmpty) return;
      if (parts.isNotEmpty && parts.last is String) {
        parts[parts.length - 1] = (parts.last as String) + s;
      } else {
        parts.add(s);
      }
    }

    for (final s in strings) {
      if (s is ast.SimpleStringLiteral) {
        addText(s.value);
      } else if (s is ast.StringInterpolation) {
        for (final el in s.elements) {
          if (el is ast.InterpolationString) {
            addText(el.value);
          } else if (el is ast.InterpolationExpression) {
            parts.add(expr(el.expression));
          }
        }
      } else {
        _unsupported('نص من نوع ${s.runtimeType}', s);
      }
    }
    if (parts.isEmpty) return LiteralExpr('');
    if (parts.length == 1 && parts.first is String) return LiteralExpr(parts.first);
    return InterpolationExpr(parts);
  }

  Expr _propertyAccess(ast.PropertyAccess e) {
    final target = e.target;
    if (target == null) _unsupported('وصول خاصية داخل cascade', e);
    if (target is ast.ThisExpression) return _ident(e.propertyName.name, e.offset);
    final t = expr(target);
    final prop = PropertyExpr(t, e.propertyName.name);
    if (e.isNullAware) {
      _requirePure(t, e, '?.');
      return TernaryExpr(_nullTest(t, '=='), LiteralExpr(null), prop);
    }
    return prop;
  }

  (List<Expr>, Map<String, Expr>) _args(ast.ArgumentList list) {
    final pos = <Expr>[];
    final named = <String, Expr>{};
    for (final a in list.arguments) {
      if (a is ast.NamedArgument) {
        named[a.name.lexeme] = expr(a.argumentExpression);
      } else {
        pos.add(expr(a.argumentExpression));
      }
    }
    return (pos, named);
  }

  Expr _methodInvocation(ast.MethodInvocation n) {
    if (n.isCascaded) _unsupported('cascade (..)', n);
    final target = n.target;
    final name = n.methodName.name;
    if (target is ast.SuperExpression) return LiteralExpr(null); // super.initState() ...
    final (pos, named) = _args(n.argumentList);
    if (target == null || target is ast.ThisExpression) {
      return _call(_ident(name, n.methodName.offset), pos, named, n.offset);
    }
    final t = expr(target);
    final call = _call(PropertyExpr(t, name), pos, named, n.offset);
    if (n.isNullAware) {
      _requirePure(t, n, '?.');
      return TernaryExpr(_nullTest(t, '=='), LiteralExpr(null), call);
    }
    return call;
  }

  Expr _creation(ast.InstanceCreationExpression n) {
    final type = n.constructorName.type.name.lexeme;
    final ctor = n.constructorName.name?.name;
    final (pos, named) = _args(n.argumentList);
    final typeIdent = _ident(type, n.constructorName.type.offset);
    final callee = ctor == null ? typeIdent : PropertyExpr(typeIdent, ctor);
    return _call(callee, pos, named, n.offset);
  }

  Expr _binary(ast.BinaryExpression e) {
    final op = e.operator.lexeme;
    final left = expr(e.leftOperand);
    final right = expr(e.rightOperand);
    switch (op) {
      case '+':
      case '-':
      case '*':
      case '/':
      case '%':
      case '==':
      case '!=':
      case '<':
      case '>':
      case '<=':
      case '>=':
      case '&&':
      case '||':
        return BinaryExpr(left, op, right);
      case '??':
        _requirePure(left, e, '??');
        return TernaryExpr(_nullTest(left, '!='), left, right);
    }
    _unsupported('العامل $op', e);
  }

  Expr _mapLiteral(ast.SetOrMapLiteral e) {
    final entries = <MapEntryNode>[];
    for (final el in e.elements) {
      if (el is ast.MapLiteralEntry) {
        entries.add(MapEntryNode(expr(el.key), expr(el.value)));
      } else {
        _unsupported('عنصر ${el.runtimeType} داخل Map/Set (Set أو spread أو if غير مدعومة)', el);
      }
    }
    return MapExpr(entries);
  }

  // ------------------------- عناصر القوائم -------------------------

  ListExpr _emptyList() => ListExpr(<Object>[]);
  ListExpr _singleton() => ListExpr(<Object>[LiteralExpr(0)]);

  List<Object> _listElements(Iterable<ast.CollectionElement> elements) => [
        for (final el in elements) ..._collect(el, null),
      ];

  /// يحوّل عنصر قائمة إلى عناصر المُفسِّر (Expr أو ListForElement...). [guard]
  /// شرط تراكمي من `if` المحيطة (أو null).
  List<Object> _collect(ast.CollectionElement el, Expr? guard) {
    if (el is ast.Expression) {
      final value = expr(el);
      if (guard == null) return [value];
      return [ListForElement('_if', TernaryExpr(guard, _singleton(), _emptyList()), value)];
    }
    if (el is ast.SpreadElement) {
      var iterable = expr(el.expression);
      if (el.isNullAware) {
        _requirePure(iterable, el, '...?');
        iterable = TernaryExpr(_nullTest(iterable, '!='), iterable, _emptyList());
      }
      if (guard != null) iterable = TernaryExpr(guard, iterable, _emptyList());
      return [ListForElement('_sp', iterable, _ident('_sp', el.offset))];
    }
    if (el is ast.IfElement) {
      if (el.caseClause != null) _unsupported('if-case داخل قائمة', el);
      final cond = expr(el.expression);
      final thenGuard = guard == null ? cond : BinaryExpr(guard, '&&', cond);
      final out = <Object>[..._collect(el.thenElement, thenGuard)];
      final elseEl = el.elseElement;
      if (elseEl != null) {
        final negated = UnaryExpr('!', cond);
        out.addAll(_collect(elseEl, guard == null ? negated : BinaryExpr(guard, '&&', negated)));
      }
      return out;
    }
    if (el is ast.ForElement) {
      if (guard != null) _unsupported('for داخل if في قائمة', el);
      if (el.awaitKeyword != null) _unsupported('await for', el);
      final body = el.body;
      if (body is! ast.Expression) _unsupported('عنصر مركّب داخل for في قائمة (فقط تعبير واحد مدعوم)', el);
      final parts = el.forLoopParts;
      if (parts is ast.ForEachPartsWithDeclaration) {
        return [ListForElement(parts.loopVariable.name.lexeme, expr(parts.iterable), expr(body))];
      }
      if (parts is ast.ForPartsWithDeclarations) {
        final vars = parts.variables.variables;
        if (vars.length != 1) _unsupported('أكثر من متغير في for داخل قائمة', el);
        final v = vars.first;
        final init = VarDeclStmt(v.name.lexeme, v.initializer == null ? null : expr(v.initializer!))
          ..line = lineOf(v.offset)
          ..file = file;
        return [
          ListClassicForElement(
            init,
            parts.condition == null ? null : expr(parts.condition!),
            _updater(parts, el),
            expr(body),
          ),
        ];
      }
      _unsupported('شكل for داخل قائمة غير مدعوم', el);
    }
    _unsupported('عنصر قائمة من نوع ${el.runtimeType}', el);
  }

  // ------------------------- الدوال المجهولة -------------------------

  LambdaExpr _lambda(ast.FunctionExpression f) {
    final params = <String>[];
    for (final p in f.parameters?.parameters ?? const <ast.FormalParameter>[]) {
      final n = p.name;
      if (n != null) params.add(n.lexeme);
    }
    return LambdaExpr(params, _functionBody(f.body), isAsync: f.body.isAsynchronous);
  }
}
