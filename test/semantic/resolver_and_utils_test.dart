import 'package:flutter_mobile_ide/features/semantic/logic/pubspec_reader.dart';
import 'package:flutter_mobile_ide/features/semantic/logic/text_similarity.dart';
import 'package:flutter_mobile_ide/features/semantic/logic/uri_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

import 'semantic_test_support.dart';

void main() {
  group('UriResolver', () {
    final colorPath = lib('core/constant/color.dart');
    final screenPath = lib('view/screen/signup.dart');
    UriResolver withFiles(List<String> paths) => UriResolver(ProjectContext(
          rootPath: root,
          packageName: 'my',
          externalPackages: const {'flutter'},
          probe: FakeProbe(paths),
        ));
    final resolver = withFiles(const []);

    test('package: للمشروع و"نسبي" يصلان لنفس الملف الفعلي', () {
      final r = withFiles([colorPath, screenPath]);
      expect(r.resolve(screenPath, 'package:my/core/constant/color.dart').path, colorPath);
      expect(r.resolve(screenPath, '../../core/constant/color.dart').path, colorPath);
    });

    test('dart: وحزمة خارجية => external', () {
      expect(resolver.resolve(screenPath, 'dart:async').isExternal, isTrue);
      expect(resolver.resolve(screenPath, 'package:flutter/material.dart').isExternal, isTrue);
    });

    test('اسم الحزمة حسّاس لحالة الأحرف', () {
      final r = withFiles([colorPath]);
      final res = r.resolve(screenPath, 'package:MY/core/constant/color.dart');
      expect(res.failure, ImportFailure.packageCaseMismatch);
      expect(res.suggestion, 'my');
    });

    test('حالة أحرف الملف تُكتشف حتى لو كان المسار "يبدو" صحيحًا', () {
      final r = withFiles([colorPath]);
      final res = r.resolve(screenPath, 'package:my/core/Constant/color.dart');
      expect(res.failure, ImportFailure.fileCaseMismatch);
      expect(res.suggestion, 'package:my/core/constant/color.dart');
    });

    test('ملف غير موجود وحزمة مجهولة', () {
      final r = withFiles([colorPath]);
      expect(r.resolve(screenPath, 'package:my/none.dart').failure, ImportFailure.fileNotFound);
      expect(r.resolve(screenPath, 'package:ghost/a.dart').failure, ImportFailure.unknownPackage);
    });
  });

  group('pubspec', () {
    test('اسم الحزمة وتبعياتها', () {
      const content = '''
name: my
description: demo
dependencies:
  flutter:
    sdk: flutter
  get: ^4.6.6 # تعليق
  flutter_otp_text_field: ^1.5.0
dev_dependencies:
  flutter_test:
    sdk: flutter
flutter:
  uses-material-design: true
''';
      final info = parsePubspec(content);
      expect(info.name, 'my');
      expect(info.dependencies, {'flutter', 'get', 'flutter_otp_text_field', 'flutter_test'});
    });

    test('pubspec.lock: كل الحزم المحلولة', () {
      const lock = '''
packages:
  async:
    dependency: transitive
    description:
      name: async
    source: hosted
    version: "2.13.1"
  flutter:
    dependency: "direct main"
    description: flutter
    source: sdk
sdks:
  dart: ">=3.0.0 <4.0.0"
''';
      expect(parsePubspecLockPackages(lock), {'async', 'flutter'});
    });
  });

  group('nearestName', () {
    test('خطأ إملائي، تبديل متجاورَين، فرق حالة', () {
      expect(nearestName('AppColors', ['AppColor', 'AppTheme']), 'AppColor');
      expect(nearestName('onPerssed', ['onPressed', 'child']), 'onPressed');
      expect(nearestName('appcolor', ['AppColor']), 'AppColor');
    });

    test('لا اقتراح للأسماء البعيدة أو القصيرة المختلفة', () {
      expect(nearestName('abc', ['xyz']), isNull);
      expect(nearestName('ab', ['ac']), isNull);
    });
  });
}
