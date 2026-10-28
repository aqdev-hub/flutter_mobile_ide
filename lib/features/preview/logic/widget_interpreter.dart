import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'builtin_widgets.dart';
import 'builtin_widgets_ext.dart';
import 'dart_subset_ast.dart';
import 'interpreted_callable.dart';
import 'native_members.dart';

class PreviewRuntimeException implements Exception {
  final String message;
  PreviewRuntimeException(this.message);
  @override
  String toString() => message;
}

class _ReturnSignal {
  final dynamic value;
  _ReturnSignal(this.value);
}

/// إشارتا break/continue داخل الحلقات — بنفس أسلوب _ReturnSignal (استثناء
/// مُلتقَط محليًا) بدل تمرير أعلام تحكّم عبر كل مستوى تنفيذ.
class _BreakSignal {
  const _BreakSignal();
}

class _ContinueSignal {
  const _ContinueSignal();
}

/// يمثّل الوصول إلى `widget.xxx` داخل صنف State — أي حقول الودجت الأب
/// (StatefulWidget) كما مُرِّرت وقت إنشائه، بمعزل عن حالة State المتغيّرة.
class _WidgetRef {
  final Map<String, dynamic> args;
  _WidgetRef(this.args);
}

/// يمثّل نتيجة `ScaffoldMessenger.of(context)` — كائن وسيط بسيط يحمل
/// BuildContext فقط، حتى نستطيع لاحقًا معالجة `.showSnackBar(...)` عليه
/// (راجع _evalInstanceMethodCall) بنفس أسلوب سلاسل الاستدعاء الحقيقية في
/// Flutter (`X.of(context).method(...)`).
class _ScaffoldMessengerRef {
  final BuildContext context;
  _ScaffoldMessengerRef(this.context);
}

/// نتيجة `Navigator.of(context)` — للاستدعاءات المتسلسلة
/// `Navigator.of(context).pushNamed(...)`.
class _NavigatorRef {
  final BuildContext context;
  _NavigatorRef(this.context);
}

/// كائن حقيقي من صنف عادي معرَّف في كود المستخدم (مثل `SignUpControllerImp`):
/// حقوله في [fields] (تشمل حقول الأسلاف)، وطرقه تُحلّ من تعريف [def].
class InterpretedObject {
  final WidgetClassDef def;
  final Map<String, dynamic> fields = {};
  InterpretedObject(this.def);
  @override
  String toString() => "Instance of '${def.name}'";
}

/// بيئة تنفيذ متسلسلة (scope chain): متغيرات محلية (معاملات lambda/دوال)
/// تبحث أولًا، ثم حقول الحالة المتغيّرة (fields)، ثم الأب (closures متداخلة).
///
/// [methods] تحمل الدوال المساعدة المُعرَّفة في الصنف الحالي — تُورَّث عبر
/// السلسلة تمامًا مثل fields.
///
/// [instancePath] مسار هوية تراكمي (سلسلة نصية لكل مستوى حلقة/itemBuilder
/// دخلناه للوصول لهذه النقطة من التنفيذ) — يُستخدم مع معرّف [CallExpr.id]
/// لبناء مفتاح فريد ومستقر لكل "نسخة" StatefulWidget، بما يسمح بوجود عدة
/// نسخ نشطة من نفس الصنف (مثل بطاقات داخل قائمة) دون أن تتشارك الحالة.
/// راجع [Interpreter._instantiateUserClass] للتفاصيل.
///
/// [instanceKey] معرّف نسخة StatefulWidget "الحالية" (إن وُجدت) — يُورَّث
/// عبر السلسلة بنفس طريقة fields/methods. يُستخدَم عند setState() لتحديد
/// **أي** [InterpretedStatefulHost] يجب إعادة رسمه محليًا. يبقى null خارج أي
/// صنف Stateful.
///
/// [classDef] الصنف الذي يُنفَّذ كوده الآن (يُورَّث): لحلّ أعضاء static
/// بالاسم المجرّد و`super.method()`.
class RuntimeScope {
  final Map<String, dynamic> locals;
  final Map<String, dynamic> fields;
  final Map<String, MethodDef> methods;
  final List<String> instancePath;
  final String? instanceKey;
  final WidgetClassDef? classDef;
  final RuntimeScope? parent;

  RuntimeScope({
    Map<String, dynamic>? locals,
    Map<String, dynamic>? fields,
    Map<String, MethodDef>? methods,
    List<String>? instancePath,
    String? instanceKey,
    WidgetClassDef? classDef,
    this.parent,
  })  : locals = locals ?? {},
        fields = fields ?? (parent?.fields ?? {}),
        methods = methods ?? (parent?.methods ?? {}),
        instancePath = instancePath ?? (parent?.instancePath ?? const []),
        instanceKey = instanceKey ?? parent?.instanceKey,
        classDef = classDef ?? parent?.classDef;

  bool _localExists(String name) {
    if (locals.containsKey(name)) return true;
    return parent?._localExists(name) ?? false;
  }

  dynamic _getLocal(String name) {
    if (locals.containsKey(name)) return locals[name];
    return parent!._getLocal(name);
  }

  bool _setLocalIfExists(String name, dynamic value) {
    if (locals.containsKey(name)) {
      locals[name] = value;
      return true;
    }
    return parent?._setLocalIfExists(name, value) ?? false;
  }

  dynamic resolve(String name) {
    if (_localExists(name)) return _getLocal(name);
    if (fields.containsKey(name)) return fields[name];
    return null; // يُترك التحقق من الوجود لموقع الاستدعاء
  }

  bool has(String name) => _localExists(name) || fields.containsKey(name);

  /// يعيّن قيمة لمتغيّر: إن كان متغيّرًا محليًا معلنًا يُحدَّث في مكانه؛ وإلا
  /// فهو حقل حالة فيُحدَّث في خريطة [fields] المشتركة والدائمة.
  void assign(String name, dynamic value) {
    if (_setLocalIfExists(name, value)) return;
    fields[name] = value;
  }
}

/// ودجت Flutter **حقيقية** (State حقيقي من Flutter نفسه، وليس محاكاة) تُمثّل
/// نسخة واحدة من صنف StatefulWidget مُفسَّر. عند setState() من كود المستخدم
/// يستدعي المُفسِّر `.setState()` الحقيقي على هذا العنصر تحديدًا.
///
/// **تحديث (دورة الحياة)**: تُستدعى `initState` (مرة لكل نسخة حالة) و`dispose`
/// فعليًا من كود المستخدم.
class InterpretedStatefulHost extends StatefulWidget {
  final String instanceKey;
  final WidgetClassDef stateDef;
  final Map<String, dynamic> constructorArgs;
  final List<String> instancePath;
  final Interpreter interpreter;

  InterpretedStatefulHost({
    required this.instanceKey,
    required this.stateDef,
    required this.constructorArgs,
    required this.instancePath,
    required this.interpreter,
  }) : super(key: ValueKey(instanceKey));

  @override
  State<InterpretedStatefulHost> createState() => _InterpretedStatefulHostState();
}

class _InterpretedStatefulHostState extends State<InterpretedStatefulHost> {
  @override
  void initState() {
    super.initState();
    widget.interpreter._registerHost(widget.instanceKey, this);
    widget.interpreter._runLifecycle(
      widget.stateDef,
      widget.constructorArgs,
      widget.instanceKey,
      widget.instancePath,
      context,
      'initState',
    );
  }

  @override
  void didUpdateWidget(covariant InterpretedStatefulHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.instanceKey != widget.instanceKey) {
      widget.interpreter._unregisterHost(oldWidget.instanceKey, this);
      widget.interpreter._registerHost(widget.instanceKey, this);
    }
  }

  @override
  void dispose() {
    widget.interpreter._runLifecycle(
      widget.stateDef,
      widget.constructorArgs,
      widget.instanceKey,
      widget.instancePath,
      context,
      'dispose',
    );
    widget.interpreter._unregisterHost(widget.instanceKey, this);
    super.dispose();
  }

  void requestLocalRebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return widget.interpreter._buildStatefulInstance(
      widget.stateDef,
      widget.constructorArgs,
      widget.instanceKey,
      widget.instancePath,
      context,
    );
  }
}

/// المُفسِّر الرئيسي: يحوّل AST مستخرجة من كود المستخدم إلى شجرة ودجتس
/// Flutter حقيقية، وينفّذ setState/Navigator/الحلقات/الدوال المساعدة/
/// async-await المبسَّط ونموذج الكائنات (أصناف عادية، مُنشئات، static،
/// getters، وراثة) كأفعال حقيقية على محرك Flutter المستضيف (وليس محاكاة).
class Interpreter {
  final Map<String, WidgetClassDef> classRegistry;
  final void Function(String message, {bool isError}) log;
  final VoidCallback onStateChanged;

  /// مسار جذر المشروع المفتوح حاليًا على القرص — يُستخدَم حصرًا لحلّ مسارات
  /// الصور النسبية في Image.asset(...).
  final String projectRootPath;

  /// متغيّرات ودوال المستوى الأعلى (top-level) في المشروع (مثل `routes`).
  final Map<String, Expr?> globalVars;
  final Map<String, MethodDef> globalFunctions;

  final Map<String, Map<String, dynamic>> _stateStores = {};
  final Set<String> _initDone = {};
  final Map<String, _InterpretedStatefulHostState> _hosts = {};

  final Map<String, Map<String, dynamic>> _staticStores = {};
  final Set<String> _staticEvaluating = {};
  final Map<String, dynamic> _globalValues = {};
  final Set<String> _globalEvaluating = {};
  final Map<String, Map<String, MethodDef>> _methodsCache = {};
  final Map<MethodDef, WidgetClassDef> _methodOwners = Map.identity();
  final Set<String> _warned = {};

  bool _isBuilding = false;
  int _lifecycleDepth = 0;

  String? _currentFile;
  int? _currentLine;

  Interpreter({
    required this.classRegistry,
    required this.log,
    required this.onStateChanged,
    required this.projectRootPath,
    this.globalVars = const {},
    this.globalFunctions = const {},
  }) {
    for (final def in classRegistry.values) {
      for (final m in def.methods) {
        _methodOwners[m] = def;
      }
    }
  }

  Widget buildRoot(Expr rootExpr, BuildContext context) {
    _isBuilding = true;
    try {
      final result = _eval(rootExpr, RuntimeScope(locals: {'context': context}));
      if (result is Widget) return result;
      return _errorWidget('التعبير الجذري لا يُنتج Widget صالحًا.');
    } catch (e) {
      return _errorWidget(_cleanError(e));
    } finally {
      _isBuilding = false;
    }
  }

  /// يضبط "الموضع الحالي" المستخدَم في رسائل الخطأ من عقدة الشجرة نفسها
  /// (ملفها وسطرها المطلق).
  void _markLocation(String? file, int line) {
    if (file != null) _currentFile = file;
    if (line > 0) _currentLine = line;
  }

  String _formatLocation() {
    final file = _currentFile;
    final line = _currentLine;
    if (file != null && line != null) return '$file — السطر $line';
    if (file != null) return file;
    if (line != null) return 'السطر $line';
    return 'موضع غير معروف';
  }

  String _cleanError(Object e) {
    if (e is PreviewRuntimeException) return e.message;
    if (e is NativeMemberError) return e.message;
    return e.toString();
  }

  Widget _errorWidget(String message) {
    final fullMessage = '${_formatLocation()}: $message';
    log('خطأ في المعاينة — $fullMessage', isError: true);
    return Material(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(height: 8),
            Text(fullMessage, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }

  /// يُنشئ دالة قابلة للاستدعاء تُبلِّغ أخطاء معالجات الأحداث إلى لوحة Output
  /// بدل أن تضيع صامتةً داخل محرك Flutter.
  InterpretedCallable _callable(dynamic Function(List<dynamic> args) fn) =>
      InterpretedCallable(fn, onError: _reportError, onBuildError: _buildError);

  void _reportError(Object e, StackTrace st) {
    log('خطأ أثناء تنفيذ معالج حدث (${_formatLocation()}): ${_cleanError(e)}', isError: true);
  }

  Widget _buildError(Object e, StackTrace st) => _errorWidget('خطأ أثناء تنفيذ builder: ${_cleanError(e)}');

  void _warnOnce(String message) {
    if (_warned.add(message)) log('تحذير: $message');
  }

  // ------------------------- المضيفون ودورة الحياة -------------------------

  void _registerHost(String instanceKey, _InterpretedStatefulHostState host) {
    _hosts[instanceKey] = host;
  }

  void _unregisterHost(String instanceKey, _InterpretedStatefulHostState host) {
    if (identical(_hosts[instanceKey], host)) _hosts.remove(instanceKey);
  }

  Map<String, MethodDef> _stateMethods(WidgetClassDef stateDef) => {for (final m in stateDef.methods) m.name: m};

  Widget _buildStatefulInstance(
    WidgetClassDef stateDef,
    Map<String, dynamic> constructorArgs,
    String instanceKey,
    List<String> instancePath,
    BuildContext context,
  ) {
    final store = _stateStores[instanceKey]!;
    final buildScope = RuntimeScope(
      locals: {
        'context': context,
        'widget': _WidgetRef(constructorArgs),
      },
      fields: store,
      methods: _stateMethods(stateDef),
      instancePath: instancePath,
      instanceKey: instanceKey,
      classDef: stateDef,
    );
    return _runBuild(stateDef, buildScope);
  }

  /// يستدعي initState/dispose من كود المستخدم. initState مرة واحدة لكل نسخة
  /// حالة (الحالة تبقى محفوظة بين تبديل المحرر/المعاينة، فلا نكرّر التهيئة).
  /// أي setState داخل initState يُنفَّذ تعديله دون طلب رسم (كما في Flutter).
  void _runLifecycle(
    WidgetClassDef stateDef,
    Map<String, dynamic> args,
    String key,
    List<String> path,
    BuildContext context,
    String name,
  ) {
    if (name == 'initState' && !_initDone.add(key)) return;
    MethodDef? method;
    for (final m in stateDef.methods) {
      if (m.name == name && !m.isStatic) {
        method = m;
        break;
      }
    }
    final store = _stateStores[key];
    if (method == null || store == null) return;

    final scope = RuntimeScope(
      locals: {'context': context, 'widget': _WidgetRef(args)},
      fields: store,
      methods: _stateMethods(stateDef),
      instancePath: path,
      instanceKey: key,
      classDef: stateDef,
    );
    _lifecycleDepth++;
    try {
      _runMethod(method, const [], const {}, scope);
    } catch (e) {
      log('خطأ أثناء تنفيذ $name في ${stateDef.name} (${_formatLocation()}): ${_cleanError(e)}', isError: true);
    } finally {
      _lifecycleDepth--;
    }
  }

  void _requestInstanceRebuild(String? instanceKey) {
    if (instanceKey != null) {
      final host = _hosts[instanceKey];
      if (host != null) {
        try {
          host.requestLocalRebuild();
          return;
        } catch (e) {
          log(
            'تعذّر تحديث الشاشة مباشرة بعد setState (على الأرجح استُدعيت أثناء '
            'بناء ودجت آخر قيد التنفيذ فعليًا الآن): $e',
            isError: true,
          );
          return;
        }
      }
    }
    onStateChanged();
  }

  // ------------------------- Expression evaluation -------------------------

  bool _asBool(dynamic v, String what) {
    if (v is bool) return v;
    throw PreviewRuntimeException('$what يتطلب قيمة منطقية (bool) لكن وُجد ${v == null ? 'null' : v.runtimeType}.');
  }

  num _asNum(dynamic v, String op) {
    if (v is num) return v;
    throw PreviewRuntimeException('العملية "$op" تتطلب عددًا لكن وُجد ${v == null ? 'null' : v.runtimeType}.');
  }

  dynamic _eval(Expr expr, RuntimeScope scope) {
    if (expr is LiteralExpr) return expr.value;

    if (expr is InterpolationExpr) {
      final buffer = StringBuffer();
      for (final part in expr.parts) {
        buffer.write(part is Expr ? _stringify(_eval(part, scope)) : part.toString());
      }
      return buffer.toString();
    }

    if (expr is IdentifierExpr) {
      _markLocation(expr.file, expr.line);
      return _resolveIdentifier(expr.name, scope);
    }

    if (expr is AwaitExpr) {
      throw PreviewRuntimeException(
        'لا يمكن استخدام await هنا: التعبير المحيط ليس داخل دالة/lambda '
        'مُعلَّمة async. أضيفي async بعد قوس المعاملات مباشرة، مثل: '
        '() async { ... }.',
      );
    }

    if (expr is ListExpr) {
      final result = <dynamic>[];
      for (final element in expr.elements) {
        if (element is ListForElement) {
          final iterable = _eval(element.iterable, scope);
          if (iterable is! Iterable) {
            throw PreviewRuntimeException('for داخل قائمة يتطلب قيمة قابلة للتكرار (List)');
          }
          var index = 0;
          for (final item in iterable) {
            final loopScope = RuntimeScope(
              locals: {element.varName: item},
              fields: scope.fields,
              methods: scope.methods,
              instancePath: [...scope.instancePath, 'listfor:$index'],
              parent: scope,
            );
            result.add(_eval(element.element, loopScope));
            index++;
          }
        } else if (element is ListClassicForElement) {
          final loopScope = RuntimeScope(fields: scope.fields, methods: scope.methods, parent: scope);
          if (element.init != null) _exec(element.init!, loopScope);
          var iteration = 0;
          while (element.condition == null || _asBool(_eval(element.condition!, loopScope), 'شرط for')) {
            final iterScope = RuntimeScope(
              fields: loopScope.fields,
              methods: loopScope.methods,
              instancePath: [...scope.instancePath, 'listforclassic:$iteration'],
              parent: loopScope,
            );
            result.add(_eval(element.element, iterScope));
            if (element.increment != null) _exec(element.increment!, loopScope);
            iteration++;
          }
        } else {
          result.add(_eval(element as Expr, scope));
        }
      }
      return result;
    }

    if (expr is MapExpr) {
      return {for (final entry in expr.entries) _eval(entry.key, scope): _eval(entry.value, scope)};
    }

    if (expr is LambdaExpr) {
      if (expr.isAsync) {
        return _callable((args) => _invokeLambdaAsync(expr, args, scope));
      }
      return _callable((args) {
        final callScope = RuntimeScope(fields: scope.fields, methods: scope.methods, parent: scope);
        for (var i = 0; i < expr.params.length && i < args.length; i++) {
          callScope.locals[expr.params[i]] = args[i];
        }
        var execScope = callScope;
        if (args.length == 2 && args[0] is BuildContext && args[1] is int) {
          execScope = RuntimeScope(
            fields: callScope.fields,
            methods: callScope.methods,
            parent: callScope,
            instancePath: [...scope.instancePath, 'item:${args[1]}'],
          );
        }
        try {
          for (final stmt in expr.body) {
            _exec(stmt, execScope);
          }
        } on _ReturnSignal catch (signal) {
          return signal.value;
        }
        return null;
      });
    }

    if (expr is UnaryExpr) {
      final value = _eval(expr.operand, scope);
      if (expr.op == '!') return !_asBool(value, 'العامل !');
      if (expr.op == '-') return -_asNum(value, '-');
      return value;
    }

    if (expr is BinaryExpr) return _evalBinary(expr, scope);

    if (expr is TernaryExpr) {
      return _asBool(_eval(expr.condition, scope), 'شرط ?:') ? _eval(expr.thenExpr, scope) : _eval(expr.elseExpr, scope);
    }

    if (expr is IndexExpr) {
      final target = _eval(expr.target, scope);
      final index = _eval(expr.index, scope);
      if (target is List) return target[index as int];
      if (target is Map) return target[index];
      if (target is String) return target[index as int];
      throw PreviewRuntimeException(
        'لا يمكن الفهرسة (استخدام []) على قيمة من نوع ${target.runtimeType} — الفهرسة مدعومة فقط على List وMap وString.',
      );
    }

    if (expr is PropertyExpr) return _evalProperty(expr, scope);

    if (expr is CallExpr) {
      _markLocation(expr.file, expr.line);
      return _evalCall(expr, scope);
    }

    throw PreviewRuntimeException('نوع تعبير غير مدعوم: ${expr.runtimeType}');
  }

  dynamic _resolveIdentifier(String name, RuntimeScope scope) {
    if (scope.has(name)) return scope.resolve(name);

    final method = scope.methods[name];
    if (method != null) {
      if (method.isGetter) return _runMethod(method, const [], const {}, scope);
      return _callable((args) => _runMethod(method, args, const {}, scope));
    }

    // عضو static في الصنف الحالي (أو أسلافه) بالاسم المجرّد.
    final cd = scope.classDef;
    if (cd != null) {
      final sf = _findStaticField(cd, name);
      if (sf != null) return _staticFieldValue(sf.$1, sf.$2);
    }

    if (globalVars.containsKey(name)) return _globalValue(name);
    final gf = globalFunctions[name];
    if (gf != null) return _callable((args) => _runMethod(gf, args, const {}, RuntimeScope()));

    if (name == 'true') return true;
    if (name == 'false') return false;
    if (name == 'null') return null;
    if (name == 'this') {
      throw PreviewRuntimeException('"this" غير متاح كقيمة هنا (مدعوم داخل دوال الأصناف العادية فقط).');
    }
    throw PreviewRuntimeException('متغيّر غير معروف: $name');
  }

  dynamic _evalBinary(BinaryExpr expr, RuntimeScope scope) {
    if (expr.op == '&&') {
      return _asBool(_eval(expr.left, scope), 'العامل &&') && _asBool(_eval(expr.right, scope), 'العامل &&');
    }
    if (expr.op == '||') {
      return _asBool(_eval(expr.left, scope), 'العامل ||') || _asBool(_eval(expr.right, scope), 'العامل ||');
    }

    final left = _eval(expr.left, scope);
    final right = _eval(expr.right, scope);

    switch (expr.op) {
      case '+':
        if (left is String || right is String) return _stringify(left) + _stringify(right);
        if (left is List && right is List) return [...left, ...right];
        return _asNum(left, '+') + _asNum(right, '+');
      case '-':
        return _asNum(left, '-') - _asNum(right, '-');
      case '*':
        return _asNum(left, '*') * _asNum(right, '*');
      case '/':
        return _asNum(left, '/') / _asNum(right, '/');
      case '%':
        return _asNum(left, '%') % _asNum(right, '%');
      case '==':
        return left == right;
      case '!=':
        return left != right;
      case '<':
        return _asNum(left, '<') < _asNum(right, '<');
      case '>':
        return _asNum(left, '>') > _asNum(right, '>');
      case '<=':
        return _asNum(left, '<=') <= _asNum(right, '<=');
      case '>=':
        return _asNum(left, '>=') >= _asNum(right, '>=');
      default:
        throw PreviewRuntimeException('عملية غير مدعومة: ${expr.op}');
    }
  }

  String _stringify(dynamic value) {
    if (value == null) return '';
    if (value is InterpretedObject) {
      final m = _allMethods(value.def)['toString'];
      if (m != null && !m.isGetter && !m.isStatic) {
        return _stringify(_runMethod(m, const [], const {}, _objectScope(value.def, value)));
      }
      return value.toString();
    }
    return value.toString();
  }

  static final Set<String> _knownStaticNamespaces = {
    'Colors', 'Icons', 'FontWeight', 'MainAxisAlignment', 'CrossAxisAlignment',
    'MainAxisSize', 'TextAlign', 'FontStyle', 'Alignment', 'BoxShape', 'Axis',
    'WrapAlignment', 'FlexFit', 'BoxFit', 'TextDecoration', 'TextOverflow',
    'BottomNavigationBarType', 'InputBorder', 'FloatingLabelBehavior', 'double',
    ...BuiltinWidgetsExt.staticNamespaces,
  };

  // ------------------------- الخصائص -------------------------

  dynamic _evalProperty(PropertyExpr expr, RuntimeScope scope) {
    final t = expr.target;
    if (t is IdentifierExpr) {
      final targetName = t.name;
      if (targetName == 'this' && !scope.has('this')) return _thisMember(expr.name, scope);
      if (!scope.has(targetName)) {
        final userDef = classRegistry[targetName];
        if (userDef != null) {
          _markLocation(t.file, t.line);
          return _staticMember(userDef, expr.name);
        }
        final composed = '$targetName.${expr.name}';
        if (BuiltinWidgetsExt.staticProperties.containsKey(composed)) {
          return BuiltinWidgetsExt.staticProperties[composed];
        }
        if (BuiltinWidgets.staticProperties.containsKey(composed)) {
          return BuiltinWidgets.staticProperties[composed];
        }
        if (_knownStaticNamespaces.contains(targetName)) {
          _markLocation(t.file, t.line);
          throw PreviewRuntimeException(
            'الخاصية "$composed" غير مُسجَّلة في قائمة الثوابت المدعومة — '
            'تحقّقوا من الاسم، أو أضيفوها يدويًا في builtin_widgets.dart (staticProperties).',
          );
        }
      }
    }
    return _memberOf(_eval(expr.target, scope), expr.name);
  }

  /// `this.x` داخل ودجت/State (حيث الحقول في scope.fields لا في كائن).
  dynamic _thisMember(String name, RuntimeScope scope) {
    if (scope.fields.containsKey(name)) return scope.fields[name];
    final m = scope.methods[name];
    if (m != null) {
      if (m.isGetter) return _runMethod(m, const [], const {}, scope);
      return _callable((args) => _runMethod(m, args, const {}, scope));
    }
    final cd = scope.classDef;
    if (cd != null) {
      final sf = _findStaticField(cd, name);
      if (sf != null) return _staticFieldValue(sf.$1, sf.$2);
    }
    throw PreviewRuntimeException('لا يوجد حقل أو دالة باسم "$name" في الصنف الحالي (this.$name).');
  }

  dynamic _memberOf(dynamic target, String name) {
    if (target is _WidgetRef) return target.args[name];
    if (target is InterpretedObject) return _objectMember(target, name);
    if (target is Map) {
      if (target.containsKey(name)) return target[name];
      final r = nativeProperty(target, name);
      return identical(r, kNoNative) ? null : r;
    }
    if (target == null) {
      _warnOnce('قراءة الخاصية "$name" من قيمة null (تُعاد null هنا؛ في Dart الحقيقي هذا خطأ).');
      return null;
    }
    try {
      final r = nativeProperty(target, name);
      if (!identical(r, kNoNative)) return r;
    } on NativeMemberError catch (e) {
      throw PreviewRuntimeException(e.message);
    }
    throw PreviewRuntimeException(
      'الخاصية "$name" على قيمة من نوع ${target.runtimeType} غير مدعومة في المعاينة '
      'الحالية (قيد في المُفسِّر، وليس بالضرورة خطأ في كودك).',
    );
  }

  dynamic _objectMember(InterpretedObject o, String name) {
    if (o.fields.containsKey(name)) return o.fields[name];
    final m = _allMethods(o.def)[name];
    if (m != null && !m.isStatic) {
      final s = _objectScope(o.def, o);
      if (m.isGetter) return _runMethod(m, const [], const {}, s);
      return _callable((args) => _runMethod(m, args, const {}, s));
    }
    final names = <String>{...o.fields.keys, ..._allMethods(o.def).keys}.toList()..sort();
    throw PreviewRuntimeException(
      'الصنف ${o.def.name} لا يملك عضوًا باسم "$name"'
      '${names.isEmpty ? '' : ' (المتاح: ${names.take(8).join('، ')})'}.',
    );
  }

  // ------------------------- الاستدعاءات -------------------------

  dynamic _evalCall(CallExpr expr, RuntimeScope scope) {
    final callee = expr.callee;

    if (callee is IdentifierExpr) {
      return _evalNamedCall(callee.name, expr, scope);
    }

    if (callee is PropertyExpr) {
      final t = callee.target;
      if (t is IdentifierExpr) {
        if (t.name == 'this' && !scope.has('this')) return _evalNamedCall(callee.name, expr, scope);
        if (t.name == 'super') return _evalSuperCall(callee.name, expr, scope);
        if (!scope.has(t.name)) {
          return _evalNamespacedCall(t.name, callee.name, expr, scope);
        }
      }
      return _evalInstanceMethodCall(callee, expr, scope);
    }

    final fn = _eval(callee, scope);
    if (fn is InterpretedCallable) {
      final (pos, _) = _evalArgs(expr, scope);
      return fn.call(pos);
    }
    throw PreviewRuntimeException(
      'استدعاء غير مدعوم في هذا الإصدار من المُفسِّر (نوع الاستدعاء: ${callee.runtimeType}).',
    );
  }

  dynamic _evalInstanceMethodCall(PropertyExpr callee, CallExpr expr, RuntimeScope scope) {
    final target = _eval(callee.target, scope);
    final name = callee.name;
    final (pos, named) = _evalArgs(expr, scope);
    _markLocation(expr.file, expr.line);

    if (target is InterpretedObject) return _callObjectMethod(target, name, pos, named);

    if (target is _ScaffoldMessengerRef && name == 'showSnackBar') {
      if (pos.isNotEmpty && pos.first is SnackBar) {
        ScaffoldMessenger.of(target.context).showSnackBar(pos.first as SnackBar);
      }
      return null;
    }

    if (target is _NavigatorRef) return _navigatorCall(target, name, pos, named);

    if (target is InterpretedCallable && name == 'call') return target.call(pos);

    if (target is _WidgetRef) {
      final v = target.args[name];
      if (v is InterpretedCallable) return v.call(pos);
    }

    if (target is Map && target[name] is InterpretedCallable) {
      return (target[name] as InterpretedCallable).call(pos);
    }

    if (target == null) {
      throw PreviewRuntimeException(
        'استُدعيت الدالة ".$name()" على قيمة null (قيمة غير مُهيَّأة أو حقل late لم يُعيَّن).',
      );
    }

    try {
      final r = nativeMethod(target, name, pos, named);
      if (!identical(r, kNoNative)) return r;
    } on NativeMemberError catch (e) {
      throw PreviewRuntimeException(e.message);
    }
    throw PreviewRuntimeException(
      'الاستدعاء ".$name()" على قيمة من نوع ${target.runtimeType} غير مدعوم في المعاينة '
      'الحالية (قيد في المُفسِّر، وليس بالضرورة خطأ في كودك).',
    );
  }

  dynamic _navigatorCall(_NavigatorRef ref, String name, List<dynamic> pos, Map<String, dynamic> named) {
    final nav = Navigator.of(ref.context);
    switch (name) {
      case 'push':
        final route = pos.isNotEmpty ? pos[0] : null;
        if (route is InterpretedRouteSpec) {
          nav.push(MaterialPageRoute<void>(builder: route.builder.asContextBuilder));
          return null;
        }
        throw PreviewRuntimeException('Navigator.push يحتاج MaterialPageRoute(builder: ...).');
      case 'pop':
        nav.pop(pos.isNotEmpty ? pos[0] : null);
        return null;
      case 'maybePop':
        nav.maybePop();
        return null;
      case 'canPop':
        return nav.canPop();
      case 'pushNamed':
        if (pos.isNotEmpty && pos[0] is String) nav.pushNamed(pos[0] as String, arguments: named['arguments']);
        return null;
      case 'pushReplacementNamed':
        if (pos.isNotEmpty && pos[0] is String) {
          nav.pushReplacementNamed(pos[0] as String, arguments: named['arguments']);
        }
        return null;
    }
    throw PreviewRuntimeException('Navigator.of(context).$name() غير مدعوم في المعاينة بعد.');
  }

  (List<dynamic>, Map<String, dynamic>) _evalArgs(CallExpr expr, RuntimeScope scope) {
    final positional = [for (final a in expr.positionalArgs) _eval(a, scope)];
    final named = {for (final e in expr.namedArgs.entries) e.key: _eval(e.value, scope)};
    return (positional, named);
  }

  dynamic _evalNamedCall(String name, CallExpr expr, RuntimeScope scope) {
    switch (name) {
      case 'setState':
        final fnValue = expr.positionalArgs.isNotEmpty ? _eval(expr.positionalArgs.first, scope) : null;
        if (fnValue is InterpretedCallable) fnValue.call(const []);
        if (_lifecycleDepth > 0) return null; // setState داخل initState/dispose: لا رسم
        if (_isBuilding) {
          log(
            'تحذير: تم استدعاء setState() مباشرة داخل build() (وليس داخل معالج '
            'حدث مثل onPressed). هذا نمط غير صالح في Flutter الحقيقي أيضًا '
            'ويُسبّب حلقة إعادة بناء لا نهائية — تم تنفيذ التعديل على القيم لكن '
            'دون طلب رسم جديد لمنع ارتجاف الشاشة. انقل هذا المنطق إلى تهيئة '
            'الحقل مباشرة أو داخل معالج حدث فعلي.',
            isError: true,
          );
          return null;
        }
        _requestInstanceRebuild(scope.instanceKey);
        return null;

      case 'print':
        final (pos, _) = _evalArgs(expr, scope);
        log(pos.isNotEmpty ? _stringify(pos.first) : '');
        return null;

      case 'MaterialPageRoute':
        final (_, named) = _evalArgs(expr, scope);
        final builder = named['builder'];
        if (builder is InterpretedCallable) return InterpretedRouteSpec(builder);
        throw PreviewRuntimeException('MaterialPageRoute يحتاج builder صالح');

      case 'showDialog':
        final (_, named) = _evalArgs(expr, scope);
        final dialogContext = named['context'];
        final dialogBuilder = named['builder'];
        if (dialogContext is! BuildContext) {
          throw PreviewRuntimeException('showDialog يحتاج context: صالحًا.');
        }
        if (dialogBuilder is! InterpretedCallable) {
          throw PreviewRuntimeException('showDialog يحتاج builder: صالحًا.');
        }
        showDialog<void>(context: dialogContext, builder: (ctx) => dialogBuilder.asContextBuilder(ctx));
        return null;

      default:
        // متغيّر محلي/معامل/حقل حالة يحمل قيمة قابلة للاستدعاء (builder() ...).
        if (scope.has(name)) {
          final localValue = scope.resolve(name);
          if (localValue is InterpretedCallable) {
            final (pos, _) = _evalArgs(expr, scope);
            return localValue.call(pos);
          }
        }
        if (classRegistry.containsKey(name)) {
          return _instantiateUserClass(name, expr, scope);
        }
        final method = scope.methods[name];
        if (method != null) {
          final (pos, named) = _evalArgs(expr, scope);
          return _runMethod(method, pos, named, scope);
        }
        final globalFn = globalFunctions[name];
        if (globalFn != null) {
          final (pos, named) = _evalArgs(expr, scope);
          return _runMethod(globalFn, pos, named, RuntimeScope());
        }
        if (globalVars.containsKey(name)) {
          final value = _globalValue(name);
          if (value is InterpretedCallable) {
            final (pos, _) = _evalArgs(expr, scope);
            return value.call(pos);
          }
        }
        final (pos, named) = _evalArgs(expr, scope);
        try {
          final g = nativeGlobal(name, pos);
          if (!identical(g, kNoNative)) return g;
        } on NativeMemberError catch (e) {
          throw PreviewRuntimeException(e.message);
        }
        if (BuiltinWidgetsExt.valueConstructors.contains(name)) {
          return BuiltinWidgetsExt.buildValue(name, pos, named);
        }
        if (BuiltinWidgets.valueConstructors.contains(name)) {
          return BuiltinWidgets.buildValue(name, pos, named);
        }
        final widget = BuiltinWidgetsExt.build(name, pos, named) ?? BuiltinWidgets.build(name, pos, named);
        if (widget != null) return widget;
        _markLocation(expr.file, expr.line);
        return _errorWidget(
          'الصنف/الودجت "$name" غير معروف: ليس صنفًا معرَّفًا في مشروعكم، وليس '
          'مُسجَّلًا في قائمة الودجتس المدعومة (قيد في المعاينة الحالية: قد يكون الصنف معرَّفًا في مشروعك بصيغة لا يفهمها '
          'المُفسِّر بعد، وليس بالضرورة خطأ في كودك)، ولا يوجد '
          'باسم هذا دالة مساعدة في الصنف الحالي.',
        );
    }
  }

  dynamic _evalNamespacedCall(String namespace, String member, CallExpr expr, RuntimeScope scope) {
    final userDef = classRegistry[namespace];
    if (userDef != null) return _callClassMember(userDef, member, expr, scope);

    if (namespace == 'Navigator') {
      final context = scope.resolve('context') as BuildContext?;
      if (member == 'of') {
        final ctx = expr.positionalArgs.isNotEmpty ? _eval(expr.positionalArgs.first, scope) : context;
        if (ctx is! BuildContext) throw PreviewRuntimeException('Navigator.of() يتطلّب BuildContext صالحًا.');
        return _NavigatorRef(ctx);
      }
      if (context == null) throw PreviewRuntimeException('لا يوجد BuildContext صالح للتنقل');
      switch (member) {
        case 'push':
          final routeArg = expr.positionalArgs.length > 1 ? _eval(expr.positionalArgs[1], scope) : null;
          if (routeArg is InterpretedRouteSpec) {
            Navigator.of(context).push(MaterialPageRoute(builder: routeArg.builder.asContextBuilder));
          }
          return null;
        case 'pop':
          Navigator.of(context).pop();
          return null;
        case 'pushNamed':
          final routeName = expr.positionalArgs.length > 1 ? _eval(expr.positionalArgs[1], scope) : null;
          if (routeName is String) Navigator.of(context).pushNamed(routeName);
          return null;
        case 'pushReplacementNamed':
          final routeName = expr.positionalArgs.length > 1 ? _eval(expr.positionalArgs[1], scope) : null;
          if (routeName is String) Navigator.of(context).pushReplacementNamed(routeName);
          return null;
      }
    }

    if (namespace == 'ScaffoldMessenger' && member == 'of') {
      final context = expr.positionalArgs.isNotEmpty ? _eval(expr.positionalArgs.first, scope) : null;
      if (context is! BuildContext) {
        throw PreviewRuntimeException('ScaffoldMessenger.of() يتطلّب BuildContext صالحًا كوسيط أول.');
      }
      return _ScaffoldMessengerRef(context);
    }

    if (namespace == 'Theme' && member == 'of') {
      final context = expr.positionalArgs.isNotEmpty ? _eval(expr.positionalArgs.first, scope) : null;
      if (context is! BuildContext) throw PreviewRuntimeException('Theme.of() يتطلّب BuildContext صالحًا.');
      return Theme.of(context);
    }

    if (namespace == 'MediaQuery' && member == 'of') {
      final context = expr.positionalArgs.isNotEmpty ? _eval(expr.positionalArgs.first, scope) : null;
      if (context is! BuildContext) throw PreviewRuntimeException('MediaQuery.of() يتطلّب BuildContext صالحًا.');
      return MediaQuery.of(context);
    }

    if (namespace == 'Future') {
      final (pos, named) = _evalArgs(expr, scope);
      switch (member) {
        case 'delayed':
          final duration = pos.isNotEmpty && pos.first is Duration ? pos.first as Duration : Duration.zero;
          final computation = pos.length > 1 ? pos[1] : named['computation'];
          return Future.delayed(duration, () {
            if (computation is InterpretedCallable) return computation.call(const []);
            return null;
          });
        case 'value':
          return Future.value(pos.isNotEmpty ? pos.first : null);
        default:
          throw PreviewRuntimeException(
            'Future.$member() غير مدعوم بعد — المدعوم حاليًا فقط: '
            'Future.delayed(duration) وFuture.value(x).',
          );
      }
    }

    // ------------------------- دعم Image.asset عبر إعادة توجيه لملف حقيقي -------------------------
    // **قرار معماري موثَّق**: Image.asset() الحقيقية تعتمد على AssetBundle يُجمَّع
    // وقت بناء الـ APK الخاص بتطبيق الـ IDE نفسه — لا يمكنها الوصول لملفات مشروع
    // المستخدم المفتوح ديناميكيًا. نعترضها ونعيد توجيهها لِـ Image.file(...) مع
    // حلّ المسار نسبة لجذر المشروع المفتوح. الكود الناتج لن يعمل دون تعديل لو نُسخ
    // خارج هذا الـ IDE (سيحتاج Image.asset حقيقية + تصريح pubspec.yaml).
    if (namespace == 'Image' && member == 'asset') {
      final (pos, named) = _evalArgs(expr, scope);
      final relativePath = pos.isNotEmpty ? pos[0] as String : (named['name'] as String? ?? '');
      final resolvedPath = p.join(projectRootPath, relativePath);
      return Image.file(
        File(resolvedPath),
        width: (named['width'] as num?)?.toDouble(),
        height: (named['height'] as num?)?.toDouble(),
        fit: named['fit'] as BoxFit?,
        errorBuilder: (ctx, error, stackTrace) {
          return Container(
            color: Colors.red.shade50,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(6),
            child: Text(
              'تعذّر تحميل الصورة من المشروع:\n$relativePath',
              style: const TextStyle(color: Colors.red, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          );
        },
      );
    }

    final composedName = '$namespace.$member';
    final (pos, named) = _evalArgs(expr, scope);
    try {
      final s = nativeStatic(namespace, member, pos, named);
      if (!identical(s, kNoNative)) return s;
    } on NativeMemberError catch (e) {
      throw PreviewRuntimeException(e.message);
    }
    if (BuiltinWidgetsExt.valueConstructors.contains(composedName)) {
      return BuiltinWidgetsExt.buildValue(composedName, pos, named);
    }
    if (BuiltinWidgets.valueConstructors.contains(composedName)) {
      return BuiltinWidgets.buildValue(composedName, pos, named);
    }
    final widget = BuiltinWidgetsExt.build(composedName, pos, named) ?? BuiltinWidgets.build(composedName, pos, named);
    if (widget != null) return widget;
    _markLocation(expr.file, expr.line);
    return _errorWidget(
      'العنصر "$composedName" غير مُسجَّل في قائمة الودجتس/القيم المدعومة '
      '(قيد في المعاينة الحالية، وليس بالضرورة خطأ في كودك) — تحقّقوا من الاسم، أو أضيفوه يدويًا إن كان مطلوبًا فعليًا.',
    );
  }

  // ------------------------- أصناف المستخدم (ودجتس + كائنات) -------------------------

  /// `Name.member(...)` حيث Name صنف معرَّف في المشروع: مُنشئ مسمّى أو دالة static.
  dynamic _callClassMember(WidgetClassDef def, String member, CallExpr expr, RuntimeScope scope) {
    final (pos, named) = _evalArgs(expr, scope);
    _markLocation(expr.file, expr.line);
    if (_findCtor(def, member) != null) {
      return _instantiate(def, member, pos, named, scope, expr.id);
    }
    final m = _allMethods(def)[member];
    if (m != null && m.isStatic && !m.isGetter) {
      final owner = _methodOwners[m] ?? def;
      return _runMethod(m, pos, named, _objectScope(owner, null));
    }
    final sf = _findStaticField(def, member);
    if (sf != null) {
      final v = _staticFieldValue(sf.$1, sf.$2);
      if (v is InterpretedCallable) return v.call(pos);
    }
    throw PreviewRuntimeException(
      'الصنف ${def.name} لا يملك مُنشئًا مسمّى ولا دالة static باسم "$member".',
    );
  }

  dynamic _instantiateUserClass(String name, CallExpr expr, RuntimeScope scope) {
    final def = classRegistry[name]!;
    final (pos, named) = _evalArgs(expr, scope);
    return _instantiate(def, '', pos, named, scope, expr.id);
  }

  dynamic _instantiate(
    WidgetClassDef def,
    String ctorName,
    List<dynamic> pos,
    Map<String, dynamic> named,
    RuntimeScope scope,
    int callId,
  ) {
    if (def.isObjectClass) return _constructObject(def, ctorName, pos, named);
    return _instantiateWidget(def, ctorName, pos, named, scope, callId);
  }

  Widget _instantiateWidget(
    WidgetClassDef def,
    String ctorName,
    List<dynamic> pos,
    Map<String, dynamic> named,
    RuntimeScope scope,
    int callId,
  ) {
    final constructorArgs = <String, dynamic>{};

    if (def.fromAnalyzer) {
      final ctor = _findCtor(def, ctorName);
      if (ctor != null) {
        final ps = RuntimeScope(
          locals: {if (scope.has('context')) 'context': scope.resolve('context')},
          classDef: def,
        );
        _bindParamDefs(ctor.params, pos, named, ps, "المُنشئ '${def.name}'", ignoreKey: true);
        for (final prm in ctor.params) {
          if (prm.isSuper) continue;
          constructorArgs[prm.name] = ps.locals[prm.name];
        }
        final initScope = RuntimeScope(locals: ps.locals, fields: constructorArgs, classDef: def);
        for (final fi in ctor.initializers) {
          constructorArgs[fi.name] = _eval(fi.value, initScope);
        }
      } else if (ctorName.isNotEmpty) {
        throw PreviewRuntimeException("الصنف ${def.name} لا يملك مُنشئًا باسم '$ctorName'.");
      } else {
        if (pos.isNotEmpty) {
          throw PreviewRuntimeException('الصنف ${def.name} لا يملك مُنشئًا يقبل وسائط موضعية.');
        }
        for (final k in named.keys) {
          if (k != 'key') {
            throw PreviewRuntimeException("الصنف ${def.name} لا يملك وسيطًا مسمّى باسم '$k' (لا مُنشئ يعرّفه).");
          }
        }
      }
      final fieldScope = RuntimeScope(fields: constructorArgs, classDef: def);
      for (final f in def.fields) {
        if (f.isStatic) continue;
        if (constructorArgs.containsKey(f.name)) continue;
        constructorArgs[f.name] = f.initializer == null ? null : _eval(f.initializer!, fieldScope);
      }
    } else {
      constructorArgs.addAll(named);
      for (var i = 0; i < pos.length && i < def.fields.length; i++) {
        constructorArgs[def.fields[i].name] = pos[i];
      }
    }

    if (def.baseType == 'StatefulWidget' && def.stateClassName != null) {
      final stateDef = classRegistry[def.stateClassName];
      if (stateDef == null) {
        return _errorWidget('تعذّر إيجاد صنف الحالة ${def.stateClassName} لِـ ${def.name}');
      }

      final instanceKey = '${stateDef.name}#$callId#${scope.instancePath.join('/')}';
      _stateStores.putIfAbsent(instanceKey, () {
        final initial = <String, dynamic>{};
        final fieldScope = RuntimeScope(locals: const {}, classDef: stateDef, methods: _stateMethods(stateDef));
        for (final field in stateDef.fields) {
          if (field.isStatic) continue;
          initial[field.name] = field.initializer == null ? null : _eval(field.initializer!, fieldScope);
        }
        return initial;
      });

      return InterpretedStatefulHost(
        instanceKey: instanceKey,
        stateDef: stateDef,
        constructorArgs: constructorArgs,
        instancePath: scope.instancePath,
        interpreter: this,
      );
    }

    final buildScope = RuntimeScope(
      locals: {'context': scope.resolve('context')},
      fields: constructorArgs,
      methods: {for (final m in def.methods) m.name: m},
      instancePath: scope.instancePath,
      classDef: def,
    );
    return _runBuild(def, buildScope);
  }

  Widget _runBuild(WidgetClassDef def, RuntimeScope buildScope) {
    final previousFile = _currentFile;
    final previousLine = _currentLine;
    _currentFile = def.sourceFile ?? _currentFile;
    try {
      if (def.buildBody == null) {
        final reason = def.buildParseError ??
            'لا توجد دالة build في هذا الصنف (طبيعي لأصناف StatefulWidget نفسها؛ تحقّق من صنف State المرتبط به).';
        return _errorWidget('تعذّر بناء ${def.name}: $reason');
      }
      try {
        for (final stmt in def.buildBody!) {
          _exec(stmt, buildScope);
        }
        return _errorWidget('دالة build في ${def.name} لم تنفّذ عبارة return.');
      } on _ReturnSignal catch (signal) {
        final result = signal.value;
        if (result is Widget) return result;
        return _errorWidget('دالة build في ${def.name} لم تُنتج Widget صالحًا.');
      } catch (e) {
        return _errorWidget('خطأ أثناء بناء ${def.name}: ${_cleanError(e)}');
      }
    } finally {
      // استعادة الموضع بعد بناء ودجت فرعية، حتى لا تُنسب أخطاء الأب لملف الابن.
      _currentFile = previousFile;
      _currentLine = previousLine;
    }
  }

  // ------------------------- نموذج الكائنات -------------------------

  WidgetClassDef? _superDef(WidgetClassDef d) {
    final n = d.superName;
    return n == null ? null : classRegistry[n];
  }

  ConstructorDef? _findCtor(WidgetClassDef def, String name) {
    for (final c in def.constructors) {
      if (c.name == name) return c;
    }
    return null;
  }

  /// كل دوال الصنف مع الموروثة من أسلاف المشروع (الابن يتقدّم على الأب).
  Map<String, MethodDef> _allMethods(WidgetClassDef def) {
    final cached = _methodsCache[def.name];
    if (cached != null) return cached;
    final out = <String, MethodDef>{};
    final sd = _superDef(def);
    if (sd != null && !identical(sd, def)) out.addAll(_allMethods(sd));
    for (final m in def.methods) {
      out[m.name] = m;
    }
    _methodsCache[def.name] = out;
    return out;
  }

  /// نطاق تنفيذ لدوال صنف: [obj] لدوال النسخة، أو null لدوال static.
  RuntimeScope _objectScope(WidgetClassDef def, InterpretedObject? obj) {
    return RuntimeScope(
      locals: {if (obj != null) 'this': obj},
      fields: obj?.fields ?? <String, dynamic>{},
      methods: _allMethods(def),
      classDef: def,
    );
  }

  dynamic _constructObject(WidgetClassDef def, String ctorName, List<dynamic> pos, Map<String, dynamic> named) {
    final ctor = _findCtor(def, ctorName);
    if (ctor != null && ctor.isFactory) return _runFactory(def, ctor, pos, named);
    if (def.isAbstract) {
      throw PreviewRuntimeException(
        'الصنف ${def.name} abstract فلا يمكن إنشاء كائن منه مباشرة (استخدم صنفًا فرعيًا يُنفّذه).',
      );
    }
    final obj = InterpretedObject(def);
    _runConstructor(def, ctorName, obj, pos, named);
    return obj;
  }

  dynamic _runFactory(WidgetClassDef def, ConstructorDef ctor, List<dynamic> pos, Map<String, dynamic> named) {
    final scope = _objectScope(def, null);
    _bindParamDefs(ctor.params, pos, named, scope, "المُنشئ 'factory ${def.name}'");
    final result = _runBody(ctor.body, scope);
    if (result == null) {
      throw PreviewRuntimeException('مُنشئ factory في ${def.name} لم يُعِد كائنًا (يلزم return).');
    }
    return result;
  }

  void _runConstructor(
    WidgetClassDef def,
    String ctorName,
    InterpretedObject obj,
    List<dynamic> pos,
    Map<String, dynamic> named,
  ) {
    final ctor = _findCtor(def, ctorName);
    final scope = _objectScope(def, obj);
    final label = "المُنشئ '${def.name}${ctorName.isEmpty ? '' : '.$ctorName'}'";

    if (ctor == null) {
      if (ctorName.isNotEmpty) {
        throw PreviewRuntimeException("الصنف ${def.name} لا يملك مُنشئًا باسم '$ctorName'.");
      }
      if (pos.isNotEmpty || named.isNotEmpty) {
        throw PreviewRuntimeException(
          'الصنف ${def.name} لا يملك مُنشئًا يقبل وسائط (المُنشئ الافتراضي بلا معاملات).',
        );
      }
      _initFields(def, obj, scope);
      _runSuper(def, obj, null, scope, const [], const {});
      return;
    }

    _bindParamDefs(ctor.params, pos, named, scope, label);

    final redirect = ctor.redirect;
    if (redirect != null) {
      final (rp, rn) = _evalCtorArgs(redirect, scope);
      _runConstructor(def, redirect.name, obj, rp, rn);
      _runBody(ctor.body, scope);
      return;
    }

    _initFields(def, obj, scope);

    final superPos = <dynamic>[];
    final superNamed = <String, dynamic>{};
    for (final prm in ctor.params) {
      final v = scope.locals[prm.name];
      if (prm.isThis) obj.fields[prm.name] = v;
      if (prm.isSuper) {
        if (prm.isNamed) {
          superNamed[prm.name] = v;
        } else {
          superPos.add(v);
        }
      }
    }
    for (final fi in ctor.initializers) {
      obj.fields[fi.name] = _eval(fi.value, scope);
    }
    _runSuper(def, obj, ctor, scope, superPos, superNamed);
    _runBody(ctor.body, scope);
  }

  void _initFields(WidgetClassDef def, InterpretedObject obj, RuntimeScope scope) {
    for (final f in def.fields) {
      if (f.isStatic) continue;
      if (f.initializer != null) {
        obj.fields[f.name] = _eval(f.initializer!, scope);
      } else {
        obj.fields.putIfAbsent(f.name, () => null);
      }
    }
  }

  void _runSuper(
    WidgetClassDef def,
    InterpretedObject obj,
    ConstructorDef? ctor,
    RuntimeScope scope,
    List<dynamic> implicitPos,
    Map<String, dynamic> implicitNamed,
  ) {
    final superDef = _superDef(def);
    if (superDef == null || !superDef.isObjectClass) return; // أب خارجي (Object/ChangeNotifier...)
    final call = ctor?.superCall;
    if (call != null) {
      final (sp, sn) = _evalCtorArgs(call, scope);
      _runConstructor(superDef, call.name, obj, sp, sn);
    } else {
      _runConstructor(superDef, '', obj, implicitPos, implicitNamed);
    }
  }

  (List<dynamic>, Map<String, dynamic>) _evalCtorArgs(CtorCall call, RuntimeScope scope) {
    return (
      [for (final e in call.positional) _eval(e, scope)],
      {for (final e in call.named.entries) e.key: _eval(e.value, scope)},
    );
  }

  dynamic _callObjectMethod(InterpretedObject o, String name, List<dynamic> pos, Map<String, dynamic> named) {
    final m = _allMethods(o.def)[name];
    if (m != null && !m.isStatic) {
      final s = _objectScope(o.def, o);
      final result = _runMethod(m, m.isGetter ? const [] : pos, m.isGetter ? const {} : named, s);
      if (m.isGetter) {
        if (result is InterpretedCallable) return result.call(pos);
        throw PreviewRuntimeException('"$name" في ${o.def.name} getter وليس دالة قابلة للاستدعاء.');
      }
      return result;
    }
    final f = o.fields[name];
    if (f is InterpretedCallable) return f.call(pos);
    if (name == 'toString') return _stringify(o);
    final names = _allMethods(o.def).keys.toList()..sort();
    throw PreviewRuntimeException(
      'الصنف ${o.def.name} لا يملك دالة باسم "$name"'
      '${names.isEmpty ? '' : ' (المتاح: ${names.take(8).join('، ')})'}.',
    );
  }

  /// يحوّل وسائط الاستدعاء إلى معاملات [params] (موضعية/مسمّاة/افتراضية/مطلوبة).
  void _bindParamDefs(
    List<ParamDef> params,
    List<dynamic> pos,
    Map<String, dynamic> named,
    RuntimeScope into,
    String label, {
    bool ignoreKey = false,
  }) {
    var i = 0;
    final usedNamed = <String>{};
    for (final prm in params) {
      if (!prm.isNamed) {
        if (i < pos.length) {
          into.locals[prm.name] = pos[i];
          i++;
        } else if (prm.defaultValue != null) {
          into.locals[prm.name] = _eval(prm.defaultValue!, into);
        } else if (prm.isRequired) {
          throw PreviewRuntimeException('$label يحتاج وسيطًا موضعيًا "${prm.name}" لكن لم يُمرَّر.');
        } else {
          into.locals[prm.name] = null;
        }
      } else {
        if (named.containsKey(prm.name)) {
          into.locals[prm.name] = named[prm.name];
          usedNamed.add(prm.name);
        } else if (prm.defaultValue != null) {
          into.locals[prm.name] = _eval(prm.defaultValue!, into);
        } else if (prm.isRequired) {
          throw PreviewRuntimeException('$label يحتاج الوسيط المسمّى "${prm.name}" لكن لم يُمرَّر.');
        } else {
          into.locals[prm.name] = null;
        }
      }
    }
    if (i < pos.length) {
      throw PreviewRuntimeException('$label يقبل $i وسيطًا موضعيًا فقط لكن مُرِّر ${pos.length}.');
    }
    for (final k in named.keys) {
      if (usedNamed.contains(k)) continue;
      if (ignoreKey && k == 'key') continue;
      throw PreviewRuntimeException('$label لا يقبل وسيطًا مسمّى باسم "$k".');
    }
  }

  // ---- static / globals ----

  (WidgetClassDef, FieldDecl)? _findStaticField(WidgetClassDef def, String name) {
    WidgetClassDef? d = def;
    var guard = 0;
    while (d != null && guard++ < 64) {
      for (final f in d.fields) {
        if (f.isStatic && f.name == name) return (d, f);
      }
      d = _superDef(d);
    }
    return null;
  }

  dynamic _staticFieldValue(WidgetClassDef owner, FieldDecl f) {
    final store = _staticStores.putIfAbsent(owner.name, () => {});
    if (store.containsKey(f.name)) return store[f.name];
    final key = '${owner.name}.${f.name}';
    if (!_staticEvaluating.add(key)) {
      throw PreviewRuntimeException('تبعية دائرية عند تهيئة الحقل static "$key".');
    }
    try {
      final v = f.initializer == null ? null : _eval(f.initializer!, _objectScope(owner, null));
      store[f.name] = v;
      return v;
    } finally {
      _staticEvaluating.remove(key);
    }
  }

  dynamic _staticMember(WidgetClassDef def, String name) {
    final sf = _findStaticField(def, name);
    if (sf != null) return _staticFieldValue(sf.$1, sf.$2);
    final m = _allMethods(def)[name];
    if (m != null && m.isStatic) {
      final s = _objectScope(_methodOwners[m] ?? def, null);
      if (m.isGetter) return _runMethod(m, const [], const {}, s);
      return _callable((args) => _runMethod(m, args, const {}, s));
    }
    final statics = <String>{
      for (WidgetClassDef? d = def; d != null; d = _superDef(d))
        for (final f in d.fields)
          if (f.isStatic) f.name,
    }.toList()
      ..sort();
    throw PreviewRuntimeException(
      'الصنف ${def.name} لا يملك عضو static باسم "$name"'
      '${statics.isEmpty ? '' : ' (الحقول static المتاحة: ${statics.take(8).join('، ')})'}.',
    );
  }

  void _setStatic(WidgetClassDef def, String name, dynamic value) {
    final sf = _findStaticField(def, name);
    if (sf == null) {
      throw PreviewRuntimeException('الصنف ${def.name} لا يملك حقل static باسم "$name" لتعيينه.');
    }
    _staticStores.putIfAbsent(sf.$1.name, () => {})[name] = value;
  }

  dynamic _globalValue(String name) {
    if (_globalValues.containsKey(name)) return _globalValues[name];
    if (!_globalEvaluating.add(name)) {
      throw PreviewRuntimeException('تبعية دائرية عند تهيئة المتغيّر العام "$name".');
    }
    try {
      final init = globalVars[name];
      final v = init == null ? null : _eval(init, RuntimeScope());
      _globalValues[name] = v;
      return v;
    } finally {
      _globalEvaluating.remove(name);
    }
  }

  /// `super.method(...)`: يُنفِّذ دالة الأب (إن كان من أصناف المشروع)، وإلا لا شيء.
  dynamic _evalSuperCall(String name, CallExpr expr, RuntimeScope scope) {
    final (pos, named) = _evalArgs(expr, scope);
    final cd = scope.classDef;
    final sd = cd == null ? null : _superDef(cd);
    if (sd == null) return null; // أب خارجي (State.initState() ...)
    final m = _allMethods(sd)[name];
    if (m == null) return null;
    final s = RuntimeScope(
      locals: {if (scope.has('this')) 'this': scope.resolve('this')},
      fields: scope.fields,
      methods: _allMethods(sd),
      classDef: sd,
      instanceKey: scope.instanceKey,
    );
    return _runMethod(m, pos, named, s);
  }

  // ------------------------- تنفيذ الدوال -------------------------

  void _bindMethodParams(MethodDef m, List<dynamic> pos, Map<String, dynamic> named, RuntimeScope into) {
    final defs = m.paramDefs;
    if (defs != null) {
      _bindParamDefs(defs, pos, named, into, "الدالة '${m.name}'");
      return;
    }
    for (var i = 0; i < m.params.length && i < pos.length; i++) {
      into.locals[m.params[i]] = pos[i];
    }
  }

  dynamic _runMethod(MethodDef m, List<dynamic> pos, Map<String, dynamic> named, RuntimeScope parent) {
    final ms = RuntimeScope(
      fields: parent.fields,
      methods: parent.methods,
      classDef: _methodOwners[m] ?? parent.classDef,
      parent: parent,
    );
    _bindMethodParams(m, pos, named, ms);
    if (m.isAsync) return _runBodyAsync(m.body, ms, m.name);
    return _runBody(m.body, ms);
  }

  dynamic _runBody(List<Stmt> body, RuntimeScope scope) {
    try {
      for (final stmt in body) {
        _exec(stmt, scope);
      }
    } on _ReturnSignal catch (signal) {
      return signal.value;
    }
    return null;
  }

  // ------------------------- Statement execution -------------------------

  void _exec(Stmt stmt, RuntimeScope scope) {
    _markLocation(stmt.file, stmt.line);
    if (stmt is ExprStmt) {
      _eval(stmt.expr, scope);
      return;
    }
    if (stmt is ReturnStmt) {
      throw _ReturnSignal(stmt.value == null ? null : _eval(stmt.value!, scope));
    }
    if (stmt is VarDeclStmt) {
      scope.locals[stmt.name] = stmt.initializer == null ? null : _eval(stmt.initializer!, scope);
      return;
    }
    if (stmt is AssignStmt) {
      _execAssign(stmt, scope);
      return;
    }
    if (stmt is IncDecStmt) {
      final current = _asNum(_evalTargetValue(stmt.target, scope), stmt.op);
      _assignTarget(stmt.target, stmt.op == '++' ? current + 1 : current - 1, scope);
      return;
    }
    if (stmt is IfStmt) {
      if (_asBool(_eval(stmt.condition, scope), 'شرط if')) {
        for (final s in stmt.thenBranch) {
          _exec(s, scope);
        }
      } else {
        for (final s in stmt.elseBranch) {
          _exec(s, scope);
        }
      }
      return;
    }
    if (stmt is WhileStmt) {
      _execWhile(stmt, scope);
      return;
    }
    if (stmt is ForStmt) {
      _execFor(stmt, scope);
      return;
    }
    if (stmt is ForInStmt) {
      _execForIn(stmt, scope);
      return;
    }
    if (stmt is BreakStmt) {
      throw const _BreakSignal();
    }
    if (stmt is ContinueStmt) {
      throw const _ContinueSignal();
    }
    throw PreviewRuntimeException('جملة غير مدعومة: ${stmt.runtimeType}');
  }

  void _execWhile(WhileStmt stmt, RuntimeScope scope) {
    while (_asBool(_eval(stmt.condition, scope), 'شرط while')) {
      try {
        for (final s in stmt.body) {
          _exec(s, scope);
        }
      } on _BreakSignal {
        break;
      } on _ContinueSignal {
        continue;
      }
    }
  }

  void _execFor(ForStmt stmt, RuntimeScope scope) {
    final loopScope = RuntimeScope(fields: scope.fields, methods: scope.methods, parent: scope);
    if (stmt.init != null) _exec(stmt.init!, loopScope);
    var iteration = 0;
    while (stmt.condition == null || _asBool(_eval(stmt.condition!, loopScope), 'شرط for')) {
      final iterScope = RuntimeScope(
        fields: loopScope.fields,
        methods: loopScope.methods,
        instancePath: [...scope.instancePath, 'for:$iteration'],
        parent: loopScope,
      );
      try {
        for (final s in stmt.body) {
          _exec(s, iterScope);
        }
      } on _BreakSignal {
        break;
      } on _ContinueSignal {
        // نتابع إلى سطر increment أدناه
      }
      if (stmt.increment != null) _exec(stmt.increment!, loopScope);
      iteration++;
    }
  }

  void _execForIn(ForInStmt stmt, RuntimeScope scope) {
    final iterable = _eval(stmt.iterable, scope);
    if (iterable is! Iterable) {
      throw PreviewRuntimeException('for-in يتطلب قيمة قابلة للتكرار (List)');
    }
    var index = 0;
    for (final item in List.of(iterable)) {
      final loopScope = RuntimeScope(
        locals: {stmt.varName: item},
        fields: scope.fields,
        methods: scope.methods,
        instancePath: [...scope.instancePath, 'forin:$index'],
        parent: scope,
      );
      try {
        for (final s in stmt.body) {
          _exec(s, loopScope);
        }
      } on _BreakSignal {
        break;
      } on _ContinueSignal {
        index++;
        continue;
      }
      index++;
    }
  }

  dynamic _evalTargetValue(Expr target, RuntimeScope scope) {
    if (target is IdentifierExpr) return _resolveIdentifier(target.name, scope);
    return _eval(target, scope);
  }

  void _execAssign(AssignStmt stmt, RuntimeScope scope) {
    final newValue = switch (stmt.op) {
      '=' => _eval(stmt.value, scope),
      '+=' => _plus(_evalTargetValue(stmt.target, scope), _eval(stmt.value, scope)),
      '-=' => _asNum(_evalTargetValue(stmt.target, scope), '-=') - _asNum(_eval(stmt.value, scope), '-='),
      _ => throw PreviewRuntimeException('عملية تعيين غير مدعومة: ${stmt.op}'),
    };
    _assignTarget(stmt.target, newValue, scope);
  }

  dynamic _plus(dynamic a, dynamic b) {
    if (a is String || b is String) return _stringify(a) + _stringify(b);
    if (a is List && b is List) return [...a, ...b];
    return _asNum(a, '+=') + _asNum(b, '+=');
  }

  void _assignTarget(Expr target, dynamic value, RuntimeScope scope) {
    if (target is IdentifierExpr) {
      final name = target.name;
      if (!scope.has(name)) {
        final cd = scope.classDef;
        if (cd != null) {
          final sf = _findStaticField(cd, name);
          if (sf != null) {
            _staticStores.putIfAbsent(sf.$1.name, () => {})[name] = value;
            return;
          }
        }
        if (globalVars.containsKey(name)) {
          _globalValues[name] = value;
          return;
        }
      }
      scope.assign(name, value);
      return;
    }

    if (target is PropertyExpr) {
      final t = target.target;
      if (t is IdentifierExpr) {
        if (t.name == 'this' && !scope.has('this')) {
          scope.fields[target.name] = value;
          return;
        }
        if (!scope.has(t.name) && classRegistry.containsKey(t.name)) {
          _setStatic(classRegistry[t.name]!, target.name, value);
          return;
        }
      }
      final obj = _eval(t, scope);
      if (obj is InterpretedObject) {
        if (!obj.fields.containsKey(target.name)) {
          throw PreviewRuntimeException('الصنف ${obj.def.name} لا يملك حقلًا باسم "${target.name}" لتعيينه.');
        }
        obj.fields[target.name] = value;
        return;
      }
      if (obj is Map) {
        obj[target.name] = value;
        return;
      }
      if (nativeSetProperty(obj, target.name, value)) return;
      throw PreviewRuntimeException(
        'لا يمكن تعيين الخاصية "${target.name}" على قيمة من نوع ${obj.runtimeType} في المعاينة الحالية.',
      );
    }

    if (target is IndexExpr) {
      final obj = _eval(target.target, scope);
      final index = _eval(target.index, scope);
      if (obj is List) {
        obj[index as int] = value;
        return;
      }
      if (obj is Map) {
        obj[index] = value;
        return;
      }
      throw PreviewRuntimeException('لا يمكن التعيين بالفهرسة على قيمة من نوع ${obj.runtimeType}.');
    }

    throw PreviewRuntimeException('لا يمكن التعيين لهذا التعبير');
  }

  // ==================================================================
  // ==================== دعم async/await المبسَّط ====================
  // ==================================================================

  Future<dynamic> _runBodyAsync(List<Stmt> body, RuntimeScope scope, String label) async {
    try {
      for (final stmt in body) {
        await _execAsync(stmt, scope);
      }
    } on _ReturnSignal catch (signal) {
      return signal.value;
    } catch (e) {
      log('خطأ أثناء تنفيذ دالة async "$label" (${_formatLocation()}): ${_cleanError(e)}', isError: true);
      return null;
    }
    return null;
  }

  Future<dynamic> _invokeLambdaAsync(LambdaExpr expr, List<dynamic> args, RuntimeScope scope) async {
    final callScope = RuntimeScope(
      fields: scope.fields,
      methods: scope.methods,
      instanceKey: scope.instanceKey,
      parent: scope,
    );
    for (var i = 0; i < expr.params.length && i < args.length; i++) {
      callScope.locals[expr.params[i]] = args[i];
    }
    var execScope = callScope;
    if (args.length == 2 && args[0] is BuildContext && args[1] is int) {
      execScope = RuntimeScope(
        fields: callScope.fields,
        methods: callScope.methods,
        instanceKey: callScope.instanceKey,
        parent: callScope,
        instancePath: [...scope.instancePath, 'item:${args[1]}'],
      );
    }
    return _runBodyAsync(expr.body, execScope, 'lambda');
  }

  Future<void> _execAsync(Stmt stmt, RuntimeScope scope) async {
    _markLocation(stmt.file, stmt.line);

    if (stmt is ExprStmt) {
      await _evalMaybeAwait(stmt.expr, scope);
      return;
    }
    if (stmt is ReturnStmt) {
      final value = stmt.value == null ? null : await _evalMaybeAwait(stmt.value!, scope);
      throw _ReturnSignal(value);
    }
    if (stmt is VarDeclStmt) {
      scope.locals[stmt.name] = stmt.initializer == null ? null : await _evalMaybeAwait(stmt.initializer!, scope);
      return;
    }
    if (stmt is AssignStmt) {
      await _execAssignAsync(stmt, scope);
      return;
    }
    if (stmt is IfStmt) {
      if (_asBool(await _evalMaybeAwait(stmt.condition, scope), 'شرط if')) {
        for (final s in stmt.thenBranch) {
          await _execAsync(s, scope);
        }
      } else {
        for (final s in stmt.elseBranch) {
          await _execAsync(s, scope);
        }
      }
      return;
    }
    if (stmt is WhileStmt) {
      while (_asBool(await _evalMaybeAwait(stmt.condition, scope), 'شرط while')) {
        try {
          for (final s in stmt.body) {
            await _execAsync(s, scope);
          }
        } on _BreakSignal {
          break;
        } on _ContinueSignal {
          continue;
        }
      }
      return;
    }

    _exec(stmt, scope);
  }

  Future<void> _execAssignAsync(AssignStmt stmt, RuntimeScope scope) async {
    late final dynamic newValue;
    switch (stmt.op) {
      case '=':
        newValue = await _evalMaybeAwait(stmt.value, scope);
        break;
      case '+=':
        newValue = _plus(_evalTargetValue(stmt.target, scope), await _evalMaybeAwait(stmt.value, scope));
        break;
      case '-=':
        newValue = _asNum(_evalTargetValue(stmt.target, scope), '-=') -
            _asNum(await _evalMaybeAwait(stmt.value, scope), '-=');
        break;
      default:
        throw PreviewRuntimeException('عملية تعيين غير مدعومة: ${stmt.op}');
    }
    _assignTarget(stmt.target, newValue, scope);
  }

  Future<dynamic> _evalMaybeAwait(Expr expr, RuntimeScope scope) async {
    if (expr is AwaitExpr) {
      final value = _eval(expr.inner, scope);
      if (value is Future) return await value;
      return value;
    }
    return _eval(expr, scope);
  }
}
