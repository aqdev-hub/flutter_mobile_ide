import 'package:flutter_mobile_ide/features/semantic/data/project_model.dart';
import 'package:flutter_mobile_ide/features/semantic/logic/ast_to_model.dart';
import 'package:flutter_mobile_ide/features/semantic/logic/semantic_checker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'semantic_test_support.dart';

/// اختبارات من الطرف إلى الطرف: كود Dart حقيقي ← محلل Dart الرسمي ← [AstToModel]
/// ← الفهرس ← المدقِّق. هي الحالات الواقعية نفسها التي واجهتنا.
void main() {
  final colorPath = lib('core/constant/color.dart');
  final themePath = lib('core/theme/app_theme.dart');
  final routesPath = lib('core/constant/routes.dart');
  final ctrlPath = lib('controller/signup_controller.dart');
  final fieldPath = lib('view/widget/auth/custom_text_form_auth.dart');
  final screenPath = lib('view/screen/signup.dart');

  const colorSrc = '''
import 'package:flutter/material.dart';

class AppColor {
  static const Color backgroundColor = Color(0xFFFFFFFF);
}
''';

  const themeSrc = '''
import 'package:flutter/material.dart';

class AppTheme {
  ThemeData get light => ThemeData();
}
''';

  const routesSrc = '''
class AppRoute {
  static const String signUp = '/signup';
}
''';

  const ctrlSrc = '''
import 'package:flutter/material.dart';

abstract class SignUpController {
  void signUp();
}

class SignUpControllerImp extends SignUpController {
  late TextEditingController username;
  late TextEditingController email;

  @override
  void signUp() {}

  void dispose() {
    username.dispose();
    email.dispose();
  }
}
''';

  const fieldSrc = '''
import 'package:flutter/material.dart';

class CustonTextFormAuth extends StatelessWidget {
  final String hinttext;
  final TextEditingController? mycontroller;

  const CustonTextFormAuth({super.key, required this.mycontroller, required this.hinttext});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: mycontroller,
      decoration: InputDecoration(hintText: hinttext),
    );
  }
}
''';

  const imports = '''
import 'package:flutter/material.dart';
import 'package:my/core/constant/color.dart';
import 'package:my/core/constant/routes.dart';
import 'package:my/core/theme/app_theme.dart';
import 'package:my/controller/signup_controller.dart';
import '../widget/auth/custom_text_form_auth.dart';
''';

  String screen({
    String head = imports,
    String color = 'AppColor.backgroundColor',
    String controllerArg = 'mycontroller: controller.username',
  }) =>
      '''
$head
class SignUp extends StatefulWidget {
  const SignUp({super.key});

  @override
  State<SignUp> createState() => _SignUpState();
}

class _SignUpState extends State<SignUp> {
  late SignUpControllerImp controller;

  @override
  void initState() {
    super.initState();
    controller = SignUpControllerImp();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: AppTheme().light,
      home: Scaffold(
        backgroundColor: $color,
        appBar: AppBar(
          title: Text('Sign Up', style: Theme.of(context).textTheme.titleLarge),
        ),
        body: Column(
          children: [
            CustonTextFormAuth(
              $controllerArg,
              hinttext: 'Enter your user name',
            ),
            MaterialButton(
              onPressed: () {
                Navigator.of(context).pushNamed(AppRoute.signUp);
                Navigator.pushNamed(context, AppRoute.signUp);
              },
              child: const Text('Go'),
            ),
          ],
        ),
      ),
    );
  }
}
''';

  List<SemanticDiagnostic> run(String screenSource, {String widgetSource = fieldSrc, Map<String, String> extra = const {}}) {
    final sources = <String, String>{
      colorPath: colorSrc,
      themePath: themeSrc,
      routesPath: routesSrc,
      ctrlPath: ctrlSrc,
      fieldPath: widgetSource,
      screenPath: screenSource,
      ...extra,
    };
    final models = [for (final e in sources.entries) AstToModel.build(e.key, e.value)];
    final target = models.firstWhere((m) => m.path == screenPath);
    return analyze(models, target);
  }

  test('الشاشة الصحيحة كاملة (AppColor + AppTheme().light + Theme.of + AppRoute + المتحكم) بلا أي تشخيص', () {
    final d = run(screen());
    expect([for (final x in d) '${x.code}: ${x.message}'], isEmpty);
  });

  test('AppColors (اسم صنف خاطئ) => unknown_class على الصنف، لا على العضو', () {
    final d = run(screen(color: 'AppColors.backgroundColor'));
    expect(codes(d), ['unknown_class']);
    expect(d.single.hint, contains('AppColor'));
  });

  test('AppColor.backgroundColour => unknown_member عند العضو', () {
    final d = run(screen(color: 'AppColor.backgroundColour'));
    expect(codes(d), ['unknown_member']);
    expect(d.single.hint, contains('backgroundColor'));
  });

  test('صنف معرَّف في المشروع وغير مستورَد => not_imported مع نص الاستيراد', () {
    final head = imports.replaceAll("import 'package:my/core/constant/color.dart';\n", '');
    final d = run(screen(head: head));
    expect(codes(d), ['not_imported']);
    expect(d.single.hint, contains('package:my/core/constant/color.dart'));
  });

  test('mycontroller لا يقبله المُنشئ => unknown_named_arg، ولا يُخلَط مع متغيّر', () {
    const widget = '''
import 'package:flutter/material.dart';

class CustonTextFormAuth extends StatelessWidget {
  final String hinttext;
  final TextEditingController? controller;

  const CustonTextFormAuth({super.key, required this.controller, required this.hinttext});

  @override
  Widget build(BuildContext context) {
    return TextFormField(controller: controller);
  }
}
''';
    final d = run(screen(), widgetSource: widget);
    final bad = d.where((x) => x.code == 'unknown_named_arg').toList();
    expect(bad, hasLength(1));
    expect(bad.single.message, contains('mycontroller'));
    expect(bad.single.message, contains('المُنشئ'));
    expect(d.any((x) => x.code == 'unknown_variable'), isFalse);
  });

  test('controller.usernam => unknown_member مع اقتراح username', () {
    final d = run(screen(controllerArg: 'mycontroller: controller.usernam'));
    expect(codes(d), ['unknown_member']);
    expect(d.single.hint, contains('username'));
  });

  test('تمرير المتحكم نفسه بدل TextEditingController => type_mismatch', () {
    final d = run(screen(controllerArg: 'mycontroller: controller'));
    expect(codes(d), ['type_mismatch']);
  });

  test('أخطاء مسار الاستيراد الحقيقية', () {
    final head = '''
import 'package:flutter/material.dart';
import 'package:MY/core/constant/color.dart';
import 'package:my/core/constant/Routes.dart';
import 'package:my/core/missing.dart';
import 'package:ghost/ghost.dart';
''';
    final d = run(screen(head: head));
    expect(codes(d), containsAll(['package_case_mismatch', 'import_case_mismatch', 'import_not_found', 'unknown_package']));
  });

  test('ملف part لا تُصدَر عليه تشخيصات دلالية (نطاقه موزَّع على ملفات)', () {
    final d = run("part 'signup.g.dart';\n${screen(head: '')}");
    expect(d, isEmpty);
  });

  test('enum: values والقيم صحيحة، وقيمة خاطئة => unknown_member', () {
    const modeSrc = '''
enum Mode { light, dark }
''';
    final modePath = lib('core/mode.dart');
    final ok = run(
      screen(head: "$imports\nimport 'package:my/core/mode.dart';\n", color: 'Mode.light.name == Mode.values.first.name ? AppColor.backgroundColor : AppColor.backgroundColor'),
      extra: {modePath: modeSrc},
    );
    expect(codes(ok), isEmpty);

    final bad = run(
      screen(head: "$imports\nimport 'package:my/core/mode.dart';\n", color: 'Mode.dak'),
      extra: {modePath: modeSrc},
    );
    expect(codes(bad), ['unknown_member']);
  });

  test('toString/hashCode على كائن من المشروع، وextension على الصنف، لا يُعتبران أخطاء', () {
    const extSrc = '''
import 'package:my/core/constant/color.dart';

extension AppColorX on AppColor {
  String get label => 'x';
}
''';
    final extPath = lib('core/color_ext.dart');
    final d = run(
      screen(
        head: "$imports\nimport 'package:my/core/color_ext.dart';\n",
        color: 'AppColor().label.isEmpty || AppTheme().hashCode == 1 || AppTheme().toString() == "" ? AppColor.backgroundColor : AppColor.backgroundColor',
      ),
      extra: {extPath: extSrc},
    );
    expect(codes(d), isEmpty);
  });

  test('استيراد ببادئة: c.AppColor.backgroundColor صحيح', () {
    final head = imports.replaceAll(
      "import 'package:my/core/constant/color.dart';",
      "import 'package:my/core/constant/color.dart' as c;",
    );
    final d = run(screen(head: head, color: 'c.AppColor.backgroundColor'));
    expect(codes(d), isEmpty);
  });

  test('أخطاء الصياغة في الملف تُسجَّل في النموذج', () {
    final broken = AstToModel.build(screenPath, 'class A {\n  void f() {\n    var x = ;\n  }\n}\n');
    expect(broken.syntaxErrorCount, greaterThan(0));
    expect(broken.firstSyntaxErrorLine, 3);
  });
}
