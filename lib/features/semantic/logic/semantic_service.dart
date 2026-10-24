import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/project_model.dart';
import 'ast_to_model.dart';
import 'project_index.dart';
import 'pubspec_reader.dart';
import 'semantic_checker.dart';
import 'uri_resolver.dart';

/// يحتفظ بنماذج كل ملفات `lib/` للمشروع المفتوح ويشغّل [SemanticChecker] على
/// ملف واحد بنصّه الحيّ (غير المحفوظ) مقابل بقية المشروع.
///
/// مبدأ التحديث: قائمة الملفات تأتي من شجرة المشروع في كل استدعاء — ما أُضيف
/// يُقرأ ويُحلَّل، وما اختفى يُحذَف، وما بقي يُعاد استخدام نموذجه. ملف يُحرَّر
/// يُحدَّث نموذجه بنصّه الحيّ عند كل فحص؛ أما بقية الملفات فتُقرأ من القرص عند
/// أول ظهور و[updateFileText] بعد كل حفظ.
class SemanticService {
  final bool Function(String name)? isKnownExternalName;
  SemanticService({this.isKnownExternalName});

  String? _root;
  String? _packageName;
  Set<String> _externalPackages = {'flutter'};
  DateTime? _pubspecStamp;
  final Map<String, FileModel> _models = {};
  Future<void> _lock = Future.value();

  /// بعد حفظ ملف: نموذجه في الفهرس يُبنى من النص المحفوظ.
  void updateFileText(String path, String text) {
    final k = ProjectIndex.key(path);
    if (_models.containsKey(k)) _models[k] = AstToModel.build(path, text);
  }

  /// يفحص [filePath] بنصّه [content]. يُرجع قائمة فارغة للملفات خارج `lib/`.
  Future<List<SemanticDiagnostic>> check({
    required String rootPath,
    required List<String> dartFiles,
    required String filePath,
    required String content,
  }) async {
    final run = _lock.then((_) => _sync(rootPath, dartFiles));
    _lock = run.catchError((_) {});
    await run;

    final k = ProjectIndex.key(filePath);
    if (!_models.containsKey(k)) return const [];

    final model = AstToModel.build(filePath, content);
    _models[k] = model;
    if (model.skipSemantic) return const [];

    final context = ProjectContext(
      rootPath: rootPath,
      packageName: _packageName,
      externalPackages: _externalPackages,
      probe: const IoFileProbe(),
      isKnownExternalName: isKnownExternalName,
    );
    final index = ProjectIndex(context, _models.values);
    return SemanticChecker(index).check(model);
  }

  Future<void> _sync(String rootPath, List<String> dartFiles) async {
    if (_root != rootPath) {
      _root = rootPath;
      _models.clear();
      _pubspecStamp = null;
    }
    await _readPubspec(rootPath);

    final wanted = {for (final f in dartFiles) ProjectIndex.key(f): f};
    _models.removeWhere((k, _) => !wanted.containsKey(k));

    var loaded = 0;
    for (final entry in wanted.entries) {
      if (_models.containsKey(entry.key)) continue;
      try {
        final text = await File(entry.value).readAsString();
        _models[entry.key] = AstToModel.build(entry.value, text);
      } catch (_) {
        // ملف تعذّرت قراءته: يبقى خارج الفهرس بدل إفشال الفحص كله.
      }
      // نترك للواجهة فرصة الرسم أثناء بناء فهرس مشروع كبير لأول مرة.
      if (++loaded % 15 == 0) await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> _readPubspec(String rootPath) async {
    final pubspec = File(p.join(rootPath, 'pubspec.yaml'));
    try {
      if (!await pubspec.exists()) return;
      final stamp = (await pubspec.stat()).modified;
      if (_pubspecStamp == stamp) return;
      _pubspecStamp = stamp;

      final info = parsePubspec(await pubspec.readAsString());
      _packageName = info.name;
      final packages = <String>{'flutter', ...info.dependencies};

      final lock = File(p.join(rootPath, 'pubspec.lock'));
      if (await lock.exists()) {
        packages.addAll(parsePubspecLockPackages(await lock.readAsString()));
      }
      _externalPackages = packages;
    } catch (_) {
      // pubspec غير مقروء: نُبقي القيم السابقة.
    }
  }
}
