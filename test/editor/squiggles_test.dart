import 'package:flutter/material.dart';
import 'package:flutter_mobile_ide/features/editor/logic/squiggles.dart';
import 'package:flutter_test/flutter_test.dart';

String _plain(InlineSpan span) => span.toPlainText();

/// يجمع (نص، هل هو مسطَّر) لكل جزء ورقي في الشجرة.
List<(String, bool)> _leaves(TextSpan span) {
  final out = <(String, bool)>[];
  void walk(TextSpan s) {
    final text = s.text;
    if (text != null && text.isNotEmpty) {
      out.add((text, s.style?.decoration == TextDecoration.underline));
    }
    for (final c in s.children ?? const <InlineSpan>[]) {
      if (c is TextSpan) walk(c);
    }
  }

  walk(span);
  return out;
}

void main() {
  const red = Colors.red;

  group('applySquiggles', () {
    test('لا يغيّر النص أبدًا، ويسطّر المدى المطلوب فقط', () {
      final root = TextSpan(children: [
        const TextSpan(text: 'var a = 1'),
        const TextSpan(text: '\nvar b = 2;'),
      ]);
      final result = applySquiggles(root, [const SquiggleRange(4, 5, red)]);
      expect(_plain(result), 'var a = 1\nvar b = 2;');
      final underlined = _leaves(result).where((l) => l.$2).map((l) => l.$1).toList();
      expect(underlined, ['a']);
    });

    test('مدى يمتد عبر عدة أجزاء ملوَّنة', () {
      final root = TextSpan(children: [
        TextSpan(text: 'const ', style: const TextStyle(color: Colors.blue)),
        TextSpan(text: 'Login', style: const TextStyle(color: Colors.green)),
        const TextSpan(text: '();'),
      ]);
      final result = applySquiggles(root, [const SquiggleRange(3, 8, red)]);
      expect(_plain(result), 'const Login();');
      final underlined = _leaves(result).where((l) => l.$2).map((l) => l.$1).join();
      expect(underlined, 'st Lo');
    });

    test('بلا مدى => نفس الشجرة', () {
      const root = TextSpan(text: 'abc');
      expect(identical(applySquiggles(root, const []), root), isTrue);
    });
  });

  group('remapSquiggles', () {
    test('الكتابة قبل المدى تُزيحه، وبعده لا تمسّه', () {
      const ranges = [SquiggleRange(10, 12, red)];
      final shifted = remapSquiggles(ranges, 'abcdefghij kl', 'XXabcdefghij kl');
      expect(shifted.single.start, 12);
      expect(shifted.single.end, 14);

      final same = remapSquiggles(ranges, 'abcdefghij kl', 'abcdefghij klXX');
      expect(same.single.start, 10);
    });

    test('تعديل داخل المدى يحذفه حتى يصل تحليل جديد', () {
      const ranges = [SquiggleRange(4, 8, red)];
      expect(remapSquiggles(ranges, 'abcdEFGHijkl', 'abcdEFxGHijkl'), isEmpty);
    });
  });

  group('visibleRange', () {
    test('المدى الصفري يتوسّع لمحرف مرئي ولا يقع على سطر جديد', () {
      expect(visibleRange('var a = 1\nvar b;', 9, 0), (8, 9)); // قبل السطر الجديد
      expect(visibleRange('abc', 1, 0), (1, 2));
      expect(visibleRange('', 0, 0), isNull);
    });

    test('المدى الموجب يُقصّ عند نهاية النص', () {
      expect(visibleRange('abc', 1, 10), (1, 3));
    });
  });
}
