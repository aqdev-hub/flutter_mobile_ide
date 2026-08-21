import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../editor/logic/editor_tabs_provider.dart';
import '../../data/models/file_node.dart';
import '../../logic/project_provider.dart';
import '../dialogs/create_entry_dialog.dart';
import '../dialogs/rename_dialog.dart';
import 'file_icon.dart';

enum _NodeAction { newFile, newFolder, rename, delete, copy, cut, paste }

class TreeNodeTile extends ConsumerWidget {
  final FileNode node;
  final int depth;
  final String parentPath;

  const TreeNodeTile({
    super.key,
    required this.node,
    required this.depth,
    required this.parentPath,
  });

  static const double _indentPerLevel = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasClipboard = ref.watch(projectProvider.select((s) => s.clipboard != null));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => _onTap(context, ref),
          child: Padding(
            padding: EdgeInsets.only(
              left: 8 + depth * _indentPerLevel,
              right: 4,
              top: 5,
              bottom: 5,
            ),
            child: Row(
              children: [
                if (node.isDirectory)
                  Icon(
                    node.isExpanded ? Icons.arrow_drop_down : Icons.arrow_right,
                    size: 18,
                    color: Colors.grey,
                  )
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 2),
                FileIcon(node: node),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    node.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                PopupMenuButton<_NodeAction>(
                  icon: const Icon(Icons.more_vert, size: 16),
                  padding: EdgeInsets.zero,
                  onSelected: (action) => _handleAction(context, ref, action),
                  itemBuilder: (context) => [
                    if (node.isDirectory) ...[
                      const PopupMenuItem(value: _NodeAction.newFile, child: Text('ملف جديد')),
                      const PopupMenuItem(value: _NodeAction.newFolder, child: Text('مجلد جديد')),
                      if (hasClipboard)
                        const PopupMenuItem(value: _NodeAction.paste, child: Text('لصق هنا')),
                      const PopupMenuDivider(),
                    ],
                    const PopupMenuItem(value: _NodeAction.rename, child: Text('إعادة تسمية')),
                    const PopupMenuItem(value: _NodeAction.copy, child: Text('نسخ')),
                    const PopupMenuItem(value: _NodeAction.cut, child: Text('قص')),
                    const PopupMenuItem(value: _NodeAction.delete, child: Text('حذف')),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (node.isDirectory && node.isExpanded)
          for (final child in node.children)
            TreeNodeTile(node: child, depth: depth + 1, parentPath: node.path),
      ],
    );
  }

  void _onTap(BuildContext context, WidgetRef ref) {
    if (node.isDirectory) {
      ref.read(projectProvider.notifier).toggleExpanded(node.path);
    } else {
      ref.read(editorTabsProvider.notifier).openFile(node.path, node.name);
    }
  }

  Future<void> _handleAction(BuildContext context, WidgetRef ref, _NodeAction action) async {
    final notifier = ref.read(projectProvider.notifier);
    switch (action) {
      case _NodeAction.newFile:
        final name = await showCreateEntryDialog(context, title: 'ملف جديد', hint: 'main.dart');
        if (name != null && name.isNotEmpty) notifier.createFile(node.path, name);
        break;
      case _NodeAction.newFolder:
        final name = await showCreateEntryDialog(context, title: 'مجلد جديد', hint: 'widgets');
        if (name != null && name.isNotEmpty) notifier.createDirectory(node.path, name);
        break;
      case _NodeAction.rename:
        final name = await showRenameDialog(context, currentName: node.name);
        if (name != null && name.isNotEmpty) notifier.rename(node.path, name);
        break;
      case _NodeAction.delete:
        final confirmed = await _confirmDelete(context, node.name);
        if (confirmed) notifier.delete(node.path, isDirectory: node.isDirectory);
        break;
      case _NodeAction.copy:
        notifier.copyToClipboard(node.path, isDirectory: node.isDirectory);
        break;
      case _NodeAction.cut:
        notifier.cutToClipboard(node.path, isDirectory: node.isDirectory);
        break;
      case _NodeAction.paste:
        notifier.pasteInto(node.path);
        break;
    }
  }

  Future<bool> _confirmDelete(BuildContext context, String name) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل تريد حذف "$name"؟ لا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
