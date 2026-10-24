import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../console/logic/console_provider.dart';
import '../../preview/logic/problems_provider.dart';
import '../../project_explorer/logic/fs_events.dart';
import '../../project_explorer/logic/project_provider.dart';
import '../../project_explorer/logic/project_state.dart';
import '../../search/logic/project_search_provider.dart';
import '../../semantic/logic/semantic_provider.dart';
import '../../settings/logic/settings_provider.dart';
import '../data/models/editor_tab.dart';
import 'dart_formatter.dart';
import 'dart_syntax_analyzer.dart';
import 'editor_tabs_state.dart';
import 'highlight_language_resolver.dart';
import 'ide_code_controller.dart';

final editorTabsProvider =
    StateNotifierProvider<EditorTabsNotifier, EditorTabsState>((ref) {
  return EditorTabsNotifier(ref);
});

/// يدير دورة حياة التبويبات المفتوحة بالكامل: فتح ملف (أو التركيز عليه إن
/// كان مفتوحًا مسبقًا بدل تكراره)، الانتقال لسطر محدَّد فعليًا داخل الملف
/// (لدعم نتائج البحث)، تتبّع التعديلات غير المحفوظة، الحفظ (مع تنسيق
/// تلقائي اختياري لملفات dart)، وتشغيل تحليل "Problems" الحيّ + تحديث فهرس
/// البحث لكل ملف dart مفتوح.
///
/// **تحديث (حماية البيانات)**:
/// - يستمع لأحداث نظام الملفات ([fsChangeProvider]): عند إعادة تسمية/نقل ملف
///   أو مجلد تُحوَّل مسارات تبويباته المفتوحة للمسار الجديد (فلا يُعيد "حفظ"
///   لاحق إنشاء الملف القديم)، وعند حذفه يُغلق تبويبه النظيف ويبقى تبويبه
///   غير المحفوظ مفتوحًا مع تنبيه حتى لا تضيع تعديلات المستخدم.
/// - تبديل المشروع يحفظ التعديلات غير المحفوظة تلقائيًا قبل إغلاق التبويبات.
/// - يُؤجَّل `dispose` للـ CodeController إلى ما بعد الإطار الحالي، حتى لا
///   يُستخدَم controller بعد التخلّص منه من قِبل حقل لم يُزَل من الشجرة بعد.
class EditorTabsNotifier extends StateNotifier<EditorTabsState> {
  final Ref _ref;

  // آخر نص جُدوِل تحليله لكل controller: يمنع إعادة الجدولة عندما يُعلِن الـ
  // controller عن تغيّر لا يمسّ النص (مثل وصول تسطير دلالي جديد) — وإلا دخلنا
  // حلقة تحليل لا تنتهي.
  final Expando<String> _scheduledText = Expando<String>();

  EditorTabsNotifier(this._ref) : super(const EditorTabsState()) {
    // إغلاق كل التبويبات عند تبديل المشروع فعليًا (مسار جذر مختلف)، وليس
    // عند refreshProject (نفس المسار) حتى لا تضيع تعديلات غير محفوظة.
    _ref.listen<ProjectState>(projectProvider, (previous, next) {
      if (previous?.root?.path != next.root?.path) {
        unawaited(closeAll());
      }
    });

    _ref.listen<FsChange?>(fsChangeProvider, (previous, next) {
      if (next != null) _onFsChange(next);
    });
  }

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

      final controller = IdeCodeController(
        text: content,
        language: resolveHighlightLanguage(extension),
        // محلل Dart الرسمي (أيقونات الهامش + تسطير الأخطاء) لملفات dart فقط؛
        // بقية الأنواع تبقى بالمحلل الافتراضي للمكتبة.
        analyzer: extension == '.dart' ? DartSyntaxAnalyzer() : const DefaultLocalAnalyzer(),
      );

      final tab = EditorTab(path: path, name: name, controller: controller, savedContent: content);

      // المستمع مرتبط بالـ controller نفسه (وليس بالمسار) — حتى يبقى صالحًا
      // بعد إعادة تسمية/نقل الملف دون إعادة تسجيله.
      controller.addListener(() => _onTabContentChanged(controller));

      state = state.copyWith(tabs: [...state.tabs, tab], activePath: path);

      if (extension == '.dart') {
        _scheduleAnalysis(path, name, controller, content);
      }
    } catch (e) {
      _ref.read(consoleProvider.notifier).log('تعذّر فتح الملف $name: $e', isError: true);
    }
  }

  /// يفتح الملف (إن لم يكن مفتوحًا أصلًا) وينقل مؤشر الكتابة فعليًا إلى
  /// بداية [lineNumber] المطلوب.
  Future<void> revealPosition(String path, String name, {required int lineNumber}) async {
    await openFile(path, name);

    EditorTab? tab;
    for (final t in state.tabs) {
      if (t.path == path) {
        tab = t;
        break;
      }
    }
    if (tab == null) return;

    final text = tab.controller.fullText;
    final lines = text.split('\n');
    var offset = 0;
    for (var i = 0; i < lineNumber - 1 && i < lines.length; i++) {
      offset += lines[i].length + 1;
    }
    offset = offset.clamp(0, text.length);

    tab.controller.selection = TextSelection.collapsed(offset: offset);
  }

  void _onTabContentChanged(CodeController controller) {
    final tabs = state.tabs;
    final index = tabs.indexWhere((t) => identical(t.controller, controller));
    if (index == -1) return;
    final tab = tabs[index];
    final isDirtyNow = controller.fullText != tab.savedContent;
    if (tab.isDirty != isDirtyNow) {
      tab.isDirty = isDirtyNow;
      state = state.copyWith(tabs: [...tabs]);
    }

    if (tab.extension == '.dart') {
      final text = controller.fullText;
      if (_scheduledText[controller] != text) _scheduleAnalysis(tab.path, tab.name, controller, text);
    }
  }

  /// يجدول تحليل ملف dart (صياغة + دلالي + معاينة)، وعند وصول النتيجة يمرّر
  /// الجزء الدلالي للـ controller ليرسم تسطيره.
  void _scheduleAnalysis(String path, String name, CodeController controller, String content) {
    _scheduledText[controller] = content;
    _ref.read(problemsProvider.notifier).scheduleAnalysis(
      path,
      name,
      content,
      onAnalyzed: (problems) {
        if (controller is IdeCodeController) controller.setSemanticProblems(problems, content);
      },
    );
  }

  void setActive(String path) {
    state = state.copyWith(activePath: path);
  }

  /// يُغلق التبويب فورًا دون أي سؤال. الواجهة مسؤولة عن تأكيد المستخدم قبل
  /// استدعائه إن كان [EditorTab.isDirty] (راجع `requestCloseTab`).
  void closeTab(String path) {
    EditorTab? closedTab;
    final tabs = [...state.tabs]..removeWhere((t) {
        final match = t.path == path;
        if (match) closedTab = t;
        return match;
      });
    String? newActive = state.activePath;
    if (state.activePath == path) {
      newActive = tabs.isNotEmpty ? tabs.last.path : null;
    }
    state = EditorTabsState(tabs: tabs, activePath: newActive);
    _ref.read(problemsProvider.notifier).removeFile(path);
    final controller = closedTab?.controller;
    if (controller != null) _disposeControllerLater(controller);
  }

  /// يُغلق **كل** التبويبات ويمسح Problems — يُستدعى عند تبديل المشروع.
  ///
  /// التعديلات غير المحفوظة تُحفَظ تلقائيًا في ملفاتها (المسارات مطلقة، فتبقى
  /// صالحة بعد تبديل المشروع) بدل أن تضيع بصمت؛ ويُسجَّل ذلك في الكونسول.
  Future<void> closeAll() async {
    if (state.tabs.isEmpty) return;
    final snapshot = [...state.tabs];
    state = const EditorTabsState();
    _ref.read(problemsProvider.notifier).clearAll();

    final console = _ref.read(consoleProvider.notifier);
    final repo = _ref.read(fileSystemRepositoryProvider);
    for (final tab in snapshot) {
      if (!tab.isDirty) continue;
      try {
        await repo.writeFile(tab.path, tab.controller.fullText);
        console.log('حُفظت تلقائيًا قبل تبديل المشروع: ${tab.name}');
      } catch (e) {
        console.log('تعذّر الحفظ التلقائي لـ ${tab.name} قبل تبديل المشروع: $e', isError: true);
      }
    }
    for (final tab in snapshot) {
      _disposeControllerLater(tab.controller);
    }
  }

  /// يؤجّل `dispose` إلى ما بعد الإطار الحالي: عند إغلاق تبويب يُحدَّث الـ
  /// state أولًا، لكن الحقل (CodeField/شريط الاقتراحات) لا يُزال من الشجرة إلا
  /// في الإطار التالي — والتخلّص الفوري كان يتركه مرتبطًا بـ controller مُتخلَّص
  /// منه لإطار واحد (أخطاء في debug وربما انهيار).
  void _disposeControllerLater(CodeController controller) {
    void doDispose() {
      try {
        controller.dispose();
      } catch (_) {
        // تخلّص سابق أو حالة غير متوقعة — لا شيء نفعله.
      }
    }

    try {
      WidgetsBinding.instance.addPostFrameCallback((_) => doDispose());
      WidgetsBinding.instance.scheduleFrame();
    } catch (_) {
      doDispose();
    }
  }

  // ------------------------- مواكبة نظام الملفات -------------------------

  void _onFsChange(FsChange change) {
    switch (change.type) {
      case FsChangeType.renamed:
        final newPath = change.newPath;
        if (newPath != null) _applyRename(change.oldPath, newPath);
        break;
      case FsChangeType.deleted:
        _applyDelete(change.oldPath);
        break;
    }
  }

  bool _isAffected(String tabPath, String changedPath) =>
      p.equals(tabPath, changedPath) || p.isWithin(changedPath, tabPath);

  void _applyRename(String oldPath, String newPath) {
    if (state.tabs.every((t) => !_isAffected(t.path, oldPath))) return;

    final problems = _ref.read(problemsProvider.notifier);
    final updated = <EditorTab>[];
    final toDispose = <CodeController>[];
    String? activePath = state.activePath;
    String? closedActive;

    for (final tab in state.tabs) {
      if (!_isAffected(tab.path, oldPath)) {
        updated.add(tab);
        continue;
      }
      final movedPath =
          p.equals(tab.path, oldPath) ? newPath : p.join(newPath, p.relative(tab.path, from: oldPath));
      final moved = EditorTab(
        path: movedPath,
        name: p.basename(movedPath),
        controller: tab.controller,
        savedContent: tab.savedContent,
        isDirty: tab.isDirty,
      );
      problems.removeFile(tab.path);

      // تغيّر الامتداد يعني تغيّر لغة التلوين؛ نُغلق التبويب النظيف ليُعاد فتحه
      // بالتلوين الصحيح، ونُبقي المعدَّل (غير المحفوظ) كما هو حتى لا نمسّ عمله.
      if (moved.extension != tab.extension && !tab.isDirty) {
        toDispose.add(tab.controller);
        if (state.activePath == tab.path) closedActive = tab.path;
        continue;
      }

      updated.add(moved);
      if (state.activePath == tab.path) activePath = movedPath;
      if (moved.extension == '.dart') {
        _scheduleAnalysis(movedPath, moved.name, moved.controller, moved.controller.fullText);
      }
    }

    if (closedActive != null) activePath = updated.isNotEmpty ? updated.last.path : null;
    state = EditorTabsState(tabs: updated, activePath: activePath);
    for (final controller in toDispose) {
      _disposeControllerLater(controller);
    }
  }

  void _applyDelete(String deletedPath) {
    if (state.tabs.every((t) => !_isAffected(t.path, deletedPath))) return;

    final problems = _ref.read(problemsProvider.notifier);
    final console = _ref.read(consoleProvider.notifier);
    final kept = <EditorTab>[];
    final toDispose = <CodeController>[];

    for (final tab in state.tabs) {
      if (!_isAffected(tab.path, deletedPath)) {
        kept.add(tab);
      } else if (tab.isDirty) {
        kept.add(tab);
        console.log(
          'الملف ${tab.name} حُذف من القرص لكن عليه تعديلات غير محفوظة — أبقيتُ تبويبه '
          'مفتوحًا. احفظه لإعادة إنشائه، أو أغلقه لتجاهل التعديلات.',
          isError: true,
        );
      } else {
        problems.removeFile(tab.path);
        toDispose.add(tab.controller);
      }
    }

    var activePath = state.activePath;
    if (activePath != null && !kept.any((t) => t.path == activePath)) {
      activePath = kept.isNotEmpty ? kept.last.path : null;
    }
    state = EditorTabsState(tabs: kept, activePath: activePath);
    for (final controller in toDispose) {
      _disposeControllerLater(controller);
    }
  }

  // ------------------------- التنسيق التلقائي -------------------------

  /// يُنسِّق ملف dart في التبويب [tab] داخل المحرر (بدون حفظ). يعيد true إن
  /// تغيّر النص. لا يُغيِّر إلا المسافات والأسطر الفارغة (راجع DartFormatter
  /// لضمان السلامة)، ويحافظ على موضع المؤشر.
  bool _applyFormat(EditorTab tab, {bool announce = false}) {
    final console = _ref.read(consoleProvider.notifier);
    if (tab.extension != '.dart') {
      if (announce) console.log('التنسيق التلقائي يدعم ملفات .dart فقط.');
      return false;
    }
    final original = tab.controller.fullText;
    final result = DartFormatter.format(original);
    if (result.error != null) {
      console.log(result.error!, isError: true);
      return false;
    }
    if (!result.changed) {
      if (announce) console.log('الملف منسَّق بالفعل — لا تغييرات.');
      return false;
    }
    final oldOffset = tab.controller.selection.baseOffset;
    tab.controller.text = result.text;
    if (oldOffset >= 0) {
      final mapped = DartFormatter.mapOffset(original, result.text, oldOffset);
      final len = result.text.length;
      final off = mapped < 0 ? 0 : (mapped > len ? len : mapped);
      tab.controller.selection = TextSelection.collapsed(offset: off);
    }
    if (announce) console.log('تم تنسيق ${tab.name}.');
    return true;
  }

  /// تنسيق التبويب النشط يدويًا (زر التنسيق في شريط الاقتراحات).
  void formatActive() {
    final tab = state.activeTab;
    if (tab == null) return;
    _applyFormat(tab, announce: true);
  }

  Future<void> saveActive() async {
    final tab = state.activeTab;
    if (tab == null) return;
    await _saveTab(tab);
  }

  /// يحفظ تبويبًا محدَّدًا بمساره (يُستخدَم من حوار "حفظ وإغلاق").
  Future<void> savePath(String path) async {
    for (final tab in state.tabs) {
      if (tab.path == path) {
        await _saveTab(tab);
        return;
      }
    }
  }

  Future<void> saveAll() async {
    for (final tab in [...state.tabs]) {
      if (tab.isDirty) await _saveTab(tab);
    }
  }

  Future<void> _saveTab(EditorTab tab) async {
    try {
      // تنسيق تلقائي قبل الحفظ إن فُعِّل من الإعدادات (ملفات dart فقط).
      if (_ref.read(settingsProvider).formatOnSave) {
        _applyFormat(tab);
      }
      final content = tab.controller.fullText;
      await _ref.read(fileSystemRepositoryProvider).writeFile(tab.path, content);

      // نبحث بالـ controller لا بالمسار: قد يكون التبويب أُعيدت تسميته أثناء
      // الحفظ غير المتزامن.
      final index = state.tabs.indexWhere((t) => identical(t.controller, tab.controller));
      if (index != -1) {
        final current = state.tabs[index];
        final updatedTab = EditorTab(
          path: current.path,
          name: current.name,
          controller: current.controller,
          savedContent: content,
          isDirty: current.controller.fullText != content,
        );
        final tabs = [...state.tabs];
        tabs[index] = updatedTab;
        state = state.copyWith(tabs: tabs);
      }
      _ref.read(projectSearchProvider.notifier).indexFile(tab.path, tab.name, content);
      _ref.read(semanticServiceProvider).updateFileText(tab.path, content);
      _ref.read(consoleProvider.notifier).log('تم حفظ: ${tab.name}');
    } catch (e) {
      _ref.read(consoleProvider.notifier).log('تعذّر حفظ ${tab.name}: $e', isError: true);
    }
  }
}
