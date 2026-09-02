import 'package:flutter/material.dart';

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
/// هذا يعمل للشاشة الرئيسية فقط، لكنه **لا يصل إطلاقًا** لأي ودجت مبني داخل
/// Route مفتوحة عبر `Navigator.push(...)`: الـ Navigator يحتفظ بأشجار
/// الـ Routes المفتوحة في Overlay داخلي منفصل تمامًا عن الشجرة التي يُعيد
/// `buildRoot` إنتاجها من الجذر. لذلك كانت القيمة تتغيّر فعليًا (`print`
/// يؤكّد ذلك) لكن الشاشة الفرعية المفتوحة عبر Navigator لا تُعاد رسمها إلا
/// عند التنقّل مجددًا (الذي يبني الشاشة من الصفر عبر builder فيعكس القيمة
/// الجديدة، مما أوهم أن المشكلة "تُحلّ نفسها" عند التنقّل).
///
/// **الحل**: كل نسخة StatefulWidget مُفسَّرة تحصل الآن على `State` حقيقي من
/// Flutter (هذا الكلاس)، مسجَّل في `Interpreter._hosts` بمفتاح [instanceKey]
/// نفسه المستخدَم أصلًا في `_stateStores`. عند setState() من كود المستخدم،
/// يستدعي المُفسِّر `.setState()` الحقيقي على هذا العنصر تحديدًا — فتُعيد
/// Flutter رسمه **في مكانه بالضبط** بغضّ النظر عن كونه داخل Route مدفوعة،
/// أو عنصر قائمة، أو الشاشة الرئيسية، لأنها الآن آلية Flutter الحقيقية،
/// وليست محاكاة. فائدة إضافية: لم نعد نُعيد بناء الشجرة بأكملها من الجذر
/// عند أي setState — فقط العنصر المتأثر (تحسين أداء حقيقي أيضًا).
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
    // نادر عمليًا (نفس ValueKey يعني عادة نفس instanceKey ونفس العنصر)،
    // لكن نتعامل معه دفاعيًا حتى لا يبقى تسجيل قديم يُشير لعنصر تغيّرت هويته.
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

  /// يُستدعى من Interpreter._requestInstanceRebuild عند setState() الخاص
  /// بهذه النسخة تحديدًا — إعادة رسم محلية حقيقية عبر State.setState، وليس
  /// محاكاة.
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

  /// مخازن حالة دائمة، مفتاحها **مركّب** من: اسم صنف الحالة + معرّف عقدة
  /// الاستدعاء (CallExpr.id) + مسار الحلقات المؤدّي إليها (instancePath).
  /// هذا يسمح بنسخ متعددة نشطة من نفس الصنف (مثل عناصر قائمة) دون أن
  /// تتشارك الحالة — كل عنصر في القائمة يحصل على مفتاح مختلف بفضل فهرسه
  /// ضمن instancePath، بينما يبقى المفتاح **مستقرًا** لنفس العنصر عبر
  /// عمليات إعادة البناء المتتالية (لأن CallExpr.id لا يتغيّر بين rebuilds
  /// ضمن نفس الجلسة).
  ///
  /// **حد معروف**: إن تغيّر طول قائمة ديناميكيًا (عناصر تُحذف/تُضاف) أثناء
  /// الجلسة، تبقى مخازن العناصر المحذوفة في الذاكرة حتى "إعادة تشغيل"
  /// كاملة (يُنشئ Interpreter جديدًا بمخزن فارغ) — تسريب ذاكرة محدود
  /// النطاق بحجم الجلسة، غير مُعالَج بعد.
  final Map<String, Map<String, dynamic>> _stateStores = {};

  /// سجلّ المضيفين الحقيقيين (InterpretedStatefulHost State) لكل instanceKey
  /// نشط حاليًا في شجرة الودجتس — راجع توثيق [InterpretedStatefulHost]
  /// للسبب والتفاصيل الكاملة. يُسجَّل عند initState ويُزال عند dispose.
  final Map<String, _InterpretedStatefulHostState> _hosts = {};

  /// حارس يمنع حلقة لا نهائية من إعادة البناء: إن استُدعيت setState() بينما
  /// المُفسِّر لا يزال داخل تنفيذ buildRoot فعليًا (أي أنها استُدعيت مباشرة
  /// من جسم build مباشرةً، وليس من داخل lambda معالج حدث مثل onPressed
  /// سيُنفَّذ لاحقًا بعد انتهاء البناء) — هذا خطأ في الكود المصدري نفسه
  /// (Flutter الحقيقي يرفضه أيضًا بخطأ صريح "setState() called during
  /// build"). ملاحظة: بعد التحويل لِـ InterpretedStatefulHost، هذا الحارس
  /// يُغطّي فقط الجزء التزامني من buildRoot (بناء StatelessWidgets قبل أول
  /// StatefulWidget)؛ حالات "setState أثناء build" الأخرى (مثل استدعاء
  /// setState لعنصر آخر أثناء بناء عنصر مختلف) تُعالَج بأمان عبر try/catch
  /// حول استدعاء setState الحقيقي في [_requestInstanceRebuild] بدل تعطّل
  /// المعاينة بخطأ Flutter غير مترجَم.
  bool _isBuilding = false;

  // ------------------------- نظام الأخطاء الموحَّد -------------------------
  // يتتبّعان "الموضع الحالي" أثناء التنفيذ: يُحدَّثان مع كل جملة (_exec) وكل
  // استدعاء (CallExpr) يُقيَّم، حتى تحمل أي رسالة خطأ — من أي نوع (ودجت غير
  // مدعوم، متغيّر غير معروف، استدعاء تابع غير مدعوم...) — موضعًا دقيقًا
  // (اسم الملف + رقم السطر)، وليس فقط أخطاء تحليل build كما كان سابقًا.
  String? _currentFile;
  int? _currentLine;

  Interpreter({required this.classRegistry, required this.log, required this.onStateChanged});

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

  /// تنسيق الموضع الحالي بصيغة موحَّدة: "اسم_الملف.dart — السطر N"، أو
  /// أجزاء منها إن كان جزء من المعلومة غير متوفر (مثل main.dart قبل دخول
  /// أي صنف مستخدم بعد).
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

  // ------------------------- تسجيل/إعادة رسم المضيفين الحقيقيين -------------------------

  void _registerHost(String instanceKey, _InterpretedStatefulHostState host) {
    _hosts[instanceKey] = host;
  }

  void _unregisterHost(String instanceKey, _InterpretedStatefulHostState host) {
    if (identical(_hosts[instanceKey], host)) _hosts.remove(instanceKey);
  }

  /// يُنفَّذ من [_InterpretedStatefulHostState.build] — ينفّذ جسم build
  /// الخاص بصنف State **كقائمة جُمل كاملة** بنفس فيلد الحالة الدائم
  /// (`_stateStores[instanceKey]`)، تمامًا كما كان يحدث سابقًا داخل
  /// `_instantiateUserClass` مباشرة، لكن الآن يُستدعى من داخل build()
  /// حقيقي لعنصر Flutter حقيقي بدل تنفيذه فورًا عند الإنشاء.
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

  /// يوجّه setState() إلى النسخة المحدَّدة فقط عبر مضيفها الحقيقي المسجَّل،
  /// بدل إعادة بناء الجذر بالكامل — هذا هو الإصلاح الجوهري لمشكلة "setState
  /// لا يُحدِّث الشاشة الفرعية المفتوحة عبر Navigator.push" (راجع التوثيق
  /// الكامل أعلى [InterpretedStatefulHost]).
  void _requestInstanceRebuild(String? instanceKey) {
    if (instanceKey != null) {
      final host = _hosts[instanceKey];
      if (host != null) {
        try {
          host.requestLocalRebuild();
          return;
        } catch (e) {
          // على الأرجح استثناء Flutter حقيقي "setState() or markNeedsBuild()
          // called during build" (استُدعيت أثناء تنفيذ build() لعنصر آخر
          // فعليًا قيد التنفيذ الآن) — نحوّلها لرسالة عربية واضحة في الكونسول
          // بدل ترك الاستثناء يتسبّب في شاشة حمراء غير مُترجَمة.
          log(
            'تعذّر تحديث الشاشة مباشرة بعد setState (على الأرجح استُدعيت أثناء '
            'بناء ودجت آخر قيد التنفيذ فعليًا الآن): $e',
            isError: true,
          );
          return;
        }
      }
    }
    // احتياطي دفاعي: لم يُسجَّل أي مضيف لهذه النسخة (حالة نادرة — مثلًا
    // النسخة الجذرية قبل أول Host، أو setState من مكان غير متوقَّع) —
    // نلجأ لإعادة بناء الجذر بالكامل كخيار أخير بدل تجاهل التحديث بصمت.
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

    if (expr is IdentifierExpr) return _resolveIdentifier(expr.name, scope);

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
          // for الكلاسيكية داخل قائمة — نفس منطق _execFor للجُمل العادية،
          // لكن نجمع ناتج كل تكرار في result بدل تنفيذ جُمل.
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
        // لامدا async: تُنفَّذ عبر مسار تنفيذ يدعم await (راجع _invokeLambdaAsync
        // وقسم "دعم async/await المبسَّط" أدناه). النتيجة Future<dynamic>،
        // ما يتوافق تمامًا مع onPressed/onTap وغيرها (تُطلَق ولا تُنتظَر).
        return InterpretedCallable((args) => _invokeLambdaAsync(expr, args, scope));
      }
      return InterpretedCallable((args) {
        final callScope = RuntimeScope(fields: scope.fields, methods: scope.methods, parent: scope);
        for (var i = 0; i < expr.params.length && i < args.length; i++) {
          callScope.locals[expr.params[i]] = args[i];
        }
        // نمط itemBuilder الشائع: (BuildContext context, int index) => ...
        // — نُلحق الفهرس بمسار الهوية حتى تحصل كل نسخة StatefulWidget
        // مبنية داخل عنصر قائمة على حالة مستقلة بدل تشارك مخزن واحد.
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
      if (expr.line > 0) _currentLine = expr.line;
      return _evalCall(expr, scope);
    }

    throw PreviewRuntimeException('نوع تعبير غير مدعوم: ${expr.runtimeType}');
  }

  dynamic _resolveIdentifier(String name, RuntimeScope scope) {
    if (scope.has(name)) return scope.resolve(name);
    // Method Reference: استخدام اسم دالة مساعدة كقيمة بدون استدعائها —
    // مثل `onPressed: changeMessage` (بلا أقواس). سابقًا كان يُطابَق هذا
    // فقط عند وجود استدعاء فعلي (اسم متبوع بأقواس)؛ الآن نتحقق أيضًا من
    // خريطة methods عند تحليل معرِّف مجرّد، ونُغلِّفه بـ InterpretedCallable
    // مربوطًا بنفس النطاق الحالي حتى يعمل تمامًا كأنه lambda مكافئ —
    // ويحترم isAsync إن كانت الدالة المُشار إليها مُعلَّمة async.
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

  // أسماء مساحات الثوابت المعروفة — تُستخدَم لتمييز "Icons.xxx غير مسجَّلة"
  // عن "xxx متغيّر حقيقي غير معروف"، حتى تكون رسالة الخطأ دقيقة ومفيدة.
  static const Set<String> _knownStaticNamespaces = {
    'Colors', 'Icons', 'FontWeight', 'MainAxisAlignment', 'CrossAxisAlignment',
    'MainAxisSize', 'TextAlign', 'FontStyle', 'Alignment', 'BoxShape', 'Axis',
    'WrapAlignment', 'FlexFit', 'BoxFit', 'TextDecoration', 'TextOverflow',
    'BottomNavigationBarType', 'InputBorder',
  };

  dynamic _evalProperty(PropertyExpr expr, RuntimeScope scope) {
    // مسار static معروف مسبقًا: Colors.red / Icons.add / FontWeight.bold ...
    if (expr.target is IdentifierExpr) {
      final targetName = (expr.target as IdentifierExpr).name;
      if (!scope.has(targetName)) {
        final composed = '$targetName.${expr.name}';
        if (BuiltinWidgets.staticProperties.containsKey(composed)) {
          return BuiltinWidgets.staticProperties[composed];
        }
        // كنا هنا سابقًا نسقط مباشرة لتقييم "targetName" كمتغيّر عادي، فتظهر
        // رسالة مُضلِّلة مثل "متغيّر غير معروف: Icons" — بينما المشكلة
        // الحقيقية أن "add_circle_outline" تحديدًا غير مُسجَّلة، وليست
        // Icons نفسها. الآن نميّز الحالتين بوضوح.
        if (_knownStaticNamespaces.contains(targetName)) {
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
    // خاصية غير معروفة على كائن مُفسَّر: نُرجع null بدل تعطّل المعاينة بالكامل.
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
      // استدعاء تابع على قيمة حقيقية موجودة في النطاق بالفعل (مثل
      // nameController.clear()) — نطاق مدعوم محدود عمدًا (TextEditingController
      // فقط حاليًا)، وليس إرسال توابع عام على أي كائن Dart.
      return _evalInstanceMethodCall(callee, expr, scope);
    }

    throw PreviewRuntimeException(
      'استدعاء غير مدعوم في هذا الإصدار من المُفسِّر (نوع الاستدعاء: ${callee.runtimeType}).',
    );
  }

  /// استدعاءات توابع مدعومة على كائنات Dart حقيقية (وليست ودجتس) يُنشئها
  /// المُفسِّر عبر BuiltinWidgets.buildValue أو مسارات خاصة (مثل
  /// ScaffoldMessenger.of) — التغطية محدودة عمدًا لأشيع الاستخدامات، وليس
  /// إرسال توابع عام على أي كائن Dart.
  dynamic _evalInstanceMethodCall(PropertyExpr callee, CallExpr expr, RuntimeScope scope) {
    final target = _eval(callee.target, scope);

    if (target is TextEditingController) {
      switch (callee.name) {
        case 'clear':
          target.clear();
          return null;
        case 'dispose':
          // لا دورة حياة حقيقية (initState/dispose) لأصناف State في هذا
          // المُفسِّر بعد — نتجاهل الاستدعاء بأمان بدل رفض غير مفيد.
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

    throw PreviewRuntimeException('استدعاء تابع غير مدعوم بعد: .${callee.name}()');
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
        // **الإصلاح الجوهري**: نوجّه setState لهوية النسخة الحالية تحديدًا
        // (scope.instanceKey) بدل استدعاء onStateChanged() العام — راجع
        // توثيق InterpretedStatefulHost/_requestInstanceRebuild للتفاصيل
        // الكاملة حول سبب هذا التغيير.
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
        if (classRegistry.containsKey(name)) {
          return _instantiateUserClass(name, expr, scope);
        }
        // دالة مساعدة مُعرَّفة داخل نفس الصنف (مثل `_buildRow('a')`) — تُنفَّذ
        // بنفس آلية تنفيذ build (قائمة جُمل + التقاط return الأخير)، أو عبر
        // مسار async إن كانت مُعلَّمة async.
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
        return _errorWidget(
          'الصنف/الودجت "$name" غير معروف: ليس صنفًا معرَّفًا في مشروعكم، وليس '
          'مُسجَّلًا في قائمة الودجتس المدعومة (builtin_widgets.dart)، ولا يوجد '
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

    // ------------------------- دعم async/await المبسَّط: Future.* -------------------------
    // مدعوم حاليًا: Future.delayed(duration, [computation]) وFuture.value(x)
    // — كافٍ لتغطية النمط الشائع "تأخير محاكى ثم setState()". راجع القسم
    // الكامل لدعم async/await أسفل هذا الملف لحدود الدعم بدقة.
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

    final composedName = '$namespace.$member';
    final (pos, named) = _evalArgs(expr, scope);
    if (BuiltinWidgets.valueConstructors.contains(composedName)) {
      return BuiltinWidgets.buildValue(composedName, pos, named);
    }
    final widget = BuiltinWidgets.build(composedName, pos, named);
    if (widget != null) return widget;
    return _errorWidget(
      'العنصر "$composedName" غير مُسجَّل في قائمة الودجتس/القيم المدعومة '
      '(builtin_widgets.dart) — تحقّقوا من الاسم، أو أضيفوه يدويًا إن كان مطلوبًا فعليًا.',
    );
  }

  /// ينشئ نسخة من صنف مُعرَّف داخل المشروع (StatelessWidget، أو الزوج
  /// StatefulWidget+State) ويُنتج ودجت Flutter حقيقية تُمثّله.
  ///
  /// **هوية النسخة لصنف Stateful**: مفتاح مخزن الحالة = اسم صنف الحالة +
  /// [expr.id] (معرّف ثابت لعقدة الاستدعاء هذه تحديدًا في AST) + مسار
  /// الحلقات الحالي [scope.instancePath]. النتيجة: استدعاءان مختلفان في
  /// الكود المصدري لنفس الصنف (`MyCounter()` في مكانين) يحصلان تلقائيًا على
  /// حالتين منفصلتين (لأن id مختلف)، ونفس الاستدعاء داخل حلقة (`for (var x
  /// in items) MyCounter(x)`) يحصل كل عنصر منه على حالة منفصلة أيضًا (لأن
  /// instancePath مختلف لكل تكرار) — بينما يبقى المفتاح مستقرًا لنفس العنصر
  /// عبر setState المتتالية ضمن نفس الجلسة.
  ///
  /// **تحديث جوهري**: لصنف StatefulWidget، لم نعد نُنفِّذ build() هنا فورًا
  /// (كما كان سابقًا) — بل نُعيد [InterpretedStatefulHost]، ودجت Flutter
  /// حقيقية بـ State حقيقي، يستدعي build() الفعلي عند الحاجة فقط عبر
  /// Flutter نفسه. راجع توثيق ذلك الكلاس لشرح كامل للسبب (إصلاح مشكلة
  /// setState لا يُحدِّث الشاشات المفتوحة عبر Navigator.push).
  Widget _instantiateUserClass(String name, CallExpr expr, RuntimeScope scope) {
    final def = classRegistry[name]!;
    final (pos, named) = _evalArgs(expr, scope);
    final constructorArgs = <String, dynamic>{...named};
    // دعم بسيط للوسائط الموضعية: نربطها باسم أول حقول الصنف بالترتيب، إن وُجدت.
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

    // StatelessWidget (أو صنف بلا Base معروف): الحقول تُحقن مباشرة كحالة قراءة فقط.
    final buildScope = RuntimeScope(
      locals: {'context': scope.resolve('context')},
      fields: constructorArgs,
      methods: {for (final m in def.methods) m.name: m},
      instancePath: scope.instancePath,
    );
    return _runBuild(def, buildScope);
  }

  /// ينفّذ جسم build **كقائمة جُمل كاملة** (وليس تعبير return واحد فقط) —
  /// يسمح بمتغيرات محلية/حلقات/شروط قبل الجملة الأخيرة، ويلتقط أول
  /// [_ReturnSignal] كناتج نهائي، تمامًا كأي دالة مساعدة أخرى.
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

  /// ينفّذ دالة مساعدة مُعرَّفة داخل الصنف (غير build، غير async) — نفس آلية
  /// _runBuild لكن دون تحويل غياب return إلى ودجت خطأ (لأن الناتج قد يكون
  /// أي نوع، وليس بالضرورة Widget).
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
    if (stmt.line > 0) _currentLine = stmt.line;
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
        // نتابع إلى سطر increment أدناه (نفس سلوك continue في for الحقيقية)
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
  //
  // **حدّ صريح ومهم موثَّق عمدًا (وليس خللًا)**: هذا ليس دعمًا كاملًا
  // لِـ async/await في Dart. المدعوم فعليًا هو `await expr` **كطرف كامل
  // مباشر لجملة فقط**:
  //   - `await x;`                 (جملة تعبير)
  //   - `var y = await x;`         (تصريح متغيّر)
  //   - `y = await x;`             (تعيين، بما فيها += / -=)
  //   - `return await x;`          (إرجاع)
  //   - شرط if/while: `if (await x) {...}` / `while (await x) {...}`
  //
  // **غير مدعوم عمدًا** (يظهر كخطأ واضح بدل فشل صامت أو نتيجة خاطئة):
  //   - await متداخل داخل تعبير أكبر، مثل `1 + await x` أو `foo(await x)`
  //     — سيُقيَّم الجزء الداخلي عبر _eval العادية التي تفشل بخطأ AwaitExpr
  //     الصريح أعلاه.
  //   - await داخل حلقات for/for-in الكلاسيكية (تُنفَّذ هذه الحلقات
  //     تزامنيًا حتى داخل دالة async — راجع _execAsync أدناه).
  //   - try/catch حول await، وasync*/Stream بشكل عام.
  //
  // القيم القابلة لِـ await المدعومة: أي Future حقيقي من Dart (بما فيها
  // Future.delayed/Future.value المُضافتان أعلاه في _evalNamespacedCall).

  /// ينفّذ دالة مساعدة async (مُعرَّفة داخل صنف) — النظير async لِـ
  /// _invokeMethod.
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

  /// ينفّذ لامدا async (مثل `onPressed: () async { ... }`) — النظير async
  /// لجسم اللامدا العادية داخل _eval.
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

  /// نسخة "واعية بـ await" من [_exec] — تُغطّي فقط الجُمل التي يَشيع
  /// استخدام await داخلها مباشرة (تعبير، return، تصريح متغيّر، تعيين، if،
  /// while). لأي جملة أخرى (for/for-in الكلاسيكية، ++/--، break/continue)
  /// نُفوِّض إلى [_exec] التزامنية العادية — وهذا يعني أن await **غير
  /// مسموح داخلها** (حد صريح موثَّق أعلاه، وليس خللًا).
  Future<void> _execAsync(Stmt stmt, RuntimeScope scope) async {
    if (stmt.line > 0) _currentLine = stmt.line;

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

    // بقية أنواع الجُمل: تُنفَّذ تزامنيًا كالمعتاد — await غير مدعوم داخلها
    // في هذا الإصدار المبسَّط (راجع التوثيق أعلى هذا القسم).
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

  /// يُقيِّم تعبيرًا مع دعم await **على المستوى الأعلى فقط** لهذا التعبير
  /// تحديدًا (وليس أي await متداخل بداخله بعمق أكبر — حد موثَّق أعلاه).
  Future<dynamic> _evalMaybeAwait(Expr expr, RuntimeScope scope) async {
    if (expr is AwaitExpr) {
      final value = _eval(expr.inner, scope);
      if (value is Future) return await value;
      return value; // await على قيمة غير Future صالح في Dart أيضًا (يُعيدها كما هي)
    }
    return _eval(expr, scope);
  }
}
