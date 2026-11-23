import 'package:flutter/material.dart';
import 'package:flutter_mobile_ide/features/preview/logic/generated/generated_ctors.dart';
import 'package:flutter_mobile_ide/features/preview/logic/generated_bridge.dart';
import 'package:flutter_mobile_ide/features/preview/logic/native_members.dart' show kNoNative;
import 'package:flutter_mobile_ide/features/preview/logic/preview_engine.dart';
import 'package:flutter_mobile_ide/features/preview/logic/widget_interpreter.dart';
import 'package:flutter_test/flutter_test.dart';

/// اختبارات الجسر المولَّد. تُتخطّى تلقائيًا قبل تشغيل tool/gen_widget_bridge.dart
/// (الملفات المولَّدة تكون "stub" فارغًا).
final bool _skip = kGeneratedCtors.isEmpty; // قبل التوليد: شغّل dart run tool/gen_widget_bridge.dart

const _src = r'''
import 'package:flutter/material.dart';

void main() {
  runApp(MaterialApp(
    home: Scaffold(
      body: Column(children: [
        RotatedBox(quarterTurns: 1, child: Text('rot')),
        ColoredBox(color: Colors.red, child: Text('col')),
        Transform.rotate(angle: 0.5, child: Text('tr')),
        Text('x=${Alignment.centerLeft.x}'),
        Text('h=${EdgeInsets.all(8).horizontal}'),
      ]),
    ),
  ));
}
''';

void main() {
  test('اسم غير مولَّد => kNoNative (لا يؤثّر على الجداول اليدوية)', () {
    expect(identical(GeneratedBridge.construct('NoSuchWidgetXyz', const [], const {}), kNoNative), isTrue);
    expect(identical(GeneratedBridge.staticMember('NoSuchNs', 'x'), kNoNative), isTrue);
  });

  test('مُنشئ مولَّد مباشر مع تحويل الأنواع (int→double، child)', () {
    final w = GeneratedBridge.construct('Opacity', const [], {'opacity': 1, 'child': const SizedBox()});
    expect(w, isA<Opacity>());
    expect((w as Opacity).opacity, 1.0);
  }, skip: _skip);

  test('وسيط مطلوب مفقود => رسالة عربية واضحة', () {
    expect(
      () => GeneratedBridge.construct('ColoredBox', const [], const {}),
      throwsA(predicate((e) => e.toString().contains('color'))),
    );
  }, skip: _skip);

  testWidgets('ودجتس غير مسجَّلة يدويًا + خصائص مولَّدة تعمل في المعاينة', (tester) async {
    final result = PreviewEngine().build(dartFilesByPath: {'/p/lib/main.dart': _src}, mainFilePath: '/p/lib/main.dart');
    expect(result.hasError, isFalse, reason: result.errorMessage);
    final logs = <String>[];
    final i = Interpreter(
      classRegistry: result.classRegistry,
      log: (m, {isError = false}) => logs.add(m),
      onStateChanged: () {},
      projectRootPath: '',
    );
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) => i.buildRoot(result.rootExpr!, c))));
    await tester.pumpAndSettle();
    final why = logs.join('\n');
    expect(find.text('rot'), findsOneWidget, reason: why);
    expect(find.text('col'), findsOneWidget, reason: why);
    expect(find.text('tr'), findsOneWidget, reason: why);
    expect(find.text('x=-1.0'), findsOneWidget, reason: why);
    expect(find.text('h=16.0'), findsOneWidget, reason: why);
  }, skip: _skip);
}
