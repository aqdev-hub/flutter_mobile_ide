import 'package:flutter/material.dart';

/// حوار بسيط لإدخال اسم ملف/مجلد جديد. مُستخرج كدالة مستقلة (بدل تكراره
/// مرتين لكل من "ملف جديد" و"مجلد جديد") لأن الاختلاف بينهما هو فقط
/// العنوان والنص التوضيحي.
Future<String?> showCreateEntryDialog(
  BuildContext context, {
  required String title,
  required String hint,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('إنشاء'),
        ),
      ],
    ),
  );
}
