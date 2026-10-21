import 'package:flutter_mobile_ide/features/semantic/data/expr_model.dart';
import 'package:flutter_mobile_ide/features/semantic/data/project_model.dart';
import 'package:flutter_mobile_ide/features/semantic/logic/project_index.dart';
import 'package:flutter_mobile_ide/features/semantic/logic/semantic_checker.dart';
import 'package:flutter_mobile_ide/features/semantic/logic/uri_resolver.dart';
import 'package:path/path.dart' as p;

/// جذر وهمي مطلق صالح على ويندوز وأندرويد/لينكس (لا يلمس القرص).
final String root = p.join(p.rootPrefix(p.current), 'fake_proj');
String lib(String relative) => p.normalize(p.join(root, 'lib', relative));

/// نظام ملفات في الذاكرة.
class FakeProbe implements FileProbe {
  final Set<String> files;
  FakeProbe(Iterable<String> paths) : files = {for (final f in paths) p.normalize(f)};

  @override
  bool fileExists(String path) => files.contains(p.normalize(path));

  @override
  List<String> listNames(String dirPath) {
    final dir = p.normalize(dirPath);
    final out = <String>{};
    for (final f in files) {
      if (p.isWithin(dir, f)) out.add(p.split(p.relative(f, from: dir)).first);
    }
    return out.toList();
  }
}

// ---- بُناة تعبيرات بإزاحات فريدة (لأن المدقِّق يزيل التكرار بالإزاحة+الرمز) ----
int _n = 0;
int _next() {
  _n += 20;
  return _n;
}

XIdent id(String name) => XIdent(_next(), name.length, name);
XMember mem(XExpr target, String name) => XMember(_next(), name.length, target, name, _next());
XLiteral lit(String type) => XLiteral(_next(), 3, type);
XArg arg(XExpr value, {String? name}) => XArg(name: name, nameOffset: _next(), value: value);
XCall call(String name, {XExpr? target, List<XArg> args = const []}) =>
    XCall(_next(), name.length, target: target, name: name, nameOffset: _next(), args: args);

XBody body(List<XExpr> exprs, {Map<String, LocalVar> locals = const {}, String? owner}) =>
    XBody(ownerClass: owner, root: XScope(0, 0, locals: locals, children: exprs));

ClassInfo cls(
  String name,
  String path, {
  List<MemberInfo> members = const [],
  List<ConstructorInfo> ctors = const [],
  String? superclass,
  bool isAbstract = false,
  ClassKind kind = ClassKind.classDecl,
}) =>
    ClassInfo(
      name: name,
      filePath: path,
      members: members,
      constructors: ctors,
      superclass: superclass,
      isAbstract: isAbstract,
      kind: kind,
      offset: _next(),
    );

MemberInfo field(String name, String type, {bool isStatic = false}) =>
    MemberInfo(name: name, kind: MemberKind.field, isStatic: isStatic, typeSource: type);

FileModel file(
  String path, {
  List<ClassInfo> classes = const [],
  List<ImportInfo> imports = const [],
  List<XBody> bodies = const [],
  int syntaxErrorCount = 0,
  int? firstSyntaxErrorLine,
}) =>
    FileModel(
      path: path,
      text: '',
      classes: classes,
      imports: imports,
      bodies: bodies,
      syntaxErrorCount: syntaxErrorCount,
      firstSyntaxErrorLine: firstSyntaxErrorLine,
    );

ImportInfo imp(String uri, {String? prefix, bool isExport = false, List<String> show = const [], List<String> hide = const []}) =>
    ImportInfo(uri: uri, prefix: prefix, isExport: isExport, show: show, hide: hide, offset: _next(), length: uri.length);

ProjectContext context(Iterable<FileModel> files, {Set<String> external = const {'flutter'}, bool Function(String)? known}) =>
    ProjectContext(
      rootPath: root,
      packageName: 'my',
      externalPackages: external,
      probe: FakeProbe(files.map((f) => f.path)),
      isKnownExternalName: known,
    );

List<SemanticDiagnostic> analyze(List<FileModel> files, FileModel target, {bool Function(String)? known}) {
  final index = ProjectIndex(context(files, known: known), files);
  return SemanticChecker(index).check(target);
}

List<String> codes(List<SemanticDiagnostic> d) => [for (final x in d) x.code];
