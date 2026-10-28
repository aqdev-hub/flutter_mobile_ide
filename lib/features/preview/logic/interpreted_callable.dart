import 'package:flutter/material.dart';

/// يمثّل دالة lambda مُفسَّرة من كود المستخدم (مثل `() => setState(...)` أو
/// `(context) => SecondScreen()`). المُفسِّر ينتج هذا الكائن عند تقييم أي
/// [LambdaExpr]، ثم نحوّله هنا إلى الشكل الحقيقي الذي يتوقعه كل Widget
/// (VoidCallback، builder(context)، onChanged(String)...) — بهذا تصبح
/// onPressed وonChanged وbuilder استدعاءات Dart حقيقية يُنفّذها محرك
/// Flutter نفسه، وليست محاكاة.
///
/// **تحديث (أخطاء المعالجات)**: أي استثناء يقع داخل معالج حدث يستدعيه Flutter
/// (onPressed/onChanged/...) كان يخرج لمحرك Flutter فقط فلا يظهر للمستخدم في
/// لوحة Output ("فشل صامت"). الآن تلتقطه المحوّلات [asVoidCallback] وما شابهها
/// وتمرّره إلى [onError]؛ ومحوّلات الـ builder تُعيد [onBuildError] (ودجت خطأ
/// مقروء) بدل انهيار الشجرة. الاستدعاء الداخلي المباشر [call] يُمرّر الاستثناء
/// كما هو (ليصل لأقرب معالج).
class InterpretedCallable {
  final dynamic Function(List<dynamic> args) _invoke;
  final void Function(Object error, StackTrace stack)? onError;
  final Widget Function(Object error, StackTrace stack)? onBuildError;

  InterpretedCallable(this._invoke, {this.onError, this.onBuildError});

  dynamic call(List<dynamic> args) => _invoke(args);

  void _guard(List<dynamic> args) {
    try {
      _invoke(args);
    } catch (e, st) {
      final handler = onError;
      if (handler == null) rethrow;
      handler(e, st);
    }
  }

  Widget _guardBuild(List<dynamic> args) {
    try {
      return (_invoke(args) as Widget?) ?? const SizedBox.shrink();
    } catch (e, st) {
      final handler = onBuildError;
      if (handler == null) rethrow;
      return handler(e, st);
    }
  }

  VoidCallback get asVoidCallback => () => _guard(const []);
  void Function(String) get asStringCallback => (value) => _guard([value]);
  void Function(int) get asIntCallback => (value) => _guard([value]);
  void Function(bool?) get asBoolCallback => (value) => _guard([value]);
  Widget Function(BuildContext) get asContextBuilder => (ctx) => _guardBuild([ctx]);
  Widget Function(BuildContext, int) get asIndexedBuilder => (ctx, i) => _guardBuild([ctx, i]);
}

/// يمثّل `MaterialPageRoute(builder: ...)` قبل أن يُستخدَم فعليًا في
/// Navigator.push — نُبقيه ككائن وصف بسيط بدل بنائه فورًا لأن الودجت
/// الهدف يجب أن تُبنى وقت التنقل الفعلي، لا وقت تعريف المسار.
class InterpretedRouteSpec {
  final InterpretedCallable builder;
  InterpretedRouteSpec(this.builder);
}
