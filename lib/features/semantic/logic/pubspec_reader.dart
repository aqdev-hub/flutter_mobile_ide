/// قراءة نصّية بسيطة (بلا مكتبة YAML) لما يحتاجه حلّ الاستيرادات.
class PubspecInfo {
  final String? name;
  final Set<String> dependencies;
  const PubspecInfo({this.name, this.dependencies = const {}});
}

String _stripQuotes(String s) {
  var v = s.trim();
  final hash = v.indexOf(' #');
  if (hash != -1) v = v.substring(0, hash).trim();
  if (v.length >= 2 && ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'")))) {
    v = v.substring(1, v.length - 1);
  }
  return v;
}

/// اسم الحزمة وأسماء dependencies/dev_dependencies من نص pubspec.yaml.
PubspecInfo parsePubspec(String content) {
  String? name;
  final deps = <String>{};
  var section = '';
  for (final raw in content.split('\n')) {
    final line = raw.replaceAll('\r', '');
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final indented = line.startsWith(' ') || line.startsWith('\t');
    if (!indented) {
      final m = RegExp(r'^([A-Za-z_][\w\-]*)\s*:\s*(.*)$').firstMatch(line);
      if (m == null) {
        section = '';
        continue;
      }
      final key = m.group(1)!;
      section = key;
      if (key == 'name') {
        final v = _stripQuotes(m.group(2)!);
        if (v.isNotEmpty) name = v;
      }
      continue;
    }
    if (section == 'dependencies' || section == 'dev_dependencies') {
      // مفتاح بمسافتين فقط = اسم حزمة (الأسطر الأعمق خيارات التبعية).
      final m = RegExp(r'^ {2}([A-Za-z_][\w\-]*)\s*:').firstMatch(line);
      if (m != null) deps.add(m.group(1)!);
    }
  }
  return PubspecInfo(name: name, dependencies: deps);
}

/// أسماء كل الحزم المحلولة فعليًا من pubspec.lock (تشمل المتعدّية).
Set<String> parsePubspecLockPackages(String content) {
  final result = <String>{};
  var inPackages = false;
  for (final raw in content.split('\n')) {
    final line = raw.replaceAll('\r', '');
    if (!line.startsWith(' ') && line.trim().isNotEmpty) {
      inPackages = line.trim() == 'packages:';
      continue;
    }
    if (!inPackages) continue;
    final m = RegExp(r'^ {2}([A-Za-z_][\w\-]*):\s*$').firstMatch(line);
    if (m != null) result.add(m.group(1)!);
  }
  return result;
}
