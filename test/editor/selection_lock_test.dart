import 'package:flutter/services.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';
import 'package:flutter_test/flutter_test.dart';

/// يحرس قفل التحديد الذي يمنع تنازع مقابض Flutter مع التمرير التلقائي.
void main() {
  test('أثناء القفل: كتابات التحديد الخارجية تُتجاهل، والمالك والنص يعملان', () {
    final c = CodeController(text: 'hello world');
    addTearDown(c.dispose);
    c.selection = const TextSelection(baseOffset: 0, extentOffset: 5);

    c.selectionLocked = true;
    c.selection = const TextSelection.collapsed(offset: 3); // من غير المالك
    expect(c.selection, const TextSelection(baseOffset: 0, extentOffset: 5));

    c.setSelectionOwned(const TextSelection.collapsed(offset: 8)); // المالك
    expect(c.selection.baseOffset, 8);

    c.value = c.value.copyWith(text: 'hello world!', selection: const TextSelection.collapsed(offset: 12));
    expect(c.fullText, 'hello world!'); // تغيير النص لا يُمنع أبدًا

    c.selectionLocked = false;
    c.selection = const TextSelection.collapsed(offset: 1);
    expect(c.selection.baseOffset, 1);
  });
}
