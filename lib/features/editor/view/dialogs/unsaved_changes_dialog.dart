import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/editor_tab.dart';
import '../../logic/editor_tabs_provider.dart';

enum UnsavedChoice { save, discard, cancel }

/// حوار تأكيد عند إغلاق تبويب عليه تعديلات غير محفوظة.
Future<UnsavedChoice> showUnsavedChangesDialog(BuildContext context, {required String fileName}) async {
  final result = await showDialog<UnsavedChoice>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('تعديلات غير محفوظة'),
      content: Text('الملف "$fileName" عليه تعديلات لم تُحفظ بعد. ماذا تريد أن تفعل؟'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, UnsavedChoice.cancel),
          child: const Text('إلغاء'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, UnsavedChoice.discard),
          child: const Text('تجاهل التعديلات', style: TextStyle(color: Colors.red)),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, UnsavedChoice.save),
          child: const Text('حفظ وإغلاق'),
        ),
      ],
    ),
  );
  return result ?? UnsavedChoice.cancel;
}

/// يُغلق التبويب مع حماية التعديلات غير المحفوظة: تبويب نظيف يُغلق مباشرة،
/// والمعدَّل يسأل المستخدم أولًا (حفظ/تجاهل/إلغاء). إن فشل الحفظ يبقى التبويب
/// مفتوحًا (والسبب في الكونسول) بدل أن تضيع التعديلات.
Future<void> requestCloseTab(BuildContext context, WidgetRef ref, String path) async {
  final notifier = ref.read(editorTabsProvider.notifier);

  EditorTab? findTab() {
    for (final t in ref.read(editorTabsProvider).tabs) {
      if (t.path == path) return t;
    }
    return null;
  }

  final tab = findTab();
  if (tab == null) return;
  if (!tab.isDirty) {
    notifier.closeTab(path);
    return;
  }

  final choice = await showUnsavedChangesDialog(context, fileName: tab.name);
  switch (choice) {
    case UnsavedChoice.cancel:
      return;
    case UnsavedChoice.discard:
      notifier.closeTab(path);
      return;
    case UnsavedChoice.save:
      await notifier.savePath(path);
      final after = findTab();
      if (after != null && !after.isDirty) notifier.closeTab(path);
      return;
  }
}
