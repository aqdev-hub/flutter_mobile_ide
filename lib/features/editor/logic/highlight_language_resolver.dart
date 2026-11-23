import 'package:highlight/highlight_core.dart';
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/markdown.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/yaml.dart';

/// يعيد تعريف اللغة المناسب لمكتبة highlight اعتمادًا على امتداد الملف،
/// بحيث يحصل كل نوع ملف (dart / yaml / json / md / xml) على تلوين نحوي
/// صحيح بدل معاملة كل شيء كنص Dart.
Mode? resolveHighlightLanguage(String extension) {
  switch (extension) {
    case '.dart':
      return dart;
    case '.yaml':
    case '.yml':
      return yaml;
    case '.json':
      return json;
    case '.md':
      return markdown;
    case '.xml':
      return xml;
    default:
      return null; // بدون تلوين نحوي لأنواع الملفات غير المعروفة
  }
}
