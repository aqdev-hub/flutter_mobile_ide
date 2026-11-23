import 'package:flutter_code_editor/flutter_code_editor.dart';

/// يمثّل ملفًا واحدًا مفتوحًا في تبويب. يحمل CodeController الخاص به
/// (بدل مشاركة تحكم واحد بين كل التبويبات) حتى يحتفظ كل ملف بحالة تحرير
/// مستقلة: موضع المؤشر، سجلّ undo/redo، والتحديد — تمامًا كما في VS Code
/// عندما تتنقل بين تبويبات مفتوحة دون أن يفقد كل تبويب مكانه.
class EditorTab {
  final String path;
  final String name;
  final CodeController controller;
  final String savedContent;
  bool isDirty;

  EditorTab({
    required this.path,
    required this.name,
    required this.controller,
    required this.savedContent,
    this.isDirty = false,
  });

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot == -1 ? '' : name.substring(dot);
  }
}
