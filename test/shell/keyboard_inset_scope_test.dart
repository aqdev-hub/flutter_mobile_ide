import 'package:flutter/material.dart';
import 'package:flutter_mobile_ide/core/widgets/keyboard_inset_scope.dart';
import 'package:flutter_test/flutter_test.dart';

int _staticBuilds = 0;

class _Static extends StatelessWidget {
  const _Static();
  @override
  Widget build(BuildContext context) {
    _staticBuilds++;
    return const SizedBox();
  }
}

class _Reader extends StatelessWidget {
  const _Reader();
  @override
  Widget build(BuildContext context) => Text('inset=${KeyboardInsetScope.of(context).toInt()}');
}

void main() {
  testWidgets('المستهلك يرى الارتفاع الجديد، وغير المستهلك لا يُعاد بناؤه', (tester) async {
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    _staticBuilds = 0;

    await tester.pumpWidget(const MaterialApp(
      home: KeyboardInsetScope(
        child: Column(children: [_Reader(), _Static()]),
      ),
    ));
    expect(find.text('inset=0'), findsOneWidget);
    expect(_staticBuilds, 1);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(find.text('inset=300'), findsOneWidget);
    expect(_staticBuilds, 1, reason: 'child ثابت فلا يُعاد بناؤه عند تغيّر الكيبورد');

    tester.view.viewInsets = FakeViewPadding.zero;
    await tester.pump();
    expect(find.text('inset=0'), findsOneWidget);
  });

  testWidgets('بدون نطاق فوق السياق يُعيد 0', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Reader()));
    expect(find.text('inset=0'), findsOneWidget);
  });
}
