import 'package:path/path.dart' as p;

import '../data/project_model.dart';
import 'uri_resolver.dart';

class ResolvedName {
  final ClassInfo? cls;
  final TopLevelDecl? top;
  final String filePath;
  const ResolvedName({this.cls, this.top, required this.filePath});
}

/// الأسماء الظاهرة داخل ملف: تعريفاته + ما يستورده من ملفات المشروع (مع مراعاة
/// show/hide وإعادة التصدير export) + البوادئ (`as x`).
class VisibleScope {
  final Map<String, ResolvedName> names;
  final Map<String, Map<String, ResolvedName>> prefixes;

  /// بوادئ مربوطة باستيراد خارجي/غير محلول — ما يلحقها غير معروف لنا.
  final Set<String> externalPrefixes;
  const VisibleScope(this.names, this.prefixes, this.externalPrefixes);
}

enum Subtype { yes, no, unknown }

class MemberLookup {
  final MemberInfo? member;
  final ClassInfo? owner;

  /// true إن كان في سلسلة الأسلاف نوع لا نعرف تعريفه (خارجي/غير محلول)،
  /// فغياب العضو لا يعني أنه غير موجود فعلًا.
  final bool inconclusive;
  const MemberLookup({this.member, this.owner, this.inconclusive = false});
}

/// فهرس المشروع: كل ملف بما يعرّفه، وحلّ الأسماء بين الملفات وفق الاستيرادات
/// الفعلية — لا وفق قائمة أسماء ثابتة.
class ProjectIndex {
  final ProjectContext context;
  final Map<String, FileModel> files = {};
  final UriResolver _resolver;
  final Map<String, ImportResolution> _imports = {};
  final Map<String, Map<String, ResolvedName>> _exported = {};
  final Map<String, VisibleScope> _scopes = {};

  ProjectIndex(this.context, Iterable<FileModel> models) : _resolver = UriResolver(context) {
    for (final m in models) {
      files[key(m.path)] = m;
    }
  }

  static String key(String path) => p.normalize(path);

  FileModel? fileAt(String path) => files[key(path)];

  ImportResolution resolveImport(FileModel file, ImportInfo imp) {
    final k = '${key(file.path)}|${imp.uri}';
    return _imports.putIfAbsent(k, () => _resolver.resolve(file.path, imp.uri));
  }

  Iterable<MapEntry<String, ResolvedName>> _filtered(Map<String, ResolvedName> ns, ImportInfo imp) {
    return ns.entries.where((e) {
      if (imp.show.isNotEmpty && !imp.show.contains(e.key)) return false;
      if (imp.hide.contains(e.key)) return false;
      return true;
    });
  }

  /// الأسماء العامة التي يُصدّرها ملف: تعريفاته غير الخاصة + ما يعيد تصديره.
  Map<String, ResolvedName> exportedNamespace(String filePath, [Set<String>? visiting]) {
    final k = key(filePath);
    final cached = _exported[k];
    if (cached != null) return cached;
    final seen = visiting ?? <String>{};
    if (!seen.add(k)) return const {};
    final file = files[k];
    if (file == null) return const {};

    final result = <String, ResolvedName>{};
    for (final c in file.classes) {
      if (!c.name.startsWith('_')) result[c.name] = ResolvedName(cls: c, filePath: file.path);
    }
    for (final t in file.topLevel) {
      if (!t.name.startsWith('_')) result.putIfAbsent(t.name, () => ResolvedName(top: t, filePath: file.path));
    }
    for (final imp in file.imports) {
      if (!imp.isExport) continue;
      final target = resolveImport(file, imp).path;
      if (target == null) continue;
      for (final e in _filtered(exportedNamespace(target, seen), imp)) {
        result.putIfAbsent(e.key, () => e.value);
      }
    }
    _exported[k] = result;
    return result;
  }

  VisibleScope scopeOf(String filePath) {
    final k = key(filePath);
    final cached = _scopes[k];
    if (cached != null) return cached;
    final file = files[k];
    if (file == null) return const VisibleScope({}, {}, {});

    final names = <String, ResolvedName>{};
    for (final c in file.classes) {
      names[c.name] = ResolvedName(cls: c, filePath: file.path);
    }
    for (final t in file.topLevel) {
      names.putIfAbsent(t.name, () => ResolvedName(top: t, filePath: file.path));
    }

    final prefixes = <String, Map<String, ResolvedName>>{};
    final externalPrefixes = <String>{};
    for (final imp in file.imports) {
      if (imp.isExport) continue;
      final target = resolveImport(file, imp).path;
      if (target == null) {
        if (imp.prefix != null) externalPrefixes.add(imp.prefix!);
        continue;
      }
      final ns = _filtered(exportedNamespace(target), imp);
      if (imp.prefix == null) {
        for (final e in ns) {
          names.putIfAbsent(e.key, () => e.value);
        }
      } else {
        final map = prefixes.putIfAbsent(imp.prefix!, () => {});
        for (final e in ns) {
          map.putIfAbsent(e.key, () => e.value);
        }
      }
    }
    final scope = VisibleScope(names, prefixes, externalPrefixes);
    _scopes[k] = scope;
    return scope;
  }

  /// كل أصناف المشروع العامة بهذا الاسم (لاكتشاف "معرَّف لكنه غير مستورَد").
  List<ClassInfo> classesNamed(String name) {
    final out = <ClassInfo>[];
    for (final f in files.values) {
      for (final c in f.classes) {
        if (c.name == name && !c.name.startsWith('_')) out.add(c);
      }
    }
    return out;
  }

  Iterable<String> allPublicClassNames() sync* {
    for (final f in files.values) {
      for (final c in f.classes) {
        if (!c.name.startsWith('_')) yield c.name;
      }
    }
  }

  /// أفضل نص استيراد من [fromFile] إلى [targetFile]: `package:` إن كان الهدف
  /// تحت lib/ وللمشروع اسم حزمة، وإلا مسار نسبي.
  String importUriFor(String fromFile, String targetFile) {
    final name = context.packageName;
    final libDir = p.join(context.rootPath, 'lib');
    if (name != null && p.isWithin(libDir, targetFile)) {
      return 'package:$name/${p.relative(targetFile, from: libDir).replaceAll('\\', '/')}';
    }
    return p.relative(targetFile, from: p.dirname(fromFile)).replaceAll('\\', '/');
  }

  ClassInfo? resolveClassFrom(ClassInfo from, String baseName) => scopeOf(from.filePath).names[baseName]?.cls;

  List<String> _parentNames(ClassInfo cls) => [
        if (cls.superclass != null) cls.superclass!,
        ...cls.mixins,
        ...cls.interfaces,
      ];

  /// يبحث عن عضو في الصنف ثم في أسلافه من ملفات المشروع (extends/with/implements).
  MemberLookup lookupMember(ClassInfo cls, String name, [Set<ClassInfo>? seen]) {
    final visited = seen ?? <ClassInfo>{};
    if (!visited.add(cls)) return const MemberLookup();

    MemberInfo? best;
    for (final m in cls.members) {
      if (m.name != name) continue;
      if (best == null || best.kind == MemberKind.setter) best = m;
    }
    if (best != null) return MemberLookup(member: best, owner: cls);

    var inconclusive = false;
    for (final raw in _parentNames(cls)) {
      final base = TypeName.parse(raw)?.base;
      if (base == null) {
        inconclusive = true;
        continue;
      }
      if (base == 'Object') continue;
      final parent = resolveClassFrom(cls, base);
      if (parent == null) {
        inconclusive = true;
        continue;
      }
      final r = lookupMember(parent, name, visited);
      if (r.member != null) return r;
      if (r.inconclusive) inconclusive = true;
    }
    return MemberLookup(inconclusive: inconclusive);
  }

  /// أسماء الأعضاء المتاحة (للاقتراحات): الصنف وأسلافه المعروفة.
  Set<String> memberNames(ClassInfo cls, {bool? isStatic, Set<ClassInfo>? seen}) {
    final visited = seen ?? <ClassInfo>{};
    final out = <String>{};
    if (!visited.add(cls)) return out;
    for (final m in cls.members) {
      if (isStatic == null || m.isStatic == isStatic || m.kind == MemberKind.enumValue) out.add(m.name);
    }
    for (final raw in _parentNames(cls)) {
      final base = TypeName.parse(raw)?.base;
      if (base == null || base == 'Object') continue;
      final parent = resolveClassFrom(cls, base);
      if (parent != null) out.addAll(memberNames(parent, isStatic: isStatic, seen: visited));
    }
    return out;
  }

  /// هل [cls] من نوع [targetBase]؟ `no` فقط إن كانت سلسلة الأسلاف كلها معروفة.
  Subtype subtypeOf(ClassInfo cls, String targetBase, [Set<ClassInfo>? seen]) {
    if (cls.name == targetBase) return Subtype.yes;
    final visited = seen ?? <ClassInfo>{};
    if (!visited.add(cls)) return Subtype.no;

    var unknown = false;
    for (final raw in _parentNames(cls)) {
      final base = TypeName.parse(raw)?.base;
      if (base == null) {
        unknown = true;
        continue;
      }
      if (base == targetBase) return Subtype.yes;
      if (base == 'Object') continue;
      final parent = resolveClassFrom(cls, base);
      if (parent == null) {
        unknown = true;
        continue;
      }
      final r = subtypeOf(parent, targetBase, visited);
      if (r == Subtype.yes) return Subtype.yes;
      if (r == Subtype.unknown) unknown = true;
    }
    return unknown ? Subtype.unknown : Subtype.no;
  }
}
