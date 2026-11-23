import 'package:flutter_mobile_ide/features/semantic/data/expr_model.dart';
import 'package:flutter_mobile_ide/features/semantic/data/project_model.dart';
import 'package:flutter_mobile_ide/features/semantic/logic/semantic_checker.dart';
import 'package:flutter_test/flutter_test.dart';

import 'semantic_test_support.dart';

/// الحالات الواقعية التي واجهتنا، مبنيّة على نموذج مشروع متعدد الملفات
/// (تعريفات في ملفات مستقلة + استيرادات `package:` ونسبية).
void main() {
  // ---------------- تعريفات المشروع ----------------
  final colorPath = lib('core/constant/color.dart');
  final themePath = lib('core/theme/app_theme.dart');
  final routesPath = lib('core/constant/routes.dart');
  final ctrlPath = lib('controller/signup_controller.dart');
  final fieldPath = lib('view/widget/auth/custom_text_form_auth.dart');
  final screenPath = lib('view/screen/signup.dart');

  ClassInfo appColor() => cls('AppColor', colorPath, members: [field('backgroundColor', 'Color', isStatic: true)]);
  ClassInfo appTheme() => cls('AppTheme', themePath, members: [
        const MemberInfo(name: 'light', kind: MemberKind.getter, typeSource: 'ThemeData'),
      ]);
  ClassInfo appRoute() => cls('AppRoute', routesPath, members: [
        const MemberInfo(name: 'signUp', kind: MemberKind.field, isStatic: true, inferredType: 'String'),
      ]);
  List<ClassInfo> controllers() => [
        cls('SignUpController', ctrlPath, isAbstract: true, members: [
          const MemberInfo(name: 'signUp', kind: MemberKind.method, typeSource: 'void'),
        ]),
        cls('SignUpControllerImp', ctrlPath, superclass: 'SignUpController', members: [
          field('username', 'TextEditingController'),
          field('email', 'TextEditingController'),
        ]),
      ];

  /// ودجت الحقل: المُنشئ يقبل `mycontroller` و`hinttext` كوسائط مسمّاة مطلوبة.
  ClassInfo textField({String controllerParam = 'mycontroller'}) => cls(
        'CustonTextFormAuth',
        fieldPath,
        members: [field(controllerParam, 'TextEditingController?'), field('hinttext', 'String')],
        ctors: [
          ConstructorInfo(isConst: true, params: [
            const ParamInfo(name: 'key', kind: ParamKind.named, isSuperParam: true),
            ParamInfo(name: controllerParam, kind: ParamKind.named, isRequired: true, isThisParam: true),
            const ParamInfo(name: 'hinttext', kind: ParamKind.named, isRequired: true, isThisParam: true),
          ]),
        ],
      );

  List<ImportInfo> allImports() => [
        imp('package:flutter/material.dart'),
        imp('package:my/core/constant/color.dart'),
        imp('package:my/core/theme/app_theme.dart'),
        imp('package:my/core/constant/routes.dart'),
        imp('package:my/controller/signup_controller.dart'),
        imp('../widget/auth/custom_text_form_auth.dart'),
      ];

  List<FileModel> project({ClassInfo? field0, List<ImportInfo>? imports, required List<XBody> bodies}) {
    final screen = file(screenPath, imports: imports ?? allImports(), bodies: bodies);
    return [
      file(colorPath, classes: [appColor()]),
      file(themePath, classes: [appTheme()]),
      file(routesPath, classes: [appRoute()]),
      file(ctrlPath, classes: controllers()),
      file(fieldPath, classes: [field0 ?? textField()]),
      screen,
    ];
  }

  List<SemanticDiagnostic> run(List<FileModel> files) => analyze(files, files.last);

  group('AppColor.backgroundColor', () {
    test('الاستخدام الصحيح عبر ملف مستقل واستيراد package: لا ينتج أي تشخيص', () {
      final files = project(bodies: [
        body([
          call('Scaffold', args: [arg(mem(id('AppColor'), 'backgroundColor'), name: 'backgroundColor')]),
        ]),
      ]);
      expect(run(files), isEmpty);
    });

    test('اسم صنف خاطئ (AppColors) => خطأ على الصنف نفسه مع اقتراح الاسم الصحيح', () {
      final files = project(bodies: [
        body([mem(id('AppColors'), 'backgroundColor')]),
      ]);
      final d = run(files);
      expect(codes(d), ['unknown_class']);
      expect(d.single.message, contains('AppColors'));
      expect(d.single.hint, contains('AppColor'));
    });

    test('عضو خاطئ (backgroundColour) => الخطأ عند العضو، لا "الصنف غير معروف"', () {
      final files = project(bodies: [
        body([mem(id('AppColor'), 'backgroundColour')]),
      ]);
      final d = run(files);
      expect(codes(d), ['unknown_member']);
      expect(d.single.message, contains('backgroundColour'));
      expect(d.single.message, contains('AppColor'));
      expect(d.single.hint, contains('backgroundColor'));
    });

    test('الصنف معرَّف لكن غير مستورَد في الملف => not_imported مع نص الاستيراد الجاهز', () {
      final files = project(
        imports: [imp('package:flutter/material.dart')],
        bodies: [
          body([mem(id('AppColor'), 'backgroundColor')]),
        ],
      );
      final d = run(files);
      expect(codes(d), ['not_imported']);
      expect(d.single.hint, contains('package:my/core/constant/color.dart'));
    });
  });

  group('AppTheme().light', () {
    test('عضو instance عبر كائن => صحيح', () {
      final files = project(bodies: [
        body([mem(call('AppTheme'), 'light')]),
      ]);
      expect(run(files), isEmpty);
    });

    test('عضو instance عبر اسم الصنف => خطأ دقيق يشرح الحل', () {
      final files = project(bodies: [
        body([mem(id('AppTheme'), 'light')]),
      ]);
      expect(codes(run(files)), ['instance_member_via_class']);
    });

    test('عضو static عبر كائن => خطأ دقيق', () {
      final files = project(bodies: [
        body([mem(call('AppColor'), 'backgroundColor')]),
      ]);
      expect(codes(run(files)), ['static_member_via_instance']);
    });

    test('عضو غير موجود في AppTheme', () {
      final files = project(bodies: [
        body([mem(call('AppTheme'), 'dark')]),
      ]);
      expect(codes(run(files)), ['unknown_member']);
    });
  });

  group('AppRoute.signUp', () {
    test('ثابت static معرَّف في ملف مستقل => صحيح', () {
      final files = project(bodies: [
        body([call('pushNamed', target: id('Navigator'), args: [arg(id('context')), arg(mem(id('AppRoute'), 'signUp'))])]),
      ]);
      expect(run(files), isEmpty);
    });

    test('فرق حالة أحرف في العضو (signup) => اقتراح signUp', () {
      final files = project(bodies: [
        body([mem(id('AppRoute'), 'signup')]),
      ]);
      final d = run(files);
      expect(codes(d), ['unknown_member']);
      expect(d.single.hint, contains('signUp'));
    });
  });

  group('mycontroller: controller.username', () {
    const locals = {'controller': LocalVar(typeSource: 'SignUpControllerImp')};

    test('وسيط مسمّى معرَّف + قيمة عضو من صنف مستورَد => صحيح بلا أي تشخيص', () {
      final files = project(bodies: [
        body([
          call('CustonTextFormAuth', args: [
            arg(mem(id('controller'), 'username'), name: 'mycontroller'),
            arg(lit('String'), name: 'hinttext'),
          ]),
        ], locals: locals),
      ]);
      expect(run(files), isEmpty);
    });

    test('المُنشئ لا يقبل الوسيط => unknown_named_arg عند اسم الوسيط، لا "متغير غير معروف"', () {
      final named = arg(mem(id('controller'), 'username'), name: 'mycontroller');
      final files = project(
        field0: textField(controllerParam: 'controller'),
        bodies: [
          body([
            call('CustonTextFormAuth', args: [named, arg(lit('String'), name: 'hinttext')]),
          ], locals: locals),
        ],
      );
      final d = run(files);
      final bad = d.where((x) => x.code == 'unknown_named_arg').toList();
      expect(bad, hasLength(1));
      expect(bad.single.offset, named.nameOffset); // عند اسم الوسيط تحديدًا
      expect(bad.single.message, contains('المُنشئ'));
      expect(bad.single.message, contains('mycontroller'));
      expect(bad.single.hint, contains('controller'));
      // المتغيّر controller وقيمته لا يُبلَّغ عنهما إطلاقًا
      expect(d.any((x) => x.code == 'unknown_variable' || x.code == 'unknown_class'), isFalse);
    });

    test('عضو خاطئ في القيمة (usernam) => خطأ عند العضو مع اقتراح username', () {
      final files = project(bodies: [
        body([
          call('CustonTextFormAuth', args: [
            arg(mem(id('controller'), 'usernam'), name: 'mycontroller'),
            arg(lit('String'), name: 'hinttext'),
          ]),
        ], locals: locals),
      ]);
      final d = run(files);
      expect(codes(d), ['unknown_member']);
      expect(d.single.hint, contains('username'));
    });

    test('نوع غير متوافق (تمرير المتحكم نفسه بدل TextEditingController)', () {
      final files = project(bodies: [
        body([
          call('CustonTextFormAuth', args: [
            arg(id('controller'), name: 'mycontroller'),
            arg(lit('String'), name: 'hinttext'),
          ]),
        ], locals: locals),
      ]);
      expect(codes(run(files)), ['type_mismatch']);
    });

    test('وسيط مطلوب مفقود، ووسيط موضعي زائد', () {
      final missing = project(bodies: [
        body([call('CustonTextFormAuth', args: [arg(lit('String'), name: 'hinttext')])], locals: locals),
      ]);
      expect(codes(run(missing)), ['missing_required_arg']);

      final extra = project(bodies: [
        body([call('CustonTextFormAuth', args: [arg(lit('String'))])], locals: locals),
      ]);
      expect(codes(run(extra)), contains('too_many_positional'));
    });

    test('سلسلة أسلاف خارجية (extends StatelessWidget): غياب العضو لا يُعتبر خطأ', () {
      final home = cls('Home', screenPath, superclass: 'StatelessWidget');
      final screen = file(screenPath, classes: [home], imports: [imp('package:flutter/material.dart')], bodies: [
        body([id('title'), mem(id('widget'), 'x')], owner: 'Home'),
      ]);
      final files = [
        file(colorPath, classes: [appColor()]),
        screen,
      ];
      expect(analyze(files, screen), isEmpty);
    });
  });

  group('الصنف غير المعروف', () {
    test('خطأ إملائي في اسم ودجت مخصصة => unknown_class مع اقتراح الاسم المعرَّف فعلًا', () {
      final button = cls('CustomButtonAuth', lib('view/widget/auth/custom_button_auth.dart'));
      final screen = file(screenPath, classes: [], imports: [imp('../widget/auth/custom_button_auth.dart')], bodies: [
        body([call('CustomButtomAuth')]),
      ]);
      final files = [file(button.filePath, classes: [button]), screen];
      final d = analyze(files, screen);
      expect(codes(d), ['unknown_class']);
      expect(d.single.hint, contains('CustomButtonAuth'));
    });

    test('اسم ودجت من Flutter لا نفهرسه لا يُبلَّغ عنه (حتى لو قارب اسمًا في المشروع)', () {
      final test0 = cls('Test', lib('test.dart'));
      final screen = file(screenPath, imports: [imp('package:flutter/material.dart')], bodies: [
        body([call('Text'), call('Scaffold')]),
      ]);
      final files = [file(test0.filePath, classes: [test0]), screen];
      expect(analyze(files, screen), isEmpty);
    });

    test('اسم معروف خارجيًا (known) لا يُقترح له تصحيح أبدًا', () {
      final target = cls('MaterialButtons', lib('mb.dart'));
      final screen = file(screenPath, bodies: [
        body([call('MaterialButton')]),
      ]);
      final files = [file(target.filePath, classes: [target]), screen];
      expect(analyze(files, screen, known: (n) => n == 'MaterialButton'), isEmpty);
    });
  });

  group('المُنشئات', () {
    test('مُنشئ مسمّى بخطأ إملائي => unknown_member مع اقتراح المُنشئ الصحيح', () {
      final c = cls('AppColor', colorPath, ctors: [const ConstructorInfo(name: 'dark')]);
      final screen = file(screenPath, imports: [imp('package:my/core/constant/color.dart')], bodies: [
        body([call('darc', target: id('AppColor'))]),
      ]);
      final d = analyze([file(colorPath, classes: [c]), screen], screen);
      expect(codes(d), ['unknown_member']);
      expect(d.single.hint, contains('dark'));
    });

    test('صنف abstract لا يُنشأ مباشرة', () {
      final files = project(bodies: [
        body([call('SignUpController')]),
      ]);
      expect(codes(run(files)), ['abstract_instantiation']);
    });
  });

  group('الاستيرادات والتصدير والبوادئ', () {
    test('استيراد ببادئة: c.AppColor.backgroundColor صحيح، وAppColor وحده خطأ يشرح السبب', () {
      final ok = project(
        imports: [imp('package:my/core/constant/color.dart', prefix: 'c')],
        bodies: [
          body([mem(mem(id('c'), 'AppColor'), 'backgroundColor')]),
        ],
      );
      expect(run(ok), isEmpty);

      final bad = project(
        imports: [imp('package:my/core/constant/color.dart', prefix: 'c')],
        bodies: [
          body([mem(id('AppColor'), 'backgroundColor')]),
        ],
      );
      final d = run(bad);
      expect(codes(d), ['unknown_class']);
      expect(d.single.message, contains('ببادئة'));
    });

    test('إعادة التصدير export: استيراد ملف يُصدّر color.dart يكشف AppColor', () {
      final all = lib('core/all.dart');
      final screen = file(screenPath, imports: [imp('package:my/core/all.dart')], bodies: [
        body([mem(id('AppColor'), 'backgroundColor')]),
      ]);
      final files = [
        file(colorPath, classes: [appColor()]),
        file(all, imports: [imp('package:my/core/constant/color.dart', isExport: true)]),
        screen,
      ];
      expect(analyze(files, screen), isEmpty);
    });

    test('hide في التصدير يُخفي الصنف => يعود إلى not_imported', () {
      final all = lib('core/all.dart');
      final screen = file(screenPath, imports: [imp('package:my/core/all.dart')], bodies: [
        body([mem(id('AppColor'), 'backgroundColor')]),
      ]);
      final files = [
        file(colorPath, classes: [appColor()]),
        file(all, imports: [imp('package:my/core/constant/color.dart', isExport: true, hide: ['AppColor'])]),
        screen,
      ];
      expect(codes(analyze(files, screen)), ['not_imported']);
    });

    test('استيراد نسبي صحيح بين مجلدات مختلفة', () {
      final files = project(
        imports: [imp('../widget/auth/custom_text_form_auth.dart')],
        bodies: [
          body([call('CustonTextFormAuth', args: [arg(lit('String'), name: 'hinttext'), arg(call('TextEditingController'), name: 'mycontroller')])]),
        ],
      );
      expect(run(files), isEmpty);
    });

    test('أخطاء مسار الاستيراد: غير موجود، حالة الملف، حالة اسم الحزمة، حزمة مجهولة', () {
      final screen = file(screenPath, imports: [
        imp('package:my/core/constant/missing.dart'),
        imp('package:my/core/constant/Color.dart'),
        imp('package:MY/core/constant/color.dart'),
        imp('package:nothere/x.dart'),
        imp('package:flutter/material.dart'),
        imp('dart:io'),
      ]);
      final files = [file(colorPath, classes: [appColor()]), screen];
      final d = analyze(files, screen);
      expect(codes(d), ['import_not_found', 'import_case_mismatch', 'package_case_mismatch', 'unknown_package']);
      expect(d[1].hint, contains('color.dart'));
      expect(d[2].hint, contains("'my'"));
    });

    test('ملف مستورَد فيه أخطاء صياغة => تحذير يشرح أنها قد تُخفي تعريفاته', () {
      final broken = file(colorPath, syntaxErrorCount: 2, firstSyntaxErrorLine: 5);
      final screen = file(screenPath, imports: [imp('package:my/core/constant/color.dart')]);
      final d = analyze([broken, screen], screen);
      expect(codes(d), ['imported_file_has_errors']);
      expect(d.single.severity, SemanticSeverity.warning);
    });
  });
}
