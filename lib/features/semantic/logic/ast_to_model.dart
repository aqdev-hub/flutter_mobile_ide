import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';

import '../data/expr_model.dart';
import '../data/project_model.dart';

/// يحوّل شجرة Dart الحقيقية (محلل Dart الرسمي، تحليل نحوي فقط) إلى
/// [FileModel] — النموذج الذي يقرؤه الفهرس والمدقِّق الدلالي.
///
/// هذا هو الملف الوحيد في طبقة التحقق الدلالي الذي يعرف واجهة `package:analyzer`،
/// فأي تغيّر في إصداراتها يبقى معزولًا هنا.
///
/// **الشجرة غير محلولة (unresolved)**: لا أنواع ولا عناصر، لذلك تظهر استدعاءات
/// المُنشئات العادية `Foo(...)` كـMethodInvocation، و`a.b` كـPrefixedIdentifier —
/// والمدقِّق هو من يقرّر بالفهرس ماذا يعني كلٌّ منها.
class AstToModel {
  AstToModel._();

  static FileModel build(String path, String text) {
    final result = parseString(content: text, throwIfDiagnostics: false);
    final unit = result.unit;

    final converter = _Converter(path);
    for (final decl in unit.declarations) {
      converter.declaration(decl);
    }

    final imports = <ImportInfo>[];
    var skip = false;
    for (final directive in unit.directives) {
      if (directive is ImportDirective) {
        imports.add(_namespace(directive, isExport: false, prefix: directive.prefix?.name));
      } else if (directive is ExportDirective) {
        imports.add(_namespace(directive, isExport: true, prefix: null));
      } else if (directive is PartDirective || directive is PartOfDirective) {
        skip = true;
      }
    }

    final errors = result.errors;
    int? firstLine;
    if (errors.isNotEmpty) {
      var minOffset = errors.first.offset;
      for (final e in errors) {
        if (e.offset < minOffset) minOffset = e.offset;
      }
      firstLine = result.lineInfo.getLocation(minOffset).lineNumber;
    }

    return FileModel(
      path: path,
      text: text,
      classes: converter.classes,
      topLevel: converter.topLevel,
      imports: imports,
      bodies: converter.bodies,
      syntaxErrorCount: errors.length,
      firstSyntaxErrorLine: firstLine,
      extendedTypes: converter.extendedTypes,
      skipSemantic: skip,
    );
  }

  static ImportInfo _namespace(NamespaceDirective d, {required bool isExport, required String? prefix}) {
    final show = <String>[];
    final hide = <String>[];
    for (final c in d.combinators) {
      if (c is ShowCombinator) {
        show.addAll(c.shownNames.map((n) => n.name));
      } else if (c is HideCombinator) {
        hide.addAll(c.hiddenNames.map((n) => n.name));
      }
    }
    return ImportInfo(
      uri: d.uri.stringValue ?? '',
      prefix: prefix,
      isExport: isExport,
      isDeferred: d is ImportDirective && d.deferredKeyword != null,
      show: show,
      hide: hide,
      offset: d.uri.offset,
      length: d.uri.length,
    );
  }
}

class _Converter {
  final String path;
  final List<ClassInfo> classes = [];
  final List<TopLevelDecl> topLevel = [];
  final List<XBody> bodies = [];
  final List<String> extendedTypes = [];

  _Converter(this.path);

  // ------------------------- الإعلانات -------------------------

  void declaration(CompilationUnitMember decl) {
    if (decl is ClassDeclaration) {
      _class(decl);
    } else if (decl is MixinDeclaration) {
      _mixin(decl);
    } else if (decl is EnumDeclaration) {
      _enum(decl);
    } else if (decl is FunctionDeclaration) {
      _topFunction(decl);
    } else if (decl is TopLevelVariableDeclaration) {
      _topVariables(decl);
    } else if (decl is ExtensionDeclaration) {
      _extension(decl);
    }
  }

  List<String> _typeParamNames(TypeParameterList? list) =>
      list == null ? const [] : [for (final t in list.typeParameters) t.name.lexeme];

  void _class(ClassDeclaration d) {
    final part = d.namePart;
    final name = part.typeName.lexeme;
    final members = <MemberInfo>[];
    final ctors = <ConstructorInfo>[];

    if (part is PrimaryConstructorDeclaration) {
      ctors.add(ConstructorInfo(
        name: part.constructorName?.name.lexeme ?? '',
        params: _params(part.formalParameters),
        isConst: part.constKeyword != null,
        offset: part.offset,
      ));
      for (final p in part.formalParameters.parameters) {
        final pn = p.name;
        if (pn != null && p.constFinalOrVarKeyword != null) {
          members.add(MemberInfo(
            name: pn.lexeme,
            kind: MemberKind.field,
            typeSource: p.type?.toSource(),
            offset: pn.offset,
            length: pn.length,
          ));
        }
      }
    }

    _members(d.body.members, name, members, ctors);

    classes.add(ClassInfo(
      name: name,
      filePath: path,
      kind: ClassKind.classDecl,
      isAbstract: d.abstractKeyword != null,
      superclass: d.extendsClause?.superclass.toSource(),
      mixins: [for (final t in d.withClause?.mixinTypes ?? const <NamedType>[]) t.toSource()],
      interfaces: [for (final t in d.implementsClause?.interfaces ?? const <NamedType>[]) t.toSource()],
      typeParams: _typeParamNames(part.typeParameters),
      constructors: ctors,
      members: members,
      offset: part.typeName.offset,
      length: part.typeName.length,
    ));
  }

  void _mixin(MixinDeclaration d) {
    final name = d.name.lexeme;
    final members = <MemberInfo>[];
    final ctors = <ConstructorInfo>[];
    _members(d.body.members, name, members, ctors);
    classes.add(ClassInfo(
      name: name,
      filePath: path,
      kind: ClassKind.mixinDecl,
      interfaces: [
        for (final t in d.implementsClause?.interfaces ?? const <NamedType>[]) t.toSource(),
        for (final t in d.onClause?.superclassConstraints ?? const <NamedType>[]) t.toSource(),
      ],
      typeParams: _typeParamNames(d.typeParameters),
      members: members,
      offset: d.name.offset,
      length: d.name.length,
    ));
  }

  void _enum(EnumDeclaration d) {
    final part = d.namePart;
    final name = part.typeName.lexeme;
    final members = <MemberInfo>[];
    final ctors = <ConstructorInfo>[];
    for (final c in d.body.constants) {
      members.add(MemberInfo(
        name: c.name.lexeme,
        kind: MemberKind.enumValue,
        isStatic: true,
        offset: c.name.offset,
        length: c.name.length,
      ));
      _addBody(name, true, [c.arguments]);
    }
    // أعضاء كل enum الضمنية.
    members.add(const MemberInfo(name: 'values', kind: MemberKind.field, isStatic: true, typeSource: 'List'));
    members.add(const MemberInfo(name: 'name', kind: MemberKind.getter, typeSource: 'String'));
    members.add(const MemberInfo(name: 'index', kind: MemberKind.getter, typeSource: 'int'));
    _members(d.body.members, name, members, ctors);
    classes.add(ClassInfo(
      name: name,
      filePath: path,
      kind: ClassKind.enumDecl,
      mixins: [for (final t in d.withClause?.mixinTypes ?? const <NamedType>[]) t.toSource()],
      interfaces: [for (final t in d.implementsClause?.interfaces ?? const <NamedType>[]) t.toSource()],
      typeParams: _typeParamNames(part.typeParameters),
      constructors: ctors,
      members: members,
      offset: part.typeName.offset,
      length: part.typeName.length,
    ));
  }

  void _extension(ExtensionDeclaration d) {
    final on = d.onClause?.extendedType.toSource();
    final base = on == null ? null : TypeName.parse(on)?.base;
    if (base != null) extendedTypes.add(base);
    _members(d.body.members, null, <MemberInfo>[], <ConstructorInfo>[]);
  }

  void _members(NodeList<ClassMember> list, String? owner, List<MemberInfo> members, List<ConstructorInfo> ctors) {
    for (final m in list) {
      if (m is FieldDeclaration) {
        final typeSrc = m.fields.type?.toSource();
        for (final v in m.fields.variables) {
          members.add(MemberInfo(
            name: v.name.lexeme,
            kind: MemberKind.field,
            isStatic: m.isStatic,
            typeSource: typeSrc,
            inferredType: typeSrc == null ? _inferType(v.initializer) : null,
            offset: v.name.offset,
            length: v.name.length,
          ));
          _addBody(owner, m.isStatic, [v.initializer]);
        }
      } else if (m is MethodDeclaration) {
        if (!m.isOperator) {
          members.add(MemberInfo(
            name: m.name.lexeme,
            kind: m.isGetter ? MemberKind.getter : (m.isSetter ? MemberKind.setter : MemberKind.method),
            isStatic: m.isStatic,
            typeSource: m.returnType?.toSource(),
            params: _params(m.parameters),
            offset: m.name.offset,
            length: m.name.length,
          ));
        }
        _addBody(owner, m.isStatic, [m.parameters, m.body]);
      } else if (m is ConstructorDeclaration) {
        ctors.add(ConstructorInfo(
          name: m.name?.lexeme ?? '',
          params: _params(m.parameters),
          isConst: m.constKeyword != null,
          isFactory: m.factoryKeyword != null,
          offset: m.offset,
        ));
        _addBody(owner, false, [m.parameters, ...m.initializers, m.body]);
      }
    }
  }

  void _topFunction(FunctionDeclaration d) {
    final name = d.name.lexeme;
    final fn = d.functionExpression;
    if (d.isSetter) {
      _addBody(null, true, [fn]);
      return;
    }
    topLevel.add(TopLevelDecl(
      name: name,
      kind: d.isGetter ? TopLevelKind.variable : TopLevelKind.function,
      typeSource: d.returnType?.toSource(),
      params: d.isGetter ? const [] : _params(fn.parameters),
      offset: d.name.offset,
      length: d.name.length,
    ));
    _addBody(null, true, [fn]);
  }

  void _topVariables(TopLevelVariableDeclaration d) {
    final typeSrc = d.variables.type?.toSource();
    for (final v in d.variables.variables) {
      topLevel.add(TopLevelDecl(
        name: v.name.lexeme,
        kind: TopLevelKind.variable,
        typeSource: typeSrc,
        inferredType: typeSrc == null ? _inferType(v.initializer) : null,
        offset: v.name.offset,
        length: v.name.length,
      ));
      _addBody(null, true, [v.initializer]);
    }
  }

  List<ParamInfo> _params(FormalParameterList? list) {
    if (list == null) return const [];
    final out = <ParamInfo>[];
    for (final p in list.parameters) {
      final name = p.name;
      if (name == null) continue;
      out.add(ParamInfo(
        name: name.lexeme,
        kind: p.isNamed ? ParamKind.named : (p.isOptionalPositional ? ParamKind.optionalPositional : ParamKind.positional),
        isRequired: p.isRequiredNamed,
        typeSource: p.functionTypedSuffix != null ? 'Function' : p.type?.toSource(),
        isThisParam: p is FieldFormalParameter,
        isSuperParam: p is SuperFormalParameter,
        hasDefault: p.defaultClause != null,
      ));
    }
    return out;
  }

  String? _inferType(Expression? e) {
    if (e == null) return null;
    if (e is SimpleStringLiteral || e is StringInterpolation || e is AdjacentStrings) return 'String';
    if (e is IntegerLiteral) return 'int';
    if (e is DoubleLiteral) return 'double';
    if (e is BooleanLiteral) return 'bool';
    if (e is ListLiteral) return 'List';
    if (e is SetOrMapLiteral) return e.isMap ? 'Map' : (e.isSet ? 'Set' : null);
    if (e is InstanceCreationExpression) return e.constructorName.type.name.lexeme;
    if (e is MethodInvocation && e.target == null) {
      final n = e.methodName.name;
      if (n.isNotEmpty && n[0] == n[0].toUpperCase() && n[0] != n[0].toLowerCase()) return n;
    }
    if (e is ParenthesizedExpression) return _inferType(e.expression);
    return null;
  }

  // ------------------------- الأجسام والنطاقات -------------------------

  /// يضيف جسمًا واحدًا: كل ما يُعلَن داخله من متغيّرات (بأي عمق) يُجمَع في نطاق
  /// واحد "مرفوع" (hoisted) — لا نحاكي مدى كل كتلة بدقة، بل نضمن ألا يُعتبر
  /// متغيّر معلَن اسمًا مجهولًا. اسم مُعلَن مرتين بنوعين مختلفين يصير بلا نوع.
  void _addBody(String? owner, bool isStatic, List<AstNode?> nodes) {
    final present = [for (final n in nodes) if (n != null) n];
    if (present.isEmpty) return;
    final locals = <String, LocalVar>{};
    for (final n in present) {
      _collectLocals(n, locals);
    }
    final children = [for (final n in present) _conv(n)];
    final first = present.first;
    bodies.add(XBody(
      ownerClass: owner,
      isStatic: isStatic,
      root: XScope(first.offset, first.length, locals: locals, children: children),
    ));
  }

  void _addLocal(Map<String, LocalVar> out, String name, String? typeSource, String? inferred) {
    final existing = out[name];
    if (existing == null) {
      out[name] = LocalVar(typeSource: typeSource, inferredType: inferred);
    } else if (existing.typeSource != typeSource || existing.inferredType != inferred) {
      out[name] = const LocalVar();
    }
  }

  void _collectLocals(AstNode n, Map<String, LocalVar> out) {
    if (n is VariableDeclaration) {
      final list = n.parent;
      final ts = list is VariableDeclarationList ? list.type?.toSource() : null;
      _addLocal(out, n.name.lexeme, ts, ts == null ? _inferType(n.initializer) : null);
    } else if (n is DeclaredIdentifier) {
      _addLocal(out, n.name.lexeme, n.type?.toSource(), null);
    } else if (n is CatchClauseParameter) {
      _addLocal(out, n.name.lexeme, null, null);
    } else if (n is FormalParameter) {
      final name = n.name;
      if (name != null) _addLocal(out, name.lexeme, n.type?.toSource(), null);
    } else if (n is FunctionDeclaration) {
      _addLocal(out, n.name.lexeme, null, null);
    } else if (n is DeclaredVariablePattern) {
      _addLocal(out, n.name.lexeme, n.type?.toSource(), null);
    }
    for (final c in n.childEntities) {
      if (c is AstNode) _collectLocals(c, out);
    }
  }

  // ------------------------- التعبيرات -------------------------

  XExpr _conv(AstNode n) {
    if (n is SimpleIdentifier) return XIdent(n.offset, n.length, n.name);
    if (n is PrefixedIdentifier) {
      return XMember(
        n.offset,
        n.length,
        XIdent(n.prefix.offset, n.prefix.length, n.prefix.name),
        n.identifier.name,
        n.identifier.offset,
      );
    }
    if (n is PropertyAccess) {
      final target = n.target;
      if (target == null) return _other(n);
      return XMember(n.offset, n.length, _conv(target), n.propertyName.name, n.propertyName.offset);
    }
    if (n is MethodInvocation) return _method(n);
    if (n is InstanceCreationExpression) return _creation(n);
    if (n is IntegerLiteral) return XLiteral(n.offset, n.length, 'int');
    if (n is DoubleLiteral) return XLiteral(n.offset, n.length, 'double');
    if (n is BooleanLiteral) return XLiteral(n.offset, n.length, 'bool');
    if (n is NullLiteral) return XLiteral(n.offset, n.length, 'Null');
    if (n is SimpleStringLiteral) return XLiteral(n.offset, n.length, 'String');
    if (n is ThisExpression) return XIdent(n.offset, n.length, 'this');
    if (n is SuperExpression) return XIdent(n.offset, n.length, 'super');
    if (n is ParenthesizedExpression) return _conv(n.expression);
    // اختصارات النقطة (.center / .new(...)) لا أسماء يُحقَّق منها بدون سياق نوعي.
    if (n is DotShorthandInvocation) {
      return XOther(n.offset, n.length, [for (final a in _args(n.argumentList)) a.value]);
    }
    if (n is DotShorthandConstructorInvocation) {
      return XOther(n.offset, n.length, [for (final a in _args(n.argumentList)) a.value]);
    }
    if (n is DotShorthandPropertyAccess) return XOther(n.offset, n.length);
    return _other(n);
  }

  bool _skipChild(AstNode child, AstNode parent) {
    if (child is TypeAnnotation ||
        child is TypeArgumentList ||
        child is TypeParameterList ||
        child is Annotation ||
        child is Comment) {
      return true;
    }
    // معرِّف مجرّد داخل عقدة ليست تعبيرًا (اسم حقل في initializer، اسم مُنشئ، ...)
    // ليس قيمة تُحَل كمتغيّر.
    if (child is SimpleIdentifier && parent is! Expression && parent is! ArgumentList) return true;
    return false;
  }

  XExpr _other(AstNode n) {
    final children = <XExpr>[];
    for (final c in n.childEntities) {
      if (c is! AstNode) continue;
      if (_skipChild(c, n)) continue;
      children.add(_conv(c));
    }
    return XOther(n.offset, n.length, children);
  }

  List<XArg> _args(ArgumentList list) {
    final out = <XArg>[];
    for (final a in list.arguments) {
      if (a is NamedArgument) {
        // اسم الوسيط Token وليس معرِّفًا: لا يُنشأ له XIdent أبدًا.
        out.add(XArg(name: a.name.lexeme, nameOffset: a.name.offset, value: _conv(a.argumentExpression)));
      } else {
        out.add(XArg(value: _conv(a.argumentExpression)));
      }
    }
    return out;
  }

  XExpr _method(MethodInvocation n) {
    final args = _args(n.argumentList);
    if (n.isCascaded) {
      return XOther(n.offset, n.length, [for (final a in args) a.value]);
    }
    final target = n.target;
    return XCall(
      n.offset,
      n.length,
      target: target == null ? null : _conv(target),
      name: n.methodName.name,
      nameOffset: n.methodName.offset,
      args: args,
    );
  }

  XExpr _creation(InstanceCreationExpression n) {
    final ctor = n.constructorName;
    final type = ctor.type;
    final args = _args(n.argumentList);
    final typeName = type.name.lexeme;
    final prefix = type.importPrefix;
    final named = ctor.name;

    final XIdent? prefixExpr =
        prefix == null ? null : XIdent(prefix.name.offset, prefix.name.length, prefix.name.lexeme);

    if (named != null) {
      final XExpr typeExpr = prefixExpr == null
          ? XIdent(type.name.offset, type.name.length, typeName)
          : XMember(type.offset, type.length, prefixExpr, typeName, type.name.offset);
      return XCall(
        n.offset,
        n.length,
        target: typeExpr,
        name: named.name,
        nameOffset: named.offset,
        args: args,
        isConst: n.isConst,
      );
    }
    return XCall(
      n.offset,
      n.length,
      target: prefixExpr,
      name: typeName,
      nameOffset: type.name.offset,
      args: args,
      isConst: n.isConst,
    );
  }
}
