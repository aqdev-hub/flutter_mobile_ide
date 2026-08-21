import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../console/logic/console_provider.dart';
import '../../logic/project_provider.dart';
import '../../logic/pubspec_dependency_editor.dart';

/// حوار بسيط لإدارة تبعيات pubspec.yaml (إضافة/تعديل رقم إصدار/حذف) دون
/// مغادرة التطبيق — بنفس فكرة "Project Structure > Dependencies" في
/// Android Studio، لكن مبسّطة بحسب حدود [PubspecDependencyEditor].
Future<void> showPubspecDependenciesDialog(BuildContext context, WidgetRef ref) async {
  final project = ref.read(projectProvider);
  final root = project.root;
  if (root == null) return;

  final repo = ref.read(fileSystemRepositoryProvider);
  final pubspecPath = '${root.path}/pubspec.yaml';

  String content;
  try {
    content = await repo.readFile(pubspecPath);
  } catch (e) {
    ref.read(consoleProvider.notifier).log('تعذّر قراءة pubspec.yaml: $e', isError: true);
    return;
  }

  final parsed = PubspecDependencyEditor.parse(content);
  if (!parsed.found) {
    ref.read(consoleProvider.notifier).log('لم يتم العثور على قسم dependencies داخل pubspec.yaml', isError: true);
    return;
  }

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _PubspecDependenciesDialogContent(
      pubspecPath: pubspecPath,
      originalContent: content,
      parsed: parsed,
      ref: ref,
    ),
  );
}

class _EditableDepRow {
  final TextEditingController nameController;
  final TextEditingController versionController;
  final bool isEditable;
  bool markedForDeletion = false;

  _EditableDepRow({required String name, required String? version, required this.isEditable})
      : nameController = TextEditingController(text: name),
        versionController = TextEditingController(text: version ?? '');
}

class _PubspecDependenciesDialogContent extends StatefulWidget {
  final String pubspecPath;
  final String originalContent;
  final PubspecParseResult parsed;
  final WidgetRef ref;

  const _PubspecDependenciesDialogContent({
    required this.pubspecPath,
    required this.originalContent,
    required this.parsed,
    required this.ref,
  });

  @override
  State<_PubspecDependenciesDialogContent> createState() => _PubspecDependenciesDialogContentState();
}

class _PubspecDependenciesDialogContentState extends State<_PubspecDependenciesDialogContent> {
  late List<_EditableDepRow> _rows;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _rows = widget.parsed.dependencies
        .map((d) => _EditableDepRow(name: d.name, version: d.version, isEditable: d.isEditable))
        .toList();
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.nameController.dispose();
      row.versionController.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    setState(() {
      _rows.add(_EditableDepRow(name: '', version: '^1.0.0', isEditable: true));
    });
  }

  Future<void> _save() async {
    final activeEditable = _rows.where((r) => r.isEditable && !r.markedForDeletion).toList();
    for (final row in activeEditable) {
      if (row.nameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اسم الحزمة لا يمكن أن يكون فارغًا')),
        );
        return;
      }
    }

    setState(() => _saving = true);

    final updatedSimpleDeps = activeEditable
        .map((r) => PubspecDependency(
              name: r.nameController.text.trim(),
              version: r.versionController.text.trim().isEmpty ? 'any' : r.versionController.text.trim(),
            ))
        .toList();

    final newContent = PubspecDependencyEditor.rebuild(widget.originalContent, widget.parsed, updatedSimpleDeps);

    try {
      final repo = widget.ref.read(fileSystemRepositoryProvider);
      await repo.writeFile(widget.pubspecPath, newContent);
      widget.ref
          .read(consoleProvider.notifier)
          .log('تم تحديث pubspec.yaml — نفّذ flutter pub get لتحميل أي حزمة جديدة.');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      widget.ref.read(consoleProvider.notifier).log('تعذّر حفظ pubspec.yaml: $e', isError: true);
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('إدارة الحزم (pubspec.yaml)'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'تعديل التبعيات البسيطة (name: version) فقط. التبعيات المعقّدة'
              ' (sdk/git/path) تظهر للقراءة فقط.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _rows.length,
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  if (row.markedForDeletion) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: row.nameController,
                            enabled: row.isEditable,
                            decoration: const InputDecoration(hintText: 'اسم الحزمة', isDense: true),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: row.versionController,
                            enabled: row.isEditable,
                            decoration: const InputDecoration(hintText: '^1.0.0', isDense: true),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              size: 18, color: row.isEditable ? null : Colors.grey.shade300),
                          onPressed: row.isEditable ? () => setState(() => row.markedForDeletion = true) : null,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addRow,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('إضافة حزمة'),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('حفظ'),
        ),
      ],
    );
  }
}
