import 'package:flutter/material.dart';
import 'package:flutter_mobile_ide/features/preview/logic/preview_engine.dart';
import 'package:flutter_mobile_ide/features/preview/logic/widget_interpreter.dart';
import 'package:flutter_test/flutter_test.dart';

const _lang = r'''
import 'package:flutter/material.dart';

class Temp {
  int _c = 0;
  int get c => _c;
  set c(int v) {
    _c = v * 2;
  }
}

void main() {
  runApp(const Home());
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final formKey = GlobalKey<FormState>();
  final ctl = TextEditingController();
  String out = '';

  @override
  Widget build(BuildContext context) {
    final t = Temp();
    t.c = 4;
    final Object? v = 'abc';
    String? n;
    final re = RegExp(r'^[a-z]+$');
    return MaterialApp(
      locale: const Locale('ar'),
      home: Scaffold(
        body: Form(
          key: formKey,
          child: Column(children: [
            Text('c=${t.c}'),
            Text('is=${v is String}/${v is! int}'),
            Text('n=${n?.length ?? -1}'),
            Text('re=${re.hasMatch('abc')}/${re.hasMatch('A1')}'),
            TextFormField(
              controller: ctl,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-z]'))],
              validator: (value) => (value == null || !re.hasMatch(value)) ? 'bad' : null,
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  out = formKey.currentState!.validate() ? 'ok' : 'invalid';
                });
              },
              child: Text('go'),
            ),
            Text('out:$out'),
          ]),
        ),
      ),
    );
  }
}
''';

const _nav = r'''
import 'package:flutter/material.dart';

class Ctl {
  void go(BuildContext context) {
    Navigator.pushNamedAndRemoveUntil(context, '/b', (r) => false, arguments: 'hello');
  }
}

class Home extends StatelessWidget {
  Widget build(BuildContext context) {
    return Scaffold(body: ElevatedButton(onPressed: () { Ctl().go(context); }, child: Text('go')));
  }
}

void main() {
  runApp(MaterialApp(
    home: Home(),
    routes: {'/b': (context) => Text('args:${ModalRoute.of(context)!.settings.arguments}')},
  ));
}
''';

(Interpreter, PreviewBuildResult, List<String>) _make(String src) {
  final result = PreviewEngine().build(dartFilesByPath: {'/p/lib/main.dart': src}, mainFilePath: '/p/lib/main.dart');
  expect(result.hasError, isFalse, reason: result.errorMessage);
  final logs = <String>[];
  final i = Interpreter(
    classRegistry: result.classRegistry,
    globalVars: result.globalVars,
    globalFunctions: result.globalFunctions,
    log: (m, {isError = false}) => logs.add(m),
    onStateChanged: () {},
    projectRootPath: '',
  );
  return (i, result, logs);
}

void main() {
  testWidgets('is/?./??/RegExp/setter/Form/validate/RTL', (tester) async {
    final (i, r, logs) = _make(_lang);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) => i.buildRoot(r.rootExpr!, c))));
    await tester.pumpAndSettle();
    final why = logs.join('\n');

    expect(find.text('c=8'), findsOneWidget, reason: why);
    expect(find.text('is=true/true'), findsOneWidget, reason: why);
    expect(find.text('n=-1'), findsOneWidget, reason: why);
    expect(find.text('re=true/false'), findsOneWidget, reason: why);
    expect(Directionality.of(tester.element(find.text('c=8'))), TextDirection.rtl);

    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('out:invalid'), findsOneWidget, reason: logs.join('\n'));

    await tester.enterText(find.byType(TextFormField), 'abc');
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('out:ok'), findsOneWidget, reason: logs.join('\n'));
  });

  testWidgets('pushNamedAndRemoveUntil من متحكّم + ModalRoute arguments', (tester) async {
    final (i, r, logs) = _make(_nav);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) => i.buildRoot(r.rootExpr!, c))));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('args:hello'), findsOneWidget, reason: logs.join('\n'));
  });
}
