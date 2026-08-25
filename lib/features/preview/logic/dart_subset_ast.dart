/// عقد AST لِـ"Dart Subset" — المجموعة الجزئية من صياغة Dart التي يفهمها
/// مُفسِّر المعاينة الحي. راجع README (قسم "حدود المُفسِّر") لمعرفة ما هو
/// مدعوم فعليًا وما هو خارج هذا الإصدار.
///
/// **تحديث**: أُضيفت عقد for/while/break/continue ودوال مساعدة متعددة داخل
/// الصنف — أول خطوة من خارطة التوسّع الموثَّقة في README (كانت هذه أبرز
/// أسباب رفض كود Dart سليم سابقًا).
library dart_subset_ast;

// ------------------------- Expressions -------------------------

abstract class Expr {}

class LiteralExpr extends Expr {
  final Object? value; // String | num | bool | null
  LiteralExpr(this.value);
}

/// نص يحتوي أجزاء ثابتة وأجزاء تعبيرية ${...} — يمثّل String interpolation.
class InterpolationExpr extends Expr {
  final List<Object> parts; // كل عنصر إما String ثابت أو Expr
  InterpolationExpr(this.parts);
}

class IdentifierExpr extends Expr {
  final String name;
  IdentifierExpr(this.name);
}

/// عنصر "for" داخل قائمة (collection-for) — مثل:
/// `[for (var item in items) Text(item)]`. مدعوم فقط بصيغة for-in (وليس
/// for الكلاسيكية بثلاثة أجزاء) لأنها الحالة الشائعة فعليًا لبناء children
/// ديناميكيًا في أشجار الودجتس.
class ListForElement {
  final String varName;
  final Expr iterable;
  final Expr element;
  ListForElement(this.varName, this.iterable, this.element);
}

class ListExpr extends Expr {
  // كل عنصر إمّا Expr مباشر أو ListForElement (collection-for).
  final List<Object> elements;
  ListExpr(this.elements);
}

class MapEntryNode {
  final Expr key;
  final Expr value;
  MapEntryNode(this.key, this.value);
}

class MapExpr extends Expr {
  final List<MapEntryNode> entries;
  MapExpr(this.entries);
}

/// يغطي: استدعاء دالة، إنشاء كائن (constructor call)، واستدعاء تابع على كائن
/// (عندما يكون callee من نوع PropertyExpr).
///
/// [id]: معرّف ثابت وفريد لهذه العقدة تحديدًا، يُمنَح مرة واحدة عند إنشائها
/// أثناء التحليل ويبقى كما هو طوال عمر الشجرة (لا يتغيّر عبر عمليات إعادة
/// البناء المتتالية بعد setState، لأن الشجرة نفسها لا تُعاد تحليلها إلا عند
/// "إعادة تشغيل" كاملة). يُستخدم هذا المعرّف لبناء مفتاح هوية كل نسخة
/// StatefulWidget — راجع التوثيق في widget_interpreter.dart لدعم "نسخ
/// متعددة نشطة من نفس الصنف".
class CallExpr extends Expr {
  static int _nextId = 0;
  final int id;
  final Expr callee;
  final List<Expr> positionalArgs;
  final Map<String, Expr> namedArgs;
  CallExpr(this.callee, this.positionalArgs, this.namedArgs) : id = _nextId++;
}

class PropertyExpr extends Expr {
  final Expr target;
  final String name;
  PropertyExpr(this.target, this.name);
}

class LambdaExpr extends Expr {
  final List<String> params;
  final List<Stmt> body;
  LambdaExpr(this.params, this.body);
}

class BinaryExpr extends Expr {
  final Expr left;
  final String op;
  final Expr right;
  BinaryExpr(this.left, this.op, this.right);
}

class UnaryExpr extends Expr {
  final String op; // '!' أو '-'
  final Expr operand;
  UnaryExpr(this.op, this.operand);
}

class TernaryExpr extends Expr {
  final Expr condition;
  final Expr thenExpr;
  final Expr elseExpr;
  TernaryExpr(this.condition, this.thenExpr, this.elseExpr);
}

class IndexExpr extends Expr {
  final Expr target;
  final Expr index;
  IndexExpr(this.target, this.index);
}

// ------------------------- Statements -------------------------

abstract class Stmt {}

class ExprStmt extends Stmt {
  final Expr expr;
  ExprStmt(this.expr);
}

class ReturnStmt extends Stmt {
  final Expr? value;
  ReturnStmt(this.value);
}

class VarDeclStmt extends Stmt {
  final String name;
  final Expr? initializer;
  VarDeclStmt(this.name, this.initializer);
}

class AssignStmt extends Stmt {
  final Expr target; // IdentifierExpr أو PropertyExpr
  final String op; // = | += | -=
  final Expr value;
  AssignStmt(this.target, this.op, this.value);
}

class IncDecStmt extends Stmt {
  final Expr target;
  final String op; // ++ | --
  IncDecStmt(this.target, this.op);
}

class IfStmt extends Stmt {
  final Expr condition;
  final List<Stmt> thenBranch;
  final List<Stmt> elseBranch;
  IfStmt(this.condition, this.thenBranch, this.elseBranch);
}

/// for الكلاسيكية: `for (init; condition; increment) { ... }`.
/// init/condition/increment جميعها اختيارية (تدعم `for (;;)`).
class ForStmt extends Stmt {
  final Stmt? init;
  final Expr? condition;
  final Stmt? increment;
  final List<Stmt> body;
  ForStmt(this.init, this.condition, this.increment, this.body);
}

/// for-in: `for (var x in iterable) { ... }`.
class ForInStmt extends Stmt {
  final String varName;
  final Expr iterable;
  final List<Stmt> body;
  ForInStmt(this.varName, this.iterable, this.body);
}

class WhileStmt extends Stmt {
  final Expr condition;
  final List<Stmt> body;
  WhileStmt(this.condition, this.body);
}

class BreakStmt extends Stmt {}

class ContinueStmt extends Stmt {}

/// تعريف حقل داخل صنف (مثل `int _counter = 0;`) — يُستخرج مسبقًا بواسطة
/// [ClassExtractor] وليس أثناء تنفيذ الجُمل العادية.
class FieldDecl {
  final String name;
  final Expr? initializer;
  FieldDecl(this.name, this.initializer);
}

/// تعريف دالة مساعدة داخل صنف (غير build/createState) — مثل:
/// `Widget _buildRow(String label) { ... }`. تُستدعى من داخل build (أو من
/// دالة مساعدة أخرى بنفس الصنف) كاستدعاء عادي بالاسم، وتُنفَّذ بنفس آلية
/// تنفيذ build (قائمة جُمل + التقاط ReturnStmt الأخير كناتج).
class MethodDef {
  final String name;
  final List<String> params;
  final List<Stmt> body;
  MethodDef(this.name, this.params, this.body);
}

/// تمثيل مبسّط لصنف Widget مستخرَج من الكود المصدري: اسمه، حقوله (إن وُجدت
/// كصنف State)، جسم دالة build كاملًا (قائمة جُمل وليس تعبيرًا واحدًا فقط —
/// هذا ما يسمح بوجود متغيرات/حلقات/شروط قبل return)، ودواله المساعدة.
class WidgetClassDef {
  final String name;
  final String? baseType; // StatelessWidget / StatefulWidget / State<...>
  final String? stateClassName; // لصنف Stateful: اسم صنف الحالة المرتبط به
  final List<FieldDecl> fields;
  final List<Stmt>? buildBody;
  final List<MethodDef> methods;
  // السبب الحقيقي لفشل تحليل build (إن فشل) — يُستخدَم لعرض رسالة خطأ دقيقة
  // بدل رسالة عامة "تعذّر تحليل build" لا تشرح السبب الفعلي. null يعني إما
  // نجاح التحليل، أو عدم وجود build إطلاقًا في هذا الصنف (طبيعي لأصناف
  // StatefulWidget التي تُعرَّف build في صنف State المرتبط بها لا هنا).
  final String? buildParseError;

  WidgetClassDef({
    required this.name,
    this.baseType,
    this.stateClassName,
    this.fields = const [],
    this.buildBody,
    this.methods = const [],
    this.buildParseError,
  });
}
