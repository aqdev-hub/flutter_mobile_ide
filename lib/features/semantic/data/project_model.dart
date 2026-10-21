import 'expr_model.dart';

/// نموذج بسيط (Dart خالص، بلا أي اعتماد على حزمة analyzer) لما يعرّفه كل ملف
/// في المشروع: أصنافه ومنشئاته وأعضاؤه واستيراداته. تملؤه طبقة تحويل من شجرة
/// Dart الحقيقية، ويقرؤه الفهرس والمدقِّق الدلالي — فكلاهما قابل للاختبار
/// بمعزل عن المحلل.

enum ParamKind { positional, optionalPositional, named }

class ParamInfo {
  final String name;
  final ParamKind kind;

  /// للوسائط المسمّاة: هل كُتبت بالكلمة `required`؟ (الموضعية العادية مطلوبة دائمًا.)
  final bool isRequired;

  /// النوع كما كُتب. null عند `this.x` أو `super.x` (يُستنتج من الحقل/الأب).
  final String? typeSource;
  final bool isThisParam;
  final bool isSuperParam;
  final bool hasDefault;

  const ParamInfo({
    required this.name,
    this.kind = ParamKind.positional,
    this.isRequired = false,
    this.typeSource,
    this.isThisParam = false,
    this.isSuperParam = false,
    this.hasDefault = false,
  });
}

class ConstructorInfo {
  /// اسم المُنشئ المسمّى، أو '' للمُنشئ الافتراضي (غير المسمّى).
  final String name;
  final List<ParamInfo> params;
  final bool isConst;
  final bool isFactory;
  final int offset;

  const ConstructorInfo({
    this.name = '',
    this.params = const [],
    this.isConst = false,
    this.isFactory = false,
    this.offset = 0,
  });
}

enum MemberKind { field, getter, setter, method, enumValue }

class MemberInfo {
  final String name;
  final MemberKind kind;
  final bool isStatic;

  /// النوع المُعلَن: نوع الحقل، أو نوع الإرجاع للـgetter/الدالة.
  final String? typeSource;

  /// اسم النوع المُستنتَج من المُهيِّئ عند غياب النوع المُعلَن
  /// (مثل `static const x = Color(0xFF...)` => Color، أو literal نصي => String).
  final String? inferredType;
  final List<ParamInfo> params;
  final int offset;
  final int length;

  const MemberInfo({
    required this.name,
    required this.kind,
    this.isStatic = false,
    this.typeSource,
    this.inferredType,
    this.params = const [],
    this.offset = 0,
    this.length = 0,
  });

  TypeName? get type {
    final declared = TypeName.parse(typeSource);
    if (declared != null) return declared;
    final inferred = inferredType;
    return inferred == null ? null : TypeName(inferred);
  }
}

enum ClassKind { classDecl, mixinDecl, enumDecl, extensionDecl, extensionType }

class ClassInfo {
  final String name;
  final String filePath;
  final ClassKind kind;
  final bool isAbstract;

  /// أسماء الأنواع كما كُتبت (قد تحوي generics مثل `State<Home>`).
  final String? superclass;
  final List<String> mixins;
  final List<String> interfaces;
  final List<String> typeParams;
  final List<ConstructorInfo> constructors;
  final List<MemberInfo> members;
  final int offset;
  final int length;

  ClassInfo({
    required this.name,
    required this.filePath,
    this.kind = ClassKind.classDecl,
    this.isAbstract = false,
    this.superclass,
    this.mixins = const [],
    this.interfaces = const [],
    this.typeParams = const [],
    this.constructors = const [],
    this.members = const [],
    this.offset = 0,
    this.length = 0,
  });
}

class ImportInfo {
  /// نص المسار كما كُتب (بدون علامتي الاقتباس).
  final String uri;
  final String? prefix;
  final bool isExport;
  final bool isDeferred;
  final List<String> show;
  final List<String> hide;

  /// موضع نص المسار (literal) داخل الملف — يُعلَّم تحته الخطأ.
  final int offset;
  final int length;

  const ImportInfo({
    required this.uri,
    this.prefix,
    this.isExport = false,
    this.isDeferred = false,
    this.show = const [],
    this.hide = const [],
    this.offset = 0,
    this.length = 0,
  });
}

enum TopLevelKind { function, variable, typedef }

class TopLevelDecl {
  final String name;
  final TopLevelKind kind;
  final String? typeSource;
  final String? inferredType;
  final List<ParamInfo> params;
  final int offset;
  final int length;

  const TopLevelDecl({
    required this.name,
    required this.kind,
    this.typeSource,
    this.inferredType,
    this.params = const [],
    this.offset = 0,
    this.length = 0,
  });

  TypeName? get type {
    final declared = TypeName.parse(typeSource);
    if (declared != null) return declared;
    final inferred = inferredType;
    return inferred == null ? null : TypeName(inferred);
  }
}

class FileModel {
  final String path;
  final String text;
  final List<ClassInfo> classes;
  final List<TopLevelDecl> topLevel;
  final List<ImportInfo> imports;

  /// أجسام الدوال/الحقول كشجرة تعبيرات مبسَّطة (راجع expr_model.dart).
  final List<XBody> bodies;

  /// أخطاء صياغة الملف نفسه (من محلل Dart) — تُذكَر عند الإبلاغ عن تعريف مفقود
  /// لأن الخطأ النحوي قد يُخفي تعريفات الملف.
  final int syntaxErrorCount;
  final int? firstSyntaxErrorLine;

  late final LineIndex lines = LineIndex(text);

  FileModel({
    required this.path,
    required this.text,
    this.classes = const [],
    this.topLevel = const [],
    this.imports = const [],
    this.bodies = const [],
    this.syntaxErrorCount = 0,
    this.firstSyntaxErrorLine,
  });
}

/// اسم نوع مُبسَّط: الاسم الأساسي بلا generics ولا `?`.
class TypeName {
  final String base;
  final bool nullable;
  const TypeName(this.base, {this.nullable = false});

  static TypeName? parse(String? source) {
    if (source == null) return null;
    var s = source.trim();
    if (s.isEmpty) return null;

    final lt = s.indexOf('<');
    final head = lt == -1 ? s : s.substring(0, lt);
    if (head.contains('Function')) {
      return TypeName('Function', nullable: s.endsWith('?'));
    }

    var nullable = false;
    if (s.endsWith('?')) {
      nullable = true;
      s = s.substring(0, s.length - 1).trim();
    }
    final lt2 = s.indexOf('<');
    if (lt2 != -1) s = s.substring(0, lt2).trim();
    if (s.isEmpty || s.startsWith('(')) return null;
    return TypeName(s, nullable: nullable);
  }
}

/// يحوّل إزاحة محرف إلى (سطر، عمود) — كلاهما يبدأ من 1.
class LineIndex {
  final List<int> _starts = [0];

  LineIndex(String text) {
    for (var i = 0; i < text.length; i++) {
      if (text.codeUnitAt(i) == 10) _starts.add(i + 1);
    }
  }

  (int, int) locate(int offset) {
    var lo = 0;
    var hi = _starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (_starts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return (lo + 1, offset - _starts[lo] + 1);
  }
}
