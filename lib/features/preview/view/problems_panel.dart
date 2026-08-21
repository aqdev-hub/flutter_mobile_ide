import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../editor/logic/editor_tabs_provider.dart';
import '../logic/problems_analyzer.dart';
import '../logic/problems_provider.dart';

/// يعرض كل المشاكل المكتشَفة في الملفات المفتوحة حاليًا. راجع التنويه أسفل
/// اللوحة، وتوثيق [ProblemsAnalyzer] لحدود هذا التحليل بالتفصيل.
class ProblemsPanel extends ConsumerWidget {
  const ProblemsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final problemsMap = ref.watch(problemsProvider);
    final allProblems = <ProblemItem>[for (final list in problemsMap.values) ...list]
      ..sort((a, b) {
        final byFile = a.fileName.compareTo(b.fileName);
        if (byFile != 0) return byFile;
        return (a.line ?? 0).compareTo(b.line ?? 0);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: allProblems.isEmpty
              ? const Center(
                  child: Text(
                    'لا توجد مشاكل معروفة في الملفات المفتوحة',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: allProblems.length,
                  itemBuilder: (context, index) {
                    final problem = allProblems[index];
                    final isError = problem.severity == ProblemSeverity.error;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isError ? Icons.error : Icons.warning_amber,
                        size: 16,
                        color: isError ? IdeColors.stopRed : IdeColors.warningYellow,
                      ),
                      title: Text(
                        problem.message,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        problem.line != null ? '${problem.fileName} • السطر ${problem.line}' : problem.fileName,
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                      onTap: () => ref.read(editorTabsProvider.notifier).openFile(problem.filePath, problem.fileName),
                    );
                  },
                ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: IdeColors.darkBorder))),
          child: const Text(
            'يعرض هذا التبويب أخطاء المُفسِّر الخاص بالمعاينة تحديدًا (نطاق Dart جزئي وموثَّق) — وليس محلّل Dart رسميًا كاملًا.',
            style: TextStyle(fontSize: 9, color: Colors.grey),
          ),
        ),
      ],
    );
  }
}
