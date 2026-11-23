import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../project_explorer/logic/project_provider.dart';
import '../../settings/logic/settings_provider.dart';
import '../logic/git_provider.dart';

/// لوحة Git في الشريط الجانبي: النطاق المحلي فقط حاليًا (status/stage/
/// commit) — لا push/pull/clone بعد، راجع GitService للحدود والتنبيه
/// التقني حول نضج مكتبة git_on_dart المستخدَمة.
class GitPanel extends ConsumerWidget {
  const GitPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectState = ref.watch(projectProvider);
    final gitState = ref.watch(gitProvider);

    if (!projectState.hasProject) {
      return const Center(
        child: Text('افتح مشروعًا أولًا', style: TextStyle(color: Colors.grey, fontSize: 12)),
      );
    }

    return switch (gitState.status) {
      GitPanelStatus.noProject => const Center(
          child: Text('افتح مشروعًا أولًا', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ),
      GitPanelStatus.loading => const Center(child: CircularProgressIndicator()),
      GitPanelStatus.notARepo => const _NotARepoView(),
      GitPanelStatus.error => _ErrorView(message: gitState.errorMessage ?? 'خطأ غير معروف'),
      GitPanelStatus.ready => const _ReadyView(),
    };
  }
}

class _NotARepoView extends ConsumerWidget {
  const _NotARepoView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.source_outlined, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'هذا المجلد ليس مستودع Git بعد',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => ref.read(gitProvider.notifier).initRepository(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('تهيئة مستودع Git'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends ConsumerWidget {
  final String message;
  const _ErrorView({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 32, color: IdeColors.stopRed),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => ref.read(gitProvider.notifier).refreshStatus(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReadyView extends ConsumerStatefulWidget {
  const _ReadyView();

  @override
  ConsumerState<_ReadyView> createState() => _ReadyViewState();
}

class _ReadyViewState extends ConsumerState<_ReadyView> {
  final _messageController = TextEditingController();
  bool _committing = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    final settings = ref.read(settingsProvider);
    setState(() => _committing = true);
    final success = await ref.read(gitProvider.notifier).commit(
          _messageController.text,
          authorName: settings.gitAuthorName,
          authorEmail: settings.gitAuthorEmail,
        );
    if (success) _messageController.clear();
    if (mounted) setState(() => _committing = false);
  }

  @override
  Widget build(BuildContext context) {
    final gitState = ref.watch(gitProvider);
    final settings = ref.watch(settingsProvider);
    final identityMissing = settings.gitAuthorName.trim().isEmpty || settings.gitAuthorEmail.trim().isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: IdeColors.darkBorder))),
          child: Row(
            children: [
              const Expanded(
                child: Text('التغييرات', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
              if (gitState.modifiedFiles.isNotEmpty)
                TextButton(
                  onPressed: () => ref.read(gitProvider.notifier).stageAll(),
                  child: const Text('إضافة الكل', style: TextStyle(fontSize: 11)),
                ),
              IconButton(
                tooltip: 'تحديث',
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: () => ref.read(gitProvider.notifier).refreshStatus(),
              ),
            ],
          ),
        ),
        if (identityMissing)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            color: IdeColors.warningYellow.withValues(alpha: 0.12),
            child: const Text(
              'عرّف اسمك وبريدك الإلكتروني من الإعدادات قبل تنفيذ أي commit.',
              style: TextStyle(fontSize: 11, color: IdeColors.warningYellow),
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              if (gitState.stagedFiles.isNotEmpty) ...[
                const _SectionHeader(title: 'جاهزة للالتزام (Staged)'),
                for (final path in gitState.stagedFiles)
                  _FileRow(path: path, icon: Icons.check_circle, iconColor: IdeColors.runGreen),
              ],
              if (gitState.modifiedFiles.isNotEmpty) ...[
                const _SectionHeader(title: 'تغييرات غير مُضافة'),
                for (final path in gitState.modifiedFiles)
                  _FileRow(
                    path: path,
                    icon: Icons.circle_outlined,
                    iconColor: Colors.orange,
                    trailing: IconButton(
                      tooltip: 'إضافة (stage)',
                      icon: const Icon(Icons.add, size: 16),
                      onPressed: () => ref.read(gitProvider.notifier).stageFile(path),
                    ),
                  ),
              ],
              if (gitState.stagedFiles.isEmpty && gitState.modifiedFiles.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text('لا توجد تغييرات — كل شيء محفوظ ومطابق لآخر commit',
                        style: TextStyle(fontSize: 11, color: Colors.grey), textAlign: TextAlign.center),
                  ),
                ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: IdeColors.darkBorder))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _messageController,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'رسالة الالتزام (commit message)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: (_committing || gitState.stagedFiles.isEmpty) ? null : _commit,
                icon: _committing
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check, size: 18),
                label: Text(gitState.stagedFiles.isEmpty ? 'لا توجد ملفات جاهزة' : 'التزام (Commit)'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
    );
  }
}

class _FileRow extends StatelessWidget {
  final String path;
  final IconData icon;
  final Color iconColor;
  final Widget? trailing;

  const _FileRow({required this.path, required this.icon, required this.iconColor, this.trailing});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 16, color: iconColor),
      title: Text(path, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
      trailing: trailing,
    );
  }
}
