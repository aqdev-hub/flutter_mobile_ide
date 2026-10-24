import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../project_explorer/data/models/file_node.dart';
import '../../project_explorer/logic/project_provider.dart';
import '../../semantic/logic/semantic_checker.dart';
import '../../semantic/logic/semantic_provider.dart';
import 'problems_analyzer.dart';

final problemsProvider =
    StateNotifierProvider<ProblemsNotifier, Map<String, List<ProblemItem>>>((ref) {
  return ProblemsNotifier(ref);
});

/// يحتفظ بمشاكل كل ملف dart مفتوح حاليًا (مفتاحها المسار الكامل). يُستدعى
/// من [EditorTabsNotifier] عند كل تغيير في محتوى أي تبويب (وعند فتح ملف
/// لأول مرة) — لكن التحليل الفعلي **مُؤجَّل (debounced)** هنا داخل
/// الـ Notifier نفسه حتى لا يُعاد تشغيل الاستخراج على كل ضغطة مفتاح فعليًا،
/// بل بعد توقّف قصير عن الكتابة (600ms) — توازن بين "شعور حيّ" وتكلفة أداء
/// معقولة على الهاتف.
///
/// طبقات التحليل: الصياغة الرسمية، ثم (إن كانت الصياغة سليمة) التحقق الدلالي
/// مقابل فهرس المشروع، ثم قدرة المعاينة. النتيجة تُهمَل إن وصل نص أحدث للملف
/// أثناء انتظار التحليل (فلا تظهر مشاكل نسخة قديمة من الكود).
class ProblemsNotifier extends StateNotifier<Map<String, List<ProblemItem>>> {
  final Ref _ref;
  ProblemsNotifier(this._ref) : super({});

  static const _debounceDuration = Duration(milliseconds: 600);
  final Map<String, Timer> _debounceTimers = {};
  final Map<String, String> _pendingContent = {};

  void scheduleAnalysis(
    String path,
    String fileName,
    String content, {
    void Function(List<ProblemItem> problems)? onAnalyzed,
  }) {
    _debounceTimers[path]?.cancel();
    _pendingContent[path] = content;
    _debounceTimers[path] = Timer(_debounceDuration, () async {
      var problems = ProblemsAnalyzer.analyzeDartFile(path, fileName, content);
      final hasSyntaxErrors = problems.any(
        (x) => x.category == ProblemCategory.syntax && x.severity == ProblemSeverity.error,
      );
      if (!hasSyntaxErrors) {
        problems = [...problems, ...await _semanticProblems(path, fileName, content)];
      }
      if (!mounted || _pendingContent[path] != content) return; // نص أحدث وصل أثناء التحليل
      state = {...state, path: problems};
      onAnalyzed?.call(problems);
    });
  }

  Future<List<ProblemItem>> _semanticProblems(String path, String fileName, String content) async {
    final root = _ref.read(projectProvider).root;
    if (root == null) return const [];
    try {
      final diagnostics = await _ref.read(semanticServiceProvider).check(
            rootPath: root.path,
            dartFiles: _dartFilesUnderLib(root),
            filePath: path,
            content: content,
          );
      return [for (final d in diagnostics) _toProblem(path, fileName, d)];
    } catch (e) {
      return [
        ProblemItem(
          filePath: path,
          fileName: fileName,
          message: 'تعذّر تشغيل التحقق الدلالي على هذا الملف: $e',
          severity: ProblemSeverity.info,
          category: ProblemCategory.semantic,
        ),
      ];
    }
  }

  List<String> _dartFilesUnderLib(FileNode root) {
    final libDir = p.join(root.path, 'lib');
    final out = <String>[];
    void walk(FileNode node) {
      if (node.isDirectory) {
        for (final child in node.children) {
          walk(child);
        }
        return;
      }
      if (node.extension == '.dart' && p.isWithin(libDir, node.path)) out.add(node.path);
    }

    walk(root);
    return out;
  }

  ProblemItem _toProblem(String path, String fileName, SemanticDiagnostic d) {
    return ProblemItem(
      filePath: path,
      fileName: fileName,
      line: d.line,
      column: d.column,
      offset: d.offset,
      length: d.length,
      message: d.message,
      detail: d.hint,
      severity: switch (d.severity) {
        SemanticSeverity.error => ProblemSeverity.error,
        SemanticSeverity.warning => ProblemSeverity.warning,
        SemanticSeverity.info => ProblemSeverity.info,
      },
      category: ProblemCategory.semantic,
    );
  }

  /// يُستدعى عند إغلاق تبويب حتى لا تبقى مشاكل ملف لم يعد مفتوحًا ظاهرة في
  /// اللوحة (تظل صحيحة على القرص لكنها لم تعد "قيد التحرير" فعليًا الآن).
  void removeFile(String path) {
    _debounceTimers.remove(path)?.cancel();
    _pendingContent.remove(path);
    if (state.containsKey(path)) {
      final updated = {...state}..remove(path);
      state = updated;
    }
  }

  /// يمسح كل المشاكل المُسجَّلة دفعة واحدة — يُستدعى عند تبديل المشروع
  /// بالكامل (وليس مجرد تحديثه) من [EditorTabsNotifier.closeAll], حتى لا
  /// تبقى مشاكل ملفات تخصّ مشروعًا سابقًا معروضة في اللوحة بعد الانتقال
  /// لمشروع مختلف تمامًا.
  void clearAll() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    _pendingContent.clear();
    if (state.isNotEmpty) {
      state = {};
    }
  }

  @override
  void dispose() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    super.dispose();
  }
}
