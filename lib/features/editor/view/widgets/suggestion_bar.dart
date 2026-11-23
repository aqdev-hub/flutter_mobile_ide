import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../logic/code_suggestions.dart';
import '../../logic/editor_tabs_provider.dart';
import '../../logic/widget_catalog.dart';

/// شريط الإكمال التلقائي والمساعدة أسفل المحرر (فوق لوحة Problems):
///  - أزرار: تنسيق الكود، ومساعدة الودجت تحت المؤشر.
///  - سطر توقيع الاستدعاء الحالي (معاملات الودجت، والمستخدم منها باهت).
///  - شرائح اقتراحات تُدرَج بلمسة، وبالضغط المطوَّل تُعرَض مساعدة العنصر.
///
/// يستمع لـ [controller] فقط (selection/text) ولا يعتمد على أي واجهة خاصة
/// بمكتبة flutter_code_editor غير التي يستخدمها المشروع أصلًا
/// (`text`, `selection`, addListener).
class EditorSuggestionBar extends ConsumerStatefulWidget {
  final CodeController controller;
  const EditorSuggestionBar({super.key, required this.controller});

  @override
  ConsumerState<EditorSuggestionBar> createState() => _EditorSuggestionBarState();
}

class _EditorSuggestionBarState extends ConsumerState<EditorSuggestionBar> {
  SuggestionResult _result = SuggestionResult.empty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _recompute();
  }

  @override
  void didUpdateWidget(covariant EditorSuggestionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
      _recompute();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    // أثناء تحديد نص (سحب المقابض) لا توجد اقتراحات أصلًا؛ لا داعي لإعادة بناء
    // الشريط عند كل تغيّر في التحديد.
    final sel = widget.controller.selection;
    if ((!sel.isValid || !sel.isCollapsed) && identical(_result, SuggestionResult.empty)) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.idle || phase == SchedulerPhase.postFrameCallbacks) {
      setState(_recompute);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(_recompute);
      });
    }
  }

  void _recompute() {
    final c = widget.controller;
    final sel = c.selection;
    if (!sel.isValid || !sel.isCollapsed) {
      _result = SuggestionResult.empty;
      return;
    }
    _result = CodeSuggestions.compute(c.text, sel.baseOffset);
  }

  void _apply(CodeSuggestion s) {
    final c = widget.controller;
    final sel = c.selection;
    if (!sel.isValid) return;
    final text = c.text;
    final cursor = sel.baseOffset;
    final r = CodeSuggestions.compute(text, cursor);
    final start = r.replaceStart;
    if (start > cursor) return;
    final newText = text.replaceRange(start, cursor, s.insertText);
    final caret = start + s.insertText.length - s.cursorBack;
    c.text = newText;
    c.selection = TextSelection.collapsed(offset: caret);
  }

  void _showHelpAtCursor() {
    final c = widget.controller;
    final sel = c.selection;
    final offset = sel.isValid ? sel.baseOffset : 0;
    final spec = CodeSuggestions.helpSpecAt(c.text, offset);
    if (spec == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ضع المؤشر على اسم ودجت، أو داخل أقواس استدعائه، لعرض مساعدته.')),
      );
      return;
    }
    _showHelp(spec);
  }

  String _signature(WidgetSpec spec) {
    final parts = <String>[...spec.positional];
    if (spec.named.isNotEmpty) parts.add('{${spec.named.join(', ')}}');
    return '${spec.name}(${parts.join(', ')})';
  }

  void _showHelp(WidgetSpec spec) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: IdeColors.darkSurface,
      builder: (ctx) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _signature(spec),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13, color: Color(0xFF4FC3F7)),
                  ),
                  const SizedBox(height: 10),
                  Text(spec.doc, style: const TextStyle(fontSize: 13, height: 1.5)),
                  if (spec.positional.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('معاملات موضعية', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    for (final p in spec.positional)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(p, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                      ),
                  ],
                  if (spec.named.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text('معاملات مُسمّاة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    for (final p in spec.named)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(text: '$p: ', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                              TextSpan(
                                text: WidgetCatalog.hintFor(p),
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  (IconData, Color) _look(SuggestionKind kind) {
    switch (kind) {
      case SuggestionKind.param:
        return (Icons.tune, const Color(0xFF4FC3F7));
      case SuggestionKind.widget:
        return (Icons.widgets, const Color(0xFFFFB74D));
      case SuggestionKind.value:
        return (Icons.data_object, const Color(0xFFBA68C8));
      case SuggestionKind.function:
        return (Icons.functions, const Color(0xFF81C784));
      case SuggestionKind.constant:
        return (Icons.circle, const Color(0xFF90A4AE));
      case SuggestionKind.namespace:
        return (Icons.folder_open, const Color(0xFFDCB67A));
      case SuggestionKind.local:
        return (Icons.text_fields, const Color(0xFF9E9E9E));
      case SuggestionKind.keyword:
        return (Icons.code, const Color(0xFF64B5F6));
      case SuggestionKind.snippet:
        return (Icons.bolt, const Color(0xFFFFD54F));
    }
  }

  Widget _chip(CodeSuggestion s) {
    final (icon, color) = _look(s.kind);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => _apply(s),
        onLongPress: s.specName == null
            ? null
            : () {
                final spec = WidgetCatalog.lookup(s.specName!);
                if (spec != null) _showHelp(spec);
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(s.label, style: TextStyle(fontSize: 12, color: Colors.grey.shade200)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _signatureLine(SignatureHint sig) {
    final spans = <InlineSpan>[
      TextSpan(text: '${sig.spec.name}(', style: const TextStyle(color: Color(0xFFFFB74D))),
    ];
    final parts = <InlineSpan>[];
    for (final p in sig.spec.positional) {
      parts.add(TextSpan(text: p, style: const TextStyle(color: Colors.grey)));
    }
    for (final p in sig.spec.named) {
      final used = sig.used.contains(p);
      parts.add(TextSpan(
        text: p,
        style: TextStyle(
          color: used ? Colors.grey.shade600 : const Color(0xFF4FC3F7),
          decoration: used ? TextDecoration.lineThrough : TextDecoration.none,
        ),
      ));
    }
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) spans.add(const TextSpan(text: ', ', style: TextStyle(color: Colors.grey)));
      spans.add(parts[i]);
    }
    spans.add(const TextSpan(text: ')', style: TextStyle(color: Color(0xFFFFB74D))));
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 0),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Text.rich(
          TextSpan(children: spans, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          maxLines: 1,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Container(
      decoration: const BoxDecoration(
        color: IdeColors.darkSurface,
        border: Border(top: BorderSide(color: IdeColors.darkBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (r.signature != null) _signatureLine(r.signature!),
          SizedBox(
            height: 38,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'تنسيق الكود',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                  icon: const Icon(Icons.format_align_left, size: 18),
                  onPressed: () => ref.read(editorTabsProvider.notifier).formatActive(),
                ),
                IconButton(
                  tooltip: 'مساعدة الودجت تحت المؤشر',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                  icon: const Icon(Icons.help_outline, size: 18),
                  onPressed: _showHelpAtCursor,
                ),
                Container(width: 1, height: 20, color: IdeColors.darkBorder),
                const SizedBox(width: 6),
                Expanded(
                  child: r.suggestions.isEmpty
                      ? const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('اكتب اسم ودجت أو "Colors." للاقتراحات', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: r.suggestions.length,
                          itemBuilder: (context, index) => Center(child: _chip(r.suggestions[index])),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
