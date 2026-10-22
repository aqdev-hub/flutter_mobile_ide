import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';

import '../code_theme/code_theme.dart';
import '../gutter/gutter.dart';
import '../line_numbers/gutter_style.dart';
import '../search/widget/search_widget.dart';
import '../sizes.dart';
import '../wip/autocomplete/popup.dart';
import 'actions/comment_uncomment.dart';
import 'actions/enter_key.dart';
import 'actions/indent.dart';
import 'actions/outdent.dart';
import 'actions/search.dart';
import 'actions/tab.dart';
import 'code_controller.dart';
import 'default_styles.dart';
import 'js_workarounds/js_workarounds.dart';

final _shortcuts = <ShortcutActivator, Intent>{
  // Copy
  LogicalKeySet(
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.keyC,
  ): CopySelectionTextIntent.copy,
  const SingleActivator(
    LogicalKeyboardKey.keyC,
    meta: true,
  ): CopySelectionTextIntent.copy,
  LogicalKeySet(
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.insert,
  ): CopySelectionTextIntent.copy,

  // Cut
  LogicalKeySet(
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.keyX,
  ): const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
  const SingleActivator(
    LogicalKeyboardKey.keyX,
    meta: true,
  ): const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
  LogicalKeySet(
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.delete,
  ): const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),

  // Undo
  LogicalKeySet(
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.keyZ,
  ): const UndoTextIntent(SelectionChangedCause.keyboard),
  const SingleActivator(
    LogicalKeyboardKey.keyZ,
    meta: true,
  ): const UndoTextIntent(SelectionChangedCause.keyboard),

  // Redo
  LogicalKeySet(
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.keyZ,
  ): const RedoTextIntent(SelectionChangedCause.keyboard),
  LogicalKeySet(
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.meta,
    LogicalKeyboardKey.keyZ,
  ): const RedoTextIntent(SelectionChangedCause.keyboard),

  // Indent
  LogicalKeySet(
    LogicalKeyboardKey.tab,
  ): const IndentIntent(),

  // Outdent
  LogicalKeySet(
    LogicalKeyboardKey.shift,
    LogicalKeyboardKey.tab,
  ): const OutdentIntent(),

  // Comment Uncomment
  LogicalKeySet(
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.slash,
  ): const CommentUncommentIntent(),
  const SingleActivator(
    LogicalKeyboardKey.slash,
    meta: true,
  ): const CommentUncommentIntent(),

  // Search
  LogicalKeySet(
    LogicalKeyboardKey.control,
    LogicalKeyboardKey.keyF,
  ): const SearchIntent(),
  const SingleActivator(
    LogicalKeyboardKey.keyF,
    meta: true,
  ): const SearchIntent(),

  // Dismiss
  LogicalKeySet(
    LogicalKeyboardKey.escape,
  ): const DismissIntent(),

  // EnterKey
  LogicalKeySet(
    LogicalKeyboardKey.enter,
  ): const EnterKeyIntent(),

  // TabKey
  LogicalKeySet(
    LogicalKeyboardKey.tab,
  ): const TabKeyIntent(),
};

class CodeField extends StatefulWidget {
  /// {@macro flutter.widgets.textField.minLines}
  final int? minLines;

  /// {@macro flutter.widgets.textField.maxLInes}
  final int? maxLines;

  /// {@macro flutter.widgets.textField.expands}
  final bool expands;

  /// Whether overflowing lines should wrap around
  /// or make the field scrollable horizontally.
  final bool wrap;

  /// A CodeController instance to apply
  /// language highlight, themeing and modifiers.
  final CodeController controller;

  /// An UndoHistoryController instance
  /// to control TextField history.
  final UndoHistoryController? undoController;

  @Deprecated('Use gutterStyle instead')
  final GutterStyle lineNumberStyle;

  /// {@macro flutter.widgets.textField.cursorColor}
  final Color? cursorColor;

  /// {@macro flutter.widgets.textField.textStyle}
  final TextStyle? textStyle;

  /// {@macro flutter.widgets.textField.smartDashesType}
  final SmartDashesType smartDashesType;

  /// {@macro flutter.widgets.textField.smartQuotesType}
  final SmartQuotesType smartQuotesType;

  /// A way to replace specific line numbers by a custom TextSpan
  final TextSpan Function(int, TextStyle?)? lineNumberBuilder;

  /// {@macro flutter.widgets.textField.enabled}
  final bool? enabled;

  /// {@macro flutter.widgets.editableText.onChanged}
  final void Function(String)? onChanged;

  /// {@macro flutter.widgets.editableText.readOnly}
  ///
  /// This is just passed as a parameter to a [TextField].
  /// See also [CodeController.readOnly].
  final bool readOnly;

  final Color? background;
  final EdgeInsets padding;
  final Decoration? decoration;
  final TextSelectionThemeData? textSelectionTheme;
  final FocusNode? focusNode;

  @Deprecated('Use gutterStyle instead')
  final bool? lineNumbers;

  final GutterStyle gutterStyle;

  const CodeField({
    super.key,
    required this.controller,
    this.undoController,
    this.minLines,
    this.maxLines,
    this.expands = false,
    this.wrap = false,
    this.background,
    this.decoration,
    this.textStyle,
    this.smartDashesType = SmartDashesType.disabled,
    this.smartQuotesType = SmartQuotesType.disabled,
    this.padding = EdgeInsets.zero,
    GutterStyle? gutterStyle,
    this.enabled,
    this.readOnly = false,
    this.cursorColor,
    this.textSelectionTheme,
    this.lineNumberBuilder,
    this.focusNode,
    this.onChanged,
    @Deprecated('Use gutterStyle instead') this.lineNumbers,
    @Deprecated('Use gutterStyle instead')
    this.lineNumberStyle = const GutterStyle(),
  })  : assert(
            gutterStyle == null || lineNumbers == null,
            'Can not provide gutterStyle and lineNumbers at the same time. '
            'Please use gutterStyle and provide necessary columns to show/hide'),
        gutterStyle = gutterStyle ??
            ((lineNumbers == false) ? GutterStyle.none : lineNumberStyle);

  @override
  State<CodeField> createState() => _CodeFieldState();
}

class _CodeFieldState extends State<CodeField> {
  // Add a controller
  LinkedScrollControllerGroup? _controllers;
  ScrollController? _numberScroll;
  ScrollController? _codeScroll;
  ScrollController? _horizontalCodeScroll;
  final _codeFieldKey = GlobalKey();

  OverlayEntry? _suggestionsPopup;
  OverlayEntry? _searchPopup;
  Offset _normalPopupOffset = Offset.zero;
  Offset _flippedPopupOffset = Offset.zero;
  double painterWidth = 0;
  double painterHeight = 0;

  FocusNode? _focusNode;
  String? lines;
  String longestLine = '';
  // IDE PATCH: آخر نص حُسب له longestLine؛ لتجاهل تغيّرات التحديد فقط.
  String? _lastMeasuredText;
  Size? windowSize;
  late TextStyle textStyle;
  Color? _backgroundCol;

  final _editorKey = GlobalKey();
  Offset? _editorOffset;

  @override
  void initState() {
    super.initState();
    _controllers = LinkedScrollControllerGroup();
    _numberScroll = _controllers?.addAndGet();
    _codeScroll = _controllers?.addAndGet();

    widget.controller.addListener(_onTextChanged);
    widget.controller.addListener(_updatePopupOffset);
    widget.controller.popupController.addListener(_onPopupStateChanged);
    widget.controller.searchController.addListener(
      _onSearchControllerChange,
    );
    _horizontalCodeScroll = ScrollController();
    _focusNode = widget.focusNode ?? FocusNode();
    _focusNode!.attach(context, onKeyEvent: _onKeyEvent);

    widget.controller.searchController.codeFieldFocusNode = _focusNode;

    // Workaround for disabling spellchecks in FireFox
    // https://github.com/akvelon/flutter-code-editor/issues/197
    disableSpellCheckIfWeb();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final double width = _codeFieldKey.currentContext!.size!.width;
      final double height = _codeFieldKey.currentContext!.size!.height;
      windowSize = Size(width, height);
    });
    _onTextChanged();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    return widget.controller.onKey(event);
  }

  @override
  void dispose() {
    widget.controller.searchController.codeFieldFocusNode = null;
    widget.controller.removeListener(_onTextChanged);
    widget.controller.removeListener(_updatePopupOffset);
    widget.controller.popupController.removeListener(_onPopupStateChanged);
    _suggestionsPopup?.remove();
    widget.controller.searchController.removeListener(
      _onSearchControllerChange,
    );
    _searchPopup?.remove();
    _searchPopup = null;
    _numberScroll?.dispose();
    _codeScroll?.dispose();
    _horizontalCodeScroll?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    oldWidget.controller.removeListener(_onTextChanged);
    oldWidget.controller.removeListener(_updatePopupOffset);
    oldWidget.controller.popupController.removeListener(_onPopupStateChanged);
    oldWidget.controller.searchController.removeListener(
      _onSearchControllerChange,
    );

    widget.controller.searchController.codeFieldFocusNode = _focusNode;
    widget.controller.addListener(_onTextChanged);
    widget.controller.addListener(_updatePopupOffset);
    widget.controller.popupController.addListener(_onPopupStateChanged);
    widget.controller.searchController.addListener(
      _onSearchControllerChange,
    );
  }

  void rebuild() {
    setState(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        // For some reason _codeFieldKey.currentContext is null in tests
        // so check first.
        final context = _codeFieldKey.currentContext;
        if (context != null) {
          final double width = context.size!.width;
          final double height = context.size!.height;
          windowSize = Size(width, height);
        }
      });
    });
  }

  void _onTextChanged() {
    // IDE PATCH: هذا المستمع يُستدعى عند كل تغيير في الـ controller، بما في
    // ذلك تغيّر التحديد فقط (أثناء سحب المقابض يحدث عشرات المرات في الثانية).
    // كان يعيد تقسيم النص كاملًا مرتين ويستدعي setState في كل مرة، مما يسبب
    // تأخّر المقابض واهتزاز التحديد. نكتفي الآن بالعمل حين يتغير النص فعلًا.
    final text = widget.controller.text;
    if (identical(text, _lastMeasuredText) || text == _lastMeasuredText) {
      return;
    }
    _lastMeasuredText = text;

    // Find longest line
    var longest = '';
    for (final line in text.split('\n')) {
      if (line.length > longest.length) longest = line;
    }
    longestLine = longest;

    rebuild();
  }

  /// IDE PATCH: موضع المحرر على الشاشة (لحساب موضع نافذة الإكمال). كان يُحسب
  /// داخل [_onTextChanged]؛ ننقله لوقت الحاجة فقط.
  void _refreshEditorOffset() {
    if (_codeScroll == null || _editorKey.currentContext == null) {
      return;
    }
    final box = _editorKey.currentContext!.findRenderObject() as RenderBox?;
    final offset = box?.localToGlobal(Offset.zero);
    if (offset == null) {
      return;
    }
    _editorOffset = offset + Offset(0, _codeScroll!.offset);
  }

  // Wrap the codeField in a horizontal scrollView
  Widget _wrapInScrollView(
    Widget codeField,
    TextStyle textStyle,
    double minWidth,
  ) {
    final intrinsic = IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: 0,
              minWidth: minWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(longestLine, style: textStyle),
            ), // Add extra padding
          ),
          widget.expands ? Expanded(child: codeField) : codeField,
        ],
      ),
    );

    // IDE PATCH: انظر [_HorizontalRevealBoundary].
    final boundary = _HorizontalRevealBoundary(
      horizontalController: _horizontalCodeScroll!,
      child: intrinsic,
    );

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        right: widget.padding.right,
      ),
      scrollDirection: Axis.horizontal,
      controller: _horizontalCodeScroll,
      child: boundary,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Default color scheme
    const rootKey = 'root';

    final themeData = Theme.of(context);
    final styles = CodeTheme.of(context)?.styles;
    _backgroundCol = widget.background ??
        styles?[rootKey]?.backgroundColor ??
        DefaultStyles.backgroundColor;

    if (widget.decoration != null) {
      _backgroundCol = null;
    }

    final defaultTextStyle = TextStyle(
      color: styles?[rootKey]?.color ?? DefaultStyles.textColor,
      fontSize: themeData.textTheme.titleMedium?.fontSize,
      height: themeData.textTheme.titleMedium?.height,
    );

    textStyle = defaultTextStyle.merge(widget.textStyle);

    final codeField = TextField(
      focusNode: _focusNode,
      // IDE PATCH: هامش حول المؤشر عند إظهاره/التمرير التلقائي. كان صفرًا
      // (يلتصق المؤشر بحافة الشاشة أو بشريط الاقتراحات/لوحة المفاتيح).
      scrollPadding: widget.padding + const EdgeInsets.symmetric(vertical: 24),
      style: textStyle,
      smartDashesType: widget.smartDashesType,
      smartQuotesType: widget.smartQuotesType,
      controller: widget.controller,
      undoController: widget.undoController,
      minLines: widget.minLines,
      maxLines: widget.maxLines,
      expands: widget.expands,
      scrollController: _codeScroll,
      decoration: const InputDecoration(
        isCollapsed: true,
        contentPadding: EdgeInsets.symmetric(vertical: 16),
        disabledBorder: InputBorder.none,
        border: InputBorder.none,
        focusedBorder: InputBorder.none,
      ),
      cursorColor: widget.cursorColor ?? defaultTextStyle.color,
      autocorrect: false,
      enableSuggestions: false,
      enabled: widget.enabled,
      onChanged: widget.onChanged,
      readOnly: widget.readOnly,
    );

    final editingField = Theme(
      data: Theme.of(context).copyWith(
        textSelectionTheme: widget.textSelectionTheme,
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Control horizontal scrolling
          return _wrapInScrollView(codeField, textStyle, constraints.maxWidth);
        },
      ),
    );

    return FocusableActionDetector(
      actions: widget.controller.actions,
      shortcuts: _shortcuts,
      child: Container(
        decoration: widget.decoration,
        color: _backgroundCol,
        key: _codeFieldKey,
        padding: const EdgeInsets.only(left: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.gutterStyle.showGutter) _buildGutter(),
            Expanded(key: _editorKey, child: editingField),
          ],
        ),
      ),
    );
  }

  Widget _buildGutter() {
    final lineNumberSize = textStyle.fontSize;
    final lineNumberColor =
        widget.gutterStyle.textStyle?.color ?? textStyle.color?.withOpacity(.5);

    final lineNumberTextStyle =
        (widget.gutterStyle.textStyle ?? textStyle).copyWith(
      color: lineNumberColor,
      fontFamily: textStyle.fontFamily,
      fontSize: lineNumberSize,
    );

    final gutterStyle = widget.gutterStyle.copyWith(
      textStyle: lineNumberTextStyle,
      errorPopupTextStyle: widget.gutterStyle.errorPopupTextStyle ??
          CodeTheme.of(context)?.styles['root'] ??
          textStyle.copyWith(
            fontSize: DefaultStyles.errorPopupTextSize,
            backgroundColor: DefaultStyles.backgroundColor,
            fontStyle: DefaultStyles.fontStyle,
          ),
    );

    return GutterWidget(
      codeController: widget.controller,
      style: gutterStyle,
      scrollController: _numberScroll,
    );
  }

  void _updatePopupOffset() {
    // IDE PATCH: كان يبني TextPainter للنص كاملًا ويستدعي setState عند كل
    // تغيّر في التحديد حتى لو لم تكن نافذة الإكمال ظاهرة. نحسبه الآن فقط
    // أثناء ظهورها، وعند إظهارها (انظر [_onPopupStateChanged]).
    if (_suggestionsPopup == null) {
      return;
    }
    _computePopupOffsets();
    _suggestionsPopup!.markNeedsBuild();
  }

  void _computePopupOffsets() {
    _refreshEditorOffset();

    // حجم نافذة التحرير قد يتغير (لوحة المفاتيح) دون تغيّر النص.
    final fieldSize = _codeFieldKey.currentContext?.size;
    if (fieldSize != null) {
      windowSize = fieldSize;
    }

    final textPainter = _getTextPainter(widget.controller.text);
    final caretHeight = _getCaretHeight(textPainter);

    final leftOffset = _getPopupLeftOffset(textPainter);
    final normalTopOffset = _getPopupTopOffset(textPainter, caretHeight);
    final flippedTopOffset = normalTopOffset -
        (Sizes.autocompletePopupMaxHeight + caretHeight + Sizes.caretPadding);

    _normalPopupOffset = Offset(leftOffset, normalTopOffset);
    _flippedPopupOffset = Offset(leftOffset, flippedTopOffset);
  }

  TextPainter _getTextPainter(String text) {
    return TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(text: text, style: textStyle),
    )..layout();
  }

  Offset _getCaretOffset(TextPainter textPainter) {
    return textPainter.getOffsetForCaret(
      widget.controller.selection.base,
      Rect.zero,
    );
  }

  double _getCaretHeight(TextPainter textPainter) {
    final double? caretFullHeight = textPainter.getFullHeightForCaret(
      widget.controller.selection.base,
      Rect.zero,
    );
    return caretFullHeight ?? 0;
  }

  double _getPopupLeftOffset(TextPainter textPainter) {
    return max(
      _getCaretOffset(textPainter).dx +
          widget.padding.left -
          _horizontalCodeScroll!.offset +
          (_editorOffset?.dx ?? 0),
      0,
    );
  }

  double _getPopupTopOffset(TextPainter textPainter, double caretHeight) {
    return max(
      _getCaretOffset(textPainter).dy +
          caretHeight +
          16 +
          widget.padding.top -
          _codeScroll!.offset +
          (_editorOffset?.dy ?? 0),
      0,
    );
  }

  void _onPopupStateChanged() {
    final shouldShow =
        widget.controller.popupController.shouldShow && windowSize != null;
    if (!shouldShow) {
      _suggestionsPopup?.remove();
      _suggestionsPopup = null;
      return;
    }

    if (_suggestionsPopup == null) {
      _computePopupOffsets();
      _suggestionsPopup = _buildSuggestionOverlay();
      Overlay.of(context).insert(_suggestionsPopup!);
    }

    _suggestionsPopup!.markNeedsBuild();
  }

  void _onSearchControllerChange() {
    final shouldShow = widget.controller.searchController.shouldShow;

    if (!shouldShow) {
      _searchPopup?.remove();
      _searchPopup = null;
      return;
    }

    if (_searchPopup == null) {
      _searchPopup = _buildSearchOverlay();
      Overlay.of(context).insert(_searchPopup!);
    }
  }

  OverlayEntry _buildSearchOverlay() {
    final colorScheme = Theme.of(context).colorScheme;
    final borderColor = _getTextColorFromTheme() ?? colorScheme.onBackground;
    return OverlayEntry(
      builder: (context) {
        return Positioned(
          bottom: 10,
          right: 10,
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              border: Border.all(
                color: borderColor,
              ),
              borderRadius: const BorderRadius.all(
                Radius.circular(5),
              ),
            ),
            child: Material(
              child: SearchWidget(
                searchController: widget.controller.searchController,
              ),
            ),
          ),
        );
      },
    );
  }

  Color? _getTextColorFromTheme() {
    final textTheme = Theme.of(context).textTheme;

    return textTheme.bodyLarge?.color ??
        textTheme.bodyMedium?.color ??
        textTheme.bodySmall?.color ??
        textTheme.displayLarge?.color ??
        textTheme.displayMedium?.color ??
        textTheme.displaySmall?.color ??
        textTheme.headlineLarge?.color ??
        textTheme.headlineMedium?.color ??
        textTheme.headlineSmall?.color ??
        textTheme.labelLarge?.color ??
        textTheme.labelMedium?.color ??
        textTheme.labelSmall?.color ??
        textTheme.titleLarge?.color ??
        textTheme.titleMedium?.color ??
        textTheme.titleSmall?.color;
  }

  OverlayEntry _buildSuggestionOverlay() {
    return OverlayEntry(
      builder: (context) {
        return Popup(
          normalOffset: _normalPopupOffset,
          flippedOffset: _flippedPopupOffset,
          controller: widget.controller.popupController,
          editingWindowSize: windowSize!,
          style: textStyle,
          backgroundColor: _backgroundCol,
          parentFocusNode: _focusNode!,
          editorOffset: _editorOffset,
        );
      },
    );
  }
}


/// IDE PATCH: يمنع تضارب التمرير المتداخل أثناء تحديد النص.
///
/// المحرر مُغلَّف بتمرير أفقي ([SingleChildScrollView]) وبداخله [TextField] له
/// تمريره الرأسي الخاص. عند تحريك مؤشر/مقبض التحديد قرب الحافة يطلب
/// [EditableText] إظهار المؤشر (`showOnScreen`) بحركة متحركة (animation)؛
/// فكان يتحرك التمرير الأفقي الأب تحت إصبع المستخدم، فيتغير الموضع المُحسوب
/// تحت الإصبع، فيُطلب إظهار جديد... وهكذا: اهتزاز ذهابًا وإيابًا.
///
/// هذا الصندوق يعترض الطلب، فيُمرّر أفقيًا بقفزة مباشرة بلا حركة وبهامش ثابت،
/// فيستقر المؤشر عند الحافة ولا تتولد حلقة التغذية الراجعة.
class _HorizontalRevealBoundary extends SingleChildRenderObjectWidget {
  const _HorizontalRevealBoundary({
    required this.horizontalController,
    required super.child,
  });

  final ScrollController horizontalController;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderHorizontalRevealBoundary(horizontalController);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderHorizontalRevealBoundary renderObject,
  ) {
    renderObject.horizontalController = horizontalController;
  }
}

class _RenderHorizontalRevealBoundary extends RenderProxyBox {
  _RenderHorizontalRevealBoundary(this.horizontalController);

  ScrollController horizontalController;

  /// هامش أفقي بين المؤشر وحافة العرض بعد الإظهار.
  static const double _margin = 24;

  @override
  void showOnScreen({
    RenderObject? descendant,
    Rect? rect,
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
  }) {
    if (!horizontalController.hasClients) {
      super.showOnScreen(
        descendant: descendant,
        rect: rect,
        duration: duration,
        curve: curve,
      );
      return;
    }

    // نحوّل المستطيل إلى إحداثيات هذا الصندوق (= إحداثيات محتوى التمرير).
    final target = descendant ?? this;
    final local = MatrixUtils.transformRect(
      target.getTransformTo(this),
      rect ?? target.paintBounds,
    );

    final position = horizontalController.position;
    final viewStart = position.pixels;
    final viewEnd = viewStart + position.viewportDimension;

    double? newOffset;
    if (local.left - _margin < viewStart) {
      newOffset = local.left - _margin;
    } else if (local.right + _margin > viewEnd) {
      newOffset = local.right + _margin - position.viewportDimension;
    }

    if (newOffset != null) {
      position.jumpTo(
        newOffset
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble(),
      );
    }
    // لا نمرّر الطلب للأعلى عمدًا: لا يوجد تمرير آخر مطلوب فوق المحرر.
  }
}
