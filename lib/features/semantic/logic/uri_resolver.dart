import 'dart:io';

import 'package:path/path.dart' as p;

/// واجهة صغيرة لفحص نظام الملفات — تُستبدَل في الاختبارات بنسخة في الذاكرة.
abstract class FileProbe {
  bool fileExists(String path);

  /// أسماء العناصر المباشرة داخل مجلد بحالة أحرفها الفعلية على القرص.
  List<String> listNames(String dirPath);
}

class IoFileProbe implements FileProbe {
  const IoFileProbe();

  @override
  bool fileExists(String path) => File(path).existsSync();

  @override
  List<String> listNames(String dirPath) {
    try {
      return Directory(dirPath).listSync(followLinks: false).map((e) => p.basename(e.path)).toList();
    } catch (_) {
      return const [];
    }
  }
}

/// سياق المشروع اللازم لحلّ الاستيرادات.
class ProjectContext {
  final String rootPath;

  /// اسم حزمة المشروع من `pubspec.yaml` (حقل name) — null إن لم يُعرَف.
  final String? packageName;

  /// حزم خارجية مسموح استيرادها (من pubspec.lock أو dependencies) — لا تُفهرَس.
  final Set<String> externalPackages;
  final FileProbe probe;

  /// يُرجع true لأسماء معروفة مسبقًا أنها من مكتبات خارجية (مثل ودجتس Flutter).
  /// تُستخدَم **للتخفيف فقط**: لا نقترح تصحيحًا إملائيًا لاسم معروف أنه صحيح.
  final bool Function(String name)? isKnownExternalName;

  const ProjectContext({
    required this.rootPath,
    this.packageName,
    this.externalPackages = const {},
    this.probe = const IoFileProbe(),
    this.isKnownExternalName,
  });
}

enum ImportFailure { fileNotFound, fileCaseMismatch, unknownPackage, packageCaseMismatch }

class ImportResolution {
  /// مسار ملف المشروع المحلول (مُطبَّع)، أو null.
  final String? path;

  /// مكتبة خارجية (dart:/حزمة من pubspec) — صالحة لكنها لا تُفهرَس.
  final bool isExternal;
  final ImportFailure? failure;

  /// الاقتراح الصحيح: مسار/اسم حزمة بحالة الأحرف الفعلية.
  final String? suggestion;

  const ImportResolution._({this.path, this.isExternal = false, this.failure, this.suggestion});

  factory ImportResolution.project(String path) => ImportResolution._(path: path);
  factory ImportResolution.external() => const ImportResolution._(isExternal: true);
  factory ImportResolution.failed(ImportFailure failure, {String? suggestion}) =>
      ImportResolution._(failure: failure, suggestion: suggestion);
}

/// يحلّ مسارات الاستيراد: النسبية و`package:` — بفحص المسار الفعلي واسم الحزمة
/// وحالة الأحرف (حسّاسة في Dart وعلى أندرويد)، لا بافتراض أن المسار صحيح
/// لأنه "يبدو" صحيحًا.
class UriResolver {
  final ProjectContext context;
  const UriResolver(this.context);

  ImportResolution resolve(String importingFile, String uri) {
    if (uri.startsWith('dart:')) return ImportResolution.external();
    if (uri.startsWith('package:')) return _resolvePackage(uri);

    final dir = p.dirname(importingFile);
    final target = p.normalize(p.join(dir, uri));
    return _resolveFile(target, (fixed) => _posix(p.relative(fixed, from: dir)));
  }

  ImportResolution _resolvePackage(String uri) {
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    if (slash <= 0) return ImportResolution.failed(ImportFailure.fileNotFound);
    final pkg = rest.substring(0, slash);
    final pathPart = rest.substring(slash + 1);

    final name = context.packageName;
    if (name != null && pkg == name) {
      final libDir = p.join(context.rootPath, 'lib');
      final target = p.normalize(p.join(libDir, pathPart));
      return _resolveFile(target, (fixed) => 'package:$name/${_posix(p.relative(fixed, from: libDir))}');
    }
    if (context.externalPackages.contains(pkg)) return ImportResolution.external();

    final lower = pkg.toLowerCase();
    if (name != null && name.toLowerCase() == lower) {
      return ImportResolution.failed(ImportFailure.packageCaseMismatch, suggestion: name);
    }
    for (final ext in context.externalPackages) {
      if (ext.toLowerCase() == lower) {
        return ImportResolution.failed(ImportFailure.packageCaseMismatch, suggestion: ext);
      }
    }
    return ImportResolution.failed(ImportFailure.unknownPackage);
  }

  ImportResolution _resolveFile(String target, String Function(String fixedPath) uriFor) {
    final real = _resolveIgnoringCase(target);
    if (real == null) {
      // لا يمكن سرد المجلدات (أو الملف غير موجود): نعتمد على فحص الوجود المباشر.
      if (context.probe.fileExists(target)) return ImportResolution.project(target);
      return ImportResolution.failed(ImportFailure.fileNotFound);
    }
    if (real != target) {
      return ImportResolution.failed(ImportFailure.fileCaseMismatch, suggestion: uriFor(real));
    }
    return ImportResolution.project(target);
  }

  /// يمشي مكوّنات المسار من الجذر مقارِنًا كل مكوّن بأسماء المجلد الفعلية
  /// (المطابقة التامة أولًا ثم مطابقة تتجاهل الحالة). يُرجع المسار بحالته
  /// الفعلية، أو null إن لم يوجد.
  String? _resolveIgnoringCase(String target) {
    final parts = p.split(p.normalize(target));
    if (parts.isEmpty) return null;
    var current = parts.first;
    for (var i = 1; i < parts.length; i++) {
      final names = context.probe.listNames(current);
      if (names.isEmpty) return null;
      String? match;
      if (names.contains(parts[i])) {
        match = parts[i];
      } else {
        final lower = parts[i].toLowerCase();
        for (final n in names) {
          if (n.toLowerCase() == lower) {
            match = n;
            break;
          }
        }
      }
      if (match == null) return null;
      current = p.join(current, match);
    }
    return p.normalize(current);
  }

  static String _posix(String s) => s.replaceAll('\\', '/');
}
