/// أدوات قراءة/تعديل قسم `dependencies:` داخل pubspec.yaml بشكل نصّي مباشر
/// (بدون مكتبة YAML كاملة) — بنفس روح مُفسِّر المعاينة: نطاق ضيّق وموثَّق
/// عمدًا بدل حل عام قد يُفسد تنسيق الملف الأصلي (المسافات/التعليقات) عند
/// إعادة الكتابة.
///
/// **حدود معروفة (موثَّقة عمدًا، وليست أخطاءً):**
/// - يتعامل فقط مع تبعيات السطر الواحد `name: ^1.2.3` (الحالة الشائعة —
///   راجع pubspec.yaml الحالي لهذا المشروع نفسه كمثال).
/// - تبعيات متعددة الأسطر مثل:
///   ```
///   flutter:
///     sdk: flutter
///   ```
///   تُعرَض للقراءة فقط (isEditable = false) — لا يمكن تعديلها من هذه
///   الواجهة لأنها لا تملك رقم إصدار بسيط أصلًا.
/// - لا يدعم `git:`/`path:`/`hosted:` كتبعية مركّبة — تظهر أيضًا read-only.
/// - يعمل فقط على قسم `dependencies:` (وليس `dev_dependencies:`) لأن هذا
///   هو النطاق المطلوب فعليًا لإدارة حزم المشروع من داخل التطبيق.
library pubspec_dependency_editor;

class PubspecDependency {
  final String name;
  final String? version; // null = تبعية غير بسيطة (sdk/git/path) — للقراءة فقط
  final bool isEditable;

  const PubspecDependency({required this.name, this.version, this.isEditable = true});
}

class PubspecParseResult {
  final List<PubspecDependency> dependencies;
  final int sectionStart; // فهرس سطر "dependencies:" نفسه
  final int sectionEnd; // فهرس أول سطر بعد نهاية القسم (exclusive)
  final bool found;

  const PubspecParseResult({
    required this.dependencies,
    required this.sectionStart,
    required this.sectionEnd,
    required this.found,
  });
}

class PubspecDependencyEditor {
  PubspecDependencyEditor._();

  static int _indentLevel(String line) {
    var count = 0;
    for (final ch in line.split('')) {
      if (ch == ' ') {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  static PubspecParseResult parse(String pubspecContent) {
    final lines = pubspecContent.split('\n');
    var sectionLineStart = -1;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trimRight() == 'dependencies:') {
        sectionLineStart = i;
        break;
      }
    }
    if (sectionLineStart == -1) {
      return const PubspecParseResult(dependencies: [], sectionStart: -1, sectionEnd: -1, found: false);
    }

    var sectionLineEnd = lines.length;
    for (var i = sectionLineStart + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trim().isEmpty) continue;
      // أي سطر بلا مسافة بادئة يعني الخروج من قسم dependencies بالكامل.
      if (!line.startsWith(' ') && !line.startsWith('\t')) {
        sectionLineEnd = i;
        break;
      }
    }

    final deps = <PubspecDependency>[];
    var i = sectionLineStart + 1;
    while (i < sectionLineEnd) {
      final line = lines[i];
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        i++;
        continue;
      }

      final match = RegExp(r'^(\w[\w.]*)\s*:\s*(.*)$').firstMatch(trimmed);
      if (match == null) {
        i++;
        continue;
      }
      final name = match.group(1)!;
      final rest = match.group(2)!.trim();

      if (rest.isEmpty) {
        // تبعية متعددة الأسطر (مثل flutter: \n  sdk: flutter) — نتخطى كل
        // الأسطر الفرعية الأعمق ونضيفها كعنصر read-only واحد.
        final currentIndent = _indentLevel(line);
        i++;
        while (i < sectionLineEnd && (lines[i].trim().isEmpty || _indentLevel(lines[i]) > currentIndent)) {
          i++;
        }
        deps.add(PubspecDependency(name: name, version: null, isEditable: false));
        continue;
      }

      final isSimpleVersion = !rest.contains(':') && RegExp(r'^[\^><=~!"\d.\w+\- ]+$').hasMatch(rest);
      deps.add(PubspecDependency(
        name: name,
        version: isSimpleVersion ? rest : null,
        isEditable: isSimpleVersion,
      ));
      i++;
    }

    return PubspecParseResult(
      dependencies: deps,
      sectionStart: sectionLineStart,
      sectionEnd: sectionLineEnd,
      found: true,
    );
  }

  /// يعيد بناء قسم dependencies بالكامل من قائمة تبعيات "بسيطة" مُحرَّرة
  /// (isEditable == true)، مع الإبقاء على التبعيات غير القابلة للتعديل
  /// (sdk/git/path) كما هي حرفيًا من النص الأصلي، ثم يُدرج القسم الجديد
  /// مكان القديم داخل نص pubspec.yaml الكامل ويُعيده.
  static String rebuild(
    String originalContent,
    PubspecParseResult original,
    List<PubspecDependency> updatedSimpleDeps,
  ) {
    final lines = originalContent.split('\n');
    final before = lines.sublist(0, original.sectionStart + 1); // يتضمن سطر "dependencies:"
    final after = lines.sublist(original.sectionEnd);

    final rebuiltLines = <String>[];
    final nonEditableNames = original.dependencies.where((d) => !d.isEditable).map((d) => d.name).toSet();

    if (nonEditableNames.isNotEmpty) {
      var i = original.sectionStart + 1;
      while (i < original.sectionEnd) {
        final trimmed = lines[i].trim();
        final match = RegExp(r'^(\w[\w.]*)\s*:').firstMatch(trimmed);
        if (match != null && nonEditableNames.contains(match.group(1))) {
          final startIndent = _indentLevel(lines[i]);
          rebuiltLines.add(lines[i]);
          i++;
          while (i < original.sectionEnd && lines[i].trim().isNotEmpty && _indentLevel(lines[i]) > startIndent) {
            rebuiltLines.add(lines[i]);
            i++;
          }
          continue;
        }
        i++;
      }
    }

    for (final dep in updatedSimpleDeps) {
      rebuiltLines.add('  ${dep.name}: ${dep.version}');
    }

    return [...before, ...rebuiltLines, ...after].join('\n');
  }
}
