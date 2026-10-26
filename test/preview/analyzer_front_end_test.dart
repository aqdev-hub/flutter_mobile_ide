import 'package:flutter/material.dart';
import 'package:flutter_mobile_ide/features/preview/logic/analyzer_front_end.dart';
import 'package:flutter_mobile_ide/features/preview/logic/dart_subset_ast.dart';
import 'package:flutter_mobile_ide/features/preview/logic/preview_engine.dart';
import 'package:flutter_mobile_ide/features/preview/logic/widget_interpreter.dart';
import 'package:flutter_test/flutter_test.dart';

const _counterSrc = r'''
import 'package:flutter/material.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: const HomePage());
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _counter = 0;
  String? note;

  @override
  Widget build(BuildContext ctx) {
    final List<String> labels = ['a', 'b'];
    final extra = [Text('x1')];
    return Scaffold(
      body: Column(
        children: [
          Text('count: $_counter'),
          for (final l in labels) Text('item $l'),
          if (_counter > 0) Text('positive'),
          ...extra,
          ElevatedButton(
            onPressed: () {
              setState(() {
                _counter += 1;
              });
            },
            child: Text('inc'),
          ),
        ],
      ),
    );
  }
}
''';

FrontEndFileResult _extract(String src) => AnalyzerFrontEnd.extractFile(src, fileName: 't.dart');

WidgetClassDef _cls(FrontEndFileResult r, String name) => r.classes.firstWhere((c) => c.name == name);

void main() {
  group('AnalyzerFrontEnd — بنية الأصناف', () {
    test('Stateless/Stateful/State بصياغة قياسية (super.key و@override وأنواع)', () {
      final r = _extract(_counterSrc);
      expect(r.usable, isTrue, reason: r.unusableReason);

      final app = _cls(r, 'MyApp');
      expect(app.baseType, 'StatelessWidget');
      expect(app.buildBody, isNotNull);

      final home = _cls(r, 'HomePage');
      expect(home.baseType, 'StatefulWidget');
      expect(home.stateClassName, '_HomePageState');

      final state = _cls(r, '_HomePageState');
      expect(state.baseType, 'State');
      expect(state.stateClassName, 'HomePage');
      expect(state.fields.map((f) => f.name), containsAll(['_counter', 'note']));
      expect(state.fields.firstWhere((f) => f.name == 'note').initializer, isNull);
    });

    test('اسم BuildContext غير "context" يُربَط ببديل عبر VarDeclStmt', () {
      final state = _cls(_extract(_counterSrc), '_HomePageState');
      final first = state.buildBody!.first;
      expect(first, isA<VarDeclStmt>());
      expect((first as VarDeclStmt).name, 'ctx');
    });

    test('الصنف العادي (ليس ودجت) يحمل رسالة "قيد في المعاينة" لا null صامت', () {
      final r = _extract('class AppColor { static const x = 1; }');
      final c = _cls(r, 'AppColor');
      expect(c.buildBody, isNull);
      expect(c.buildParseError, contains('قيد التطوير'));
    });

    test('مُنشئ بمعامل موضعي يُربَط باسم الحقل', () {
      final r = _extract('''
class Card1 extends StatelessWidget {
  final String title;
  const Card1(this.title);
  Widget build(BuildContext context) => Text(title);
}
''');
      expect(_cls(r, 'Card1').fields.first.name, 'title');
    });
  });

  group('AnalyzerFrontEnd — التعبيرات والجمل', () {
    List<Stmt> bodyOf(String stmts) {
      final r = _extract('''
class A extends StatelessWidget {
  Widget build(BuildContext context) {
    $stmts
    return Text('x');
  }
}
''');
      expect(r.usable, isTrue, reason: r.unusableReason);
      return _cls(r, 'A').buildBody!;
    }

    test('lambda بنوع المعامل (BuildContext c) => ...', () {
      final body = bodyOf("final f = (BuildContext c) => Text('x');");
      final decl = body.first as VarDeclStmt;
      final lambda = decl.initializer as LambdaExpr;
      expect(lambda.params, ['c']);
    });

    test('?? و?. و! تُبسَّط إلى TernaryExpr/الأصل', () {
      final body = bodyOf('''
String? a;
final b = a ?? 'z';
final c = a?.length;
final d = a!;
''');
      expect((body[1] as VarDeclStmt).initializer, isA<TernaryExpr>());
      expect((body[2] as VarDeclStmt).initializer, isA<TernaryExpr>());
      expect((body[3] as VarDeclStmt).initializer, isA<IdentifierExpr>());
    });

    test('?? مع استدعاء على اليسار يُرفَض بوضوح بدل تقييم مزدوج صامت', () {
      final r = _extract('''
class A extends StatelessWidget {
  Widget build(BuildContext context) {
    final b = foo() ?? 1;
    return Text('x');
  }
}
''');
      expect(r.hasConversionErrors, isTrue);
      expect(r.issues.first.message, contains('قيد في المعاينة'));
      expect(r.issues.first.line, 3);
    });

    test('التعيين المركّب *= و??= يتحوّل إلى = مع BinaryExpr/TernaryExpr', () {
      final body = bodyOf('''
var n = 2;
n *= 3;
int? m;
m ??= 5;
n++;
''');
      final mul = body[1] as AssignStmt;
      expect(mul.op, '=');
      expect(mul.value, isA<BinaryExpr>());
      expect(((body[3]) as AssignStmt).value, isA<TernaryExpr>());
      expect(body[4], isA<IncDecStmt>());
    });

    test('spread وif وfor داخل القوائم', () {
      final body = bodyOf('''
final xs = [Text('a')];
final ys = [
  Text('b'),
  ...xs,
  if (xs.isEmpty) Text('c') else Text('d'),
  for (final t in xs) t,
];
''');
      final list = (body[1] as VarDeclStmt).initializer as ListExpr;
      // b + spread + if + else + for
      expect(list.elements.length, 5);
      expect(list.elements.whereType<ListForElement>().length, 4);
    });

    test('Foo.named(...) وconst X() وتعبيرات النص', () {
      final body = bodyOf(r'''
final p = const EdgeInsets.all(8);
final s = 'a $p b ${p + 1}';
''');
      final call = (body[0] as VarDeclStmt).initializer as CallExpr;
      expect(call.callee, isA<PropertyExpr>());
      expect(((call.callee as PropertyExpr).target as IdentifierExpr).name, 'EdgeInsets');
      expect((body[1] as VarDeclStmt).initializer, isA<InterpolationExpr>());
    });

    test('try/catch غير مدعوم: خطأ بسطره المطلق، لا استثناء', () {
      final r = _extract('''
class A extends StatelessWidget {
  Widget build(BuildContext context) {
    try {
      return Text('x');
    } catch (e) {
      return Text('y');
    }
  }
}
''');
      expect(r.hasConversionErrors, isTrue);
      expect(r.issues.first.line, 3);
      expect(_cls(r, 'A').buildParseError, isNotNull);
    });

    test('خطأ صياغة => hasSyntaxErrors وبلا أصناف', () {
      final r = _extract('class A extends StatelessWidget { Widget build(BuildContext c) { return Foo( } }');
      expect(r.hasSyntaxErrors, isTrue);
      expect(r.classes, isEmpty);
      expect(r.usable, isFalse);
    });

    test('أرقام الأسطر والملف مطلقة على العقد', () {
      final body = _cls(_extract(_counterSrc), 'MyApp').buildBody!;
      final call = (body.single as ReturnStmt).value as CallExpr;
      expect(call.file, 't.dart');
      expect(call.line, 13);
    });
  });

  group('runApp', () {
    test('يُستخرج جذر التطبيق من main (مع تهيئة سابقة وconst)', () {
      final root = AnalyzerFrontEnd.extractRunAppRoot(_counterSrc, fileName: 'main.dart');
      expect(root, isA<CallExpr>());
      expect(((root as CallExpr).callee as IdentifierExpr).name, 'MyApp');
    });

    test('main => runApp(...) بصيغة السهم', () {
      final root = AnalyzerFrontEnd.extractRunAppRoot('void main() => runApp(MyApp());', fileName: 'main.dart');
      expect(root, isA<CallExpr>());
    });

    test('بلا runApp => null', () {
      expect(AnalyzerFrontEnd.extractRunAppRoot('void main() {}', fileName: 'm.dart'), isNull);
    });
  });

  group('PreviewEngine + Interpreter (من الطرف إلى الطرف)', () {
    test('المحرك الجديد هو المستخدم لهذا المصدر', () {
      final result = PreviewEngine().build(dartFilesByPath: {'/p/lib/main.dart': _counterSrc}, mainFilePath: '/p/lib/main.dart');
      expect(result.hasError, isFalse, reason: result.errorMessage);
      expect(result.notes.first, contains('analyzer (1 ملف)'));
    });

    testWidgets('عدّاد: نص/for/if/spread/زر وsetState تعمل على AST القادم من analyzer', (tester) async {
      final result = PreviewEngine().build(dartFilesByPath: {'/p/lib/main.dart': _counterSrc}, mainFilePath: '/p/lib/main.dart');
      expect(result.hasError, isFalse, reason: result.errorMessage);
      final logs = <String>[];
      final interpreter = Interpreter(
        classRegistry: result.classRegistry,
        log: (m, {isError = false}) => logs.add(m),
        onStateChanged: () {},
        projectRootPath: '',
      );

      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) => interpreter.buildRoot(result.rootExpr!, ctx)),
      ));
      await tester.pump();

      expect(find.text('count: 0'), findsOneWidget, reason: logs.join('\n'));
      expect(find.text('item a'), findsOneWidget);
      expect(find.text('item b'), findsOneWidget);
      expect(find.text('x1'), findsOneWidget);
      expect(find.text('positive'), findsNothing);

      await tester.tap(find.text('inc'));
      await tester.pump();

      expect(find.text('count: 1'), findsOneWidget, reason: logs.join('\n'));
      expect(find.text('positive'), findsOneWidget);
    });
  });
}
