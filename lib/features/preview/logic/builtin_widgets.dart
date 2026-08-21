import 'package:flutter/material.dart';

import 'interpreted_callable.dart';

/// يحوّل قيمة قد تكون [InterpretedCallable] (قادمة من كود المستخدم) إلى
/// VoidCallback حقيقي، أو null إن لم تكن موجودة. بدون هذا التحويل، كل
/// onPressed/onTap/onChanged القادمة من الكود المُفسَّر لن تُطابق الأنواع
/// التي يتوقعها Flutter فعليًا.
VoidCallback? _asVoid(dynamic v) => v is InterpretedCallable ? v.asVoidCallback : null;
void Function(String)? _asStringCb(dynamic v) => v is InterpretedCallable ? v.asStringCallback : null;
void Function(int)? _asIntCb(dynamic v) => v is InterpretedCallable ? v.asIntCallback : null;
void Function(bool?)? _asBoolCb(dynamic v) => v is InterpretedCallable ? v.asBoolCallback : null;
Widget Function(BuildContext, int)? _asIndexedBuilder(dynamic v) =>
    v is InterpretedCallable ? v.asIndexedBuilder : null;

/// يحوّل اسم مُنشئ (constructor name) + وسائطه المُقيَّمة مسبقًا إلى ودجت
/// Flutter حقيقي فعلي — وليس تمثيلًا وهميًا. هذا هو الجسر بين الشيفرة
/// المُفسَّرة والمحرك الفعلي لـ Flutter الذي يرسم ويستقبل الأحداث.
///
/// يعيد null إن كان الاسم غير معروف، ليقرر المُفسِّر عندها عرض عنصر نائب
/// واضح بدل تعطّل المعاينة بالكامل — حسب معيار "معالجة الأخطاء بوضوح".
///
/// **تحديث**: توسيع القائمة (ودجتس تفاعل/تخطيط/تغذية راجعة شائعة، أيقونات
/// وألوان إضافية، وقيم مساعدة مثل BoxShadow/Border/Duration) — القائمة
/// تبقى بطبيعتها محدودة عمدًا (راجع README)، لكنها الآن تغطي جزءًا أكبر
/// بكثير من الاستخدام العملي اليومي.
class BuiltinWidgets {
  BuiltinWidgets._();

  static Widget? build(String name, List<dynamic> pos, Map<String, dynamic> named) {
    dynamic arg(String key, [int? posIndex]) =>
        named[key] ?? (posIndex != null && posIndex < pos.length ? pos[posIndex] : null);

    switch (name) {
      case 'MaterialApp':
        final rawRoutes = arg('routes') as Map?;
        return MaterialApp(
          title: arg('title') as String? ?? '',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
          home: arg('home') as Widget?,
          initialRoute: arg('initialRoute') as String?,
          routes: {
            if (rawRoutes != null)
              for (final entry in rawRoutes.entries)
                entry.key as String: (context) {
                  final value = entry.value;
                  if (value is InterpretedCallable) return value.asContextBuilder(context);
                  return value as Widget;
                },
          },
        );

      case 'Scaffold':
        return Scaffold(
          appBar: arg('appBar') as PreferredSizeWidget?,
          body: arg('body') as Widget?,
          floatingActionButton: arg('floatingActionButton') as Widget?,
          bottomNavigationBar: arg('bottomNavigationBar') as Widget?,
          drawer: arg('drawer') as Widget?,
          backgroundColor: arg('backgroundColor') as Color?,
        );

      case 'AppBar':
        return AppBar(
          title: arg('title') as Widget?,
          actions: (arg('actions') as List?)?.cast<Widget>(),
          leading: arg('leading') as Widget?,
          backgroundColor: arg('backgroundColor') as Color?,
          centerTitle: arg('centerTitle') as bool?,
        );

      case 'Text':
        return Text(
          (arg('data', 0) ?? '').toString(),
          style: arg('style') as TextStyle?,
          textAlign: arg('textAlign') as TextAlign?,
          maxLines: (arg('maxLines') as num?)?.toInt(),
          overflow: arg('overflow') as TextOverflow?,
        );

      case 'Container':
        return Container(
          padding: arg('padding') as EdgeInsetsGeometry?,
          margin: arg('margin') as EdgeInsetsGeometry?,
          color: arg('decoration') == null ? arg('color') as Color? : null,
          decoration: arg('decoration') as BoxDecoration?,
          width: (arg('width') as num?)?.toDouble(),
          height: (arg('height') as num?)?.toDouble(),
          alignment: arg('alignment') as AlignmentGeometry?,
          child: arg('child') as Widget?,
        );

      case 'Padding':
        return Padding(
          padding: arg('padding') as EdgeInsetsGeometry? ?? EdgeInsets.zero,
          child: arg('child') as Widget?,
        );

      case 'Center':
        return Center(child: arg('child') as Widget?);

      case 'Align':
        return Align(
            alignment: arg('alignment') as AlignmentGeometry? ?? Alignment.center, child: arg('child') as Widget?);

      case 'Column':
        return Column(
          mainAxisAlignment: arg('mainAxisAlignment') as MainAxisAlignment? ?? MainAxisAlignment.start,
          crossAxisAlignment: arg('crossAxisAlignment') as CrossAxisAlignment? ?? CrossAxisAlignment.center,
          mainAxisSize: arg('mainAxisSize') as MainAxisSize? ?? MainAxisSize.max,
          children: (arg('children', 0) as List?)?.cast<Widget>() ?? const [],
        );

      case 'Row':
        return Row(
          mainAxisAlignment: arg('mainAxisAlignment') as MainAxisAlignment? ?? MainAxisAlignment.start,
          crossAxisAlignment: arg('crossAxisAlignment') as CrossAxisAlignment? ?? CrossAxisAlignment.center,
          mainAxisSize: arg('mainAxisSize') as MainAxisSize? ?? MainAxisSize.max,
          children: (arg('children', 0) as List?)?.cast<Widget>() ?? const [],
        );

      case 'Stack':
        return Stack(
          alignment: arg('alignment') as AlignmentGeometry? ?? AlignmentDirectional.topStart,
          children: (arg('children', 0) as List?)?.cast<Widget>() ?? const [],
        );

      case 'Wrap':
        return Wrap(
          direction: arg('direction') as Axis? ?? Axis.horizontal,
          alignment: arg('alignment') as WrapAlignment? ?? WrapAlignment.start,
          spacing: (arg('spacing') as num?)?.toDouble() ?? 0,
          runSpacing: (arg('runSpacing') as num?)?.toDouble() ?? 0,
          children: (arg('children', 0) as List?)?.cast<Widget>() ?? const [],
        );

      case 'SizedBox':
        return SizedBox(
          width: (arg('width') as num?)?.toDouble(),
          height: (arg('height') as num?)?.toDouble(),
          child: arg('child') as Widget?,
        );

      case 'Icon':
        return Icon(
          arg('icon', 0) as IconData? ?? Icons.help_outline,
          size: (arg('size') as num?)?.toDouble(),
          color: arg('color') as Color?,
        );

      case 'ElevatedButton':
        return ElevatedButton(
          onPressed: _asVoid(arg('onPressed')),
          child: arg('child') as Widget? ?? const Text(''),
        );

      case 'TextButton':
        return TextButton(
          onPressed: _asVoid(arg('onPressed')),
          child: arg('child') as Widget? ?? const Text(''),
        );

      case 'OutlinedButton':
        return OutlinedButton(
          onPressed: _asVoid(arg('onPressed')),
          child: arg('child') as Widget? ?? const Text(''),
        );

      case 'IconButton':
        return IconButton(
          onPressed: _asVoid(arg('onPressed')),
          icon: arg('icon') as Widget? ?? const Icon(Icons.circle),
          tooltip: arg('tooltip') as String?,
        );

      case 'FloatingActionButton':
        return FloatingActionButton(
          onPressed: _asVoid(arg('onPressed')),
          tooltip: arg('tooltip') as String?,
          backgroundColor: arg('backgroundColor') as Color?,
          child: arg('child') as Widget?,
        );

      case 'GestureDetector':
        return GestureDetector(
          onTap: _asVoid(arg('onTap')),
          onLongPress: _asVoid(arg('onLongPress')),
          onDoubleTap: _asVoid(arg('onDoubleTap')),
          child: arg('child') as Widget? ?? const SizedBox(),
        );

      case 'InkWell':
        return InkWell(
          onTap: _asVoid(arg('onTap')),
          onLongPress: _asVoid(arg('onLongPress')),
          borderRadius: arg('borderRadius') as BorderRadius?,
          child: arg('child') as Widget?,
        );

      case 'ListView':
        return ListView(
          padding: arg('padding') as EdgeInsetsGeometry?,
          scrollDirection: arg('scrollDirection') as Axis? ?? Axis.vertical,
          children: (arg('children', 0) as List?)?.cast<Widget>() ?? const [],
        );

      case 'ListView.builder':
        final itemCount = (arg('itemCount') as num?)?.toInt() ?? 0;
        final itemBuilder = _asIndexedBuilder(arg('itemBuilder'));
        if (itemBuilder == null) return const SizedBox.shrink();
        return ListView.builder(
          padding: arg('padding') as EdgeInsetsGeometry?,
          itemCount: itemCount,
          itemBuilder: itemBuilder,
        );

      case 'GridView.count':
        return GridView.count(
          crossAxisCount: (arg('crossAxisCount') as num?)?.toInt() ?? 2,
          mainAxisSpacing: (arg('mainAxisSpacing') as num?)?.toDouble() ?? 0,
          crossAxisSpacing: (arg('crossAxisSpacing') as num?)?.toDouble() ?? 0,
          childAspectRatio: (arg('childAspectRatio') as num?)?.toDouble() ?? 1.0,
          children: (arg('children', 0) as List?)?.cast<Widget>() ?? const [],
        );

      case 'GridView.builder':
        final gridItemCount = (arg('itemCount') as num?)?.toInt() ?? 0;
        final gridItemBuilder = _asIndexedBuilder(arg('itemBuilder'));
        final delegate = arg('gridDelegate');
        if (gridItemBuilder == null) return const SizedBox.shrink();
        return GridView.builder(
          gridDelegate: delegate is SliverGridDelegate
              ? delegate
              : const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2),
          itemCount: gridItemCount,
          itemBuilder: gridItemBuilder,
        );

      case 'ListTile':
        return ListTile(
          title: arg('title') as Widget?,
          subtitle: arg('subtitle') as Widget?,
          leading: arg('leading') as Widget?,
          trailing: arg('trailing') as Widget?,
          onTap: _asVoid(arg('onTap')),
        );

      case 'Card':
        return Card(
          elevation: (arg('elevation') as num?)?.toDouble(),
          color: arg('color') as Color?,
          shape: arg('shape') as ShapeBorder?,
          child: arg('child') as Widget?,
        );

      case 'Chip':
        return Chip(
          label: arg('label') as Widget? ?? const Text(''),
          avatar: arg('avatar') as Widget?,
          backgroundColor: arg('backgroundColor') as Color?,
          onDeleted: _asVoid(arg('onDeleted')),
        );

      case 'CircleAvatar':
        return CircleAvatar(
          backgroundColor: arg('backgroundColor') as Color?,
          radius: (arg('radius') as num?)?.toDouble(),
          child: arg('child') as Widget?,
        );

      case 'Divider':
        return const Divider();

      case 'VerticalDivider':
        return const VerticalDivider();

      case 'SingleChildScrollView':
        return SingleChildScrollView(
          scrollDirection: arg('scrollDirection') as Axis? ?? Axis.vertical,
          child: arg('child') as Widget?,
        );

      case 'Expanded':
        return Expanded(
          flex: (arg('flex') as num?)?.toInt() ?? 1,
          child: arg('child') as Widget? ?? const SizedBox(),
        );

      case 'Flexible':
        return Flexible(
          flex: (arg('flex') as num?)?.toInt() ?? 1,
          fit: arg('fit') as FlexFit? ?? FlexFit.loose,
          child: arg('child') as Widget? ?? const SizedBox(),
        );

      case 'Spacer':
        return Spacer(flex: (arg('flex', 0) as num?)?.toInt() ?? 1);

      case 'Positioned':
        return Positioned(
          left: (arg('left') as num?)?.toDouble(),
          top: (arg('top') as num?)?.toDouble(),
          right: (arg('right') as num?)?.toDouble(),
          bottom: (arg('bottom') as num?)?.toDouble(),
          width: (arg('width') as num?)?.toDouble(),
          height: (arg('height') as num?)?.toDouble(),
          child: arg('child') as Widget? ?? const SizedBox(),
        );

      case 'ClipRRect':
        return ClipRRect(
          borderRadius: arg('borderRadius') as BorderRadius? ?? BorderRadius.zero,
          child: arg('child') as Widget?,
        );

      case 'SafeArea':
        return SafeArea(child: arg('child') as Widget? ?? const SizedBox());

      case 'Tooltip':
        return Tooltip(
          message: arg('message', 0) as String? ?? '',
          child: arg('child') as Widget? ?? const SizedBox(),
        );

      case 'CircularProgressIndicator':
        return CircularProgressIndicator(
          value: (arg('value') as num?)?.toDouble(),
          color: arg('color') as Color?,
          strokeWidth: (arg('strokeWidth') as num?)?.toDouble() ?? 4.0,
        );

      case 'LinearProgressIndicator':
        return LinearProgressIndicator(
          value: (arg('value') as num?)?.toDouble(),
          color: arg('color') as Color?,
          backgroundColor: arg('backgroundColor') as Color?,
        );

      case 'Switch':
        return Switch(
          value: arg('value') as bool? ?? false,
          onChanged: _asBoolCb(arg('onChanged')),
          // 'activeColor' مُهملة منذ Flutter 3.31 لصالح activeThumbColor —
          // حدّثناها هنا للإصدار الحديث.
          activeThumbColor: arg('activeColor') as Color?,
        );

      case 'Checkbox':
        return Checkbox(
          value: arg('value') as bool? ?? false,
          onChanged: _asBoolCb(arg('onChanged')),
          activeColor: arg('activeColor') as Color?,
        );

      case 'Radio':
        {
          // مبسّط عمدًا: نقارن value/groupValue كقيم ديناميكية بدل Generics
          // حقيقية (T)، وهذا كافٍ لأغلب استخدامات Radio العملية (نص/رقم بسيط).
          // ملاحظة: معامل onChanged على Radio مُباشرةً أصبح مُهملًا في
          // إصدارات Flutter الحديثة لصالح RadioGroup، لكنه لا يزال يعمل
          // فعليًا (تحذير وليس خطأ) — نُبقيه لتفادي إعادة هيكلة أكبر الآن.
          final onChangedCallable = arg('onChanged');
          return Radio<dynamic>(
            value: arg('value'),
            groupValue: arg('groupValue'),
            onChanged: (dynamic newValue) {
              if (onChangedCallable is InterpretedCallable) {
                onChangedCallable.call([newValue]);
              }
            },
          );
        }

      case 'Slider':
        {
          final onChangedCallable = arg('onChanged');
          return Slider(
            value: (arg('value') as num?)?.toDouble() ?? 0,
            min: (arg('min') as num?)?.toDouble() ?? 0,
            max: (arg('max') as num?)?.toDouble() ?? 1,
            divisions: (arg('divisions') as num?)?.toInt(),
            label: arg('label') as String?,
            onChanged: (double newValue) {
              if (onChangedCallable is InterpretedCallable) {
                onChangedCallable.call([newValue]);
              }
            },
          );
        }

      case 'TextField':
        return TextField(
          onChanged: _asStringCb(arg('onChanged')),
          decoration: arg('decoration') as InputDecoration? ?? const InputDecoration(),
          obscureText: arg('obscureText') as bool? ?? false,
          maxLines: (arg('maxLines') as num?)?.toInt() ?? 1,
        );

      case 'Drawer':
        return Drawer(child: arg('child') as Widget?);

      case 'BottomNavigationBar':
        return BottomNavigationBar(
          currentIndex: (arg('currentIndex') as num?)?.toInt() ?? 0,
          onTap: _asIntCb(arg('onTap')),
          type: arg('type') as BottomNavigationBarType? ?? BottomNavigationBarType.fixed,
          items: (arg('items') as List?)?.cast<BottomNavigationBarItem>() ??
              const [BottomNavigationBarItem(icon: Icon(Icons.circle), label: '')],
        );

      case 'AnimatedContainer':
        return AnimatedContainer(
          duration: arg('duration') as Duration? ?? const Duration(milliseconds: 300),
          padding: arg('padding') as EdgeInsetsGeometry?,
          margin: arg('margin') as EdgeInsetsGeometry?,
          color: arg('decoration') == null ? arg('color') as Color? : null,
          decoration: arg('decoration') as BoxDecoration?,
          width: (arg('width') as num?)?.toDouble(),
          height: (arg('height') as num?)?.toDouble(),
          alignment: arg('alignment') as AlignmentGeometry?,
          child: arg('child') as Widget?,
        );

      case 'Image.network':
        return Image.network(
          arg('src', 0) as String? ?? '',
          width: (arg('width') as num?)?.toDouble(),
          height: (arg('height') as num?)?.toDouble(),
          fit: arg('fit') as BoxFit?,
        );

      case 'Placeholder':
        return const Placeholder();

      case 'BottomNavigationBarItem':
        return null; // يُعامَل كقيمة خاصة، وليس Widget مباشر — موجود للتوثيق.

      default:
        return null;
    }
  }

  /// عناصر ليست Widgets لكنها كائنات قيمة (EdgeInsets, TextStyle, Colors...)
  /// نبنيها هنا بشكل منفصل حتى لا نخلط "بناء ودجت" بـ"بناء قيمة مساعدة".
  static Object? buildValue(String name, List<dynamic> pos, Map<String, dynamic> named) {
    dynamic arg(String key, [int? posIndex]) =>
        named[key] ?? (posIndex != null && posIndex < pos.length ? pos[posIndex] : null);

    switch (name) {
      case 'EdgeInsets.all':
        return EdgeInsets.all((pos.isNotEmpty ? pos[0] as num : 0).toDouble());
      case 'EdgeInsets.symmetric':
        return EdgeInsets.symmetric(
          horizontal: (arg('horizontal') as num?)?.toDouble() ?? 0,
          vertical: (arg('vertical') as num?)?.toDouble() ?? 0,
        );
      case 'EdgeInsets.only':
        return EdgeInsets.only(
          left: (arg('left') as num?)?.toDouble() ?? 0,
          top: (arg('top') as num?)?.toDouble() ?? 0,
          right: (arg('right') as num?)?.toDouble() ?? 0,
          bottom: (arg('bottom') as num?)?.toDouble() ?? 0,
        );
      case 'TextStyle':
        return TextStyle(
          fontSize: (arg('fontSize') as num?)?.toDouble(),
          fontWeight: arg('fontWeight') as FontWeight?,
          color: arg('color') as Color?,
          fontStyle: arg('fontStyle') as FontStyle?,
          decoration: arg('decoration') as TextDecoration?,
          letterSpacing: (arg('letterSpacing') as num?)?.toDouble(),
        );
      case 'InputDecoration':
        return InputDecoration(
          hintText: arg('hintText') as String?,
          labelText: arg('labelText') as String?,
          prefixIcon: arg('prefixIcon') as Widget?,
          suffixIcon: arg('suffixIcon') as Widget?,
          border: const OutlineInputBorder(),
        );
      case 'BoxDecoration':
        return BoxDecoration(
          color: arg('color') as Color?,
          borderRadius: arg('borderRadius') as BorderRadiusGeometry?,
          border: arg('border') as BoxBorder?,
          boxShadow: (arg('boxShadow') as List?)?.cast<BoxShadow>(),
          shape: arg('shape') as BoxShape? ?? BoxShape.rectangle,
        );
      case 'BorderRadius.circular':
        return BorderRadius.circular((pos.isNotEmpty ? pos[0] as num : 0).toDouble());
      case 'BorderRadius.only':
        return BorderRadius.only(
          topLeft: Radius.circular((arg('topLeft') as num?)?.toDouble() ?? 0),
          topRight: Radius.circular((arg('topRight') as num?)?.toDouble() ?? 0),
          bottomLeft: Radius.circular((arg('bottomLeft') as num?)?.toDouble() ?? 0),
          bottomRight: Radius.circular((arg('bottomRight') as num?)?.toDouble() ?? 0),
        );
      case 'Border.all':
        return Border.all(
          color: arg('color') as Color? ?? Colors.black,
          width: (arg('width') as num?)?.toDouble() ?? 1.0,
        );
      case 'BoxShadow':
        return BoxShadow(
          color: arg('color') as Color? ?? Colors.black26,
          blurRadius: (arg('blurRadius') as num?)?.toDouble() ?? 0,
          spreadRadius: (arg('spreadRadius') as num?)?.toDouble() ?? 0,
          offset: arg('offset') as Offset? ?? Offset.zero,
        );
      case 'Offset':
        return Offset(
          (pos.isNotEmpty ? pos[0] as num : 0).toDouble(),
          (pos.length > 1 ? pos[1] as num : 0).toDouble(),
        );
      case 'Duration':
        return Duration(
          days: (arg('days') as num?)?.toInt() ?? 0,
          hours: (arg('hours') as num?)?.toInt() ?? 0,
          minutes: (arg('minutes') as num?)?.toInt() ?? 0,
          seconds: (arg('seconds') as num?)?.toInt() ?? 0,
          milliseconds: (arg('milliseconds') as num?)?.toInt() ?? 0,
        );
      case 'SliverGridDelegateWithFixedCrossAxisCount':
        return SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: (arg('crossAxisCount') as num?)?.toInt() ?? 2,
          mainAxisSpacing: (arg('mainAxisSpacing') as num?)?.toDouble() ?? 0,
          crossAxisSpacing: (arg('crossAxisSpacing') as num?)?.toDouble() ?? 0,
          childAspectRatio: (arg('childAspectRatio') as num?)?.toDouble() ?? 1.0,
        );
      case 'BottomNavigationBarItem':
        return BottomNavigationBarItem(
          icon: arg('icon') as Widget? ?? const Icon(Icons.circle),
          label: arg('label') as String? ?? '',
        );
      default:
        return null;
    }
  }

  /// أسماء ثابتة شائعة (Colors.red، Icons.add، ...) نستخدمها في PropertyExpr.
  static final Map<String, Object?> staticProperties = {
    // ---- Colors (أساسية) ----
    'Colors.red': Colors.red, 'Colors.green': Colors.green, 'Colors.blue': Colors.blue,
    'Colors.yellow': Colors.yellow, 'Colors.orange': Colors.orange, 'Colors.purple': Colors.purple,
    'Colors.black': Colors.black, 'Colors.white': Colors.white, 'Colors.grey': Colors.grey,
    'Colors.transparent': Colors.transparent, 'Colors.blueGrey': Colors.blueGrey,
    'Colors.teal': Colors.teal, 'Colors.indigo': Colors.indigo, 'Colors.pink': Colors.pink,
    'Colors.amber': Colors.amber, 'Colors.cyan': Colors.cyan,
    // ---- Colors (إضافية) ----
    'Colors.lime': Colors.lime, 'Colors.deepOrange': Colors.deepOrange, 'Colors.deepPurple': Colors.deepPurple,
    'Colors.lightBlue': Colors.lightBlue, 'Colors.lightGreen': Colors.lightGreen, 'Colors.brown': Colors.brown,
    'Colors.lightBlueAccent': Colors.lightBlueAccent, 'Colors.greenAccent': Colors.greenAccent,
    'Colors.redAccent': Colors.redAccent, 'Colors.blueAccent': Colors.blueAccent,
    'Colors.orangeAccent': Colors.orangeAccent, 'Colors.purpleAccent': Colors.purpleAccent,
    'Colors.black12': Colors.black12, 'Colors.black26': Colors.black26, 'Colors.black38': Colors.black38,
    'Colors.black45': Colors.black45, 'Colors.black54': Colors.black54, 'Colors.black87': Colors.black87,
    'Colors.white10': Colors.white10, 'Colors.white24': Colors.white24, 'Colors.white30': Colors.white30,
    'Colors.white54': Colors.white54, 'Colors.white70': Colors.white70,

    // ---- Icons (أساسية) ----
    'Icons.add': Icons.add, 'Icons.remove': Icons.remove, 'Icons.home': Icons.home,
    'Icons.menu': Icons.menu, 'Icons.settings': Icons.settings, 'Icons.search': Icons.search,
    'Icons.close': Icons.close, 'Icons.arrow_back': Icons.arrow_back,
    'Icons.arrow_forward': Icons.arrow_forward, 'Icons.favorite': Icons.favorite,
    'Icons.star': Icons.star, 'Icons.delete': Icons.delete, 'Icons.edit': Icons.edit,
    'Icons.check': Icons.check, 'Icons.person': Icons.person, 'Icons.email': Icons.email,
    // ---- Icons (إضافية) ----
    'Icons.shopping_cart': Icons.shopping_cart, 'Icons.shopping_bag': Icons.shopping_bag,
    'Icons.notifications': Icons.notifications, 'Icons.notifications_none': Icons.notifications_none,
    'Icons.favorite_border': Icons.favorite_border, 'Icons.star_border': Icons.star_border,
    'Icons.thumb_up': Icons.thumb_up, 'Icons.thumb_down': Icons.thumb_down, 'Icons.share': Icons.share,
    'Icons.more_horiz': Icons.more_horiz, 'Icons.more_vert': Icons.more_vert,
    'Icons.visibility': Icons.visibility, 'Icons.visibility_off': Icons.visibility_off,
    'Icons.lock': Icons.lock, 'Icons.lock_open': Icons.lock_open, 'Icons.camera_alt': Icons.camera_alt,
    'Icons.mic': Icons.mic, 'Icons.phone': Icons.phone, 'Icons.chat_bubble_outline': Icons.chat_bubble_outline,
    'Icons.send': Icons.send, 'Icons.download': Icons.download, 'Icons.upload': Icons.upload,
    'Icons.cloud': Icons.cloud, 'Icons.wifi': Icons.wifi, 'Icons.bluetooth': Icons.bluetooth,
    'Icons.battery_full': Icons.battery_full, 'Icons.location_on': Icons.location_on,
    'Icons.calendar_today': Icons.calendar_today, 'Icons.access_time': Icons.access_time,
    'Icons.info_outline': Icons.info_outline, 'Icons.warning_amber': Icons.warning_amber,
    'Icons.help_outline': Icons.help_outline,
    'Icons.keyboard_arrow_up': Icons.keyboard_arrow_up, 'Icons.keyboard_arrow_down': Icons.keyboard_arrow_down,
    'Icons.keyboard_arrow_left': Icons.keyboard_arrow_left, 'Icons.keyboard_arrow_right': Icons.keyboard_arrow_right,
    'Icons.chevron_left': Icons.chevron_left, 'Icons.chevron_right': Icons.chevron_right,
    'Icons.expand_more': Icons.expand_more, 'Icons.expand_less': Icons.expand_less,
    'Icons.filter_list': Icons.filter_list, 'Icons.sort': Icons.sort, 'Icons.refresh': Icons.refresh,
    'Icons.logout': Icons.logout, 'Icons.login': Icons.login,
    'Icons.local_shipping': Icons.local_shipping, 'Icons.credit_card': Icons.credit_card,
    'Icons.attach_money': Icons.attach_money, 'Icons.language': Icons.language,
    'Icons.dark_mode': Icons.dark_mode, 'Icons.light_mode': Icons.light_mode,

    // ---- FontWeight ----
    'FontWeight.bold': FontWeight.bold, 'FontWeight.normal': FontWeight.normal,
    'FontWeight.w100': FontWeight.w100, 'FontWeight.w200': FontWeight.w200, 'FontWeight.w300': FontWeight.w300,
    'FontWeight.w400': FontWeight.w400, 'FontWeight.w500': FontWeight.w500, 'FontWeight.w600': FontWeight.w600,
    'FontWeight.w700': FontWeight.w700, 'FontWeight.w800': FontWeight.w800, 'FontWeight.w900': FontWeight.w900,

    // ---- تخطيط عام (موجودة سابقًا) ----
    'MainAxisAlignment.start': MainAxisAlignment.start, 'MainAxisAlignment.end': MainAxisAlignment.end,
    'MainAxisAlignment.center': MainAxisAlignment.center,
    'MainAxisAlignment.spaceBetween': MainAxisAlignment.spaceBetween,
    'MainAxisAlignment.spaceAround': MainAxisAlignment.spaceAround,
    'MainAxisAlignment.spaceEvenly': MainAxisAlignment.spaceEvenly,
    'CrossAxisAlignment.start': CrossAxisAlignment.start, 'CrossAxisAlignment.end': CrossAxisAlignment.end,
    'CrossAxisAlignment.center': CrossAxisAlignment.center,
    'CrossAxisAlignment.stretch': CrossAxisAlignment.stretch,
    'MainAxisSize.min': MainAxisSize.min, 'MainAxisSize.max': MainAxisSize.max,
    'TextAlign.left': TextAlign.left, 'TextAlign.right': TextAlign.right,
    'TextAlign.center': TextAlign.center, 'TextAlign.justify': TextAlign.justify,
    'FontStyle.italic': FontStyle.italic, 'FontStyle.normal': FontStyle.normal,
    'Alignment.center': Alignment.center, 'Alignment.topCenter': Alignment.topCenter,
    'Alignment.bottomCenter': Alignment.bottomCenter,
    'Alignment.topLeft': Alignment.topLeft, 'Alignment.topRight': Alignment.topRight,
    'Alignment.bottomLeft': Alignment.bottomLeft, 'Alignment.bottomRight': Alignment.bottomRight,
    'Alignment.centerLeft': Alignment.centerLeft, 'Alignment.centerRight': Alignment.centerRight,

    // ---- تخطيط عام (جديدة) ----
    'BoxShape.circle': BoxShape.circle, 'BoxShape.rectangle': BoxShape.rectangle,
    'Axis.horizontal': Axis.horizontal, 'Axis.vertical': Axis.vertical,
    'WrapAlignment.start': WrapAlignment.start, 'WrapAlignment.center': WrapAlignment.center,
    'WrapAlignment.end': WrapAlignment.end, 'WrapAlignment.spaceBetween': WrapAlignment.spaceBetween,
    'WrapAlignment.spaceAround': WrapAlignment.spaceAround, 'WrapAlignment.spaceEvenly': WrapAlignment.spaceEvenly,
    'FlexFit.tight': FlexFit.tight, 'FlexFit.loose': FlexFit.loose,
    'BoxFit.cover': BoxFit.cover, 'BoxFit.contain': BoxFit.contain, 'BoxFit.fill': BoxFit.fill,
    'BoxFit.fitWidth': BoxFit.fitWidth, 'BoxFit.fitHeight': BoxFit.fitHeight, 'BoxFit.none': BoxFit.none,
    'TextDecoration.underline': TextDecoration.underline, 'TextDecoration.lineThrough': TextDecoration.lineThrough,
    'TextDecoration.none': TextDecoration.none, 'TextDecoration.overline': TextDecoration.overline,
    'TextOverflow.clip': TextOverflow.clip, 'TextOverflow.ellipsis': TextOverflow.ellipsis,
    'TextOverflow.fade': TextOverflow.fade,
    'BottomNavigationBarType.fixed': BottomNavigationBarType.fixed,
    'BottomNavigationBarType.shifting': BottomNavigationBarType.shifting,
  };

  /// أسماء المُنشئات التي تُبنى كقيمة (وليست Widget) — يستخدمها المُفسِّر
  /// لتقرير هل يستدعي [build] أو [buildValue].
  static const Set<String> valueConstructors = {
    'EdgeInsets.all', 'EdgeInsets.symmetric', 'EdgeInsets.only',
    'TextStyle', 'InputDecoration', 'BoxDecoration',
    'BorderRadius.circular', 'BorderRadius.only', 'Border.all', 'BoxShadow',
    'Offset', 'Duration', 'SliverGridDelegateWithFixedCrossAxisCount',
    'BottomNavigationBarItem',
  };
}
