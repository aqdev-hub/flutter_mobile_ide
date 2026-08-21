import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../project_explorer/view/widgets/file_icon.dart';
import '../../../project_explorer/data/models/file_node.dart';
import '../../logic/editor_tabs_provider.dart';

class EditorTabBar extends ConsumerWidget {
  const EditorTabBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabsState = ref.watch(editorTabsProvider);
    if (tabsState.tabs.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      height: 38,
      decoration: const BoxDecoration(
        color: IdeColors.darkInactiveTab,
        border: Border(bottom: BorderSide(color: IdeColors.darkBorder)),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final tab in tabsState.tabs)
            _TabChip(
              path: tab.path,
              name: tab.name,
              isDirty: tab.isDirty,
              isActive: tab.path == tabsState.activePath,
              extension: tab.extension,
            ),
        ],
      ),
    );
  }
}

class _TabChip extends ConsumerWidget {
  final String path;
  final String name;
  final bool isDirty;
  final bool isActive;
  final String extension;

  const _TabChip({
    required this.path,
    required this.name,
    required this.isDirty,
    required this.isActive,
    required this.extension,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => ref.read(editorTabsProvider.notifier).setActive(path),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isActive ? IdeColors.darkActiveTab : Colors.transparent,
          border: Border(
            right: const BorderSide(color: IdeColors.darkBorder),
            top: BorderSide(color: isActive ? IdeColors.accentBlue : Colors.transparent, width: 2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FileIcon(node: FileNode(path: path, name: name, type: FileNodeType.file)),
            const SizedBox(width: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 12,
                    color: isActive ? Colors.white : Colors.grey.shade400,
                  ),
                ),
                if (isDirty) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.circle, size: 7, color: Colors.white70),
                ],
              ],
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: () => ref.read(editorTabsProvider.notifier).closeTab(path),
              child: const Icon(Icons.close, size: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
