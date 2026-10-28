import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'interpreted_callable.dart';

/// قيمة "لا أعرف هذا العضو" — يُقارَن بها بـ identical. نستخدمها بدل null لأن
/// null قيمة صالحة لعضو موجود (مثل TextStyle.color غير المضبوط)، ولأن الإرجاع
/// الصامت لـ null كان سبب فشل صامت موثَّق سابقًا (.length وغيرها).
class _NoNative {
  const _NoNative();
}

const Object kNoNative = _NoNative();

/// خطأ عضو أصلي (نوع Dart/Flutter حقيقي) بمعنى واضح للمستخدم.
class NativeMemberError implements Exception {
  final String message;
  NativeMemberError(this.message);
  @override
  String toString() => message;
}

dynamic _call(Object? f, List<dynamic> args) {
  if (f is InterpretedCallable) return f.call(args);
  throw NativeMemberError('متوقَّع دالة (callback) كوسيط لكن وُجد ${f.runtimeType}.');
}

double? _d(Object? v) => (v as num?)?.toDouble();

/// يقرأ خاصية [name] من قيمة Dart/Flutter أصلية. يُرجع [kNoNative] إن كان
/// النوع/العضو غير مدعوم (فيُبلِّغ المُفسِّر خطأً عربيًا بدل null صامت).
Object? nativeProperty(Object? t, String name) {
  if (t is String) {
    switch (name) {
      case 'length':
        return t.length;
      case 'isEmpty':
        return t.isEmpty;
      case 'isNotEmpty':
        return t.isNotEmpty;
    }
  } else if (t is List) {
    switch (name) {
      case 'length':
        return t.length;
      case 'isEmpty':
        return t.isEmpty;
      case 'isNotEmpty':
        return t.isNotEmpty;
      case 'first':
        if (t.isEmpty) throw NativeMemberError('القائمة فارغة: لا يوجد first.');
        return t.first;
      case 'last':
        if (t.isEmpty) throw NativeMemberError('القائمة فارغة: لا يوجد last.');
        return t.last;
      case 'single':
        return t.single;
      case 'reversed':
        return t.reversed.toList();
    }
  } else if (t is Map) {
    switch (name) {
      case 'length':
        return t.length;
      case 'isEmpty':
        return t.isEmpty;
      case 'isNotEmpty':
        return t.isNotEmpty;
      case 'keys':
        return t.keys.toList();
      case 'values':
        return t.values.toList();
    }
  } else if (t is num) {
    switch (name) {
      case 'isNegative':
        return t.isNegative;
      case 'isNaN':
        return t.isNaN;
      case 'isFinite':
        return t.isFinite;
    }
  } else if (t is ColorSwatch<int>) {
    if (name.startsWith('shade')) {
      final n = int.tryParse(name.substring(5));
      if (n != null) {
        final c = t[n];
        if (c == null) throw NativeMemberError('درجة اللون $name غير موجودة في هذه العيّنة.');
        return c;
      }
    }
  } else if (t is ThemeData) {
    switch (name) {
      case 'textTheme':
        return t.textTheme;
      case 'colorScheme':
        return t.colorScheme;
      case 'primaryColor':
        return t.primaryColor;
      case 'scaffoldBackgroundColor':
        return t.scaffoldBackgroundColor;
      case 'brightness':
        return t.brightness;
    }
  } else if (t is TextTheme) {
    switch (name) {
      case 'displayLarge':
        return t.displayLarge;
      case 'displayMedium':
        return t.displayMedium;
      case 'displaySmall':
        return t.displaySmall;
      case 'headlineLarge':
        return t.headlineLarge;
      case 'headlineMedium':
        return t.headlineMedium;
      case 'headlineSmall':
        return t.headlineSmall;
      case 'titleLarge':
        return t.titleLarge;
      case 'titleMedium':
        return t.titleMedium;
      case 'titleSmall':
        return t.titleSmall;
      case 'bodyLarge':
        return t.bodyLarge;
      case 'bodyMedium':
        return t.bodyMedium;
      case 'bodySmall':
        return t.bodySmall;
      case 'labelLarge':
        return t.labelLarge;
      case 'labelMedium':
        return t.labelMedium;
      case 'labelSmall':
        return t.labelSmall;
    }
  } else if (t is ColorScheme) {
    switch (name) {
      case 'primary':
        return t.primary;
      case 'onPrimary':
        return t.onPrimary;
      case 'secondary':
        return t.secondary;
      case 'onSecondary':
        return t.onSecondary;
      case 'tertiary':
        return t.tertiary;
      case 'surface':
        return t.surface;
      case 'onSurface':
        return t.onSurface;
      case 'error':
        return t.error;
      case 'onError':
        return t.onError;
      case 'primaryContainer':
        return t.primaryContainer;
      case 'onPrimaryContainer':
        return t.onPrimaryContainer;
      case 'secondaryContainer':
        return t.secondaryContainer;
      case 'outline':
        return t.outline;
      case 'brightness':
        return t.brightness;
    }
  } else if (t is TextStyle) {
    switch (name) {
      case 'fontSize':
        return t.fontSize;
      case 'fontWeight':
        return t.fontWeight;
      case 'color':
        return t.color;
      case 'fontFamily':
        return t.fontFamily;
      case 'height':
        return t.height;
    }
  } else if (t is MediaQueryData) {
    switch (name) {
      case 'size':
        return t.size;
      case 'padding':
        return t.padding;
      case 'viewInsets':
        return t.viewInsets;
      case 'viewPadding':
        return t.viewPadding;
      case 'orientation':
        return t.orientation;
      case 'devicePixelRatio':
        return t.devicePixelRatio;
    }
  } else if (t is Size) {
    switch (name) {
      case 'width':
        return t.width;
      case 'height':
        return t.height;
    }
  } else if (t is EdgeInsets) {
    switch (name) {
      case 'left':
        return t.left;
      case 'right':
        return t.right;
      case 'top':
        return t.top;
      case 'bottom':
        return t.bottom;
    }
  } else if (t is TextEditingController) {
    if (name == 'text') return t.text;
  } else if (t is GlobalKey) {
    if (name == 'currentState') return t.currentState;
    if (name == 'currentContext') return t.currentContext;
  } else if (t is Duration) {
    switch (name) {
      case 'inMilliseconds':
        return t.inMilliseconds;
      case 'inSeconds':
        return t.inSeconds;
      case 'inMinutes':
        return t.inMinutes;
    }
  } else if (t is DateTime) {
    switch (name) {
      case 'year':
        return t.year;
      case 'month':
        return t.month;
      case 'day':
        return t.day;
      case 'hour':
        return t.hour;
      case 'minute':
        return t.minute;
      case 'second':
        return t.second;
      case 'millisecondsSinceEpoch':
        return t.millisecondsSinceEpoch;
    }
  }
  return kNoNative;
}

/// يكتب خاصية أصلية؛ true إن عُولج.
bool nativeSetProperty(Object? t, String name, Object? value) {
  if (t is TextEditingController && name == 'text') {
    t.text = value?.toString() ?? '';
    return true;
  }
  return false;
}

/// يستدعي دالة [name] على قيمة أصلية. يُرجع [kNoNative] إن لم تكن مدعومة.
Object? nativeMethod(Object? t, String name, List<dynamic> pos, Map<String, dynamic> named) {
  if (t is String) {
    switch (name) {
      case 'toUpperCase':
        return t.toUpperCase();
      case 'toLowerCase':
        return t.toLowerCase();
      case 'trim':
        return t.trim();
      case 'trimLeft':
        return t.trimLeft();
      case 'trimRight':
        return t.trimRight();
      case 'contains':
        return t.contains(pos[0] as Pattern);
      case 'startsWith':
        return t.startsWith(pos[0] as Pattern);
      case 'endsWith':
        return t.endsWith(pos[0] as String);
      case 'substring':
        return pos.length > 1 ? t.substring(pos[0] as int, pos[1] as int) : t.substring(pos[0] as int);
      case 'split':
        return t.split(pos[0] as Pattern);
      case 'replaceAll':
        return t.replaceAll(pos[0] as Pattern, pos[1] as String);
      case 'replaceFirst':
        return t.replaceFirst(pos[0] as Pattern, pos[1] as String);
      case 'indexOf':
        return t.indexOf(pos[0] as Pattern);
      case 'padLeft':
        return t.padLeft(pos[0] as int, pos.length > 1 ? pos[1] as String : ' ');
      case 'padRight':
        return t.padRight(pos[0] as int, pos.length > 1 ? pos[1] as String : ' ');
      case 'compareTo':
        return t.compareTo(pos[0] as String);
      case 'toString':
        return t;
    }
  } else if (t is List) {
    switch (name) {
      case 'add':
        t.add(pos[0]);
        return null;
      case 'addAll':
        t.addAll(pos[0] as Iterable);
        return null;
      case 'remove':
        return t.remove(pos[0]);
      case 'removeAt':
        return t.removeAt(pos[0] as int);
      case 'removeLast':
        return t.removeLast();
      case 'removeWhere':
        t.removeWhere((e) => _call(pos[0], [e]) as bool);
        return null;
      case 'insert':
        t.insert(pos[0] as int, pos[1]);
        return null;
      case 'contains':
        return t.contains(pos[0]);
      case 'indexOf':
        return t.indexOf(pos[0]);
      case 'clear':
        t.clear();
        return null;
      case 'join':
        return t.join(pos.isEmpty ? '' : pos[0] as String);
      case 'toList':
        return t.toList();
      case 'sublist':
        return pos.length > 1 ? t.sublist(pos[0] as int, pos[1] as int) : t.sublist(pos[0] as int);
      case 'map':
        return t.map((e) => _call(pos[0], [e])).toList();
      case 'where':
        return t.where((e) => _call(pos[0], [e]) as bool).toList();
      case 'any':
        return t.any((e) => _call(pos[0], [e]) as bool);
      case 'every':
        return t.every((e) => _call(pos[0], [e]) as bool);
      case 'forEach':
        for (final e in List.of(t)) {
          _call(pos[0], [e]);
        }
        return null;
      case 'fold':
        var acc = pos[0];
        for (final e in t) {
          acc = _call(pos[1], [acc, e]);
        }
        return acc;
      case 'firstWhere':
        for (final e in t) {
          if (_call(pos[0], [e]) as bool) return e;
        }
        if (named['orElse'] != null) return _call(named['orElse'], const []);
        throw NativeMemberError('firstWhere: لا يوجد عنصر مطابق.');
      case 'take':
        return t.take(pos[0] as int).toList();
      case 'skip':
        return t.skip(pos[0] as int).toList();
      case 'sort':
        t.sort(pos.isEmpty ? null : (a, b) => (_call(pos[0], [a, b]) as num).toInt());
        return null;
      case 'toString':
        return t.toString();
    }
  } else if (t is Map) {
    switch (name) {
      case 'containsKey':
        return t.containsKey(pos[0]);
      case 'containsValue':
        return t.containsValue(pos[0]);
      case 'remove':
        return t.remove(pos[0]);
      case 'putIfAbsent':
        return t.putIfAbsent(pos[0], () => _call(pos[1], const []));
      case 'addAll':
        t.addAll(pos[0] as Map);
        return null;
      case 'clear':
        t.clear();
        return null;
      case 'forEach':
        for (final e in Map.of(t).entries) {
          _call(pos[0], [e.key, e.value]);
        }
        return null;
      case 'toString':
        return t.toString();
    }
  } else if (t is num) {
    switch (name) {
      case 'toString':
        return t.toString();
      case 'toInt':
        return t.toInt();
      case 'toDouble':
        return t.toDouble();
      case 'toStringAsFixed':
        return t.toStringAsFixed(pos[0] as int);
      case 'abs':
        return t.abs();
      case 'round':
        return t.round();
      case 'floor':
        return t.floor();
      case 'ceil':
        return t.ceil();
      case 'truncate':
        return t.truncate();
      case 'clamp':
        return t.clamp(pos[0] as num, pos[1] as num);
      case 'compareTo':
        return t.compareTo(pos[0] as num);
    }
  } else if (t is bool) {
    if (name == 'toString') return t.toString();
  } else if (t is Color) {
    switch (name) {
      case 'withOpacity':
      case 'withValues':
        final alpha = name == 'withOpacity' ? _d(pos[0]) : _d(named['alpha']);
        return t.withValues(alpha: alpha);
      case 'withAlpha':
        return t.withAlpha(pos[0] as int);
    }
  } else if (t is TextStyle) {
    if (name == 'copyWith') {
      return t.copyWith(
        fontSize: _d(named['fontSize']),
        fontWeight: named['fontWeight'] as FontWeight?,
        color: named['color'] as Color?,
        fontStyle: named['fontStyle'] as FontStyle?,
        fontFamily: named['fontFamily'] as String?,
        height: _d(named['height']),
        letterSpacing: _d(named['letterSpacing']),
      );
    }
  } else if (t is TextEditingController) {
    switch (name) {
      case 'clear':
        t.clear();
        return null;
      case 'dispose':
        return null; // لا نتلف المتحكم فعليًا (قد يُعاد استخدامه بين إعادات البناء)
    }
  } else if (t is FormState) {
    switch (name) {
      case 'validate':
        return t.validate();
      case 'save':
        t.save();
        return null;
      case 'reset':
        t.reset();
        return null;
    }
  }
  if (name == 'toString') return t.toString();
  return kNoNative;
}

/// دوال static على أنواع Dart الأساسية (int.parse ...). [kNoNative] إن لم تُعرف.
Object? nativeStatic(String namespace, String member, List<dynamic> pos, Map<String, dynamic> named) {
  switch ('$namespace.$member') {
    case 'int.parse':
      final v = int.tryParse((pos[0] as String).trim());
      if (v == null) throw NativeMemberError('int.parse: "${pos[0]}" ليس عددًا صحيحًا.');
      return v;
    case 'int.tryParse':
      return int.tryParse(pos[0] as String);
    case 'double.parse':
      final v = double.tryParse((pos[0] as String).trim());
      if (v == null) throw NativeMemberError('double.parse: "${pos[0]}" ليس عددًا عشريًا.');
      return v;
    case 'double.tryParse':
      return double.tryParse(pos[0] as String);
    case 'num.tryParse':
      return num.tryParse(pos[0] as String);
    case 'List.generate':
      return [for (var i = 0; i < (pos[0] as int); i++) _call(pos[1], [i])];
    case 'List.filled':
      return List<dynamic>.filled(pos[0] as int, pos[1], growable: true);
    case 'DateTime.now':
      return DateTime.now();
  }
  return kNoNative;
}

/// دوال عامة من dart:math.
Object? nativeGlobal(String name, List<dynamic> pos) {
  switch (name) {
    case 'max':
      return math.max(pos[0] as num, pos[1] as num);
    case 'min':
      return math.min(pos[0] as num, pos[1] as num);
    case 'sqrt':
      return math.sqrt(pos[0] as num);
    case 'pow':
      return math.pow(pos[0] as num, pos[1] as num);
  }
  return kNoNative;
}
