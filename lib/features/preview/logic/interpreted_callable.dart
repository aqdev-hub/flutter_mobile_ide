import 'package:flutter/material.dart';

/// يمثّل دالة lambda مُفسَّرة من كود المستخدم (مثل `() => setState(...)` أو
/// `(context) => SecondScreen()`). المُفسِّر ينتج هذا الكائن عند تقييم أي
/// [LambdaExpr]، ثم نحوّله هنا إلى الشكل الحقيقي الذي يتوقعه كل Widget
/// (VoidCallback، builder(context)، onChanged(String)...) — بهذا تصبح
/// onPressed وonChanged وbuilder استدعاءات Dart حقيقية يُنفّذها محرك
/// Flutter نفسه، وليست محاكاة.
class InterpretedCallable {
  final dynamic Function(List<dynamic> args) _invoke;
  InterpretedCallable(this._invoke);

  dynamic call(List<dynamic> args) => _invoke(args);

  VoidCallback get asVoidCallback => () => _invoke(const []);
  void Function(String) get asStringCallback => (value) => _invoke([value]);
  void Function(int) get asIntCallback => (value) => _invoke([value]);
  void Function(bool?) get asBoolCallback => (value) => _invoke([value]);
  Widget Function(BuildContext) get asContextBuilder =>
      (ctx) => (_invoke([ctx]) as Widget?) ?? const SizedBox.shrink();
  Widget Function(BuildContext, int) get asIndexedBuilder =>
      (ctx, i) => (_invoke([ctx, i]) as Widget?) ?? const SizedBox.shrink();
}

/// يمثّل `MaterialPageRoute(builder: ...)` قبل أن يُستخدَم فعليًا في
/// Navigator.push — نُبقيه ككائن وصف بسيط بدل بنائه فورًا لأن الودجت
/// الهدف يجب أن تُبنى وقت التنقل الفعلي، لا وقت تعريف المسار.
class InterpretedRouteSpec {
  final InterpretedCallable builder;
  InterpretedRouteSpec(this.builder);
}
