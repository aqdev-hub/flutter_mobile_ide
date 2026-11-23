import 'bridge_runtime.dart';
import 'generated/generated_ctors.dart';
import 'generated/generated_methods.dart';
import 'generated/generated_props.dart';
import 'generated/generated_statics.dart';
import 'native_members.dart' show kNoNative;

/// واجهة وحيدة للجسر المولَّد من Flutter SDK (انظر tool/gen_widget_bridge.dart).
/// تُستشار **بعد** الجداول اليدوية دائمًا، فلا تغيّر سلوك ما كان يعمل أصلًا.
class GeneratedBridge {
  GeneratedBridge._();

  static bool hasCtor(String name) => kGeneratedCtors.containsKey(name);

  /// `Name(...)` أو `Name.named(...)`. [kNoNative] إن لم يكن الاسم مولَّدًا.
  static Object? construct(String name, List<dynamic> pos, Map<String, dynamic> named) {
    final f = kGeneratedCtors[name];
    if (f == null) return kNoNative;
    try {
      return f(pos, named);
    } on BridgeError {
      rethrow;
    } on TypeError catch (e) {
      throw BridgeError('نوع وسيط غير مطابق عند إنشاء $name: $e');
    }
  }

  /// ثوابت static (Colors.red، Icons.add...) وقيم أي enum.
  static Object? staticMember(String ns, String name) {
    final key = '$ns.$name';
    if (kGeneratedStatics.containsKey(key)) return kGeneratedStatics[key];
    final values = kGeneratedEnums[ns];
    if (values != null) {
      for (final v in values) {
        if (v.name == name) return v;
      }
    }
    return kNoNative;
  }

  /// خاصية (getter/حقل) على كائن Flutter أصلي.
  static Object? property(Object target, String name) => generatedProperty(target, name);

  /// استدعاء دالة على كائن Flutter أصلي (مثل controller.animateToPage(...)).
  static Object? method(Object target, String name, List<dynamic> pos, Map<String, dynamic> named) {
    try {
      return generatedMethod(target, name, pos, named);
    } on BridgeError {
      rethrow;
    } on TypeError catch (e) {
      throw BridgeError('نوع وسيط غير مطابق عند استدعاء $name على ${target.runtimeType}: $e');
    }
  }
}
