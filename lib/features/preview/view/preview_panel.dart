import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../logic/preview_provider.dart';

class PreviewPanel extends ConsumerWidget {
  const PreviewPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previewState = ref.watch(previewProvider);

    return Container(
      color: IdeColors.darkSurface,
      child: Center(
        child: switch (previewState.status) {
          PreviewStatus.idle => const _IdlePreview(),
          PreviewStatus.error => _ErrorPreview(message: previewState.errorMessage ?? 'خطأ غير معروف'),
          PreviewStatus.running => _DeviceFrame(
              // مفتاح فريد يتغيّر مع rebuildTick لضمان إعادة بناء الشجرة كاملة
              // عند كل setState، بدل الاعتماد على مقارنة Widget تلقائية قد
              // تُخفي تحديثات لا يلتقطها Flutter دون مفتاح صريح.
              key: ValueKey(previewState.rebuildTick),
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
class _DeviceFrame extends StatelessWidget {
  final Widget child;
  const _DeviceFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final maxWidth = constraints.maxWidth * 0.92;
      final maxHeight = constraints.maxHeight * 0.94;
      final frameWidth = (maxHeight * 0.5) < maxWidth ? maxHeight * 0.5 : maxWidth;

      return Container(
        width: frameWidth,
        height: maxHeight,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 20)],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: MediaQuery(
            data: MediaQueryData(size: Size(frameWidth - 12, maxHeight - 12)),
            child: child,
          ),
        ),
      );
    });
  }
}
