import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'builtin_widgets.dart';
import 'dart_subset_ast.dart';
import 'interpreted_callable.dart';

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
/// **أي** [InterpretedStatefulHost] يجب إعادة رسمه محليًا (راجع
/// Interpreter._requestInstanceRebuild) بدل إعادة بناء الجذر بالكامل — هذا
/// هو الإصلاح الجوهري لمشكلة "setState لا يُحدِّث الشاشة الفرعية المفتوحة
/// عبر Navigator.push". يبقى null خارج أي صنف Stateful (مثل داخل بناء
/// StatelessWidget، الذي لا يملك state أصلًا في Dart الحقيقي أيضًا).
class RuntimeScope {
  final Map<String, dynamic> locals;
  final Map<String, dynamic> fields;
  final Map<String, MethodDef> methods;
  final List<String> instancePath;
  final String? instanceKey;
  final RuntimeScope? parent;

  RuntimeScope({
    Map<String, dynamic>? locals,
    Map<String, dynamic>? fields,
    Map<String, MethodDef>? methods,
    List<String>? instancePath,
    String? instanceKey,
    this.parent,
  })  : locals = locals ?? {},
        fields = fields ?? (parent?.fields ?? {}),
        methods = methods ?? (parent?.methods ?? {}),
        instancePath = instancePath ?? (parent?.instancePath ?? const []),
        instanceKey = instanceKey ?? parent?.instanceKey;

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
    return null; // يُترك التحقق من الوجود لموقع الاستدعاء (لدعم static lookups لاحقًا)
  }

  bool has(String name) => _localExists(name) || fields.containsKey(name);

  /// يعيّن قيمة لمتغيّر: إن كان متغيّرًا محليًا معلنًا (معامل أو `var`/`final`
  /// داخل جسم الدالة) يُحدَّث في مكانه؛ وإلا فهو حقل حالة (مثل `_counter`)
  /// فيُحدَّث مباشرة في خريطة [fields] المشتركة والدائمة، حتى تبقى القيمة
  /// محفوظة بين عمليات إعادة البناء المتتالية بعد setState.
  void assign(String name, dynamic value) {
    if (_setLocalIfExists(name, value)) return;
    fields[name] = value;
  }
}

/// ودجت Flutter **حقيقية** (State حقيقي من Flutter نفسه، وليس محاكاة) تُمثّل
/// نسخة واحدة من صنف StatefulWidget مُفسَّر.
///
/// **لماذا أُضيف هذا الكلاس (الإصلاح الجوهري لمشكلة موثَّقة)**: قبل هذا
/// التعديل، كان `Interpreter._instantiateUserClass` يُنفِّذ build() فورًا
/// ويُعيد ناتجها كودجت عادي مباشرة — أي لم يكن هناك أي `StatefulWidget`/
/// `State` حقيقي من Flutter في الشجرة إطلاقًا؛ الحالة كانت محفوظة فقط في
/// خريطة داخلية (`_stateStores`)، وآلية setState() الوحيدة كانت "أعِد بناء
/// الجذر بالكامل" (`onStateChanged` → rebuildTick في Riverpod).
///
/// **الحل**: كل نسخة StatefulWidget مُفسَّرة تحصل الآن على `State` حقيقي من
/// Flutter (هذا الكلاس)، مسجَّل في `Interpreter._hosts` بمفتاح [instanceKey]
/// نفسه المستخدَم أصلًا في `_stateStores`. عند setState() من كود المستخدم،
/// يستدعي المُفسِّر `.setState()` الحقيقي على هذا العنصر تحديدًا.
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
/// async-await المبسَّط كأفعال حقيقية على محرك Flutter المستضيف (وليس
/// محاكاة). راجع README لحدود الدعم.
class Interpreter {
  final Map<String, WidgetClassDef> classRegistry;
  final void Function(String message, {bool isError}) log;
  final VoidCallback onStateChanged;

  /// مسار جذر المشروع المفتوح حاليًا على القرص — يُستخدَم حصرًا لحلّ مسارات
  /// الصور النسبية في Image.asset(...) (راجع التوثيق الكامل عند معالجة
  /// 'Image'/'asset' في _evalNamespacedCall أدناه لشرح السبب المعماري).
  final String projectRootPath;

  final Map<String, Map<String, dynamic>> _stateStores = {};
  final Map<String, _InterpretedStatefulHostState> _hosts = {};

  bool _isBuilding = false;

  String? _currentFile;
  int? _currentLine;

  Interpreter({
    required this.classRegistry,
    required this.log,
    required this.onStateChanged,
    required this.projectRootPath,
  });

  Widget buildRoot(Expr rootExpr, BuildContext context) {
    _isBuilding = true;
    try {
      final result = _eval(rootExpr, RuntimeScope(locals: {'context': context}));
      if (result is Widget) return result;
      return _errorWidget('التعبير الجذري لا يُنتج Widget صالحًا.');
    } catch (e) {
      return _errorWidget(e.toString());
    } finally {
      _isBuilding = false;
    }
  }

  /// يضبط "الموضع الحالي" المستخدَم في رسائل الخطأ من عقدة الشجرة نفسها
  /// (ملفها وسطرها المطلق)، بدل الاعتماد على آخر صنف بُني (كان يُنسب الخطأ
  /// لملف خاطئ عندما يحدث أثناء تقييم وسيط يخص ودجت من ملف آخر).
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

  void _registerHost(String instanceKey, _InterpretedStatefulHostState host) {
    _hosts[instanceKey] = host;
  }

  void _unregisterHost(String instanceKey, _InterpretedStatefulHostState host) {
    if (identical(_hosts[instanceKey], host)) _hosts.remove(instanceKey);
  }

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
      methods: {for (final m in stateDef.methods) m.name: m},
      instancePath: instancePath,
      instanceKey: instanceKey,
    );
    return _runBuild(stateDef, buildScope);
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
          while (element.condition == null || (_eval(element.condition!, loopScope) as bool)) {
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
        return InterpretedCallable((args) => _invokeLambdaAsync(expr, args, scope));
      }
      return InterpretedCallable((args) {
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
      if (expr.op == '!') return !(value as bool);
      if (expr.op == '-') return -(value as num);
      return value;
    }

    if (expr is BinaryExpr) return _evalBinary(expr, scope);

    if (expr is TernaryExpr) {
      return (_eval(expr.condition, scope) as bool)
          ? _eval(expr.thenExpr, scope)
          : _eval(expr.elseExpr, scope);
    }

    if (expr is IndexExpr) {
      final target = _eval(expr.target, scope);
      final index = _eval(expr.index, scope);
      if (target is List) return target[index as int];
      if (target is Map) return target[index];
      throw PreviewRuntimeException(
        'لا يمكن الفهرسة (استخدام []) على قيمة من نوع ${target.runtimeType} — الفهرسة مدعومة فقط على List وMap.',
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
    if (scope.methods.containsKey(name)) {
      final method = scope.methods[name]!;
      return InterpretedCallable(
        (args) => method.isAsync ? _invokeMethodAsync(method, args, scope) : _invokeMethod(method, args, scope),
      );
    }
    if (name == 'true') return true;
    if (name == 'false') return false;
    if (name == 'null') return null;
    throw PreviewRuntimeException('متغيّر غير معروف: $name');
  }

  dynamic _evalBinary(BinaryExpr expr, RuntimeScope scope) {
    if (expr.op == '&&') return (_eval(expr.left, scope) as bool) && (_eval(expr.right, scope) as bool);
    if (expr.op == '||') return (_eval(expr.left, scope) as bool) || (_eval(expr.right, scope) as bool);

    final left = _eval(expr.left, scope);
    final right = _eval(expr.right, scope);

    switch (expr.op) {
      case '+':
        if (left is String || right is String) return _stringify(left) + _stringify(right);
        return (left as num) + (right as num);
      case '-':
        return (left as num) - (right as num);
      case '*':
        return (left as num) * (right as num);
      case '/':
        return (left as num) / (right as num);
      case '%':
        return (left as num) % (right as num);
      case '==':
        return left == right;
      case '!=':
        return left != right;
      case '<':
        return (left as num) < (right as num);
      case '>':
        return (left as num) > (right as num);
      case '<=':
        return (left as num) <= (right as num);
      case '>=':
        return (left as num) >= (right as num);
      default:
        throw PreviewRuntimeException('عملية غير مدعومة: ${expr.op}');
    }
  }

  String _stringify(dynamic value) => value == null ? '' : value.toString();

  static const Set<String> _knownStaticNamespaces = {
    'Colors', 'Icons', 'FontWeight', 'MainAxisAlignment', 'CrossAxisAlignment',
    'MainAxisSize', 'TextAlign', 'FontStyle', 'Alignment', 'BoxShape', 'Axis',
    'WrapAlignment', 'FlexFit', 'BoxFit', 'TextDecoration', 'TextOverflow',
    'BottomNavigationBarType', 'InputBorder', 'FloatingLabelBehavior', 'double',
  };

  dynamic _evalProperty(PropertyExpr expr, RuntimeScope scope) {
    if (expr.target is IdentifierExpr) {
      final targetName = (expr.target as IdentifierExpr).name;
      if (!scope.has(targetName)) {
        final composed = '$targetName.${expr.name}';
        if (BuiltinWidgets.staticProperties.containsKey(composed)) {
          return BuiltinWidgets.staticProperties[composed];
        }
        if (_knownStaticNamespaces.contains(targetName)) {
          final targetIdent = expr.target as IdentifierExpr;
          _markLocation(targetIdent.file, targetIdent.line);
          throw PreviewRuntimeException(
            'الخاصية "$composed" غير مُسجَّلة في قائمة الثوابت المدعومة — '
            'تحقّقوا من الاسم، أو أضيفوها يدويًا في builtin_widgets.dart (staticProperties).',
          );
        }
      }
    }

    final target = _eval(expr.target, scope);
    if (target is _WidgetRef) return target.args[expr.name];
    if (target is Map) return target[expr.name];
    if (target is TextEditingController && expr.name == 'text') return target.text;
    return null;
  }

  dynamic _evalCall(CallExpr expr, RuntimeScope scope) {
    final callee = expr.callee;

    if (callee is IdentifierExpr) {
      return _evalNamedCall(callee.name, expr, scope);
    }

    if (callee is PropertyExpr) {
      if (callee.target is IdentifierExpr) {
        final namespace = (callee.target as IdentifierExpr).name;
        if (!scope.has(namespace)) {
          return _evalNamespacedCall(namespace, callee.name, expr, scope);
        }
      }
      return _evalInstanceMethodCall(callee, expr, scope);
    }

    throw PreviewRuntimeException(
      'استدعاء غير مدعوم في هذا الإصدار من المُفسِّر (نوع الاستدعاء: ${callee.runtimeType}).',
    );
  }

  dynamic _evalInstanceMethodCall(PropertyExpr callee, CallExpr expr, RuntimeScope scope) {
    final target = _eval(callee.target, scope);

    if (target is TextEditingController) {
      switch (callee.name) {
        case 'clear':
          target.clear();
          return null;
        case 'dispose':
          return null;
      }
    }

    if (target is _ScaffoldMessengerRef && callee.name == 'showSnackBar') {
      final (pos, _) = _evalArgs(expr, scope);
      if (pos.isNotEmpty && pos.first is SnackBar) {
        ScaffoldMessenger.of(target.context).showSnackBar(pos.first as SnackBar);
      }
      return null;
    }

    _markLocation(expr.file, expr.line);
    throw PreviewRuntimeException(
      'الاستدعاء ".${callee.name}()" على قيمة من نوع ${target.runtimeType} غير مدعوم في المعاينة '
      'الحالية (قيد في المُفسِّر، وليس بالضرورة خطأ في كودك).',
    );
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
        // **إصلاح جوهري**: إن كان "name" متغيّرًا محليًا/معاملًا/حقل حالة
        // يحمل بالفعل قيمة قابلة للاستدعاء (InterpretedCallable) — مثل
        // معامل دالة مساعدة استُلم عبر Method Reference أو لامدا، ثم نُودي
        // استدعاؤه لاحقًا بصياغة `name(...)` — استدعها مباشرة الآن، قبل
        // افتراض أن "name" اسم صنف/ودجت غير معروف.
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
        if (scope.methods.containsKey(name)) {
          final (pos, _) = _evalArgs(expr, scope);
          final method = scope.methods[name]!;
          return method.isAsync ? _invokeMethodAsync(method, pos, scope) : _invokeMethod(method, pos, scope);
        }
        final (pos, named) = _evalArgs(expr, scope);
        if (BuiltinWidgets.valueConstructors.contains(name)) {
          return BuiltinWidgets.buildValue(name, pos, named);
        }
        final widget = BuiltinWidgets.build(name, pos, named);
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
    if (namespace == 'Navigator') {
      final context = scope.resolve('context') as BuildContext?;
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
    // **قرار معماري موثَّق بالكامل**: Image.asset() الحقيقية في Flutter تعتمد
    // على AssetBundle يُجمَّع **وقت بناء الـ APK** من pubspec.yaml الخاص
    // بتطبيق الـ IDE نفسه — لا يمكنها إطلاقًا الوصول لملفات مشروع المستخدم
    // المفتوح ديناميكيًا وقت التشغيل، مهما فعلنا، لأن الأصول الحقيقية
    // تُحزَم داخل الـ APK نفسه عند flutter build وليست نظام ملفات حيًّا.
    // الحل: نعترض Image.asset(...) هنا ونُعيد توجيهها فعليًا لِـ
    // Image.file(...) مع حلّ المسار نسبة لجذر المشروع المفتوح حاليًا
    // (projectRootPath) — يبقى استدعاء المستخدم "Image.asset" كما هو، لكن
    // التنفيذ الفعلي خلف الكواليس مختلف تمامًا. **تنويه صريح**: الكود
    // الناتج لن يعمل دون تعديل إن نُسخ لاحقًا لمشروع Flutter حقيقي خارج
    // هذا الـ IDE (سيحتاج حينها Image.asset حقيقية + تصريح pubspec.yaml
    // حقيقي تحت assets:).
    if (namespace == 'Image' && member == 'asset') {
      final (pos, named) = _evalArgs(expr, scope);
      final relativePath = pos.isNotEmpty
          ? pos[0] as String
          : (named['name'] as String? ?? '');
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
    if (BuiltinWidgets.valueConstructors.contains(composedName)) {
      return BuiltinWidgets.buildValue(composedName, pos, named);
    }
    final widget = BuiltinWidgets.build(composedName, pos, named);
    if (widget != null) return widget;
    _markLocation(expr.file, expr.line);
    return _errorWidget(
      'العنصر "$composedName" غير مُسجَّل في قائمة الودجتس/القيم المدعومة '
      '(قيد في المعاينة الحالية، وليس بالضرورة خطأ في كودك) — تحقّقوا من الاسم، أو أضيفوه يدويًا إن كان مطلوبًا فعليًا.',
    );
  }

  Widget _instantiateUserClass(String name, CallExpr expr, RuntimeScope scope) {
    final def = classRegistry[name]!;
    final (pos, named) = _evalArgs(expr, scope);
    final constructorArgs = <String, dynamic>{...named};
    for (var i = 0; i < pos.length && i < def.fields.length; i++) {
      constructorArgs[def.fields[i].name] = pos[i];
    }

    if (def.baseType == 'StatefulWidget' && def.stateClassName != null) {
      final stateDef = classRegistry[def.stateClassName];
      if (stateDef == null) {
        return _errorWidget('تعذّر إيجاد صنف الحالة ${def.stateClassName} لِـ $name');
      }

      final instanceKey = '${stateDef.name}#${expr.id}#${scope.instancePath.join('/')}';
      _stateStores.putIfAbsent(instanceKey, () {
        final initial = <String, dynamic>{};
        final fieldScope = RuntimeScope(locals: const {});
        for (final field in stateDef.fields) {
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
    );
    return _runBuild(def, buildScope);
  }

  Widget _runBuild(WidgetClassDef def, RuntimeScope buildScope) {
    _currentFile = def.sourceFile ?? _currentFile;
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
      return _errorWidget('خطأ أثناء بناء ${def.name}: $e');
    }
  }

  dynamic _invokeMethod(MethodDef method, List<dynamic> args, RuntimeScope callerScope) {
    final methodScope = RuntimeScope(
      fields: callerScope.fields,
      methods: callerScope.methods,
      parent: callerScope,
    );
    for (var i = 0; i < method.params.length && i < args.length; i++) {
      methodScope.locals[method.params[i]] = args[i];
    }
    try {
      for (final stmt in method.body) {
        _exec(stmt, methodScope);
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
      final current = _evalTargetValue(stmt.target, scope) as num;
      _assignTarget(stmt.target, stmt.op == '++' ? current + 1 : current - 1, scope);
      return;
    }
    if (stmt is IfStmt) {
      if (_eval(stmt.condition, scope) as bool) {
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
    while (_eval(stmt.condition, scope) as bool) {
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
    while (stmt.condition == null || (_eval(stmt.condition!, loopScope) as bool)) {
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
    for (final item in iterable) {
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
    if (target is IdentifierExpr) return scope.resolve(target.name);
    return _eval(target, scope);
  }

  void _execAssign(AssignStmt stmt, RuntimeScope scope) {
    final newValue = switch (stmt.op) {
      '=' => _eval(stmt.value, scope),
      '+=' => (_evalTargetValue(stmt.target, scope) as dynamic) + _eval(stmt.value, scope),
      '-=' => (_evalTargetValue(stmt.target, scope) as num) - (_eval(stmt.value, scope) as num),
      _ => throw PreviewRuntimeException('عملية تعيين غير مدعومة: ${stmt.op}'),
    };
    _assignTarget(stmt.target, newValue, scope);
  }

  void _assignTarget(Expr target, dynamic value, RuntimeScope scope) {
    if (target is IdentifierExpr) {
      scope.assign(target.name, value);
      return;
    }
    throw PreviewRuntimeException('لا يمكن التعيين لهذا التعبير');
  }

  // ==================================================================
  // ==================== دعم async/await المبسَّط ====================
  // ==================================================================

  Future<dynamic> _invokeMethodAsync(MethodDef method, List<dynamic> args, RuntimeScope callerScope) async {
    final methodScope = RuntimeScope(
      fields: callerScope.fields,
      methods: callerScope.methods,
      instanceKey: callerScope.instanceKey,
      parent: callerScope,
    );
    for (var i = 0; i < method.params.length && i < args.length; i++) {
      methodScope.locals[method.params[i]] = args[i];
    }
    try {
      for (final stmt in method.body) {
        await _execAsync(stmt, methodScope);
      }
    } on _ReturnSignal catch (signal) {
      return signal.value;
    } catch (e) {
      log('خطأ أثناء تنفيذ دالة async "${method.name}": $e', isError: true);
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
    try {
      for (final stmt in expr.body) {
        await _execAsync(stmt, execScope);
      }
    } on _ReturnSignal catch (signal) {
      return signal.value;
    } catch (e) {
      log('خطأ أثناء تنفيذ دالة async: $e', isError: true);
      return null;
    }
    return null;
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
      if (await _evalMaybeAwait(stmt.condition, scope) as bool) {
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
      while (await _evalMaybeAwait(stmt.condition, scope) as bool) {
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
        newValue = (_evalTargetValue(stmt.target, scope) as dynamic) + await _evalMaybeAwait(stmt.value, scope);
        break;
      case '-=':
        newValue =
            (_evalTargetValue(stmt.target, scope) as num) - (await _evalMaybeAwait(stmt.value, scope) as num);
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
