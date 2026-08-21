import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/atom-one-light.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../settings/logic/settings_provider.dart';
import '../../data/models/editor_tab.dart';

/// يغلّف [CodeField] من flutter_code_editor بالثيم والخط المناسبين.
///
/// نستخدم مكتبة جاهزة بدل بناء محرر نصوص من الصفر لأنها توفّر افتراضيًا:
/// أرقام أسطر، auto-indent، auto-close للأقواس/الاقتباسات، تحديد متعدد،
/// و undo/redo — وكلها متطلبات صريحة، وإعادة بنائها يدويًا كان سيستهلك
/// جزءًا كبيرًا من الوقت لتكرار سلوك موجود وموثوق أصلًا.
///
/// **إصلاح**: `expands: true` مضافة هنا لأن [CodeField] بدونها لا يلتزم
/// بالمساحة الرأسية المتاحة من والده (`Expanded` في app_shell.dart) بشكل
/// يسمح بالتمرير الداخلي الصحيح لكود يتجاوز ارتفاع الشاشة — وهو ما كان
/// يمنع التمرير رأسيًا في ملفات متوسطة/كبيرة الحجم. هذا الحل يفترض أن أصل
/// الودجت يمنحها ارتفاعًا محدودًا (bounded)، وهو محقَّق فعليًا هنا لأن
/// CodeEditorWidget دائمًا داخل Expanded. كما هو موثَّق في README (قسم 5)،
/// اسم/سلوك هذه الخاصية بالضبط قد يحتاج تأكيدًا مقابل الإصدار المثبَّت
/// فعليًا من flutter_code_editor عند أول flutter analyze/run.
class CodeEditorWidget extends ConsumerWidget {
  final EditorTab tab;
  const CodeEditorWidget({super.key, required this.tab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return CodeTheme(
      data: CodeThemeData(
        styles: settings.isDarkMode ? atomOneDarkTheme : atomOneLightTheme,
      ),
      child: CodeField(
        controller: tab.controller,
        expands: true,
        textStyle: TextStyle(
          fontFamily: 'monospace',
          fontSize: settings.editorFontSize,
          height: 1.5,
        ),
        gutterStyle: GutterStyle(
          showLineNumbers: true,
          // عطّلنا أسهم الطي (folding handles) — هي أكبر مساهم في عرض
          // العمود على شاشة هاتف ضيقة، وقيمتها محدودة عمليًا هنا (ملفات
          // Flutter المُحرَّرة على الهاتف غالبًا قصيرة/متوسطة الطول).
          // إن كان العمود لا يزال عريضًا بعد هذا، افتحوا GutterStyle عبر
          // الإكمال التلقائي في VS Code (بنفس أسلوب لقطات git_service.dart
          // السابقة) بحثًا عن خاصية margin/width إضافية يمكن ضبطها يدويًا.
          showFoldingHandles: false,
          textStyle: TextStyle(color: Colors.grey.shade600, fontSize: settings.editorFontSize - 3),
        ),
        wrap: settings.wordWrap,
      ),
    );
  }
}
