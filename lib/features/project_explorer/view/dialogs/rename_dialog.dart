import 'package:flutter/material.dart';

Future<String?> showRenameDialog(BuildContext context, {required String currentName}) {
  final controller = TextEditingController(text: currentName);
  final dotIndex = currentName.contains('.') ? currentName.lastIndexOf('.') : currentName.length;
  // نحدد اسم الملف بدون الامتداد مسبقًا، حتى يكتب المستخدم الاسم الجديد مباشرة
  // دون الحاجة لمسح الامتداد يدويًا في كل مرة — سلوك مألوف من محررات سطح المكتب.
  controller.selection = TextSelection(baseOffset: 0, extentOffset: dotIndex);

  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('إعادة تسمية'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(border: OutlineInputBorder()),
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('حفظ'),
        ),
      ],
    ),
  );
}
