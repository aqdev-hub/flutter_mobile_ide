// ignore: implementation_imports
import 'package:flutter_code_editor/src/code_field/ide_selection_autoscroll.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('edgeScrollDelta', () {
    double d(double p) => edgeScrollDelta(pointer: p, min: 100, max: 500);

    test('داخل المنطقة الآمنة: صفر', () {
      expect(d(300), 0);
      expect(d(160), 0); // الحد الداخلي للمنطقة (100 + 48 = 148)
    });

    test('قرب الحافة العليا/اليسرى: سالب، وتزداد السرعة كلما اقترب', () {
      final far = d(140);
      final near = d(105);
      expect(far, lessThan(0));
      expect(near, lessThan(far));
    });

    test('قرب الحافة السفلى/اليمنى: موجب', () {
      expect(d(490), greaterThan(0));
      expect(d(490), lessThan(d(500) + 0.0001));
    });

    test('تجاوز الحافة يُثبّت السرعة عند الحد الأقصى (320 بكسل/ث)', () {
      expect(d(0), -320);
      expect(d(900), 320);
    });

    test('لا قفزة عند حدّ المنطقة: السرعة هناك شبه صفر ثم تتصاعد تربيعيًا', () {
      expect(d(147).abs(), lessThan(1));
      // منتصف المنطقة (t=0.5) => ربع الحد الأقصى
      expect(d(124), closeTo(-80, 0.001));
    });

    test('مدى صغير أو معدوم: لا تمرير ولا انهيار', () {
      expect(edgeScrollDelta(pointer: 5, min: 10, max: 10), 0);
      expect(edgeScrollDelta(pointer: 5, min: 10, max: 8), 0);
      // مدى 30: المنطقة = 10، فمنتصفه آمن.
      expect(edgeScrollDelta(pointer: 25, min: 10, max: 40), 0);
    });
  });
}
