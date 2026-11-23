import 'package:path/path.dart' as p;

import '../data/expr_model.dart';
import '../data/project_model.dart';
import 'project_index.dart';
import 'text_similarity.dart';
import 'uri_resolver.dart';

enum SemanticSeverity { error, warning, info }

class SemanticDiagnostic {
  final String filePath;
  final int offset;
  final int length;
  final int line;
  final int column;

  /// رمز ثابت لنوع الخطأ (للاختبارات والتصنيف): unknown_class, unknown_member,
  /// unknown_named_arg, not_imported, import_not_found, ...
  final String code;
  final String message;
  final String? hint;
  final SemanticSeverity severity;

  const SemanticDiagnostic({
    required this.filePath,
    required this.offset,
    required this.length,
    required this.line,
    required this.column,
    required this.code,
    required this.message,
    this.hint,
    this.severity = SemanticSeverity.error,
  });
}

/// نوع قيمة تعبير كما استنتجناه (null = مجهول، فلا يُبلَّغ عن شيء بشأنه).
class StaticType {
  final String name;

  /// صنف المشروع المقابل إن عُرف.
  final ClassInfo? cls;

  /// التعبير يدلّ على الصنف نفسه (وصول static) لا على كائن منه.
  final bool isTypeRef;

  /// التعبير هو بادئة استيراد (`as x`).
  final String? prefix;
  final bool nullable;

  const StaticType(this.name, {this.cls, this.isTypeRef = false, this.prefix, this.nullable = false});

  const StaticType.forPrefix(String prefixName)
      : name = '',
        cls = null,
        isTypeRef = false,
        prefix = prefixName,
        nullable = false;
}

/// المدقِّق الدلالي: يتحقق من سياق كل تعبير وتعريفه الفعلي في فهرس المشروع قبل
/// إصدار أي خطأ. القاعدة العامة: **لا خطأ إلا عند اليقين** — اسم قد يأتي من
/// مكتبة خارجية لا نفهرسها (Flutter مثلًا) لا يُبلَّغ عنه إلا إن كان خطأً
/// إملائيًا واضحًا لاسم معروف في المشروع، أو معرَّفًا في المشروع لكنه غير
/// مستورَد. أعضاء الأصناف الخارجية وأنواعها تنتظر سجل أنواع Flutter (الخطوة 4).
class SemanticChecker {
  final ProjectIndex index;
  SemanticChecker(this.index);

  List<SemanticDiagnostic> check(FileModel file) {
    if (file.skipSemantic) return const [];
    return _FileCheck(index, file).run();
  }
}

class _Env {
  final ClassInfo? cls;
  final bool isStatic;
  final List<Map<String, LocalVar>> scopes = [];
  _Env(this.cls, this.isStatic);
}

const _primitives = {'int', 'double', 'num', 'String', 'bool'};

class _FileCheck {
  final ProjectIndex index;
  final FileModel file;
  final VisibleScope scope;
  final List<SemanticDiagnostic> diagnostics = [];
  final Set<String> _seen = {};

  _FileCheck(this.index, this.file) : scope = index.scopeOf(file.path);

  List<SemanticDiagnostic> run() {
    _checkImports();
    for (final body in file.bodies) {
      ClassInfo? owner;
      final ownerName = body.ownerClass;
      if (ownerName != null) {
        for (final c in file.classes) {
          if (c.name == ownerName) {
            owner = c;
            break;
          }
        }
      }
      _eval(body.root, _Env(owner, body.isStatic));
    }
    return diagnostics;
  }

  // ------------------------- الإبلاغ -------------------------

  void _report(
    int offset,
    int length,
    String code,
    String message, {
    SemanticSeverity severity = SemanticSeverity.error,
    String? hint,
  }) {
    if (!_seen.add('$offset:$code')) return;
    final (line, column) = file.lines.locate(offset);
    diagnostics.add(SemanticDiagnostic(
      filePath: file.path,
      offset: offset,
      length: length < 1 ? 1 : length,
      line: line,
      column: column,
      code: code,
      message: message,
      hint: hint,
      severity: severity,
    ));
  }

  String _where(ClassInfo c) {
    final f = index.fileAt(c.filePath);
    final line = f?.lines.locate(c.offset).$1;
    return '${p.basename(c.filePath)}${line == null ? '' : ':$line'}';
  }

  String _list(Iterable<String> names, {int max = 8}) {
    final sorted = names.toList()..sort();
    final shown = sorted.take(max).join('، ');
    return sorted.length > max ? '$shown ...' : shown;
  }

  // ------------------------- الاستيرادات -------------------------

  void _checkImports() {
    for (final imp in file.imports) {
      final r = index.resolveImport(file, imp);
      final failure = r.failure;
      if (failure == null) {
        final target = r.path;
        final model = target == null ? null : index.fileAt(target);
        if (model != null && model.syntaxErrorCount > 0) {
          _report(
            imp.offset,
            imp.length,
            'imported_file_has_errors',
            "الملف المستورد '${p.basename(model.path)}' فيه ${model.syntaxErrorCount} أخطاء صياغة"
            "${model.firstSyntaxErrorLine == null ? '' : ' (أولها في السطر ${model.firstSyntaxErrorLine})'}",
            severity: SemanticSeverity.warning,
            hint: 'الأخطاء النحوية قد تُخفي تعريفات الملف، فتظهر أسماؤه "غير معرَّفة" في الملفات التي تستورده.',
          );
        }
        continue;
      }
      switch (failure) {
        case ImportFailure.fileNotFound:
          _report(imp.offset, imp.length, 'import_not_found', "الملف المستورد غير موجود: '${imp.uri}'",
              hint: 'تحقّق من المسار واسم الملف ومن أنه داخل المشروع.');
          break;
        case ImportFailure.fileCaseMismatch:
          _report(imp.offset, imp.length, 'import_case_mismatch',
              "اختلاف في حالة الأحرف في مسار الاستيراد '${imp.uri}'",
              hint: "المسار الفعلي: '${r.suggestion}' — مسارات Dart حسّاسة لحالة الأحرف (وكذلك نظام ملفات أندرويد).");
          break;
        case ImportFailure.unknownPackage:
          _report(imp.offset, imp.length, 'unknown_package', "الحزمة في '${imp.uri}' غير معرَّفة",
              hint: 'ليست حزمة هذا المشروع (${index.context.packageName ?? 'غير معروفة'}) ولا موجودة في تبعيات pubspec.yaml.');
          break;
        case ImportFailure.packageCaseMismatch:
          _report(imp.offset, imp.length, 'package_case_mismatch',
              "اسم الحزمة في '${imp.uri}' يختلف في حالة الأحرف",
              hint: "اسم الحزمة الصحيح في pubspec.yaml هو '${r.suggestion}' (أسماء الحزم حسّاسة لحالة الأحرف في Dart).");
          break;
      }
    }
  }

  // ------------------------- تقييم التعبيرات -------------------------

  StaticType? _eval(XExpr e, _Env env) {
    if (e is XLiteral) return StaticType(e.typeName, nullable: e.typeName == 'Null');
    if (e is XIdent) return _evalIdent(e, env);
    if (e is XMember) return _evalMember(e, env);
    if (e is XCall) return _evalCall(e, env);
    if (e is XScope) {
      env.scopes.add(e.locals);
      for (final c in e.children) {
        _eval(c, env);
      }
      env.scopes.removeLast();
      return null;
    }
    if (e is XOther) {
      for (final c in e.children) {
        _eval(c, env);
      }
    }
    return null;
  }

  List<StaticType?> _evalArgs(List<XArg> args, _Env env) => [for (final a in args) _eval(a.value, env)];

  LocalVar? _findLocal(String name, _Env env) {
    for (var i = env.scopes.length - 1; i >= 0; i--) {
      final lv = env.scopes[i][name];
      if (lv != null) return lv;
    }
    return null;
  }

  StaticType? _typeFromName(TypeName? t, String inFile) {
    if (t == null || t.base == 'dynamic' || t.base == 'var') return null;
    final cls = index.scopeOf(inFile).names[t.base]?.cls;
    return StaticType(t.base, cls: cls, nullable: t.nullable);
  }

  StaticType? _typeOfMember(MemberInfo m, ClassInfo? owner) {
    if (m.kind == MemberKind.enumValue) {
      return owner == null ? null : StaticType(owner.name, cls: owner);
    }
    if (m.kind == MemberKind.method || m.kind == MemberKind.setter) return null;
    return _typeFromName(m.type, owner?.filePath ?? file.path);
  }

  StaticType? _evalIdent(XIdent e, _Env env) {
    final name = e.name;
    if (name == 'this') {
      final c = env.cls;
      return c == null ? null : StaticType(c.name, cls: c);
    }
    if (name == 'super') return null;

    final lv = _findLocal(name, env);
    if (lv != null) {
      return _typeFromName(TypeName.parse(lv.typeSource) ?? (lv.inferredType == null ? null : TypeName(lv.inferredType!)), file.path);
    }

    final cls = env.cls;
    if (cls != null) {
      final r = index.lookupMember(cls, name);
      final m = r.member;
      if (m != null) return _typeOfMember(m, r.owner);
    }

    final resolved = scope.names[name];
    if (resolved != null) {
      final c = resolved.cls;
      if (c != null) return StaticType(c.name, cls: c, isTypeRef: true);
      final t = resolved.top;
      if (t != null && t.kind == TopLevelKind.variable) return _typeFromName(t.type, resolved.filePath);
      return null;
    }
    if (scope.prefixes.containsKey(name)) return StaticType.forPrefix(name);
    if (scope.externalPrefixes.contains(name)) return null;

    _reportUnknownName(name, e.offset, e.length, env);
    return null;
  }

  /// اسم لا نجده في أي نطاق نعرفه. لا نبلّغ إلا عند قرينة واضحة (راجع توثيق الصنف).
  void _reportUnknownName(String name, int offset, int length, _Env env) {
    if (name.isEmpty) return;
    final known = index.context.isKnownExternalName;
    if (known != null && known(name)) return;

    // 1) صنف مستورَد ببادئة فقط.
    for (final entry in scope.prefixes.entries) {
      if (entry.value[name]?.cls != null) {
        _report(offset, length, 'unknown_class', "الصنف '$name' مستورَد ببادئة '${entry.key}'",
            hint: "استخدم '${entry.key}.$name'.");
        return;
      }
    }

    // 2) معرَّف في المشروع لكنه غير مستورَد في هذا الملف.
    final elsewhere = index.classesNamed(name);
    if (elsewhere.isNotEmpty) {
      final target = elsewhere.first;
      final uri = index.importUriFor(file.path, target.filePath);
      _report(offset, length, 'not_imported', "الصنف '$name' معرَّف في ${_where(target)} لكن هذا الملف لا يستورده",
          hint: "أضف: import '$uri';");
      return;
    }

    // 3) خطأ إملائي/حالة أحرف لاسم صنف معروف في المشروع.
    final isTypeLike = name[0].toUpperCase() == name[0] && name[0].toLowerCase() != name[0];
    final classNames = {...index.allPublicClassNames()};
    final near = nearestName(name, classNames, minLength: 6);
    if (near != null && (isTypeLike || near.toLowerCase() == name.toLowerCase())) {
      final cls = index.classesNamed(near).first;
      final visible = scope.names[near]?.cls != null;
      final importNote = visible ? '' : " (عرّفه ${_where(cls)}؛ أضف: import '${index.importUriFor(file.path, cls.filePath)}';)";
      _report(offset, length, 'unknown_class', "الصنف '$name' غير معرَّف",
          hint: "هل تقصد '$near'؟$importNote");
      return;
    }

    // 4) متغيّر/عضو بخطأ إملائي واضح لاسم ظاهر.
    if (!isTypeLike) {
      final candidates = <String>{};
      for (final m in env.scopes) {
        candidates.addAll(m.keys);
      }
      final c = env.cls;
      if (c != null) candidates.addAll(index.memberNames(c));
      final nearVar = nearestName(name, candidates, minLength: 4);
      if (nearVar != null) {
        _report(offset, length, 'unknown_variable', "الاسم '$name' غير معرَّف في هذا النطاق",
            severity: SemanticSeverity.warning, hint: "هل تقصد '$nearVar'؟");
      }
    }
  }

  StaticType? _evalMember(XMember e, _Env env) {
    final t = _eval(e.target, env);
    if (t == null) return null;

    final prefix = t.prefix;
    if (prefix != null) {
      final ns = scope.prefixes[prefix];
      final r = ns?[e.name];
      if (r == null) {
        final near = ns == null ? null : nearestName(e.name, ns.keys);
        if (near != null) {
          _report(e.nameOffset, e.name.length, 'unknown_member',
              "الاسم '${e.name}' غير موجود في المكتبة المستوردة ببادئة '$prefix'",
              hint: "هل تقصد '$near'؟");
        }
        return null;
      }
      final c = r.cls;
      if (c != null) return StaticType(c.name, cls: c, isTypeRef: true);
      return null;
    }

    final cls = t.cls;
    if (cls == null) return null;

    final lookup = index.lookupMember(cls, e.name);
    final m = lookup.member;
    if (m != null) {
      _checkAccessKind(t, m, e.nameOffset, e.name);
      return _typeOfMember(m, lookup.owner);
    }
    if (lookup.inconclusive) return null;
    if (t.isTypeRef && cls.constructors.any((c) => c.name == e.name)) return null; // tear-off لمُنشئ مسمّى

    _reportUnknownMember(t, cls, e.name, e.nameOffset);
    return null;
  }

  void _checkAccessKind(StaticType t, MemberInfo m, int nameOffset, String name) {
    final cls = t.cls;
    if (cls == null) return;
    if (t.isTypeRef && !m.isStatic && m.kind != MemberKind.enumValue) {
      _report(nameOffset, name.length, 'instance_member_via_class',
          "العضو '$name' ليس static، فلا يُستخدَم عبر اسم الصنف ${cls.name}",
          hint: 'استخدم كائنًا: ${cls.name}().$name — أو عرّف العضو static في ${_where(cls)}.');
    } else if (!t.isTypeRef && m.isStatic) {
      _report(nameOffset, name.length, 'static_member_via_instance',
          "العضو '$name' معرَّف static فلا يُستخدَم عبر كائن",
          hint: 'استخدم ${cls.name}.$name');
    }
  }

  void _reportUnknownMember(StaticType t, ClassInfo cls, String name, int nameOffset) {
    final available = index.memberNames(cls, isStatic: t.isTypeRef);
    if (t.isTypeRef) {
      for (final c in cls.constructors) {
        if (c.name.isNotEmpty) available.add(c.name);
      }
    }
    final near = nearestName(name, available, minLength: 3);
    final buffer = StringBuffer();
    if (near != null) buffer.write("هل تقصد '$near'؟ ");
    if (available.isNotEmpty) buffer.write('المتاح: ${_list(available)}.');
    _report(
      nameOffset,
      name.length,
      'unknown_member',
      "العضو '$name' غير موجود في الصنف ${cls.name} (المعرَّف في ${_where(cls)})",
      hint: buffer.isEmpty ? null : buffer.toString().trim(),
    );
  }

  // ------------------------- الاستدعاءات -------------------------

  StaticType? _evalCall(XCall e, _Env env) {
    final target = e.target;
    if (target == null) return _evalBareCall(e, env);

    final t = _eval(target, env);
    if (t == null) {
      _evalArgs(e.args, env);
      return null;
    }

    final prefix = t.prefix;
    if (prefix != null) {
      final r = scope.prefixes[prefix]?[e.name];
      final c = r?.cls;
      if (c != null) return _constructorCall(c, '', e, env);
      _evalArgs(e.args, env);
      return null;
    }

    final cls = t.cls;
    if (cls == null) {
      _evalArgs(e.args, env);
      return null;
    }

    if (t.isTypeRef) {
      // Foo.named(...) مُنشئ مسمّى، أو دالة static.
      if (cls.constructors.any((c) => c.name == e.name)) return _constructorCall(cls, e.name, e, env);
      final lookup = index.lookupMember(cls, e.name);
      final m = lookup.member;
      if (m != null) {
        _checkAccessKind(t, m, e.nameOffset, e.name);
        return _memberCall(m, lookup.owner, e, env);
      }
      _evalArgs(e.args, env);
      if (!lookup.inconclusive) _reportUnknownMember(t, cls, e.name, e.nameOffset);
      return null;
    }

    final lookup = index.lookupMember(cls, e.name);
    final m = lookup.member;
    if (m != null) {
      _checkAccessKind(t, m, e.nameOffset, e.name);
      return _memberCall(m, lookup.owner, e, env);
    }
    _evalArgs(e.args, env);
    if (!lookup.inconclusive) _reportUnknownMember(t, cls, e.name, e.nameOffset);
    return null;
  }

  StaticType? _evalBareCall(XCall e, _Env env) {
    final name = e.name;

    if (_findLocal(name, env) != null) {
      _evalArgs(e.args, env);
      return null;
    }

    final cls = env.cls;
    if (cls != null) {
      final r = index.lookupMember(cls, name);
      final m = r.member;
      if (m != null) return _memberCall(m, r.owner, e, env);
    }

    final resolved = scope.names[name];
    if (resolved != null) {
      final c = resolved.cls;
      if (c != null) return _constructorCall(c, '', e, env);
      final top = resolved.top;
      if (top != null && top.kind == TopLevelKind.function) {
        final argTypes = _evalArgs(e.args, env);
        _checkArgs(top.params, e, argTypes, "الدالة '$name'", null, resolved.filePath);
        return _typeFromName(TypeName.parse(top.typeSource), resolved.filePath);
      }
      _evalArgs(e.args, env);
      return null;
    }

    _evalArgs(e.args, env);
    _reportUnknownName(name, e.nameOffset, name.length, env);
    return null;
  }

  StaticType? _memberCall(MemberInfo m, ClassInfo? owner, XCall e, _Env env) {
    final argTypes = _evalArgs(e.args, env);
    if (m.kind != MemberKind.method) return null;
    final inFile = owner?.filePath ?? file.path;
    _checkArgs(m.params, e, argTypes, "الدالة '${e.name}'", owner, inFile);
    return _typeFromName(TypeName.parse(m.typeSource), inFile);
  }

  StaticType? _constructorCall(ClassInfo cls, String ctorName, XCall e, _Env env) {
    final argTypes = _evalArgs(e.args, env);
    final result = StaticType(cls.name, cls: cls);
    if (cls.kind != ClassKind.classDecl) return result;

    ConstructorInfo? ctor;
    for (final c in cls.constructors) {
      if (c.name == ctorName) {
        ctor = c;
        break;
      }
    }

    final label = ctorName.isEmpty ? "المُنشئ '${cls.name}'" : "المُنشئ '${cls.name}.$ctorName'";
    List<ParamInfo> params;
    if (ctor != null) {
      params = ctor.params;
    } else if (ctorName.isEmpty && cls.constructors.isEmpty) {
      params = const [];
    } else if (ctorName.isNotEmpty) {
      final near = nearestName(ctorName, cls.constructors.map((c) => c.name).where((n) => n.isNotEmpty), minLength: 3);
      final all = cls.constructors.map((c) => c.name).where((n) => n.isNotEmpty);
      final hintText = [
        if (near != null) "هل تقصد '$near'؟",
        if (all.isNotEmpty) 'المُنشئات المسمّاة: ${_list(all)}.',
      ].join(' ');
      _report(e.nameOffset, ctorName.length, 'unknown_constructor',
          "الصنف ${cls.name} (المعرَّف في ${_where(cls)}) لا يملك مُنشئًا باسم '$ctorName'",
          hint: hintText.isEmpty ? null : hintText);
      return result;
    } else {
      final named = cls.constructors.map((c) => c.name).where((n) => n.isNotEmpty);
      _report(e.nameOffset, e.name.length, 'no_default_constructor',
          "الصنف ${cls.name} (المعرَّف في ${_where(cls)}) لا يملك مُنشئًا افتراضيًا (بلا اسم)",
          hint: named.isEmpty ? null : 'المُنشئات المتاحة: ${_list(named)}.');
      return result;
    }

    if (cls.isAbstract && ctorName.isEmpty && (ctor == null || !ctor.isFactory)) {
      _report(e.nameOffset, e.name.length, 'abstract_instantiation',
          "الصنف ${cls.name} abstract فلا يمكن إنشاء كائن منه مباشرة",
          hint: 'استخدم صنفًا فرعيًا يُنفّذه، أو أضف مُنشئ factory.');
    }

    _checkArgs(params, e, argTypes, label, cls, cls.filePath);
    return result;
  }

  // ------------------------- الوسائط -------------------------

  /// يطابق وسائط الاستدعاء مع المعاملات المعرَّفة فعلًا. أسماء الوسائط المسمّاة
  /// تُقارَن بأسماء معاملات المُنشئ/الدالة فقط — ولا تُحلّ كمتغيّرات إطلاقًا.
  void _checkArgs(
    List<ParamInfo> params,
    XCall e,
    List<StaticType?> argTypes,
    String label,
    ClassInfo? owner,
    String paramFile,
  ) {
    final positional = params.where((p) => p.kind != ParamKind.named).toList();
    final requiredPositional = positional.where((p) => p.kind == ParamKind.positional).length;
    final named = <String, ParamInfo>{
      for (final p in params)
        if (p.kind == ParamKind.named) p.name: p,
    };

    var positionalGiven = 0;
    final provided = <String>{};
    for (var i = 0; i < e.args.length; i++) {
      final a = e.args[i];
      final argType = argTypes[i];
      final argName = a.name;
      if (argName == null) {
        if (positionalGiven >= positional.length) {
          _report(a.value.offset, a.value.length, 'too_many_positional',
              '$label يقبل ${positional.length} وسيطًا موضعيًا فقط لكن مُرِّر أكثر من ذلك',
              hint: named.isEmpty ? null : 'الوسائط المسمّاة المتاحة: ${_list(named.keys)}.');
        } else {
          _checkArgType(positional[positionalGiven], a, argType, owner, paramFile);
        }
        positionalGiven++;
        continue;
      }

      final param = named[argName];
      if (param == null) {
        final near = nearestName(argName, named.keys, minLength: 3);
        final positionalMatch = positional.any((p) => p.name == argName);
        final hints = <String>[];
        if (near != null) hints.add("هل تقصد '$near'؟");
        if (positionalMatch) hints.add("'$argName' معامل موضعي وليس مسمّى — مرِّر قيمته بدون اسم.");
        hints.add(named.isEmpty ? 'لا يعرّف $label أي وسائط مسمّاة.' : 'الوسائط المسمّاة المعرَّفة: ${_list(named.keys)}.');
        _report(a.nameOffset, argName.length, 'unknown_named_arg', "$label لا يقبل وسيطًا مسمّى باسم '$argName'",
            hint: hints.join(' '));
        continue;
      }
      provided.add(argName);
      _checkArgType(param, a, argType, owner, paramFile);
    }

    if (positionalGiven < requiredPositional) {
      _report(e.nameOffset, e.name.length, 'missing_positional',
          '$label يحتاج $requiredPositional وسيطًا موضعيًا على الأقل لكن مُرِّر $positionalGiven');
    }
    for (final param in named.values) {
      if (param.isRequired && !provided.contains(param.name)) {
        _report(e.nameOffset, e.name.length, 'missing_required_arg',
            "الوسيط المسمّى المطلوب '${param.name}' غير مُمرَّر إلى $label");
      }
    }
  }

  void _checkArgType(ParamInfo param, XArg a, StaticType? from, ClassInfo? owner, String paramFile) {
    final to = _paramType(param, owner, 0);
    final ok = _compatible(from, to, owner);
    if (ok == false && from != null && to != null) {
      _report(a.value.offset, a.value.length, 'type_mismatch',
          "نوع القيمة '${from.name}' لا يطابق نوع الوسيط '${param.name}' المتوقَّع '${to.base}${to.nullable ? '?' : ''}'");
    }
  }

  TypeName? _paramType(ParamInfo param, ClassInfo? owner, int depth) {
    if (param.typeSource != null) return TypeName.parse(param.typeSource);
    if (owner == null || depth > 8) return null;
    if (param.isThisParam) return index.lookupMember(owner, param.name).member?.type;
    if (param.isSuperParam) {
      final raw = owner.superclass;
      final base = raw == null ? null : TypeName.parse(raw)?.base;
      if (base == null) return null;
      final parent = index.resolveClassFrom(owner, base);
      if (parent == null) return null;
      for (final c in parent.constructors) {
        if (c.name.isNotEmpty) continue;
        for (final pp in c.params) {
          if (pp.name == param.name) return _paramType(pp, parent, depth + 1);
        }
      }
    }
    return null;
  }

  /// true = متوافق، false = غير متوافق يقينًا، null = لا نستطيع الجزم.
  bool? _compatible(StaticType? from, TypeName? to, ClassInfo? owner) {
    if (from == null || to == null) return null;
    if (from.prefix != null || from.isTypeRef) return null;
    final target = to.base;
    if (target == 'dynamic' || target == 'Object' || target == 'var') return true;
    if (owner != null && owner.typeParams.contains(target)) return null;
    if (target.length == 1 && target == target.toUpperCase()) return null;
    if (from.name == 'Null') return to.nullable;
    if (from.name == target) return true;
    if (from.name == 'int' && (target == 'num' || target == 'double')) return true;
    if (from.name == 'double' && target == 'num') return true;

    if (_primitives.contains(from.name)) {
      if (_primitives.contains(target)) return false;
      if (scope.names[target]?.cls != null) return false;
      return null;
    }

    final cls = from.cls;
    if (cls != null) {
      switch (index.subtypeOf(cls, target)) {
        case Subtype.yes:
          return true;
        case Subtype.no:
          return false;
        case Subtype.unknown:
          return null;
      }
    }
    return null;
  }
}
