import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/keyboard_inset_scope.dart';
import '../logic/preview_provider.dart';

class PreviewPanel extends ConsumerWidget {
  /// ارتفاع لوحة مفاتيح الجهاز الحقيقية يُقرأ من [KeyboardInsetScope] (موضوع
  /// فوق Scaffold في AppShell). لا تُقلّص المعاينة؛ بل يُحسب الجزء المتقاطع مع
  /// إطار المحاكي ويُمرَّر لداخله كـ viewInsets ليتصرف Scaffold المُفسَّر كما
  /// في هاتف حقيقي.
  const PreviewPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewState = ref.watch(previewProvider);
    final keyboardInset = KeyboardInsetScope.of(context);

    return Container(
      color: IdeColors.darkSurface,
      child: Center(
        child: switch (previewState.status) {
          PreviewStatus.idle => const _IdlePreview(),
          PreviewStatus.error => _ErrorPreview(message: previewState.errorMessage ?? 'خطأ غير معروف'),
          PreviewStatus.running => _DeviceFrame(
              keyboardInset: keyboardInset,
              // ⚠️ لا يوجد أي مفتاح (Key) قسري هنا عمدًا — كان موجودًا سابقًا
              // (ValueKey(rebuildTick)) بهدف إجبار إعادة البناء، لكنه كان
              // السبب الجذري لمشكلة حقيقية: أي setState داخل شاشة فرعية
              // مفتوحة عبر Navigator.push كان يُهدم شجرة Navigator بالكامل
              // ويُعيد إنشاءها من الصفر (لأن تغيّر المفتاح يجعل Flutter
              // يتعامل مع الشجرة كعنصر جديد كليًا لا عنصر يُحدَّث)، فتفقد
              // Navigator مسارها الحالي — وهذا بالضبط ما بدا وكأن "الشاشة
              // الفرعية لا تتحدث فورًا" رغم أن القيمة كانت تتغيّر بالفعل.
              // بدون هذا المفتاح، تُعاد شجرة widgets **جديدة فعليًا** من
              // buildRoot() (بما يعكس القيم المحدَّثة)، لكن Flutter يُحدِّث
              // العناصر الحالية في مكانها بدل هدمها، فتُحافَظ حالة Navigator
              // الداخلية تلقائيًا.
              child: Builder(
                builder: (innerContext) =>
                    previewState.interpreter!.buildRoot(previewState.rootExpr!, innerContext),
              ),
            ),
        },
      ),
    );
  }
}

class _IdlePreview extends ConsumerWidget {
  const _IdlePreview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.play_circle_outline, size: 48, color: Colors.grey),
        const SizedBox(height: 12),
        const Text('لم يتم تشغيل المشروع بعد', style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => ref.read(previewProvider.notifier).run(),
          icon: const Icon(Icons.play_arrow),
          label: const Text('تشغيل المشروع'),
        ),
      ],
    );
  }
}

class _ErrorPreview extends ConsumerWidget {
  final String message;
  const _ErrorPreview({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40, color: IdeColors.stopRed),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => ref.read(previewProvider.notifier).run(),
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
          ),
        ],
      ),
    );
  }
}

/// إطار يشبه جهاز الهاتف حول المحتوى المُشغَّل، ليُعطي إحساسًا بصريًا
/// بأن هذه "معاينة تطبيق حقيقي" وليست جزءًا من واجهة المحرر نفسها.
///
/// عند ظهور لوحة المفاتيح يبقى الإطار بحجمه، ويُمرَّر لداخله فقط الجزء من
/// الكيبورد الذي يغطّي الإطار فعليًا (viewInsets.bottom)، فيرفع Scaffold
/// المُفسَّر المحتوى تمامًا كما يحدث في تطبيق على هاتف حقيقي.
class _DeviceFrame extends StatefulWidget {
  final Widget child;
  final double keyboardInset;
  const _DeviceFrame({required this.child, this.keyboardInset = 0});

  @override
  State<_DeviceFrame> createState() => _DeviceFrameState();
}

class _DeviceFrameState extends State<_DeviceFrame> {
  static const double _bezel = 6;
  final GlobalKey _frameKey = GlobalKey();

  /// الجزء من الكيبورد المتقاطع مع المنطقة الداخلية للإطار (بعد الحواف).
  /// موضع الإطار ثابت لأن Scaffold لا يُقلَّص في وضع المعاينة، فنقرأ موضعه
  /// من آخر تخطيط (render box) بأمان.
  double _overlap(double innerHeight) {
    if (widget.keyboardInset <= 0) return 0;
    final box = _frameKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return 0;
    final frameBottom = box.localToGlobal(Offset(0, box.size.height)).dy;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboardTop = screenHeight - widget.keyboardInset;
    final innerBottom = frameBottom - _bezel;
    return (innerBottom - keyboardTop).clamp(0.0, innerHeight).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth = constraints.maxWidth * 0.92;
      final maxHeight = constraints.maxHeight * 0.94;
      final frameWidth = (maxHeight * 0.5) < maxWidth ? maxHeight * 0.5 : maxWidth;
      final innerSize = Size(frameWidth - _bezel * 2, maxHeight - _bezel * 2);

      return Container(
        key: _frameKey,
        width: frameWidth,
        height: maxHeight,
        padding: const EdgeInsets.all(_bezel),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: MediaQuery(
            data: MediaQueryData(
              size: innerSize,
              viewInsets: EdgeInsets.only(bottom: _overlap(innerSize.height)),
            ),
            child: widget.child,
          ),
        ),
      );
    });
  }
}
