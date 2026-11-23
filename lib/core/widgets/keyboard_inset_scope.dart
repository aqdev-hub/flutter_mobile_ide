import 'package:flutter/widgets.dart';

/// يوفّر ارتفاع لوحة المفاتيح الحقيقي (viewInsets.bottom) لمن يحتاجه أسفل
/// الشجرة، دون أن يُعاد بناء الشاشة كلها في كل إطار من حركة الكيبورد.
///
/// يُوضع فوق Scaffold مباشرة. عند تغيّر MediaQuery يُعاد بناء هذا الودجت فقط،
/// ولأن [child] نفس النسخة تمامًا لا يُعاد بناؤه؛ بل تُخطَر فقط الودجتس التي
/// استدعت [KeyboardInsetScope.of] (مثل لوحة المعاينة).
class KeyboardInsetScope extends StatelessWidget {
  final Widget child;
  const KeyboardInsetScope({super.key, required this.child});

  /// ارتفاع الكيبورد الحالي، أو 0 إن لم يوجد نطاق فوق [context].
  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_KeyboardInsetData>()?.bottom ?? 0;

  @override
  Widget build(BuildContext context) {
    return _KeyboardInsetData(bottom: MediaQuery.viewInsetsOf(context).bottom, child: child);
  }
}

class _KeyboardInsetData extends InheritedWidget {
  final double bottom;
  const _KeyboardInsetData({required this.bottom, required super.child});

  @override
  bool updateShouldNotify(_KeyboardInsetData oldWidget) => bottom != oldWidget.bottom;
}
