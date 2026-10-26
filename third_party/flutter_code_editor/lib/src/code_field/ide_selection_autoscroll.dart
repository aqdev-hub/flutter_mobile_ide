import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'code_controller.dart';

/// IDE PATCH (ملف جديد): تمرير تلقائي عند سحب التحديد إلى حافة المحرر.
///
/// مع الماوس يستمر التمرير طالما بقي المؤشر عند الحافة، وفي لمس الهاتف لا
/// يفعل Flutter ذلك للمقابض (يتحرك الأب فقط مع حركة الإصبع). هذا الصنف يملأ
/// الفجوة دون لمس منطق المكتبة الداخلي:
///  - يراقب كل مؤشرات اللمس عبر `pointerRouter` العام (لا يشارك في ساحة
///    الإيماءات، فلا يتعارض مع المقابض ولا مع التمرير العادي).
///  - يُفعَّل فقط حين: الإصبع نازل + تحرّك أكثر من هامش صغير + تغيّر التحديد
///    أثناء اللمس (أي أنه سحب تحديد فعلًا، لا تمرير عادي ولا نقرة).
///  - كل 16ms قرب الحافة: يمرّر المحرر (رأسيًا/أفقيًا) ثم يمدّ طرف التحديد
///    المتحرك إلى النص الواقع تحت الإصبع، لأن Flutter لا يُحدّث التحديد من
///    تلقاء نفسه ما دام الإصبع ثابتًا.
///  - أي استثناء غير متوقع يُعطّل الميزة نهائيًا لهذه الجلسة بدل أن يُسقط
///    التطبيق (انظر [_onTick]).

/// سرعة التمرير (بكسل في الثانية) بحسب قرب [pointer] من حافتي المدى
/// [min]..[max]: 0 داخل المنطقة الآمنة، وتتزايد **تربيعيًا** (تحكّم أدق قرب
/// بداية المنطقة) من [minSpeed] إلى [maxSpeed] عند الحافة أو بعدها، دون قفزة
/// عند حدّ المنطقة. السالب = نحو [min]. تُضرب بزمن الخطوة الفعلي عند التطبيق.
double edgeScrollDelta({
  required double pointer,
  required double min,
  required double max,
  double zone = 48,
  double minSpeed = 0,
  double maxSpeed = 320,
}) {
  final span = max - min;
  if (span <= 0) return 0;
  // لا تتجاوز المنطقة ثلث المدى كي لا تتداخل الحافتان في محرر صغير.
  final z = math.min(zone, span / 3);
  if (z <= 0) return 0;
  if (pointer < min + z) {
    final t = ((min + z - pointer) / z).clamp(0.0, 1.0).toDouble();
    return -(minSpeed + (maxSpeed - minSpeed) * t * t);
  }
  if (pointer > max - z) {
    final t = ((pointer - (max - z)) / z).clamp(0.0, 1.0).toDouble();
    return minSpeed + (maxSpeed - minSpeed) * t * t;
  }
  return 0;
}

class IdeSelectionAutoscroller {
  IdeSelectionAutoscroller({
    required CodeController controller,
    required BuildContext? Function() viewportContext,
    required ScrollController? Function() vertical,
    required ScrollController? Function() horizontal,
  })  : _controller = controller,
        _viewportContext = viewportContext,
        _vertical = vertical,
        _horizontal = horizontal;

  CodeController _controller;
  final BuildContext? Function() _viewportContext;
  final ScrollController? Function() _vertical;
  final ScrollController? Function() _horizontal;

  static const Duration _tickInterval = Duration(milliseconds: 16);
  static const double _dragSlop = 10;
  static const double _maxGrabDy = 60;

  bool _attached = false;
  bool _broken = false;
  Timer? _timer;

  int? _pointer;
  Offset _downPosition = Offset.zero;
  Offset _position = Offset.zero;
  bool _moved = false;
  bool _selectionChanged = false;
  TextSelection? _selectionAtDown;
  String? _textAtDown;

  // حالة السحب الجاري (تُحسب مرة عند أول خطوة تمرير).
  bool _dragResolved = false;
  // بعد أول تمرير تلقائي نمتلك التحديد حتى رفع الإصبع (انظر selectionLocked).
  bool _owning = false;
  final Stopwatch _clock = Stopwatch();
  Duration _lastTick = Duration.zero;
  bool _collapsed = false;
  bool _movingIsBase = false;
  int _anchorOffset = 0;
  double _grabDy = 0;

  void attach() {
    if (_attached) return;
    _attached = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_route);
    _controller.addListener(_onControllerChanged);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_route);
    _controller.removeListener(_onControllerChanged);
    _reset();
  }

  /// يربط الصنف بمتحكم جديد (عند استبدال المتحكم في CodeField).
  void rebind(CodeController controller) {
    if (identical(controller, _controller)) return;
    final wasAttached = _attached;
    detach();
    _controller = controller;
    if (wasAttached) attach();
  }

  bool get _active => _pointer != null && _moved && _selectionChanged;

  void _route(PointerEvent event) {
    if (_broken) return;
    if (event is PointerDownEvent) {
      if (_pointer != null) return; // إصبع ثانٍ: نتجاهله
      // أمان: لو بقي قفل من لمسة سابقة لم يصلنا رفعها، نفكّه قبل أن يعالج Flutter
      // هذه اللمسة (المسار العام يُستدعى قبل ساحة الإيماءات).
      _owning = false;
      _controller.selectionLocked = false;
      _pointer = event.pointer;
      _downPosition = event.position;
      _position = event.position;
      _moved = false;
      _selectionChanged = false;
      _dragResolved = false;
      _selectionAtDown = _controller.selection;
      _textAtDown = _controller.text;
      return;
    }
    if (event.pointer != _pointer) return;
    if (event is PointerMoveEvent) {
      _position = event.position;
      if (!_moved && (_position - _downPosition).distance > _dragSlop) {
        _moved = true;
      }
      _evaluate();
      if (_owning) _extendNow();
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _reset();
    }
  }

  void _onControllerChanged() {
    if (_pointer == null || _selectionChanged) return;
    if (_controller.selection != _selectionAtDown && _controller.text == _textAtDown) {
      _selectionChanged = true;
      _evaluate();
    }
  }

  void _evaluate() {
    if (!_active || _deltas() == Offset.zero) {
      _stopTimer();
      return;
    }
    if (_timer == null) {
      _clock
        ..reset()
        ..start();
      _lastTick = Duration.zero;
      _timer = Timer.periodic(_tickInterval, (_) => _onTick());
    }
  }

  Offset _deltas() {
    final box = _viewportContext()?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return Offset.zero;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    return Offset(
      edgeScrollDelta(pointer: _position.dx, min: rect.left, max: rect.right),
      edgeScrollDelta(pointer: _position.dy, min: rect.top, max: rect.bottom),
    );
  }

  RenderEditable? _findEditable() {
    final root = _viewportContext()?.findRenderObject();
    if (root == null) return null;
    RenderEditable? found;
    void visit(RenderObject object) {
      if (found != null) return;
      if (object is RenderEditable) {
        found = object;
        return;
      }
      object.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  void _onTick() {
    try {
      if (!_active) {
        _stopTimer();
        return;
      }
      final delta = _deltas();
      if (delta == Offset.zero) {
        _stopTimer();
        return;
      }
      final editable = _findEditable();
      if (editable == null || !editable.attached) return;
      if (!_dragResolved) _resolveDrag(editable);
      if (!_dragResolved) return;
      if (!_owning) {
        _owning = true;
        _controller.selectionLocked = true;
      }
      final now = _clock.elapsed;
      final dt = ((now - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05).toDouble();
      _lastTick = now;
      _scroll(_vertical(), delta.dy * dt);
      _scroll(_horizontal(), delta.dx * dt);
      _extendSelection(editable);
    } catch (e) {
      // أمان: لا نُسقط المحرر بسبب ميزة تحسينية.
      debugPrint('IdeSelectionAutoscroller disabled: $e');
      _broken = true;
      _reset();
    }
  }

  Offset _caretCenter(RenderEditable editable, int offset) {
    final local = editable.getLocalRectForCaret(TextPosition(offset: offset)).center;
    return editable.localToGlobal(local);
  }

  void _resolveDrag(RenderEditable editable) {
    final sel = _controller.selection;
    if (!sel.isValid) return;
    _collapsed = sel.isCollapsed;
    int moving;
    if (_collapsed) {
      _movingIsBase = false;
      moving = sel.extentOffset;
      _anchorOffset = sel.extentOffset;
    } else {
      final baseDistance = (_caretCenter(editable, sel.baseOffset) - _position).distance;
      final extentDistance = (_caretCenter(editable, sel.extentOffset) - _position).distance;
      _movingIsBase = baseDistance < extentDistance;
      moving = _movingIsBase ? sel.baseOffset : sel.extentOffset;
      _anchorOffset = _movingIsBase ? sel.extentOffset : sel.baseOffset;
    }
    // المقبض يقع تحت سطر الكرت؛ نحتفظ بفرق الارتفاع فقط (لا الأفقي).
    final grab = _caretCenter(editable, moving) - _position;
    _grabDy = grab.dy.clamp(-_maxGrabDy, _maxGrabDy).toDouble();
    _dragResolved = true;
  }

  void _scroll(ScrollController? controller, double delta) {
    if (controller == null || delta == 0 || !controller.hasClients) return;
    final position = controller.position;
    if (!position.hasContentDimensions) return;
    final target = (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();
    if (target != position.pixels) controller.jumpTo(target);
  }

  void _extendSelection(RenderEditable editable) {
    final offset = editable.getPositionForPoint(_position + Offset(0, _grabDy)).offset;
    final TextSelection next;
    if (_collapsed) {
      next = TextSelection.collapsed(offset: offset);
    } else if (_movingIsBase) {
      next = TextSelection(baseOffset: offset, extentOffset: _anchorOffset);
    } else {
      next = TextSelection(baseOffset: _anchorOffset, extentOffset: offset);
    }
    if (next != _controller.selection) _controller.setSelectionOwned(next);
  }

  /// يمدّ التحديد إلى النص تحت الإصبع الآن (يُستدعى مع كل حركة أثناء الملكية).
  void _extendNow() {
    try {
      final editable = _findEditable();
      if (editable == null || !editable.attached || !_dragResolved) return;
      _extendSelection(editable);
    } catch (e) {
      debugPrint('IdeSelectionAutoscroller disabled: $e');
      _broken = true;
      _reset();
    }
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _reset() {
    _stopTimer();
    _owning = false;
    _controller.selectionLocked = false;
    _pointer = null;
    _moved = false;
    _selectionChanged = false;
    _dragResolved = false;
    _selectionAtDown = null;
    _textAtDown = null;
  }
}
