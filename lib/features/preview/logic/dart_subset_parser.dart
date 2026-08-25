import 'dart_subset_ast.dart';

class ParseException implements Exception {
  final String message;
  ParseException(this.message);
  @override
  String toString() => 'خطأ تحليل: $message';
}

enum _TokType { identifier, string, number, symbol, eof }

class _Token {
  final _TokType type;
  final String text;
  final Object? value; // للنصوص المحتوية على أجزاء تفاعلية (InterpolationExpr)
  _Token(this.type, this.text, [this.value]);
}

const _kSymbols = [
  '=>', '==', '!=', '<=', '>=', '&&', '||', '??', '+=', '-=', '++', '--',
  '(', ')', '{', '}', '[', ']', ',', ':', ';', '.', '+', '-', '*', '/', '%',
  '!', '?', '<', '>', '=',
];

/// محلّل لفظي مبسّط: يفصل نص Dart إلى tokens. يدعم الفواصل، السلاسل النصية
/// (بما فيها ${...} interpolation)، الأرقام، والرموز الشائعة في تعبيرات
/// بناء الواجهات واستدعاءات setState/Navigator البسيطة.
class _Lexer {
  final String src;
  int pos = 0;
  _Lexer(this.src);

  List<_Token> tokenize() {
    final tokens = <_Token>[];
    while (true) {
      _skipWhitespaceAndComments();
      if (pos >= src.length) break;
      final ch = src[pos];

      if (ch == '"' || ch == "'") {
        tokens.add(_readString(ch));
        continue;
      }
      if (RegExp(r'[0-9]').hasMatch(ch)) {
        tokens.add(_readNumber());
        continue;
      }
      if (RegExp(r'[A-Za-z_$]').hasMatch(ch)) {
        tokens.add(_readIdentifier());
        continue;
      }
      final symbol = _readSymbol();
      tokens.add(_Token(_TokType.symbol, symbol));
    }
    tokens.add(_Token(_TokType.eof, ''));
    return tokens;
  }

  void _skipWhitespaceAndComments() {
    while (pos < src.length) {
      final ch = src[pos];
      if (ch == ' ' || ch == '\n' || ch == '\t' || ch == '\r') {
        pos++;
      } else if (ch == '/' && pos + 1 < src.length && src[pos + 1] == '/') {
        while (pos < src.length && src[pos] != '\n') {
          pos++;
        }
      } else {
        break;
      }
    }
  }

  _Token _readNumber() {
    final start = pos;
    // دعم الصيغة السداسية عشرية: 0x.../0X... — بدونها كانت 0xFFE3F2FD
    // تُقرأ كرمزين مكسورين ("0" ثم مُعرِّف "xFFE3F2FD")، وهو السبب الجذري
    // وراء فشل أي استخدام لـ Color(0x...).
    if (src[pos] == '0' && pos + 1 < src.length && (src[pos + 1] == 'x' || src[pos + 1] == 'X')) {
      pos += 2;
      while (pos < src.length && RegExp(r'[0-9a-fA-F]').hasMatch(src[pos])) {
        pos++;
      }
      return _Token(_TokType.number, src.substring(start, pos));
    }
    while (pos < src.length && RegExp(r'[0-9.]').hasMatch(src[pos])) {
      pos++;
    }
    return _Token(_TokType.number, src.substring(start, pos));
  }

  _Token _readIdentifier() {
    final start = pos;
    while (pos < src.length && RegExp(r'[A-Za-z0-9_$]').hasMatch(src[pos])) {
      pos++;
    }
    return _Token(_TokType.identifier, src.substring(start, pos));
  }

  String _readSymbol() {
    for (final symbol in _kSymbols) {
      if (src.startsWith(symbol, pos)) {
        pos += symbol.length;
        return symbol;
      }
    }
    // رمز غير معروف: نتخطاه بدل تعطيل التحليل بالكامل.
    pos++;
    return '';
  }

  _Token _readString(String quote) {
    pos++; // تجاوز علامة الاقتباس الافتتاحية
    final parts = <Object>[];
    final buffer = StringBuffer();
    while (pos < src.length && src[pos] != quote) {
      if (src[pos] == r'$' && pos + 1 < src.length && src[pos + 1] == '{') {
        if (buffer.isNotEmpty) {
          parts.add(buffer.toString());
          buffer.clear();
        }
        pos += 2;
        final exprStart = pos;
        var depth = 1;
        while (pos < src.length && depth > 0) {
          if (src[pos] == '{') depth++;
          if (src[pos] == '}') depth--;
          if (depth > 0) pos++;
        }
        final exprSrc = src.substring(exprStart, pos);
        pos++; // تجاوز '}'
        parts.add(DartSubsetParser.parseExpressionSource(exprSrc));
      } else if (src[pos] == r'$' && pos + 1 < src.length && RegExp(r'[A-Za-z_]').hasMatch(src[pos + 1])) {
        if (buffer.isNotEmpty) {
          parts.add(buffer.toString());
          buffer.clear();
        }
        pos++;
        final start = pos;
        while (pos < src.length && RegExp(r'[A-Za-z0-9_]').hasMatch(src[pos])) {
          pos++;
        }
        parts.add(IdentifierExpr(src.substring(start, pos)));
      } else if (src[pos] == '\\' && pos + 1 < src.length) {
        buffer.write(src[pos + 1]);
        pos += 2;
      } else {
        buffer.write(src[pos]);
        pos++;
      }
    }
    if (buffer.isNotEmpty) parts.add(buffer.toString());
    pos++; // تجاوز علامة الاقتباس الختامية
    return _Token(_TokType.string, '', parts);
  }
}

/// محلّل نحوي تنازلي (recursive-descent) يبني AST من قائمة tokens.
/// يدعم تعبيرات إنشاء الودجتس المتشعبة، وجُملًا (شروط/تعيينات/زيادة/حلقات
/// for و while وbreak/continue) كافية لأغلب أنماط الشاشات العملية.
class DartSubsetParser {
  final List<_Token> _tokens;
  int pos = 0;
  DartSubsetParser(this._tokens);

  static Expr parseExpressionSource(String source) {
    final tokens = _Lexer(source).tokenize();
    return DartSubsetParser(tokens)._expression();
  }

  static List<Stmt> parseStatementsSource(String source) {
    final tokens = _Lexer(source).tokenize();
    final parser = DartSubsetParser(tokens);
    final statements = <Stmt>[];
    while (!parser._check(_TokType.eof)) {
      statements.add(parser._statement());
    }
    return statements;
  }

  _Token get _current => _tokens[pos];

  bool _check(_TokType type, [String? text]) {
    if (_current.type != type) return false;
    if (text != null && _current.text != text) return false;
    return true;
  }

  bool _match(String symbolOrKeyword) {
    if ((_current.type == _TokType.symbol || _current.type == _TokType.identifier) &&
        _current.text == symbolOrKeyword) {
      pos++;
      return true;
    }
    return false;
  }

  _Token _advance() => _tokens[pos++];

  _Token _expect(String text) {
    if (!_match(text)) {
      throw ParseException('متوقَّع "$text" لكن وُجد "${_current.text}"');
    }
    return _tokens[pos - 1];
  }

  // ------------------------- Statements -------------------------

  Stmt _statement() {
    if (_match('if')) return _ifStatement();
    if (_match('for')) return _forStatement();
    if (_match('while')) return _whileStatement();
    if (_match('break')) {
      _match(';');
      return BreakStmt();
    }
    if (_match('continue')) {
      _match(';');
      return ContinueStmt();
    }
    if (_match('return')) {
      if (_match(';')) return ReturnStmt(null);
      final value = _expression();
      _match(';');
      return ReturnStmt(value);
    }
    if (_check(_TokType.identifier, 'final') || _check(_TokType.identifier, 'var')) {
      _advance();
      final name = _advance().text; // اسم المتغيّر التالي مباشرة بعد final/var
      Expr? init;
      if (_match('=')) init = _expression();
      _match(';');
      return VarDeclStmt(name, init);
    }
    return _expressionOrAssignStatement();
  }

  Stmt _ifStatement() {
    _expect('(');
    final condition = _expression();
    _expect(')');
    final thenBranch = _block();
    var elseBranch = <Stmt>[];
    if (_match('else')) {
      elseBranch = _match('if') ? [_ifStatement()] : _block();
    }
    return IfStmt(condition, thenBranch, elseBranch);
  }

  /// يدعم صيغتين: for-in (`for (var x in items) {...}`) وfor الكلاسيكية
  /// (`for (init; cond; increment) {...}`) — يميّز بينهما بترقّب الرمزين
  /// التاليين (اسم ثم 'in') قبل الالتزام بأي مسار.
  Stmt _forStatement() {
    _expect('(');

    final startPos = pos;
    var lookahead = pos;
    if (_tokens[lookahead].type == _TokType.identifier &&
        (_tokens[lookahead].text == 'final' || _tokens[lookahead].text == 'var')) {
      lookahead++;
    }
    if (_tokens[lookahead].type == _TokType.identifier &&
        lookahead + 1 < _tokens.length &&
        _tokens[lookahead + 1].type == _TokType.identifier &&
        _tokens[lookahead + 1].text == 'in') {
      final varName = _tokens[lookahead].text;
      pos = lookahead + 2; // تجاوز الاسم و'in'
      final iterable = _expression();
      _expect(')');
      final body = _block();
      return ForInStmt(varName, iterable, body);
    }

    pos = startPos;
    Stmt? init;
    if (!_check(_TokType.symbol, ';')) {
      init = _statement(); // تستهلك الفاصلة المنقوطة تلقائيًا
    } else {
      _match(';');
    }
    final condition = _check(_TokType.symbol, ';') ? null : _expression();
    _expect(';');
    final increment = _check(_TokType.symbol, ')') ? null : _expressionOrAssignStatement();
    _expect(')');
    final body = _block();
    return ForStmt(init, condition, increment, body);
  }

  Stmt _whileStatement() {
    _expect('(');
    final condition = _expression();
    _expect(')');
    final body = _block();
    return WhileStmt(condition, body);
  }

  List<Stmt> _block() {
    if (_match('{')) {
      final statements = <Stmt>[];
      while (!_check(_TokType.symbol, '}') && !_check(_TokType.eof)) {
        statements.add(_statement());
      }
      _expect('}');
      return statements;
    }
    // جملة واحدة بدون أقواس، مثل: `if (x) y = 1;`
    return [_statement()];
  }

  Stmt _expressionOrAssignStatement() {
    final expr = _expression();
    if (_match('=')) {
      final value = _expression();
      _match(';');
      return AssignStmt(expr, '=', value);
    }
    if (_match('+=')) {
      final value = _expression();
      _match(';');
      return AssignStmt(expr, '+=', value);
    }
    if (_match('-=')) {
      final value = _expression();
      _match(';');
      return AssignStmt(expr, '-=', value);
    }
    if (_match('++')) {
      _match(';');
      return IncDecStmt(expr, '++');
    }
    if (_match('--')) {
      _match(';');
      return IncDecStmt(expr, '--');
    }
    _match(';');
    return ExprStmt(expr);
  }

  // ------------------------- Expressions -------------------------
  // ترتيب الأولوية: ternary > or > and > equality > relational > additive
  // > multiplicative > unary > postfix > primary

  Expr _expression() => _ternary();

  Expr _ternary() {
    final condition = _or();
    if (_match('?')) {
      final thenExpr = _expression();
      _expect(':');
      final elseExpr = _expression();
      return TernaryExpr(condition, thenExpr, elseExpr);
    }
    return condition;
  }

  Expr _or() {
    var left = _and();
    while (_match('||')) {
      left = BinaryExpr(left, '||', _and());
    }
    return left;
  }

  Expr _and() {
    var left = _equality();
    while (_match('&&')) {
      left = BinaryExpr(left, '&&', _equality());
    }
    return left;
  }

  Expr _equality() {
    var left = _relational();
    while (_check(_TokType.symbol, '==') || _check(_TokType.symbol, '!=')) {
      final op = _advance().text;
      left = BinaryExpr(left, op, _relational());
    }
    return left;
  }

  Expr _relational() {
    var left = _additive();
    while (['<', '>', '<=', '>='].contains(_current.text) && _current.type == _TokType.symbol) {
      final op = _advance().text;
      left = BinaryExpr(left, op, _additive());
    }
    return left;
  }

  Expr _additive() {
    var left = _multiplicative();
    while (_check(_TokType.symbol, '+') || _check(_TokType.symbol, '-')) {
      final op = _advance().text;
      left = BinaryExpr(left, op, _multiplicative());
    }
    return left;
  }

  Expr _multiplicative() {
    var left = _unary();
    while (_check(_TokType.symbol, '*') || _check(_TokType.symbol, '/') || _check(_TokType.symbol, '%')) {
      final op = _advance().text;
      left = BinaryExpr(left, op, _unary());
    }
    return left;
  }

  Expr _unary() {
    if (_match('!') || _check(_TokType.symbol, '-')) {
      final op = _advance().text;
      return UnaryExpr(op, _unary());
    }
    return _postfix();
  }

  Expr _postfix() {
    var expr = _primary();
    while (true) {
      if (_match('.')) {
        final name = _advance().text;
        if (_check(_TokType.symbol, '(')) {
          final (positional, named) = _argumentList();
          expr = CallExpr(PropertyExpr(expr, name), positional, named);
        } else {
          expr = PropertyExpr(expr, name);
        }
      } else if (_check(_TokType.symbol, '(')) {
        final (positional, named) = _argumentList();
        expr = CallExpr(expr, positional, named);
      } else if (_match('[')) {
        final index = _expression();
        _expect(']');
        expr = IndexExpr(expr, index);
      } else {
        break;
      }
    }
    return expr;
  }

  (List<Expr>, Map<String, Expr>) _argumentList() {
    _expect('(');
    final positional = <Expr>[];
    final named = <String, Expr>{};
    while (!_check(_TokType.symbol, ')')) {
      if (_current.type == _TokType.identifier && _tokens[pos + 1].text == ':') {
        final name = _advance().text;
        _expect(':');
        named[name] = _expression();
      } else {
        positional.add(_expression());
      }
      if (!_match(',')) break;
    }
    _expect(')');
    return (positional, named);
  }

  Expr _primary() {
    // const / new: كلمات مفتاحية زخرفية، نتجاوزها ونكمل تحليل التعبير التالي.
    if (_match('const') || _match('new')) return _primary();

    if (_check(_TokType.number)) {
      final text = _advance().text;
      return LiteralExpr(text.contains('.') ? double.parse(text) : int.parse(text));
    }
    if (_check(_TokType.string)) {
      final token = _advance();
      final parts = token.value as List<Object>;
      if (parts.length == 1 && parts.first is String) return LiteralExpr(parts.first);
      if (parts.isEmpty) return LiteralExpr('');
      return InterpolationExpr(parts);
    }
    if (_match('true')) return LiteralExpr(true);
    if (_match('false')) return LiteralExpr(false);
    if (_match('null')) return LiteralExpr(null);

    if (_match('[')) {
      final elements = <Object>[];
      while (!_check(_TokType.symbol, ']')) {
        if (_match('for')) {
          elements.add(_collectionForElement());
        } else {
          elements.add(_expression());
        }
        if (!_match(',')) break;
      }
      _expect(']');
      return ListExpr(elements);
    }

    if (_match('{')) {
      final entries = <MapEntryNode>[];
      while (!_check(_TokType.symbol, '}')) {
        final key = _expression();
        _expect(':');
        final value = _expression();
        entries.add(MapEntryNode(key, value));
        if (!_match(',')) break;
      }
      _expect('}');
      return MapExpr(entries);
    }

    if (_match('(')) {
      // إمّا تعبير بين أقواس، أو دالة لامدا: (params) => expr / (params) { ... }
      final savedPos = pos;
      final params = <String>[];
      var isParamList = true;
      if (!_check(_TokType.symbol, ')')) {
        while (true) {
          if (_current.type != _TokType.identifier) {
            isParamList = false;
            break;
          }
          params.add(_advance().text);
          if (!_match(',')) break;
        }
      }
      if (isParamList && _match(')') && (_check(_TokType.symbol, '=>') || _check(_TokType.symbol, '{'))) {
        if (_match('=>')) {
          final bodyExpr = _expression();
          _match(';');
          return LambdaExpr(params, [ReturnStmt(bodyExpr)]);
        }
        final body = _block();
        return LambdaExpr(params, body);
      }
      // لم تكن قائمة معاملات لامدا: نُرجع المؤشر ونحلّلها كتعبير بين أقواس عادي.
      pos = savedPos;
      final inner = _expression();
      _expect(')');
      return inner;
    }

    if (_check(_TokType.identifier)) {
      final name = _advance().text;
      return IdentifierExpr(name);
    }

    throw ParseException('تعبير غير متوقَّع: "${_current.text}"');
  }

  /// عنصر collection-for داخل قائمة: `for (var x in items) elementExpr`.
  /// مدعوم فقط بصيغة for-in (الحالة العملية لبناء children ديناميكيًا) —
  /// وليس for الكلاسيكية بثلاثة أجزاء، ولا شرط `if` مصاحب.
  ListForElement _collectionForElement() {
    _expect('(');
    _match('final');
    _match('var');
    final varName = _advance().text;
    if (!_match('in')) {
      throw ParseException('صيغة for داخل قائمة تتطلب "in" (نمط for-in فقط مدعوم هنا)');
    }
    final iterable = _expression();
    _expect(')');
    final element = _expression();
    return ListForElement(varName, iterable, element);
  }
}
