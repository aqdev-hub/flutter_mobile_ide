import 'package:flutter_mobile_ide/features/preview/logic/problems_analyzer.dart';
import 'package:flutter_mobile_ide/features/preview/logic/syntax_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SyntaxDiagnostics (محلل Dart الرسمي)', () {
    test('كود سليم بصياغة Dart حديثة لا ينتج أي أخطاء', () {
      const source = '''
import 'package:flutter/material.dart';

abstract class SignUpController {
  void signUp();
}

class Login extends StatelessWidget {
  const Login({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Sign In',
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      body: Builder(builder: (BuildContext c) => Text(title ?? 'x')),
    );
  }
}
''';
      expect(SyntaxDiagnostics.analyze(source), isEmpty);
    });

    test('const Login({super?key}) يُكتشف على سطره', () {
      const source = '''
class Login extends StatelessWidget {
  const Login({super?key});

  Widget build(BuildContext context) => Container();
}
''';
      final errors = SyntaxDiagnostics.analyze(source);
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.line == 2), isTrue);
    });

    test('bstract class SignUpController يُكتشف على سطره', () {
      const source = '''
bstract class SignUpController {
  void signUp();
}
''';
      final errors = SyntaxDiagnostics.analyze(source);
      expect(errors, isNotEmpty);
      expect(errors.first.line, 1);
    });

    test('فاصلة منقوطة منسيّة', () {
      const source = '''
void main() {
  var a = 1
  var b = 2;
}
''';
      final errors = SyntaxDiagnostics.analyze(source);
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.line >= 2 && e.line <= 3), isTrue);
    });

    test('قوس غير مغلق', () {
      const source = '''
void main() {
  runApp(MyApp(
}
''';
      expect(SyntaxDiagnostics.analyze(source), isNotEmpty);
    });

    test('الرسائل المعروفة تُترجم، والمجهولة تبقى بأصلها مع تصنيف عربي', () {
      expect(SyntaxDiagnostics.localizeMessage("Expected to find ';'."), contains(';'));
      expect(SyntaxDiagnostics.localizeMessage("Expected to find ';'."), contains('متوقَّع'));
      expect(SyntaxDiagnostics.localizeMessage('Some brand new message.'), contains('Some brand new message.'));
    });
  });

  group('ProblemsAnalyzer (تصنيف المشاكل)', () {
    test('خطأ صياغة => أخطاء من فئة syntax فقط، بلا ضجيج من المعاينة', () {
      const source = '''
class Login extends StatelessWidget {
  const Login({super?key});

  Widget build(BuildContext context) {
    return Text('x');
  }
}
''';
      final problems = ProblemsAnalyzer.analyzeDartFile('/p/login.dart', 'login.dart', source);
      expect(problems, isNotEmpty);
      expect(problems.every((p) => p.category == ProblemCategory.syntax), isTrue);
      expect(problems.every((p) => p.severity == ProblemSeverity.error), isTrue);
      expect(problems.every((p) => p.line != null && p.column != null), isTrue);
    });

    test('صياغة سليمة لكن المعاينة لا تدعمها => تحذير من فئة preview وليس خطأ', () {
      const source = '''
class Home extends StatelessWidget {
  Widget build(BuildContext context) {
    return Builder(builder: (BuildContext c) => Text('x'));
  }
}
''';
      final problems = ProblemsAnalyzer.analyzeDartFile('/p/home.dart', 'home.dart', source);
      expect(problems, isNotEmpty);
      expect(problems.every((p) => p.category == ProblemCategory.preview), isTrue);
      expect(problems.every((p) => p.severity != ProblemSeverity.error), isTrue);
    });

    test('تعديل الكود وإصلاحه يُنتج نتيجة جديدة بلا بقايا من النتيجة القديمة', () {
      const broken = 'void main() {\n  var a = 1\n}\n';
      const fixed = 'void main() {\n  var a = 1;\n}\n';
      expect(ProblemsAnalyzer.analyzeDartFile('/p/m.dart', 'm.dart', broken), isNotEmpty);
      expect(ProblemsAnalyzer.analyzeDartFile('/p/m.dart', 'm.dart', fixed), isEmpty);
    });
  });
}
