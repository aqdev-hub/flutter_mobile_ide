import 'package:flutter/material.dart';
import 'package:flutter_mobile_ide/features/preview/logic/generated_bridge.dart';
import 'package:flutter_mobile_ide/features/preview/logic/native_members.dart' show kNoNative;
import 'package:flutter_mobile_ide/features/preview/logic/preview_engine.dart';
import 'package:flutter_mobile_ide/features/preview/logic/widget_interpreter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _flow = r'''
import 'package:flutter/material.dart';

class Calc {
  static String run(int n) {
    var out = '';
    try {
      if (n == 0) {
        throw FormatException('zero');
      }
      out = 'ok$n';
    } on FormatException catch (e) {
      out = 'fmt:${e.toString()}';
    } catch (e) {
      out = 'other';
    } finally {
      out = out + '!';
    }
    return out;
  }

  static String sw(int n) {
    switch (n) {
      case 1:
      case 2:
        return 'low';
      case 3:
        return 'three';
      default:
        return 'many';
    }
  }

  static int loop() {
    var i = 0;
    do {
      i++;
    } while (i < 3);
    return i;
  }

  static String cascade() {
    final c = TextEditingController()..text = 'hi';
    return c.text;
  }
}

void main() {
  runApp(MaterialApp(
    home: Scaffold(
      body: Column(children: [
        Text(Calc.run(0)),
        Text(Calc.run(5)),
        Text(Calc.sw(2)),
        Text(Calc.sw(9)),
        Text('loop${Calc.loop()}'),
        Text('casc:${Calc.cascade()}'),
      ]),
    ),
  ));
}
''';

const _async = r'''
import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(home: Home()));
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  String out = 'idle';
  int inits = 0;
  int taps = 0;

  @override
  void initState() {
    super.initState();
    inits += 1;
    print('init');
  }

  Future<void> _go() async {
    try {
      await Future.delayed(Duration(milliseconds: 5));
      throw Exception('x');
    } catch (e) {
      setState(() {
        out = 'caught';
      });
    } finally {
      print('finally');
    }
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('k', 'v');
    final n = p.getInt('n') ?? 41;
    await p.setInt('n', n + 1);
    setState(() {
      out = '${p.getString('k')}/${p.getInt('n')}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        Text('out:$out'),
        Text('inits:$inits'),
        Text('taps:$taps'),
        ElevatedButton(
          onPressed: () {
            setState(() {
              taps += 1;
            });
            _go();
          },
          child: Text('go'),
        ),
        ElevatedButton(
          onPressed: () {
            _save();
          },
          child: Text('save'),
        ),
      ]),
    );
  }
}
''';

const _method = r'''
import 'package:flutter/material.dart';

void main() {
  runApp(MaterialApp(home: Scaffold(body: Text('cp:${EdgeInsets.all(8).copyWith(left: 3).left}'))));
}
''';

const _enums = r'''
import 'package:flutter/material.dart';

enum Mode { light, dark }

enum Level {
  low('L', 1),
  high('H', 3);

  final String tag;
  final int weight;
  const Level(this.tag, this.weight);

  String describe() => '$tag:$weight';
}

String pick(Mode m) {
  switch (m) {
    case Mode.light:
      return 'L';
    case Mode.dark:
      return 'D';
  }
  return '?';
}

String code(int n) {
  switch (n) {
    case 1 || 2:
      return 'low';
    case 3:
      return 'three';
    default:
      return 'many';
  }
}

void main() {
  runApp(MaterialApp(
    home: Scaffold(
      body: Column(children: [
        Text('m:${Mode.dark.name}/${Mode.dark.index}/${Mode.values.length}'),
        Text('l:${Level.high.describe()}/${Level.low}'),
        Text(Mode.light == Mode.light ? 'eq' : 'ne'),
        Text(pick(Mode.dark)),
        Text('c:${code(2)}/${code(9)}'),
      ]),
    ),
  ));
}
''';

const _prelude = r'''
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('who', 'ali');
  runApp(MaterialApp(home: Scaffold(body: Text('hi ${prefs.getString('who')}'))));
}
''';

const _func = r'''
import 'package:flutter/material.dart';

void main() {
  runApp(MaterialApp(home: Scaffold(body: Text('eq:${listEquals([1, 2], [1, 2])}'))));
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
    projectRootPath: '/p',
  );
  logs.addAll(result.notes); // يظهر سبب الرجوع للمحرك القديم عند أي فشل
  return (i, result, logs);
}

Future<List<String>> _pumpSource(WidgetTester tester, String src) async {
  final (i, r, logs) = _make(src);
  await i.runPrelude(r.mainPrelude);
  await tester.pumpWidget(MaterialApp(home: Builder(builder: (c) => i.buildRoot(r.rootExpr!, c))));
  await tester.pump();
  return logs;
}

final bool _noMethods = identical(
  GeneratedBridge.method(const EdgeInsets.all(1), 'copyWith', const [], const {}),
  kNoNative,
);

final bool _noFuncs = !GeneratedBridge.hasCtor('listEquals');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('try/catch/finally وthrow وswitch وdo-while وcascade', (tester) async {
    final logs = await _pumpSource(tester, _flow);
    final why = logs.join('\n');
    expect(find.text('fmt:FormatException: zero!'), findsOneWidget, reason: why);
    expect(find.text('ok5!'), findsOneWidget, reason: why);
    expect(find.text('low'), findsOneWidget, reason: why);
    expect(find.text('many'), findsOneWidget, reason: why);
    expect(find.text('loop3'), findsOneWidget, reason: why);
    expect(find.text('casc:hi'), findsOneWidget, reason: why);
  });

  testWidgets('async try/catch + دورة الحياة بلا تكرار + SharedPreferences معزول', (tester) async {
    final logs = await _pumpSource(tester, _async);
    expect(logs.where((l) => l == 'init').length, 1, reason: 'initState مرة واحدة');

    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('out:caught'), findsOneWidget, reason: logs.join('\n'));
    expect(find.text('taps:1'), findsOneWidget);
    expect(logs.where((l) => l == 'finally').length, 1);

    await tester.tap(find.text('go'));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('taps:2'), findsOneWidget);
    expect(logs.where((l) => l == 'finally').length, 2, reason: 'callback مرة واحدة لكل ضغطة');
    expect(logs.where((l) => l == 'init').length, 1, reason: 'setState لا يعيد initState');

    await tester.tap(find.text('save'));
    await tester.pump(const Duration(milliseconds: 20));
    expect(find.text('out:v/42'), findsOneWidget, reason: logs.join('\n'));

    // معزول: المفتاح مخزَّن بمقدّمة المشروع وليس باسمه المجرّد.
    final raw = await SharedPreferences.getInstance();
    expect(raw.getString('k'), isNull);
    expect(raw.getKeys().any((k) => k.startsWith('preview.') && k.endsWith('.k')), isTrue);
  });

  testWidgets('enum المستخدم (بسيط ومحسَّن) + switch بالأنماط الثابتة', (tester) async {
    final logs = await _pumpSource(tester, _enums);
    final why = logs.join('\n');
    expect(find.text('m:dark/1/2'), findsOneWidget, reason: why);
    expect(find.text('l:H:3/Level.low'), findsOneWidget, reason: why);
    expect(find.text('eq'), findsOneWidget, reason: why);
    expect(find.text('D'), findsOneWidget, reason: why);
    expect(find.text('c:low/many'), findsOneWidget, reason: why);
  });

  testWidgets('متغيرات main قبل runApp (await SharedPreferences)', (tester) async {
    final logs = await _pumpSource(tester, _prelude);
    expect(find.text('hi ali'), findsOneWidget, reason: logs.join('\n'));
  });

  testWidgets('دالة عليا مولَّدة (listEquals)', (tester) async {
    final logs = await _pumpSource(tester, _func);
    expect(find.text('eq:true'), findsOneWidget, reason: logs.join('\n'));
  }, skip: _noFuncs);

  testWidgets('دالة مولَّدة على كائن Flutter (EdgeInsets.copyWith)', (tester) async {
    await _pumpSource(tester, _method);
    expect(find.text('cp:3.0'), findsOneWidget);
  }, skip: _noMethods);
}
