import 'package:flutter/material.dart';
import 'package:flutter_mobile_ide/features/settings/logic/settings_provider.dart';
import 'package:flutter_mobile_ide/main.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('أول تشغيل: تظهر شاشة الترحيب', (WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        initialSettingsProvider.overrideWithValue(const SettingsState(isLoaded: true)),
      ],
      child: const FlutterMobileIdeApp(),
    ));
    await tester.pump();

    expect(find.textContaining('Flutter Mobile IDE'), findsWidgets);
    expect(find.text('التالي'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
