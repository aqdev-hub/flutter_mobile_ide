import 'package:flutter_mobile_ide/features/preview/logic/class_extractor.dart';
import 'package:flutter_mobile_ide/features/preview/logic/dart_subset_ast.dart';
import 'package:flutter_test/flutter_test.dart';

/// يتحقق من أن أرقام الأسطر وأسماء الملفات المسجَّلة على عقد الشجرة مطلقة
/// (داخل الملف الكامل) وليست نسبية لبداية الدالة كما كان سابقًا.
void main() {
  test('جملة build تحمل رقم سطرها المطلق واسم ملفها', () {
    const source = '''
import 'package:flutter/material.dart';

class A extends StatelessWidget {
  Widget build(BuildContext context) {
    return Text('x');
  }
}
''';
    final defs = ClassExtractor(source, fileName: 'a.dart').extractAll();
    final stmt = defs.single.buildBody!.first;
    expect(stmt.line, 5);
    expect(stmt.file, 'a.dart');

    final call = (stmt as ReturnStmt).value as CallExpr;
    expect(call.line, 5);
    expect(call.file, 'a.dart');
  });

  test('خطأ التحليل داخل build يُنسَب لسطره المطلق في الملف', () {
    const source = '''
class B extends StatelessWidget {
  Widget build(BuildContext context) {
    var a = 1;
    return Foo(
  }
}
''';
    final extractor = ClassExtractor(source, fileName: 'b.dart');
    extractor.extractAll();
    expect(extractor.issues, isNotEmpty);
    // الخطأ يقع عند نهاية جسم build (السطر 5) لا عند "السطر 3" النسبي داخل الجسم.
    expect(extractor.issues.any((i) => i.line == 5), isTrue);
  });

  test('دالة مساعدة تحمل أسطرها المطلقة أيضًا', () {
    const source = '''
class C extends StatelessWidget {
  Widget build(BuildContext context) {
    return Text('x');
  }

  Widget _helper() {
    return Text('y');
  }
}
''';
    final def = ClassExtractor(source, fileName: 'c.dart').extractAll().single;
    final helper = def.methods.firstWhere((m) => m.name == '_helper');
    expect(helper.body.first.line, 7);
    expect(helper.body.first.file, 'c.dart');
  });
}
