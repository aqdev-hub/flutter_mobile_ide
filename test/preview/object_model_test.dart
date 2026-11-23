import 'package:flutter/material.dart';
import 'package:flutter_mobile_ide/features/preview/logic/preview_engine.dart';
import 'package:flutter_mobile_ide/features/preview/logic/widget_interpreter.dart';
import 'package:flutter_test/flutter_test.dart';

/// مشروع متعدد الملفات يعيد سيناريو المالك: أصناف بلا extends وأعضاء static،
/// getter، مُنشئات مسمّاة وافتراضية، controller ككائن، initState، routes كمتغيّر
/// عام، Theme.of، Navigator.of(...).pushNamed، MaterialButton.
const _color = r'''
import 'package:flutter/material.dart';

class AppColor {
  static const Color backgroundColor = Color(0xFFEEEEEE);
  static const Color primary = Colors.teal;
}
''';

const _routes = r'''
import 'package:flutter/material.dart';
import 'package:my/screens.dart';

class AppRoute {
  static const String second = '/second';
}

Map<String, WidgetBuilder> routes = {
  AppRoute.second: (context) => const SecondPage(),
};
''';

const _controller = r'''
import 'package:flutter/material.dart';

abstract class BaseController {
  int created = 0;
  BaseController() {
    created = 1;
  }
  void signUp();
}

class SignUpControllerImp extends BaseController {
  late TextEditingController username;
  int count = 0;

  SignUpControllerImp() {
    username = TextEditingController();
  }

  @override
  void signUp() {
    count++;
  }

  String get label => 'n:$count/$created';
}

class Counter {
  int step;
  Counter({this.step = 2});
  int next(int v, {int times = 1}) => v + step * times;
}

class Util {
  static int twice(int x) => x * 2;
}
''';

const _theme = r'''
import 'package:flutter/material.dart';

class AppTheme {
  ThemeData get light => ThemeData(primarySwatch: Colors.green, useMaterial3: true);
}
''';

const _screens = r'''
import 'package:flutter/material.dart';

class Field extends StatelessWidget {
  final String hint;
  final TextEditingController? ctl;
  const Field({super.key, required this.hint, this.ctl});

  @override
  Widget build(BuildContext context) {
    return TextFormField(controller: ctl, decoration: InputDecoration(hintText: hint));
  }
}

class SecondPage extends StatelessWidget {
  const SecondPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(body: Text('second page'));
}

class SignUp extends StatefulWidget {
  const SignUp({super.key});

  @override
  State<SignUp> createState() => _SignUpState();
}

class _SignUpState extends State<SignUp> {
  late SignUpControllerImp controller;
  int inits = 0;

  @override
  void initState() {
    super.initState();
    controller = SignUpControllerImp();
    inits += 1;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Text(controller.label),
          Text('inits:$inits'),
          Text('calc:${Counter().next(1, times: 3)}/${Util.twice(4)}'),
          Text('native:${[1, 2, 3].length}/${'abc'.toUpperCase()}'),
          Field(hint: 'user', ctl: controller.username),
          Text('styled', style: Theme.of(context).textTheme.titleLarge),
          Text('bg', style: TextStyle(color: AppColor.backgroundColor)),
          MaterialButton(
            color: AppColor.primary,
            onPressed: () {
              setState(() {
                controller.signUp();
              });
            },
            child: Text('go'),
          ),
          MaterialButton(
            onPressed: () {
              Navigator.of(context).pushNamed(AppRoute.second);
            },
            child: Text('next'),
          ),
        ],
      ),
    );
  }
}
''';

const _main = r'''
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme().light,
      routes: routes,
      home: const SignUp(),
    );
  }
}
''';

const _files = {
  '/p/lib/core/color.dart': _color,
  '/p/lib/routes.dart': _routes,
  '/p/lib/controller.dart': _controller,
  '/p/lib/theme.dart': _theme,
  '/p/lib/screens.dart': _screens,
  '/p/lib/main.dart': _main,
};

void main() {
  test('كل الملفات تُحوَّل بمحرك analyzer (لا رجوع للقديم)', () {
    final result = PreviewEngine().build(dartFilesByPath: _files, mainFilePath: '/p/lib/main.dart');
    expect(result.hasError, isFalse, reason: result.errorMessage);
    expect(result.notes.join('\n'), contains('analyzer (6 ملف)'));
    expect(result.globalVars.containsKey('routes'), isTrue);
  });

  testWidgets('سيناريو المالك: static وgetter وكائنات وinitState وrouteو Theme', (tester) async {
    final result = PreviewEngine().build(dartFilesByPath: _files, mainFilePath: '/p/lib/main.dart');
    expect(result.hasError, isFalse, reason: result.errorMessage);
    final logs = <String>[];
    final interpreter = Interpreter(
      classRegistry: result.classRegistry,
      globalVars: result.globalVars,
      globalFunctions: result.globalFunctions,
      log: (m, {isError = false}) => logs.add(m),
      onStateChanged: () {},
      projectRootPath: '',
    );

    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) => interpreter.buildRoot(result.rootExpr!, ctx)),
    ));
    await tester.pump();
    final why = logs.join('\n');

    // مُنشئ الأب نُفِّذ (created = 1)، وgetter، ومعاملات مسمّاة/افتراضية، وstatic، وnative.
    expect(find.text('n:0/1'), findsOneWidget, reason: why);
    expect(find.text('inits:1'), findsOneWidget, reason: why);
    expect(find.text('calc:7/8'), findsOneWidget, reason: why);
    expect(find.text('native:3/ABC'), findsOneWidget, reason: why);
    expect(find.text('styled'), findsOneWidget, reason: why);
    expect(find.text('bg'), findsOneWidget, reason: why);

    await tester.tap(find.text('go'));
    await tester.pump();
    expect(find.text('n:1/1'), findsOneWidget, reason: logs.join('\n'));
    expect(find.text('inits:1'), findsOneWidget, reason: 'initState لا تُعاد عند setState');

    await tester.tap(find.text('next'));
    await tester.pumpAndSettle();
    expect(find.text('second page'), findsOneWidget, reason: logs.join('\n'));
  });

  testWidgets('عضو static غير موجود => خطأ عربي واضح لا null صامت', (tester) async {
    const files = {
      '/p/lib/main.dart': r'''
import 'package:flutter/material.dart';

class AppColor {
  static const Color a = Colors.red;
}

void main() {
  runApp(MaterialApp(home: Scaffold(body: Text('${AppColor.nope}'))));
}
''',
    };
    final result = PreviewEngine().build(dartFilesByPath: files, mainFilePath: '/p/lib/main.dart');
    final interpreter = Interpreter(
      classRegistry: result.classRegistry,
      log: (m, {isError = false}) {},
      onStateChanged: () {},
      projectRootPath: '',
    );
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (ctx) => interpreter.buildRoot(result.rootExpr!, ctx)),
    ));
    expect(find.textContaining('AppColor'), findsWidgets);
    expect(find.textContaining('nope'), findsWidgets);
  });
}
