import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../logic/project_provider.dart';
import 'create_entry_dialog.dart';

/// قواعد اسم حزمة Dart المبسّطة (تكفي لهذا الاستخدام): حرف إنجليزي صغير أولًا،
/// ثم أحرف/أرقام/underscore. نرفض غير ذلك هنا بدل تمريره لـ pubspec.yaml
/// وترك المستخدم يكتشف الخطأ لاحقًا عند flutter pub get.
final RegExp _validProjectName = RegExp(r'^[a-z][a-z0-9_]*$');

/// يدير تدفّق "إنشاء مشروع جديد" الكامل: اسم صالح ← صلاحية التخزين ←
/// اختيار مكان الحفظ ← إنشاء البنية الفعلية عبر [ProjectNotifier.createNewProject].
///
/// موضوعة كدالة مستقلة (بدل تكرارها) لأنها تُستدعى من أكثر من مكان: شاشة
/// الترحيب الأولى، وشجرة المشروع عندما تكون فارغة.
Future<void> runCreateNewProjectFlow(BuildContext context, WidgetRef ref) async {
  final name = await showCreateEntryDialog(
    context,
    title: 'مشروع جديد',
    hint: 'my_app (أحرف إنجليزية صغيرة وأرقام و _ فقط)',
  );
  if (name == null || name.isEmpty) return;

  if (!_validProjectName.hasMatch(name)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اسم غير صالح: يجب أن يبدأ بحرف إنجليزي صغير ويحتوي أحرفًا/أرقامًا/_ فقط'),
        ),
      );
    }
    return;
  }

  final granted = await ref.read(projectProvider.notifier).ensureStoragePermission();
  if (!granted) return; // السبب مُسجَّل بالفعل في الكونسول وكـ errorMessage

  if (!context.mounted) return;
  final parentPath = await FilePicker.platform.getDirectoryPath(
    dialogTitle: 'اختر مكان حفظ المشروع الجديد',
  );
  if (parentPath == null) return; // المستخدم ألغى الاختيار

  await ref.read(projectProvider.notifier).createNewProject(parentPath: parentPath, projectName: name);
}
