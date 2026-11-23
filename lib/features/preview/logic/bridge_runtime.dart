import 'package:flutter/widgets.dart';

import 'interpreted_callable.dart';

/// مُنشئ مولَّد: يستقبل الوسائط الموضعية والمسمّاة المُقيَّمة من المُفسِّر.
typedef BridgeCtor = Object? Function(List<dynamic> pos, Map<String, dynamic> named);

/// خطأ عربي مقروء من الجسر المولَّد (وسيط مفقود / نوع غير مطابق / غير مدعوم).
class BridgeError implements Exception {
  final String message;
  BridgeError(this.message);
  @override
  String toString() => message;
}

dynamic bridgeArg(List<dynamic> pos, Map<String, dynamic> named, String name, [int? index]) {
  if (named.containsKey(name)) return named[name];
  if (index != null && index < pos.length) return pos[index];
  return null;
}

T bridgeReq<T>(String cls, String param, T? v) {
  if (v == null) throw BridgeError("الوسيط المطلوب '$param' مفقود (أو null) عند إنشاء $cls.");
  return v;
}

/// وسائط يعرفها Flutter لكن الجسر لا يستطيع تحويل نوعها (مثل callbacks بمعاملات مسمّاة).
void bridgeCheck(String cls, Map<String, dynamic> named, List<String> unsupported) {
  for (final n in unsupported) {
    if (named.containsKey(n)) {
      throw BridgeError("الوسيط '$n' في $cls غير مدعوم عبر الجسر المولَّد (نوعه لا يمكن تحويله من الكود المُفسَّر).");
    }
  }
}

InterpretedCallable? _callable(dynamic v) {
  if (v == null) return null;
  if (v is InterpretedCallable) return v;
  throw BridgeError('متوقَّع دالة (callback) لكن وُجد ${v.runtimeType}.');
}

// ---- محوّلات الدوال: void ----
void Function()? fnV0(dynamic v) {
  final c = _callable(v);
  return c == null ? null : () => c.callGuarded(const []);
}

void Function(A)? fnV1<A>(dynamic v) {
  final c = _callable(v);
  return c == null ? null : (A a) => c.callGuarded([a]);
}

void Function(A, B)? fnV2<A, B>(dynamic v) {
  final c = _callable(v);
  return c == null ? null : (A a, B b) => c.callGuarded([a, b]);
}

void Function(A, B, C)? fnV3<A, B, C>(dynamic v) {
  final c = _callable(v);
  return c == null ? null : (A a, B b, C d) => c.callGuarded([a, b, d]);
}

// ---- محوّلات الدوال: تُرجع Widget (أخطاء البناء تظهر كودجت خطأ مقروء) ----
Widget Function()? fnW0(dynamic v) {
  final c = _callable(v);
  return c == null ? null : () => c.callGuardedBuild(const []);
}

Widget Function(A)? fnW1<A>(dynamic v) {
  final c = _callable(v);
  return c == null ? null : (A a) => c.callGuardedBuild([a]);
}

Widget Function(A, B)? fnW2<A, B>(dynamic v) {
  final c = _callable(v);
  return c == null ? null : (A a, B b) => c.callGuardedBuild([a, b]);
}

Widget Function(A, B, C)? fnW3<A, B, C>(dynamic v) {
  final c = _callable(v);
  return c == null ? null : (A a, B b, C d) => c.callGuardedBuild([a, b, d]);
}

// ---- محوّلات الدوال: تُرجع قيمة R ----
R Function()? fnR0<R>(dynamic v) {
  final c = _callable(v);
  return c == null ? null : () => c.call(const []) as R;
}

R Function(A)? fnR1<R, A>(dynamic v) {
  final c = _callable(v);
  return c == null ? null : (A a) => c.call([a]) as R;
}

R Function(A, B)? fnR2<R, A, B>(dynamic v) {
  final c = _callable(v);
  return c == null ? null : (A a, B b) => c.call([a, b]) as R;
}

R Function(A, B, C)? fnR3<R, A, B, C>(dynamic v) {
  final c = _callable(v);
  return c == null ? null : (A a, B b, C d) => c.call([a, b, d]) as R;
}
