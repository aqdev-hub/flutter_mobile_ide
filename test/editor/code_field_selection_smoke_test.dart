import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// اختبار دخان لتعديلات third_party/flutter_code_editor (IDE_PATCHES.md):
/// يتأكد أن المحرر يعمل بعدها دون استثناءات، وأن تغيير التحديد وحده ثم النص
/// ثم استبدال المتحكم كلها مسارات سليمة. لا يقيس عدد إعادات البناء (واجهته
/// داخلية)، فهو يحرس السلامة لا الأداء.
void main() {
  Widget host(CodeController c) => MaterialApp(
        home: Scaffold(body: CodeField(controller: c, expands: true)),
      );

  testWidgets('تغيّر التحديد فقط ثم النص ثم استبدال المتحكم بلا استثناءات', (tester) async {
    final first = CodeController(text: 'void main() {\n  print(1);\n}\n');
    final second = CodeController(text: 'a\nb\nc\n');
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(host(first));
    await tester.pump();

    first.selection = const TextSelection(baseOffset: 2, extentOffset: 9);
    await tester.pump();
    first.selection = const TextSelection.collapsed(offset: 5);
    await tester.pump();
    expect(tester.takeException(), isNull);

    first.text = 'void main() {}\n';
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(host(second));
    await tester.pump();
    second.text = 'a\nb\nc\nd\n';
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(second.fullText, 'a\nb\nc\nd\n');
  });

  testWidgets('لمس عادي وسحب تمرير على المحرر لا يُسقطان التمرير التلقائي', (tester) async {
    final c = CodeController(text: List.generate(80, (i) => 'line $i').join('\n'));
    addTearDown(c.dispose);
    await tester.pumpWidget(host(c));
    await tester.pump();

    await tester.drag(find.byType(CodeField), const Offset(0, -200));
    await tester.pump();
    await tester.tap(find.byType(CodeField));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
