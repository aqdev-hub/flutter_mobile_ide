import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'problems_analyzer.dart';

final problemsProvider =
    StateNotifierProvider<ProblemsNotifier, Map<String, List<ProblemItem>>>((ref) {
  return ProblemsNotifier();
});

/// يحتفظ بمشاكل كل ملف dart مفتوح حاليًا (مفتاحها المسار الكامل). يُستدعى
/// من [EditorTabsNotifier] عند كل تغيير في محتوى أي تبويب (وعند فتح ملف
/// لأول مرة) — لكن التحليل الفعلي **مُؤجَّل (debounced)** هنا داخل
/// الـ Notifier نفسه حتى لا يُعاد تشغيل الاستخراج على كل ضغطة مفتاح فعليًا،
/// بل بعد توقّف قصير عن الكتابة (600ms) — توازن بين "شعور حيّ" وتكلفة أداء
/// معقولة على الهاتف.
class ProblemsNotifier extends StateNotifier<Map<String, List<ProblemItem>>> {
  ProblemsNotifier() : super({});

  static const _debounceDuration = Duration(milliseconds: 600);
  final Map<String, Timer> _debounceTimers = {};

  void scheduleAnalysis(String path, String fileName, String content) {
    _debounceTimers[path]?.cancel();
    _debounceTimers[path] = Timer(_debounceDuration, () {
      final problems = ProblemsAnalyzer.analyzeDartFile(path, fileName, content);
      state = {...state, path: problems};
    });
  }

  /// يُستدعى عند إغلاق تبويب حتى لا تبقى مشاكل ملف لم يعد مفتوحًا ظاهرة في
  /// اللوحة (تظل صحيحة على القرص لكنها لم تعد "قيد التحرير" فعليًا الآن).
  void removeFile(String path) {
    _debounceTimers.remove(path)?.cancel();
    if (state.containsKey(path)) {
      final updated = {...state}..remove(path);
      state = updated;
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
