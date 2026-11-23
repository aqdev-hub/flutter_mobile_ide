import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'interpreted_callable.dart';
import 'native_members.dart' show kNoNative;

VoidCallback? _asVoid(dynamic v) => v is InterpretedCallable ? v.asVoidCallback : null;
void Function(String)? _asStringCb(dynamic v) => v is InterpretedCallable ? v.asStringCallback : null;
double? _d(dynamic v) => (v as num?)?.toDouble();
void Function(int)? _asIntCb(dynamic v) => v is InterpretedCallable ? v.asIntCallback : null;
Widget Function(BuildContext, int)? _asIndexedBuilder(dynamic v) =>
    v is InterpretedCallable ? v.asIndexedBuilder : null;

/// امتداد لـ [BuiltinWidgets] (builtin_widgets.dart) دون تعديل ذلك الملف:
/// المُفسِّر يستشير هذا الصنف **أولًا**، فما يُعرِّفه هنا يتقدّم على القديم.
///
/// يضيف: MaterialApp كاملًا (theme/darkTheme/themeMode/routes...)، MaterialButton،
/// Form + GlobalKey، نسخًا موسَّعة من TextField/TextFormField (keyboardType،
/// style، enabled، readOnly، autofocus، onSubmitted...)، ThemeData/ColorScheme/
/// TextTheme، أشكال الحدود، ومفاتيح (Key/ValueKey/UniqueKey)، وثوابت جديدة.
///
/// ⚠️ تنويه صريح: أسماء المعاملات هنا من معرفتي بواجهات Flutter المستقرة
/// وليست مؤكَّدة بلقطة إكمال من مشروعكم. ThemeData لا تُمرَّر له عمدًا
/// خصائص قليلة الاستقرار (appBarTheme وغيرها). إن ظهر عند البناء خطأ
/// "The named parameter 'x' isn't defined" فاحذفوا ذلك المعامل فقط.
class BuiltinWidgetsExt {
  BuiltinWidgetsExt._();

  static Widget? build(String name, List<dynamic> pos, Map<String, dynamic> named) {
    dynamic arg(String key, [int? posIndex]) =>
        named[key] ?? (posIndex != null && posIndex < pos.length ? pos[posIndex] : null);

    switch (name) {
      case 'MaterialApp':
        final rawRoutes = arg('routes') as Map?;
        return MaterialApp(
          title: arg('title') as String? ?? '',
          debugShowCheckedModeBanner: false,
          theme: arg('theme') as ThemeData? ?? ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
          darkTheme: arg('darkTheme') as ThemeData?,
          themeMode: arg('themeMode') as ThemeMode? ?? ThemeMode.light,
          home: arg('home') as Widget?,
          initialRoute: arg('initialRoute') as String?,
          locale: arg('locale') as Locale?,
          supportedLocales: (arg('supportedLocales') as List?)?.cast<Locale>() ??
              [if (arg('locale') is Locale) arg('locale') as Locale, const Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
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

      case 'Builder':
        {
          final b = arg('builder');
          return Builder(builder: b is InterpretedCallable ? b.asContextBuilder : (c) => const SizedBox.shrink());
        }

      case 'Directionality':
        return Directionality(
          textDirection: arg('textDirection') as TextDirection? ?? TextDirection.ltr,
          child: arg('child') as Widget? ?? const SizedBox.shrink(),
        );

      case 'PageView':
        return PageView(
          controller: arg('controller') as PageController?,
          scrollDirection: arg('scrollDirection') as Axis? ?? Axis.horizontal,
          reverse: arg('reverse') as bool? ?? false,
          onPageChanged: _asIntCb(arg('onPageChanged')),
          children: (arg('children', 0) as List?)?.cast<Widget>() ?? const [],
        );

      case 'PageView.builder':
        {
          final builder = _asIndexedBuilder(arg('itemBuilder'));
          if (builder == null) return const SizedBox.shrink();
          return PageView.builder(
            controller: arg('controller') as PageController?,
            scrollDirection: arg('scrollDirection') as Axis? ?? Axis.horizontal,
            reverse: arg('reverse') as bool? ?? false,
            itemCount: (arg('itemCount') as num?)?.toInt(),
            onPageChanged: _asIntCb(arg('onPageChanged')),
            itemBuilder: builder,
          );
        }

      case 'GestureDetector':
        return GestureDetector(
          behavior: arg('behavior') as HitTestBehavior?,
          onTap: _asVoid(arg('onTap')),
          onLongPress: _asVoid(arg('onLongPress')),
          onDoubleTap: _asVoid(arg('onDoubleTap')),
          child: arg('child') as Widget?,
        );

      case 'MaterialButton':
        return MaterialButton(
          onPressed: _asVoid(arg('onPressed')),
          onLongPress: _asVoid(arg('onLongPress')),
          color: arg('color') as Color?,
          textColor: arg('textColor') as Color?,
          disabledColor: arg('disabledColor') as Color?,
          disabledTextColor: arg('disabledTextColor') as Color?,
          splashColor: arg('splashColor') as Color?,
          highlightColor: arg('highlightColor') as Color?,
          elevation: _d(arg('elevation')),
          padding: arg('padding') as EdgeInsetsGeometry?,
          shape: arg('shape') as ShapeBorder?,
          minWidth: _d(arg('minWidth')),
          height: _d(arg('height')),
          clipBehavior: arg('clipBehavior') as Clip? ?? Clip.none,
          child: arg('child') as Widget?,
        );

      // Radio بالصيغة الحديثة (RadioGroup) — بديل groupValue/onChanged المتقادمَين.
      case 'Radio':
        {
          final onChangedCallable = arg('onChanged');
          return RadioGroup<dynamic>(
            groupValue: arg('groupValue'),
            onChanged: (dynamic newValue) {
              if (onChangedCallable is InterpretedCallable) onChangedCallable.call([newValue]);
            },
            child: Radio<dynamic>(value: arg('value')),
          );
        }

      case 'Form':
        return Form(
          key: arg('key') as Key?,
          autovalidateMode: arg('autovalidateMode') as AutovalidateMode?,
          child: arg('child') as Widget? ?? const SizedBox.shrink(),
        );

      case 'TextField':
        return TextField(
          controller: arg('controller') as TextEditingController?,
          onChanged: _asStringCb(arg('onChanged')),
          onSubmitted: _asStringCb(arg('onSubmitted')),
          decoration: arg('decoration') as InputDecoration? ?? const InputDecoration(),
          obscureText: arg('obscureText') as bool? ?? false,
          maxLines: (arg('maxLines') as num?)?.toInt() ?? 1,
          minLines: (arg('minLines') as num?)?.toInt(),
          maxLength: (arg('maxLength') as num?)?.toInt(),
          keyboardType: arg('keyboardType') as TextInputType?,
          textInputAction: arg('textInputAction') as TextInputAction?,
          style: arg('style') as TextStyle?,
          textAlign: arg('textAlign') as TextAlign? ?? TextAlign.start,
          enabled: arg('enabled') as bool?,
          readOnly: arg('readOnly') as bool? ?? false,
          autofocus: arg('autofocus') as bool? ?? false,
          inputFormatters: (arg('inputFormatters') as List?)?.cast<TextInputFormatter>(),
          focusNode: arg('focusNode') as FocusNode?,
          textCapitalization: arg('textCapitalization') as TextCapitalization? ?? TextCapitalization.none,
          cursorColor: arg('cursorColor') as Color?,
          onEditingComplete: _asVoid(arg('onEditingComplete')),
        );

      case 'TextFormField':
        {
          final validatorCallable = arg('validator');
          final onSavedCallable = arg('onSaved');
          final hasController = arg('controller') != null;
          return TextFormField(
            controller: arg('controller') as TextEditingController?,
            initialValue: hasController ? null : arg('initialValue') as String?,
            decoration: arg('decoration') as InputDecoration? ?? const InputDecoration(),
            obscureText: arg('obscureText') as bool? ?? false,
            maxLines: (arg('maxLines') as num?)?.toInt() ?? 1,
            minLines: (arg('minLines') as num?)?.toInt(),
            maxLength: (arg('maxLength') as num?)?.toInt(),
            keyboardType: arg('keyboardType') as TextInputType?,
            textInputAction: arg('textInputAction') as TextInputAction?,
            style: arg('style') as TextStyle?,
            textAlign: arg('textAlign') as TextAlign? ?? TextAlign.start,
            enabled: arg('enabled') as bool?,
            readOnly: arg('readOnly') as bool? ?? false,
            autofocus: arg('autofocus') as bool? ?? false,
            inputFormatters: (arg('inputFormatters') as List?)?.cast<TextInputFormatter>(),
            focusNode: arg('focusNode') as FocusNode?,
            textCapitalization: arg('textCapitalization') as TextCapitalization? ?? TextCapitalization.none,
            cursorColor: arg('cursorColor') as Color?,
            onEditingComplete: _asVoid(arg('onEditingComplete')),
            autovalidateMode: arg('autovalidateMode') as AutovalidateMode?,
            onChanged: _asStringCb(arg('onChanged')),
            onFieldSubmitted: _asStringCb(arg('onFieldSubmitted')),
            validator: validatorCallable is InterpretedCallable
                ? (String? value) => validatorCallable.call([value])?.toString()
                : null,
            onSaved: onSavedCallable is InterpretedCallable
                ? (String? value) {
                    onSavedCallable.call([value]);
                  }
                : null,
          );
        }
    }
    return null;
  }

  /// أسماء المُنشئات التي تُبنى كقيمة (وليست Widget) وتُعالَج هنا.
  static const Set<String> valueConstructors = {
    'ThemeData', 'ThemeData.light', 'ThemeData.dark',
    'ColorScheme.fromSeed', 'TextTheme',
    'RoundedRectangleBorder', 'StadiumBorder', 'CircleBorder',
    'Radius.circular', 'BorderRadius.all',
    'GlobalKey', 'Key', 'ValueKey', 'UniqueKey',
    'InputDecoration', 'Locale', 'FocusNode', 'PageController',
    'FilteringTextInputFormatter.allow', 'FilteringTextInputFormatter.deny',
    'LengthLimitingTextInputFormatter',
  };

  static Object? buildValue(String name, List<dynamic> pos, Map<String, dynamic> named) {
    dynamic arg(String key, [int? posIndex]) =>
        named[key] ?? (posIndex != null && posIndex < pos.length ? pos[posIndex] : null);

    switch (name) {
      case 'ThemeData':
        return ThemeData(
          useMaterial3: arg('useMaterial3') as bool? ?? true,
          primarySwatch: arg('primarySwatch') as MaterialColor?,
          primaryColor: arg('primaryColor') as Color?,
          colorScheme: arg('colorScheme') as ColorScheme?,
          scaffoldBackgroundColor: arg('scaffoldBackgroundColor') as Color?,
          brightness: arg('brightness') as Brightness?,
          textTheme: arg('textTheme') as TextTheme?,
          fontFamily: arg('fontFamily') as String?,
        );
      case 'ThemeData.light':
        return ThemeData.light(useMaterial3: arg('useMaterial3') as bool? ?? true);
      case 'ThemeData.dark':
        return ThemeData.dark(useMaterial3: arg('useMaterial3') as bool? ?? true);
      case 'ColorScheme.fromSeed':
        return ColorScheme.fromSeed(
          seedColor: arg('seedColor', 0) as Color? ?? Colors.blue,
          brightness: arg('brightness') as Brightness? ?? Brightness.light,
        );
      case 'TextTheme':
        return TextTheme(
          displayLarge: arg('displayLarge') as TextStyle?,
          displayMedium: arg('displayMedium') as TextStyle?,
          displaySmall: arg('displaySmall') as TextStyle?,
          headlineLarge: arg('headlineLarge') as TextStyle?,
          headlineMedium: arg('headlineMedium') as TextStyle?,
          headlineSmall: arg('headlineSmall') as TextStyle?,
          titleLarge: arg('titleLarge') as TextStyle?,
          titleMedium: arg('titleMedium') as TextStyle?,
          titleSmall: arg('titleSmall') as TextStyle?,
          bodyLarge: arg('bodyLarge') as TextStyle?,
          bodyMedium: arg('bodyMedium') as TextStyle?,
          bodySmall: arg('bodySmall') as TextStyle?,
          labelLarge: arg('labelLarge') as TextStyle?,
          labelMedium: arg('labelMedium') as TextStyle?,
          labelSmall: arg('labelSmall') as TextStyle?,
        );
      case 'RoundedRectangleBorder':
        return RoundedRectangleBorder(
          borderRadius: arg('borderRadius') as BorderRadiusGeometry? ?? BorderRadius.zero,
          side: arg('side') as BorderSide? ?? BorderSide.none,
        );
      case 'StadiumBorder':
        return StadiumBorder(side: arg('side') as BorderSide? ?? BorderSide.none);
      case 'CircleBorder':
        return CircleBorder(side: arg('side') as BorderSide? ?? BorderSide.none);
      case 'Radius.circular':
        return Radius.circular((pos.isNotEmpty ? pos[0] as num : 0).toDouble());
      case 'BorderRadius.all':
        return BorderRadius.all(pos.isNotEmpty ? pos[0] as Radius : Radius.zero);
      case 'Locale':
        return Locale(pos[0] as String, pos.length > 1 ? pos[1] as String? : null);
      case 'FocusNode':
        return FocusNode();
      case 'PageController':
        return PageController(
          initialPage: (arg('initialPage') as num?)?.toInt() ?? 0,
          viewportFraction: (arg('viewportFraction') as num?)?.toDouble() ?? 1.0,
          keepPage: arg('keepPage') as bool? ?? true,
        );
      case 'FilteringTextInputFormatter.allow':
        return FilteringTextInputFormatter.allow(pos[0] as RegExp);
      case 'FilteringTextInputFormatter.deny':
        return FilteringTextInputFormatter.deny(pos[0] as RegExp);
      case 'LengthLimitingTextInputFormatter':
        return LengthLimitingTextInputFormatter((pos.isNotEmpty ? pos[0] as num? : null)?.toInt());
      case 'InputDecoration':
        return InputDecoration(
          hintText: arg('hintText') as String?,
          labelText: arg('labelText') as String?,
          label: arg('label') as Widget?,
          floatingLabelBehavior: arg('floatingLabelBehavior') as FloatingLabelBehavior?,
          helperText: arg('helperText') as String?,
          errorText: arg('errorText') as String?,
          counterText: arg('counterText') as String?,
          prefixText: arg('prefixText') as String?,
          suffixText: arg('suffixText') as String?,
          isDense: arg('isDense') as bool?,
          filled: arg('filled') as bool?,
          fillColor: arg('fillColor') as Color?,
          contentPadding: arg('contentPadding') as EdgeInsetsGeometry?,
          labelStyle: arg('labelStyle') as TextStyle?,
          hintStyle: arg('hintStyle') as TextStyle?,
          prefixIcon: arg('prefixIcon') as Widget?,
          suffixIcon: arg('suffixIcon') as Widget?,
          enabledBorder: arg('enabledBorder') as InputBorder?,
          focusedBorder: arg('focusedBorder') as InputBorder?,
          border: arg('border') as InputBorder? ?? const OutlineInputBorder(),
        );
      case 'GlobalKey':
        return GlobalKey();
      case 'Key':
        return ValueKey<String>((pos.isNotEmpty ? pos[0] : '').toString());
      case 'ValueKey':
        return ValueKey<dynamic>(pos.isNotEmpty ? pos[0] : null);
      case 'UniqueKey':
        return UniqueKey();
    }
    return null;
  }

  /// أي enum مسجَّل هنا تُحَل قيمه آليًا بالاسم (HitTestBehavior.opaque ...) بدل
  /// تسجيل كل قيمة يدويًا. إضافة enum جديد = سطر واحد.
  static final Map<String, List<Enum>> enumTypes = {
    'TextDirection': TextDirection.values,
    'HitTestBehavior': HitTestBehavior.values,
    'TextCapitalization': TextCapitalization.values,
    'StackFit': StackFit.values,
    'VerticalDirection': VerticalDirection.values,
    'TextBaseline': TextBaseline.values,
    'MaterialTapTargetSize': MaterialTapTargetSize.values,
    'ScrollViewKeyboardDismissBehavior': ScrollViewKeyboardDismissBehavior.values,
  };

  static Object? enumValue(String type, String name) {
    final values = enumTypes[type];
    if (values == null) return kNoNative;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return kNoNative;
  }

  /// ثوابت جديدة (تُستشار قبل BuiltinWidgets.staticProperties).
  static final Map<String, Object?> staticProperties = {
    'ThemeMode.light': ThemeMode.light, 'ThemeMode.dark': ThemeMode.dark, 'ThemeMode.system': ThemeMode.system,
    'Brightness.light': Brightness.light, 'Brightness.dark': Brightness.dark,
    'Orientation.portrait': Orientation.portrait, 'Orientation.landscape': Orientation.landscape,
    'TextInputType.text': TextInputType.text, 'TextInputType.emailAddress': TextInputType.emailAddress,
    'TextInputType.number': TextInputType.number, 'TextInputType.phone': TextInputType.phone,
    'TextInputType.multiline': TextInputType.multiline, 'TextInputType.url': TextInputType.url,
    'TextInputType.visiblePassword': TextInputType.visiblePassword, 'TextInputType.name': TextInputType.name,
    'TextInputType.datetime': TextInputType.datetime,
    'TextInputAction.next': TextInputAction.next, 'TextInputAction.done': TextInputAction.done,
    'TextInputAction.go': TextInputAction.go, 'TextInputAction.search': TextInputAction.search,
    'TextInputAction.send': TextInputAction.send,
    'AutovalidateMode.always': AutovalidateMode.always, 'AutovalidateMode.disabled': AutovalidateMode.disabled,
    'AutovalidateMode.onUserInteraction': AutovalidateMode.onUserInteraction,
    'Clip.none': Clip.none, 'Clip.hardEdge': Clip.hardEdge, 'Clip.antiAlias': Clip.antiAlias,
    'BorderSide.none': BorderSide.none,
    'BorderRadius.zero': BorderRadius.zero,
    'EdgeInsets.zero': EdgeInsets.zero,
    'Duration.zero': Duration.zero,
    'Curves.linear': Curves.linear, 'Curves.ease': Curves.ease, 'Curves.easeIn': Curves.easeIn,
    'Curves.easeOut': Curves.easeOut, 'Curves.easeInOut': Curves.easeInOut,
    'Curves.fastOutSlowIn': Curves.fastOutSlowIn, 'Curves.bounceOut': Curves.bounceOut,
    'Curves.decelerate': Curves.decelerate,
    'FilteringTextInputFormatter.digitsOnly': FilteringTextInputFormatter.digitsOnly,
  };

  /// المساحات الاسمية الجديدة لرسائل "غير مسجَّل" الواضحة.
  static const Set<String> staticNamespaces = {
    'ThemeMode', 'Brightness', 'Orientation', 'TextInputType', 'TextInputAction',
    'AutovalidateMode', 'Clip', 'Curves', 'FilteringTextInputFormatter',
  };
}
