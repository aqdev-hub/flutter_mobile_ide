import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../editor/logic/editor_tabs_provider.dart';
import '../logic/problems_analyzer.dart';
import '../logic/problems_provider.dart';

/// يعرض كل المشاكل المكتشَفة في الملفات المفتوحة حاليًا، مع التفريق بين:
/// أخطاء صياغة حقيقية (محلل Dart الرسمي) وقيود المعاينة. راجع التنويه أسفل
/// اللوحة، وتوثيق [ProblemsAnalyzer] لحدود هذا التحليل بالتفصيل.
class ProblemsPanel extends ConsumerWidget {
  const ProblemsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final problemsMap = ref.watch(problemsProvider);
    final allProblems = <ProblemItem>[for (final list in problemsMap.values) ...list]
      ..sort((a, b) {
        final bySeverity = a.severity.index.compareTo(b.severity.index);
        if (bySeverity != 0) return bySeverity;
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
                  itemBuilder: (context, index) => _ProblemTile(problem: allProblems[index]),
                ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: IdeColors.darkBorder))),
          child: const Text(
            'أخطاء "صياغة" = أكّدها محلل Dart الرسمي. "قيد في المعاينة" = الصياغة سليمة لكن المُفسِّر الحالي لا يدعمها. '
            'لا يوجد بعد فحص للأنواع والأسماء غير المعرَّفة.',
            style: TextStyle(fontSize: 9, color: Colors.grey),
          ),
        ),
      ],
    );
  }
}

class _ProblemTile extends ConsumerWidget {
  final ProblemItem problem;
  const _ProblemTile({required this.problem});

  (IconData, Color) get _icon => switch (problem.severity) {
        ProblemSeverity.error => (Icons.error, IdeColors.stopRed),
        ProblemSeverity.warning => (Icons.warning_amber, IdeColors.warningYellow),
        ProblemSeverity.info => (Icons.info_outline, IdeColors.accentBlue),
      };

  String get _location {
    final line = problem.line;
    if (line == null) return problem.fileName;
    final column = problem.column;
    return column == null
        ? '${problem.fileName} • السطر $line'
        : '${problem.fileName} • السطر $line:$column';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (icon, color) = _icon;
    final categoryLabel = problem.category == ProblemCategory.syntax ? 'صياغة' : 'قيد في المعاينة';

    return ListTile(
      dense: true,
      leading: Icon(icon, size: 16, color: color),
      title: Text(
        problem.message,
        style: const TextStyle(fontSize: 12),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '$_location • $categoryLabel${problem.detail != null ? '\n${problem.detail}' : ''}',
        style: const TextStyle(fontSize: 10, color: Colors.grey),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () {
        final notifier = ref.read(editorTabsProvider.notifier);
        final line = problem.line;
        if (line != null) {
          notifier.revealPosition(problem.filePath, problem.fileName, lineNumber: line);
        } else {
          notifier.openFile(problem.filePath, problem.fileName);
        }
      },
    );
  }
}
