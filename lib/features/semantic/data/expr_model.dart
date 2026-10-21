/// شجرة تعبيرات مبسَّطة تحوي فقط ما يحتاجه التحقق الدلالي: المعرِّفات،
/// الوصول لعضو، الاستدعاءات (مع الوسائط المسمّاة)، القيم الحرفية. أي تعبير
/// آخر يُمثَّل بـ[XOther] مع ما بداخله من تعبيرات مهمّة، فلا يضيع شيء.
///
/// **مبدأ حاسم**: اسم الوسيط المسمّى يُحفَظ في [XArg.name] كنص فقط، ولا يُنشأ
/// له [XIdent] أبدًا — فالمدقِّق لا يستطيع بنيويًا أن يحلّه كمتغيّر.
abstract class XExpr {
  final int offset;
  final int length;
  const XExpr(this.offset, this.length);
}

/// معرِّف بسيط: `controller`, `AppColor`, `this`.
class XIdent extends XExpr {
  final String name;
  const XIdent(super.offset, super.length, this.name);
}

/// وصول لعضو بلا استدعاء: `AppColor.backgroundColor`، `controller.username`،
/// `AppTheme().light`، `Theme.of(context).textTheme`.
class XMember extends XExpr {
  final XExpr target;
  final String name;
  final int nameOffset;
  const XMember(super.offset, super.length, this.target, this.name, this.nameOffset);
}

class XArg {
  /// اسم الوسيط المسمّى (`mycontroller`)، أو null للموضعي.
  final String? name;
  final int nameOffset;
  final XExpr value;
  const XArg({this.name, this.nameOffset = 0, required this.value});
}

/// استدعاء: `Foo(...)`، `Foo.named(...)`، `x.method(...)`، `foo(...)`.
/// [target] هو ما قبل النقطة (null للاستدعاء المباشر)، و[name] اسم
/// المُنشئ/الدالة، و[nameOffset] موضع هذا الاسم.
class XCall extends XExpr {
  final XExpr? target;
  final String name;
  final int nameOffset;
  final List<XArg> args;
  final bool isConst;
  const XCall(
    super.offset,
    super.length, {
    this.target,
    required this.name,
    required this.nameOffset,
    this.args = const [],
    this.isConst = false,
  });
}

/// قيمة حرفية. [typeName]: String / int / double / bool / Null / List / Map / Set / Symbol.
class XLiteral extends XExpr {
  final String typeName;
  const XLiteral(super.offset, super.length, this.typeName);
}

/// متغيّر محلي ظاهر في نطاق: نوعه المُعلَن أو المُستنتَج من مُهيِّئه.
class LocalVar {
  final String? typeSource;
  final String? inferredType;
  const LocalVar({this.typeSource, this.inferredType});
}

/// نطاق (كتلة/دالة) يعرّف متغيّرات محلية ظاهرة لكل ما بداخله.
class XScope extends XExpr {
  final Map<String, LocalVar> locals;
  final List<XExpr> children;
  const XScope(super.offset, super.length, {this.locals = const {}, this.children = const []});
}

/// أي تعبير لا يهمّ المدقِّق بنفسه (عمليات، شروط، lambdas...) مع تعبيراته الداخلية.
class XOther extends XExpr {
  final List<XExpr> children;
  const XOther(super.offset, super.length, [this.children = const []]);
}

/// جسم عضو (دالة/حقل/مُنشئ/دالة عليا): [ownerClass] اسم الصنف الحاوي (null
/// للدوال العليا)، و[isStatic] هل السياق static (لا `this`).
class XBody {
  final String? ownerClass;
  final bool isStatic;
  final XExpr root;
  const XBody({this.ownerClass, this.isStatic = false, required this.root});
}
