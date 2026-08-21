import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../console/logic/console_provider.dart';
import '../../preview/logic/problems_provider.dart';
import '../../project_explorer/logic/project_provider.dart';
import '../../search/logic/project_search_provider.dart';
import '../data/models/editor_tab.dart';
import 'editor_tabs_state.dart';
import 'highlight_language_resolver.dart';

final editorTabsProvider =
    StateNotifierProvider<EditorTabsNotifier, EditorTabsState>((ref) {
  return EditorTabsNotifier(ref);
});

/// يدير دورة حياة التبويبات المفتوحة بالكامل: فتح ملف (أو التركيز عليه إن
/// كان مفتوحًا مسبقًا بدل تكراره)، الانتقال لسطر محدَّد فعليًا داخل الملف
/// (لدعم نتائج البحث)، تتبّع التعديلات غير المحفوظة، الحفظ، وتشغيل تحليل
/// "Problems" الحيّ + تحديث فهرس البحث لكل ملف dart مفتوح.
class EditorTabsNotifier extends StateNotifier<EditorTabsState> {
  final Ref _ref;

  EditorTabsNotifier(this._ref) : super(const EditorTabsState());

  Future<void> openFile(String path, String name) async {
    final existing = state.tabs.where((t) => t.path == path);
    if (existing.isNotEmpty) {
      state = state.copyWith(activePath: path);
      return;
    }

    try {
      final content = await _ref.read(fileSystemRepositoryProvider).readFile(path);
      final dot = name.lastIndexOf('.');
      final extension = dot == -1 ? '' : name.substring(dot);

      final controller = CodeController(
        text: content,
        language: resolveHighlightLanguage(extension),
      );

      final tab = EditorTab(path: path, name: name, controller: controller, savedContent: content);

      controller.addListener(() => _onTabContentChanged(path));

      state = state.copyWith(tabs: [...state.tabs, tab], activePath: path);

      // تحليل أولي فور الفتح (بدون انتظار أول تعديل) حتى تظهر مشاكل
      // موجودة أصلًا في الملف فورًا في تبويب Problems.
      if (extension == '.dart') {
        _ref.read(problemsProvider.notifier).scheduleAnalysis(path, name, content);
      }
    } catch (e) {
      _ref.read(consoleProvider.notifier).log('تعذّر فتح الملف $name: $e', isError: true);
    }
  }

  /// يفتح الملف (إن لم يكن مفتوحًا أصلًا) وينقل مؤشر الكتابة فعليًا إلى
  /// بداية [lineNumber] المطلوب — هذا ما كان ناقصًا سابقًا: نتائج البحث
  /// كانت تفتح الملف فقط دون الانتقال للسطر المطلوب داخله، بعكس أي محرر
  /// حقيقي (مثل VS Code) حيث النقر على نتيجة بحث ينقلك مباشرة لموضعها.
  Future<void> revealPosition(String path, String name, {required int lineNumber}) async {
    await openFile(path, name);

    EditorTab? tab;
    for (final t in state.tabs) {
      if (t.path == path) {
        tab = t;
        break;
      }
    }
    if (tab == null) return; // فشل الفتح أصلًا (تم تسجيل السبب في الكونسول من openFile)

    final text = tab.controller.fullText;
    final lines = text.split('\n');
    var offset = 0;
    // نجمع أطوال كل الأسطر قبل السطر المطلوب (+1 لحرف السطر الجديد نفسه)
    // للوصول لموضع بداية السطر المطلوب كإزاحة حرفية داخل النص الكامل.
    for (var i = 0; i < lineNumber - 1 && i < lines.length; i++) {
      offset += lines[i].length + 1;
    }
    offset = offset.clamp(0, text.length);

    tab.controller.selection = TextSelection.collapsed(offset: offset);
  }

  void _onTabContentChanged(String path) {
    final tabs = state.tabs;
    final index = tabs.indexWhere((t) => t.path == path);
    if (index == -1) return;
    final tab = tabs[index];
    final isDirtyNow = tab.controller.fullText != tab.savedContent;
    if (tab.isDirty != isDirtyNow) {
      tab.isDirty = isDirtyNow;
      state = state.copyWith(tabs: [...tabs]); // إعادة إشعار الواجهة بتغيّر مؤشر التعديل
    }

    // تحليل حيّ لـ Problems أثناء الكتابة — مستقل عمدًا عن تغيّر مؤشر
    // isDirty أعلاه (الذي لا يتغيّر إلا مرة واحدة عند أول تعديل).
    if (tab.extension == '.dart') {
      _ref.read(problemsProvider.notifier).scheduleAnalysis(path, tab.name, tab.controller.fullText);
    }
  }

  void setActive(String path) {
    state = state.copyWith(activePath: path);
  }

  void closeTab(String path) {
    final tabs = [...state.tabs]..removeWhere((t) => t.path == path);
    String? newActive = state.activePath;
    if (state.activePath == path) {
      newActive = tabs.isNotEmpty ? tabs.last.path : null;
    }
    state = EditorTabsState(tabs: tabs, activePath: newActive);
    _ref.read(problemsProvider.notifier).removeFile(path);
  }

  Future<void> saveActive() async {
    final tab = state.activeTab;
    if (tab == null) return;
    await _saveTab(tab);
  }

  Future<void> saveAll() async {
    for (final tab in state.tabs) {
      if (tab.isDirty) await _saveTab(tab);
    }
  }

  Future<void> _saveTab(EditorTab tab) async {
    try {
      final content = tab.controller.fullText;
      await _ref.read(fileSystemRepositoryProvider).writeFile(tab.path, content);

      final index = state.tabs.indexWhere((t) => t.path == tab.path);
      if (index != -1) {
        final updatedTab = EditorTab(
          path: tab.path,
          name: tab.name,
          controller: tab.controller,
          savedContent: content,
          isDirty: false,
        );
        final tabs = [...state.tabs];
        tabs[index] = updatedTab;
        state = state.copyWith(tabs: tabs);
      }
      _ref.read(projectSearchProvider.notifier).indexFile(tab.path, tab.name, content);
      _ref.read(consoleProvider.notifier).log('تم حفظ: ${tab.name}');
    } catch (e) {
      _ref.read(consoleProvider.notifier).log('تعذّر حفظ ${tab.name}: $e', isError: true);
    }
  }
}
