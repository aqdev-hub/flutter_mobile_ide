import 'package:shared_preferences/shared_preferences.dart';

import 'native_members.dart' show kNoNative;

/// غلاف `SharedPreferences` للكود المُفسَّر.
///
/// **عزل**: كل مفاتيح المشروع المُعاين تُخزَّن بمقدّمة خاصة بمساره
/// (`preview.<hash>.`) داخل نفس التخزين الفعلي للتطبيق، فلا تتصادم مع إعدادات
/// الـIDE نفسه (`settings.*`, `project.*`) ولا مع مشروع معاين آخر، و`clear()`
/// تمسح مفاتيح هذا المشروع فقط.
class InterpretedPrefs {
  final SharedPreferences _p;
  final String _prefix;
  InterpretedPrefs._(this._p, this._prefix);

  static Future<InterpretedPrefs> open(String projectRoot) async {
    final p = await SharedPreferences.getInstance();
    return InterpretedPrefs._(p, 'preview.${_fnv(projectRoot)}.');
  }

  static String _fnv(String s) {
    var h = 0x811c9dc5;
    for (final u in s.codeUnits) {
      h ^= u;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16);
  }

  String _k(dynamic key) => '$_prefix$key';

  Iterable<String> get _ownKeys => _p.getKeys().where((k) => k.startsWith(_prefix));

  /// يستدعي دالة على الكائن؛ [kNoNative] إن لم تكن مدعومة.
  Object? invoke(String name, List<dynamic> pos) {
    switch (name) {
      case 'getString':
        return _p.getString(_k(pos[0]));
      case 'getInt':
        return _p.getInt(_k(pos[0]));
      case 'getDouble':
        return _p.getDouble(_k(pos[0]));
      case 'getBool':
        return _p.getBool(_k(pos[0]));
      case 'getStringList':
        return _p.getStringList(_k(pos[0]));
      case 'get':
        return _p.get(_k(pos[0]));
      case 'containsKey':
        return _p.containsKey(_k(pos[0]));
      case 'getKeys':
        return _ownKeys.map((k) => k.substring(_prefix.length)).toSet();
      case 'setString':
        return _p.setString(_k(pos[0]), pos[1] as String);
      case 'setInt':
        return _p.setInt(_k(pos[0]), (pos[1] as num).toInt());
      case 'setDouble':
        return _p.setDouble(_k(pos[0]), (pos[1] as num).toDouble());
      case 'setBool':
        return _p.setBool(_k(pos[0]), pos[1] as bool);
      case 'setStringList':
        return _p.setStringList(_k(pos[0]), (pos[1] as List).cast<String>());
      case 'remove':
        return _p.remove(_k(pos[0]));
      case 'clear':
        return Future.wait(_ownKeys.toList().map(_p.remove)).then((_) => true);
      case 'reload':
        return _p.reload();
    }
    return kNoNative;
  }

  @override
  String toString() => 'SharedPreferences(معزول لهذا المشروع)';
}
