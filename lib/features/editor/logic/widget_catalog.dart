import '../../preview/logic/builtin_widgets.dart';
import '../../preview/logic/builtin_widgets_ext.dart';
import '../../preview/logic/generated/generated_specs.dart';

enum SpecKind { widget, value, function }

/// مواصفة ودجت/مُنشئ قيمة/دالة خاصة مدعومة في مُفسِّر المعاينة — مصدر
/// الإكمال التلقائي والتلميحات.
///
/// **قاعدة الصيانة (مهمة)**: هذا الكتالوج يُكتب يدويًا بالتوازي مع
/// `builtin_widgets.dart` (لا يمكن اشتقاقه آليًا بدون reflection). أي ودجت أو
/// معامل يُضاف هناك يجب أن يُضاف هنا ليظهر في الاقتراحات. أمّا الثوابت
/// (Colors/Icons/...) فتُقرأ **مباشرة** من `BuiltinWidgets.staticProperties`
/// ولا يمكن أن تنحرف.
class WidgetSpec {
  final String name;
  final List<String> positional; // معاملات موضعية (للعرض فقط)
  final List<String> named; // معاملات مُسمّاة (تُقترَح داخل الاستدعاء)
  final String doc;
  final SpecKind kind;

  const WidgetSpec(
    this.name, {
    this.positional = const [],
    this.named = const [],
    required this.doc,
    this.kind = SpecKind.widget,
  });

  bool get isDotted => name.contains('.');
  String get baseName => isDotted ? name.substring(0, name.indexOf('.')) : name;
  String get memberName => isDotted ? name.substring(name.indexOf('.') + 1) : name;
}

class WidgetCatalog {
  WidgetCatalog._();

  static const List<WidgetSpec> specs = [
    // ---------------- ودجتس هيكلية ----------------
    WidgetSpec('MaterialApp',
        named: ['title', 'home', 'routes', 'initialRoute', 'locale', 'supportedLocales', 'theme', 'darkTheme', 'themeMode'], doc: 'جذر التطبيق: يوفّر Navigator والثيم والمسارات المُسمّاة.'),
    WidgetSpec('Scaffold',
        named: ['appBar', 'body', 'floatingActionButton', 'bottomNavigationBar', 'drawer', 'backgroundColor'],
        doc: 'هيكل الشاشة الأساسي (شريط علوي، جسم، زر عائم، تنقّل سفلي، درج).'),
    WidgetSpec('AppBar',
        named: ['title', 'actions', 'leading', 'backgroundColor', 'centerTitle'], doc: 'الشريط العلوي للشاشة.'),
    WidgetSpec('Drawer', named: ['child'], doc: 'درج جانبي يُمرَّر لمعامل drawer في Scaffold.'),
    WidgetSpec('BottomNavigationBar',
        named: ['currentIndex', 'onTap', 'type', 'items'], doc: 'شريط تنقّل سفلي. items قائمة BottomNavigationBarItem (2 على الأقل).'),
    WidgetSpec('SafeArea', named: ['child'], doc: 'يتجنّب مناطق النظام (النتوء/الشريط).'),
    // ---------------- عرض ----------------
    WidgetSpec('Text',
        positional: ['data'], named: ['style', 'textAlign', 'maxLines', 'overflow'], doc: 'نص مع تنسيق اختياري.'),
    WidgetSpec('Icon', positional: ['icon'], named: ['size', 'color'], doc: 'أيقونة من Icons.'),
    WidgetSpec('Image.network', positional: ['src'], named: ['width', 'height', 'fit'], doc: 'صورة من رابط إنترنت.'),
    WidgetSpec('Image.asset',
        positional: ['path'],
        named: ['width', 'height', 'fit'],
        doc: 'صورة من ملف داخل مجلد المشروع المفتوح (المسار نسبي لجذر المشروع، مثل assets/images/a.png).'),
    WidgetSpec('Placeholder', doc: 'مربع نائب بخطوط قطرية.'),
    WidgetSpec('Divider', named: ['color', 'thickness', 'height'], doc: 'خط فاصل أفقي.'),
    WidgetSpec('VerticalDivider', named: ['color', 'thickness', 'width'], doc: 'خط فاصل رأسي.'),
    WidgetSpec('Card', named: ['elevation', 'color', 'shape', 'child'], doc: 'بطاقة Material بظل.'),
    WidgetSpec('Chip', named: ['label', 'avatar', 'backgroundColor', 'onDeleted'], doc: 'رقاقة صغيرة.'),
    WidgetSpec('CircleAvatar', named: ['backgroundColor', 'radius', 'child'], doc: 'صورة/أيقونة دائرية.'),
    WidgetSpec('ListTile', named: ['title', 'subtitle', 'leading', 'trailing', 'onTap'], doc: 'صف قائمة قياسي.'),
    WidgetSpec('Tooltip', positional: ['message'], named: ['child'], doc: 'تلميحة تظهر عند الضغط المطوَّل.'),
    WidgetSpec('CircularProgressIndicator', named: ['value', 'color', 'strokeWidth'], doc: 'مؤشر تقدّم دائري.'),
    WidgetSpec('LinearProgressIndicator', named: ['value', 'color', 'backgroundColor'], doc: 'مؤشر تقدّم خطّي.'),
    // ---------------- تخطيط ----------------
    WidgetSpec('Container',
        named: ['padding', 'margin', 'color', 'decoration', 'width', 'height', 'alignment', 'child'],
        doc: 'حاوية: حشو/هامش/لون/ديكور/حجم/محاذاة. لا تُمرِّر color مع decoration معًا.'),
    WidgetSpec('Padding', named: ['padding', 'child'], doc: 'يضيف حشوًا حول الابن.'),
    WidgetSpec('Center', named: ['child'], doc: 'يوسّط الابن.'),
    WidgetSpec('Align', named: ['alignment', 'child'], doc: 'يحاذي الابن داخل المساحة المتاحة.'),
    WidgetSpec('Column',
        named: ['mainAxisAlignment', 'crossAxisAlignment', 'mainAxisSize', 'children'], doc: 'ترتيب رأسي للأبناء.'),
    WidgetSpec('Row',
        named: ['mainAxisAlignment', 'crossAxisAlignment', 'mainAxisSize', 'children'], doc: 'ترتيب أفقي للأبناء.'),
    WidgetSpec('Stack', named: ['alignment', 'children'], doc: 'يكدّس الأبناء فوق بعض (مع Positioned).'),
    WidgetSpec('Positioned',
        named: ['left', 'top', 'right', 'bottom', 'width', 'height', 'child'], doc: 'موضع مطلق داخل Stack.'),
    WidgetSpec('Wrap',
        named: ['direction', 'alignment', 'spacing', 'runSpacing', 'children'], doc: 'ترتيب يلتفّ على أسطر.'),
    WidgetSpec('SizedBox', named: ['width', 'height', 'child'], doc: 'صندوق بحجم ثابت أو فاصل.'),
    WidgetSpec('SizedBox.shrink', named: ['child'], doc: 'صندوق بحجم صفر (عنصر فارغ).'),
    WidgetSpec('SizedBox.expand', named: ['child'], doc: 'صندوق يملأ كل المساحة المتاحة.'),
    WidgetSpec('Expanded', named: ['flex', 'child'], doc: 'يملأ المساحة المتبقية داخل Row/Column.'),
    WidgetSpec('Flexible', named: ['flex', 'fit', 'child'], doc: 'يشغل مساحة مرنة داخل Row/Column.'),
    WidgetSpec('Spacer', named: ['flex'], doc: 'فراغ مرن داخل Row/Column.'),
    WidgetSpec('AspectRatio', named: ['aspectRatio', 'child'], doc: 'يفرض نسبة عرض/ارتفاع.'),
    WidgetSpec('FractionallySizedBox', named: ['widthFactor', 'heightFactor', 'child'], doc: 'حجم كنسبة من الأب.'),
    WidgetSpec('ClipRRect', named: ['borderRadius', 'child'], doc: 'يقصّ الابن بزوايا مدوَّرة.'),
    WidgetSpec('Opacity', positional: ['opacity'], named: ['child'], doc: 'شفافية من 0 إلى 1.'),
    WidgetSpec('Visibility', named: ['visible', 'child'], doc: 'يُظهر/يُخفي الابن.'),
    WidgetSpec('Hero', named: ['tag', 'child'], doc: 'انتقال Hero بين شاشتين بنفس الوسم.'),
    WidgetSpec('AnimatedContainer',
        named: ['duration', 'padding', 'margin', 'color', 'decoration', 'width', 'height', 'alignment', 'child'],
        doc: 'Container يتحرّك تلقائيًا عند تغيّر خصائصه.'),
    WidgetSpec('SingleChildScrollView', named: ['scrollDirection', 'child'], doc: 'يجعل ابنًا واحدًا قابلًا للتمرير.'),
    // ---------------- قوائم ----------------
    WidgetSpec('ListView', named: ['padding', 'scrollDirection', 'children'], doc: 'قائمة قابلة للتمرير.'),
    WidgetSpec('ListView.builder',
        named: ['padding', 'itemCount', 'itemBuilder'], doc: 'قائمة تُبنى عناصرها عند الطلب: itemBuilder: (context, index) => ...'),
    WidgetSpec('GridView.count',
        named: ['crossAxisCount', 'mainAxisSpacing', 'crossAxisSpacing', 'childAspectRatio', 'children'],
        doc: 'شبكة بعدد أعمدة ثابت.'),
    WidgetSpec('GridView.builder',
        named: ['gridDelegate', 'itemCount', 'itemBuilder'], doc: 'شبكة تُبنى عناصرها عند الطلب.'),
    // ---------------- أزرار وتفاعل ----------------
    WidgetSpec('ElevatedButton', named: ['onPressed', 'style', 'child'], doc: 'زر بارز. onPressed: null يعطّله.'),
    WidgetSpec('TextButton', named: ['onPressed', 'style', 'child'], doc: 'زر نصّي مسطّح.'),
    WidgetSpec('OutlinedButton', named: ['onPressed', 'style', 'child'], doc: 'زر بحدود.'),
    WidgetSpec('IconButton', named: ['onPressed', 'icon', 'tooltip'], doc: 'زر أيقونة.'),
    WidgetSpec('FloatingActionButton', named: ['onPressed', 'tooltip', 'backgroundColor', 'child'], doc: 'زر عائم.'),
    WidgetSpec('GestureDetector', named: ['onTap', 'onLongPress', 'onDoubleTap', 'behavior', 'child'], doc: 'يلتقط اللمسات على ابنه.'),
    WidgetSpec('InkWell', named: ['onTap', 'onLongPress', 'borderRadius', 'child'], doc: 'لمسة بتأثير موجة Material.'),
    WidgetSpec('Material', named: ['color', 'elevation', 'borderRadius', 'child'], doc: 'سطح Material (لون/ظل/زوايا).'),
    // ---------------- إدخال ----------------
    WidgetSpec('TextField',
        named: ['controller', 'onChanged', 'decoration', 'obscureText', 'maxLines', 'inputFormatters', 'focusNode', 'keyboardType', 'textCapitalization', 'onEditingComplete', 'onSubmitted', 'maxLength'], doc: 'حقل إدخال نص.'),
    WidgetSpec('TextFormField',
        named: ['controller', 'initialValue', 'decoration', 'obscureText', 'maxLines', 'onChanged', 'validator', 'onSaved', 'inputFormatters', 'focusNode', 'keyboardType', 'textCapitalization', 'onEditingComplete', 'maxLength'],
        doc: 'حقل نموذج. لا تُمرِّر controller مع initialValue معًا. validator موصول لكن لا يعمل فعليًا قبل دعم Form.'),
    WidgetSpec('Switch', named: ['value', 'onChanged', 'activeColor'], doc: 'مفتاح تبديل. onChanged: (value) {...}'),
    WidgetSpec('Checkbox', named: ['value', 'onChanged', 'activeColor'], doc: 'خانة اختيار.'),
    WidgetSpec('Radio', named: ['value', 'groupValue', 'onChanged'], doc: 'زر اختيار ضمن مجموعة.'),
    WidgetSpec('Slider',
        named: ['value', 'min', 'max', 'divisions', 'label', 'onChanged'], doc: 'شريط تمرير لقيمة رقمية.'),
    WidgetSpec('DropdownButton', named: ['value', 'items', 'onChanged'], doc: 'قائمة منسدلة. items قائمة DropdownMenuItem.'),
    // ---------------- حوارات ----------------
    WidgetSpec('SnackBar', named: ['content', 'backgroundColor', 'duration'], doc: 'رسالة سفلية مؤقتة (مع ScaffoldMessenger.of(context).showSnackBar).'),
    WidgetSpec('AlertDialog', named: ['title', 'content', 'actions'], doc: 'حوار تنبيه (مع showDialog).'),
    // ---------------- قيم ----------------
    WidgetSpec('EdgeInsets.all', positional: ['value'], doc: 'حشو متساوٍ من كل الجهات.', kind: SpecKind.value),
    WidgetSpec('EdgeInsets.symmetric',
        named: ['horizontal', 'vertical'], doc: 'حشو أفقي/رأسي.', kind: SpecKind.value),
    WidgetSpec('EdgeInsets.only',
        named: ['left', 'top', 'right', 'bottom'], doc: 'حشو لجهات محدَّدة.', kind: SpecKind.value),
    WidgetSpec('EdgeInsets.fromLTRB',
        positional: ['left', 'top', 'right', 'bottom'], doc: 'حشو بأربع قيم موضعية.', kind: SpecKind.value),
    WidgetSpec('TextStyle',
        named: ['fontSize', 'fontWeight', 'color', 'fontStyle', 'decoration', 'letterSpacing'],
        doc: 'تنسيق النص.', kind: SpecKind.value),
    WidgetSpec('InputDecoration',
        named: [
          'hintText', 'labelText', 'label', 'floatingLabelBehavior', 'helperText', 'errorText', 'filled',
          'fillColor', 'contentPadding', 'labelStyle', 'hintStyle', 'prefixIcon', 'suffixIcon',
          'enabledBorder', 'focusedBorder', 'border', 'counterText', 'isDense', 'prefixText', 'suffixText'
        ],
        doc: 'مظهر حقل الإدخال. floatingLabelBehavior: FloatingLabelBehavior.always يثبّت التسمية بالأعلى.',
        kind: SpecKind.value),
    WidgetSpec('BoxDecoration',
        named: ['color', 'borderRadius', 'border', 'boxShadow', 'shape'], doc: 'ديكور الحاوية.', kind: SpecKind.value),
    WidgetSpec('BorderRadius.circular', positional: ['radius'], doc: 'زوايا مدوَّرة متساوية.', kind: SpecKind.value),
    WidgetSpec('BorderRadius.only',
        named: ['topLeft', 'topRight', 'bottomLeft', 'bottomRight'], doc: 'زوايا مدوَّرة لجهات محدَّدة.', kind: SpecKind.value),
    WidgetSpec('Border.all', named: ['color', 'width'], doc: 'حدود موحَّدة.', kind: SpecKind.value),
    WidgetSpec('BoxShadow',
        named: ['color', 'blurRadius', 'spreadRadius', 'offset'], doc: 'ظل.', kind: SpecKind.value),
    WidgetSpec('Offset', positional: ['dx', 'dy'], doc: 'إزاحة (x, y).', kind: SpecKind.value),
    WidgetSpec('Duration',
        named: ['days', 'hours', 'minutes', 'seconds', 'milliseconds'], doc: 'مدة زمنية.', kind: SpecKind.value),
    WidgetSpec('SliverGridDelegateWithFixedCrossAxisCount',
        named: ['crossAxisCount', 'mainAxisSpacing', 'crossAxisSpacing', 'childAspectRatio'],
        doc: 'تعريف أعمدة الشبكة لِـ GridView.builder.', kind: SpecKind.value),
    WidgetSpec('BottomNavigationBarItem', named: ['icon', 'label'], doc: 'عنصر شريط التنقّل السفلي.', kind: SpecKind.value),
    WidgetSpec('Color', positional: ['0xAARRGGBB'], doc: 'لون سداسي عشري، مثل Color(0xFF2196F3).', kind: SpecKind.value),
    WidgetSpec('TextEditingController', named: ['text'], doc: 'متحكّم نص. اقرأ .text وامسح بـ .clear(). عرّفه كحقل صنف.', kind: SpecKind.value),
    WidgetSpec('OutlineInputBorder', named: ['borderSide', 'borderRadius'], doc: 'حدود محيطية لحقل الإدخال.', kind: SpecKind.value),
    WidgetSpec('UnderlineInputBorder', named: ['borderSide'], doc: 'خط سفلي لحقل الإدخال.', kind: SpecKind.value),
    WidgetSpec('BorderSide', named: ['color', 'width'], doc: 'جانب حدّ (لون/عرض).', kind: SpecKind.value),
    WidgetSpec('DropdownMenuItem', named: ['value', 'child'], doc: 'عنصر قائمة منسدلة.', kind: SpecKind.value),
    WidgetSpec('ElevatedButton.styleFrom',
        named: ['backgroundColor', 'foregroundColor', 'padding', 'elevation', 'textStyle', 'side'],
        doc: 'نمط زر ElevatedButton.', kind: SpecKind.value),
    WidgetSpec('TextButton.styleFrom',
        named: ['backgroundColor', 'foregroundColor', 'padding', 'elevation', 'textStyle', 'side'],
        doc: 'نمط زر TextButton.', kind: SpecKind.value),
    WidgetSpec('OutlinedButton.styleFrom',
        named: ['backgroundColor', 'foregroundColor', 'padding', 'elevation', 'textStyle', 'side'],
        doc: 'نمط زر OutlinedButton.', kind: SpecKind.value),
    // ---------------- الدفعة 1 ----------------
    WidgetSpec('PageView', named: ['controller', 'onPageChanged', 'scrollDirection', 'reverse', 'children'], doc: 'صفحات قابلة للتمرير.'),
    WidgetSpec('PageView.builder', named: ['controller', 'itemCount', 'itemBuilder', 'onPageChanged', 'scrollDirection'], doc: 'صفحات تُبنى عند الطلب.'),
    WidgetSpec('Directionality', named: ['textDirection', 'child'], doc: 'يفرض اتجاه النص (TextDirection.rtl / ltr).'),
    WidgetSpec('Builder', named: ['builder'], doc: 'يعطيك BuildContext جديدًا: builder: (context) => ...'),
    WidgetSpec('Locale', positional: ['languageCode', 'countryCode'], doc: 'لغة، مثل Locale("ar").', kind: SpecKind.value),
    WidgetSpec('PageController', named: ['initialPage', 'viewportFraction'], doc: 'متحكم PageView (nextPage/animateToPage...).', kind: SpecKind.value),
    WidgetSpec('FocusNode', doc: 'عقدة تركيز للحقول.', kind: SpecKind.value),
    WidgetSpec('RegExp', positional: ['pattern'], named: ['caseSensitive', 'multiLine'], doc: 'تعبير نمطي: .hasMatch(text).', kind: SpecKind.value),
    WidgetSpec('FilteringTextInputFormatter.allow', positional: ['RegExp'], doc: 'يسمح بالمحارف المطابقة فقط.', kind: SpecKind.value),
    WidgetSpec('FilteringTextInputFormatter.deny', positional: ['RegExp'], doc: 'يمنع المحارف المطابقة.', kind: SpecKind.value),
    WidgetSpec('LengthLimitingTextInputFormatter', positional: ['maxLength'], doc: 'يحدّد الحد الأقصى للأحرف.', kind: SpecKind.value),
    WidgetSpec('Navigator.pushNamedAndRemoveUntil', positional: ['context', 'routeName', 'predicate'], named: ['arguments'], doc: 'ينتقل ويحذف ما قبله: (r) => false.', kind: SpecKind.function),
    WidgetSpec('ModalRoute.of', positional: ['context'], doc: 'المسار الحالي: .settings.arguments', kind: SpecKind.function),
    WidgetSpec('Localizations.localeOf', positional: ['context'], doc: 'لغة التطبيق الحالية.', kind: SpecKind.function),
    WidgetSpec('FocusScope.of', positional: ['context'], doc: '.nextFocus() / .previousFocus() / .unfocus()', kind: SpecKind.function),
    // ---------------- دوال خاصة ----------------
    WidgetSpec('setState', positional: ['() { ... }'], doc: 'يُحدِّث الواجهة بعد تعديل الحالة (داخل State فقط، وليس داخل build).', kind: SpecKind.function),
    WidgetSpec('print', positional: ['value'], doc: 'يطبع في لوحة Output.', kind: SpecKind.function),
    WidgetSpec('MaterialPageRoute', named: ['builder'], doc: 'مسار انتقال: builder: (context) => Screen()', kind: SpecKind.function),
    WidgetSpec('showDialog', named: ['context', 'builder'], doc: 'يعرض حوارًا: builder: (ctx) => AlertDialog(...)', kind: SpecKind.function),
    WidgetSpec('Navigator.push', positional: ['context', 'route'], doc: 'ينتقل لشاشة جديدة: Navigator.push(context, MaterialPageRoute(builder: ...))', kind: SpecKind.function),
    WidgetSpec('Navigator.pop', positional: ['context'], doc: 'يرجع للشاشة السابقة.', kind: SpecKind.function),
    WidgetSpec('Navigator.pushNamed', positional: ['context', 'routeName'], doc: 'ينتقل لمسار مُسمّى معرَّف في MaterialApp.routes.', kind: SpecKind.function),
    WidgetSpec('Navigator.pushReplacementNamed', positional: ['context', 'routeName'], doc: 'يستبدل الشاشة الحالية بمسار مُسمّى.', kind: SpecKind.function),
    WidgetSpec('ScaffoldMessenger.of', positional: ['context'], doc: 'ثم .showSnackBar(SnackBar(...)).', kind: SpecKind.function),
    WidgetSpec('Future.delayed', positional: ['duration', 'computation'], doc: 'ينتظر مدة (استخدمه مع await داخل دالة async).', kind: SpecKind.function),
    WidgetSpec('Future.value', positional: ['value'], doc: 'Future مكتمل بقيمة.', kind: SpecKind.function),
  ];

  static final Map<String, WidgetSpec> byName = {for (final s in specs) s.name: s};

  static WidgetSpec? lookup(String name) => byName[name] ?? _generatedByName[name];

  /// مواصفات مولَّدة من Flutter SDK (tool/gen_widget_bridge.dart) للتلميحات والإكمال.
  static final Map<String, WidgetSpec> _generatedByName = {
    for (final g in kGeneratedSpecs)
      if (!byName.containsKey(g[0]))
        g[0]: WidgetSpec(
          g[0],
          positional: g[2].isEmpty ? const [] : g[2].split(','),
          named: g[3].isEmpty ? const [] : g[3].split(','),
          doc: 'من Flutter SDK (مُولَّد تلقائيًا).',
          kind: g[1] == 'widget'
              ? SpecKind.widget
              : (g[1] == 'function' ? SpecKind.function : SpecKind.value),
        ),
  };

  static List<WidgetSpec>? _allCache;

  /// الكتالوج اليدوي + المولَّد.
  static List<WidgetSpec> get allSpecs => _allCache ??= [...specs, ..._generatedByName.values];

  /// وصف مختصر لنوع قيمة المعامل (للمساعدة فقط).
  static const Map<String, String> paramHints = {
    'child': 'Widget', 'children': 'List<Widget>', 'title': 'Widget', 'body': 'Widget',
    'home': 'Widget', 'appBar': 'AppBar', 'drawer': 'Drawer', 'leading': 'Widget',
    'trailing': 'Widget', 'subtitle': 'Widget', 'label': 'Widget', 'content': 'Widget',
    'actions': 'List<Widget>', 'icon': 'Icon', 'avatar': 'Widget', 'prefixIcon': 'Widget',
    'suffixIcon': 'Widget', 'floatingActionButton': 'Widget', 'bottomNavigationBar': 'Widget',
    'onPressed': 'VoidCallback — () { ... }', 'onTap': '() { ... }', 'onLongPress': '() { ... }',
    'onDoubleTap': '() { ... }', 'onChanged': '(value) { ... }', 'onSaved': '(value) { ... }',
    'validator': '(value) => String?', 'onDeleted': '() { ... }', 'itemBuilder': '(context, index) => Widget',
    'builder': '(context) => Widget', 'padding': 'EdgeInsets', 'margin': 'EdgeInsets',
    'contentPadding': 'EdgeInsets', 'color': 'Color', 'backgroundColor': 'Color',
    'foregroundColor': 'Color', 'fillColor': 'Color', 'activeColor': 'Color',
    'decoration': 'BoxDecoration / InputDecoration', 'style': 'TextStyle / ButtonStyle',
    'labelStyle': 'TextStyle', 'hintStyle': 'TextStyle', 'textStyle': 'TextStyle',
    'borderRadius': 'BorderRadius', 'border': 'Border / InputBorder', 'enabledBorder': 'InputBorder',
    'focusedBorder': 'InputBorder', 'borderSide': 'BorderSide', 'side': 'BorderSide',
    'boxShadow': 'List<BoxShadow>', 'shape': 'BoxShape', 'alignment': 'Alignment',
    'mainAxisAlignment': 'MainAxisAlignment', 'crossAxisAlignment': 'CrossAxisAlignment',
    'mainAxisSize': 'MainAxisSize', 'textAlign': 'TextAlign', 'overflow': 'TextOverflow',
    'fontWeight': 'FontWeight', 'fontStyle': 'FontStyle', 'fit': 'BoxFit / FlexFit',
    'scrollDirection': 'Axis', 'direction': 'Axis', 'type': 'BottomNavigationBarType',
    'floatingLabelBehavior': 'FloatingLabelBehavior', 'controller': 'TextEditingController',
    'duration': 'Duration', 'width': 'عدد', 'height': 'عدد', 'size': 'عدد', 'flex': 'عدد',
    'maxLines': 'عدد', 'itemCount': 'عدد', 'crossAxisCount': 'عدد', 'currentIndex': 'عدد',
    'spacing': 'عدد', 'runSpacing': 'عدد', 'elevation': 'عدد', 'radius': 'عدد', 'value': 'قيمة',
    'groupValue': 'قيمة', 'items': 'List', 'text': 'String', 'hintText': 'String',
    'labelText': 'String', 'helperText': 'String', 'errorText': 'String', 'tooltip': 'String',
    'initialValue': 'String', 'routes': 'Map<String, builder>', 'initialRoute': 'String',
    'obscureText': 'bool', 'visible': 'bool', 'filled': 'bool', 'centerTitle': 'bool',
    'min': 'عدد', 'max': 'عدد', 'divisions': 'عدد', 'tag': 'قيمة', 'gridDelegate': 'SliverGridDelegate',
    'letterSpacing': 'عدد', 'fontSize': 'عدد', 'blurRadius': 'عدد', 'spreadRadius': 'عدد',
    'offset': 'Offset', 'thickness': 'عدد', 'opacity': 'عدد (0..1)', 'aspectRatio': 'عدد',
    'widthFactor': 'عدد', 'heightFactor': 'عدد', 'strokeWidth': 'عدد',
  };

  static String hintFor(String param) => paramHints[param] ?? '';

  /// أسماء المساحات الثابتة (Colors, Icons, ...) مأخوذة من السجلّ الفعلي.
  static List<String> staticNamespaces() {
    final set = <String>{};
    for (final k in BuiltinWidgets.staticProperties.keys) {
      final dot = k.indexOf('.');
      if (dot > 0) set.add(k.substring(0, dot));
    }
    set.addAll(BuiltinWidgetsExt.enumTypes.keys);
    final list = set.toList()..sort();
    return list;
  }

  /// أعضاء مساحة ثابتة (مثل أسماء كل ألوان Colors) من السجلّ الفعلي.
  static List<String> staticMembers(String namespace) {
    final prefix = '$namespace.';
    final out = <String>[];
    for (final k in BuiltinWidgets.staticProperties.keys) {
      if (k.startsWith(prefix)) out.add(k.substring(prefix.length));
    }
    for (final v in BuiltinWidgetsExt.enumTypes[namespace] ?? const <Enum>[]) {
      out.add(v.name);
    }
    out.sort();
    return out;
  }
}
