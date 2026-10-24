import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../editor/logic/widget_catalog.dart';
import 'semantic_service.dart';

/// أسماء معروفة مسبقًا أنها صالحة من Flutter/Dart (لا نفهرس هذه المكتبات بعد):
/// تُستخدم **للتخفيف فقط** — اسم هنا لا يُقترح له تصحيح إملائي أبدًا حتى لو قارب
/// اسم صنف في المشروع. المصدر: كتالوج الودجتس الحالي + أسماء إضافية شائعة.
const _extraKnownNames = {
  'Navigator', 'Theme', 'ThemeData', 'TextTheme', 'ColorScheme', 'MediaQuery', 'BuildContext',
  'State', 'StatelessWidget', 'StatefulWidget', 'Widget', 'Key', 'GlobalKey', 'FocusNode',
  'TextEditingController', 'ScrollController', 'AnimationController', 'Form', 'FormState',
  'MaterialButton', 'MaterialApp', 'Color', 'Colors', 'Icons', 'Curves', 'Duration', 'DateTime',
  'Future', 'Stream', 'Timer', 'List', 'Map', 'Set', 'String', 'int', 'double', 'bool', 'num',
  'Object', 'Function', 'Exception', 'Error', 'RegExp', 'Uri', 'Platform', 'Directory', 'File',
};

Set<String>? _known;

bool _isKnownExternalName(String name) {
  _known ??= {
    for (final s in WidgetCatalog.specs) s.baseName,
    ...WidgetCatalog.staticNamespaces(),
    ..._extraKnownNames,
  };
  return _known!.contains(name);
}

final semanticServiceProvider = Provider<SemanticService>((ref) {
  return SemanticService(isKnownExternalName: _isKnownExternalName);
});
