import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/recent_project.dart';
import '../../logic/project_provider.dart';
import '../dialogs/create_project_dialog.dart';
import 'tree_node_tile.dart';

/// شجرة المشروع الكاملة: تعرض العقدة الجذرية وأبناءها بشكل هرمي متكرر.
/// عندما لا يوجد مشروع مفتوح، تعمل كـ"شاشة مشاريع حديثة" فعليًا: قائمة آخر
/// المشاريع (مع إمكانية الحذف من القائمة) + خياري "فتح" و"إنشاء مشروع جديد".
class FileTreeView extends ConsumerWidget {
  const FileTreeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final projectState = ref.watch(projectProvider);

    if (projectState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (!projectState.hasProject) {
      return _EmptyProjectState(recentProjects: projectState.recentProjects);
    }

    final root = projectState.root!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: IdeColors.darkBorder)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  root.name.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
              ),
              IconButton(
                tooltip: 'مشاريع أخرى',
                icon: const Icon(Icons.folder_shared_outlined, size: 16),
                onPressed: () => ref.read(projectProvider.notifier).closeCurrentProjectView(),
              ),
              IconButton(
                tooltip: 'تحديث المشروع',
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: () => ref.read(projectProvider.notifier).refreshProject(),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 4),
            children: [
              for (final child in root.children)
                TreeNodeTile(node: child, depth: 0, parentPath: root.path),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyProjectState extends ConsumerWidget {
  final List<RecentProject> recentProjects;
  const _EmptyProjectState({required this.recentProjects});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.folder_open, size: 40, color: Colors.grey),
          const SizedBox(height: 12),
          const Text(
            'لا يوجد مشروع مفتوح',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => ref.read(projectProvider.notifier).openProjectFromDevice(),
            icon: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: const Text('فتح مجلد مشروع'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => runCreateNewProjectFlow(context, ref),
            icon: const Icon(Icons.add_box_outlined, size: 18),
            label: const Text('إنشاء مشروع جديد'),
          ),
          if (recentProjects.isNotEmpty) ...[
            const SizedBox(height: 24),
            const Align(
              alignment: Alignment.centerRight,
              child: Text('مشاريع حديثة', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 6),
            for (final project in recentProjects) _RecentProjectTile(project: project),
          ],
        ],
      ),
    );
  }
}

class _RecentProjectTile extends ConsumerWidget {
  final RecentProject project;
  const _RecentProjectTile({required this.project});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.history, size: 18),
        title: Text(project.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
        subtitle: Text(project.path, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10)),
        trailing: IconButton(
          tooltip: 'إزالة من القائمة',
          icon: const Icon(Icons.close, size: 16),
          onPressed: () => ref.read(projectProvider.notifier).removeFromRecent(project.path),
        ),
        onTap: () => ref.read(projectProvider.notifier).openProjectAtPath(project.path),
      ),
    );
  }
}
