import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../../editor/logic/editor_tabs_provider.dart';
import '../../preview/logic/preview_provider.dart';
import '../../project_explorer/logic/project_provider.dart';
import '../../project_explorer/view/dialogs/pubspec_dependencies_dialog.dart';

enum MainSegment { editor, preview }

class TopBar extends ConsumerWidget {
  final bool sidebarVisible;
  final VoidCallback onToggleSidebar;
  final MainSegment segment;
  final ValueChanged<MainSegment> onSegmentChanged;
  final VoidCallback onToggleFind;

  const TopBar({
    super.key,
    required this.sidebarVisible,
    required this.onToggleSidebar,
    required this.segment,
    required this.onSegmentChanged,
    required this.onToggleFind,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final project = ref.watch(projectProvider);
    final previewStatus = ref.watch(previewProvider.select((s) => s.status));
    final projectName = project.root?.name ?? AppConstants.appName;

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: const BoxDecoration(
        color: IdeColors.darkTopBar,
        border: Border(bottom: BorderSide(color: IdeColors.darkBorder)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: sidebarVisible ? 'إخفاء شجرة الملفات' : 'إظهار شجرة الملفات',
            icon: Icon(sidebarVisible ? Icons.view_sidebar : Icons.view_sidebar_outlined, size: 20),
            onPressed: onToggleSidebar,
          ),
          Flexible(
            child: Text(
              projectName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          _StatusPill(status: previewStatus),
          const Spacer(),
          _EditorSegmentToggle(segment: segment, onChanged: onSegmentChanged),
          const Spacer(),
          IconButton(
            tooltip: 'بحث داخل الملف',
            icon: const Icon(Icons.manage_search, size: 20),
            onPressed: onToggleFind,
          ),
          IconButton(
            tooltip: 'حفظ الملف الحالي',
            icon: const Icon(Icons.save_outlined, size: 20),
            onPressed: () => ref.read(editorTabsProvider.notifier).saveActive(),
          ),
          _RunButton(status: previewStatus),
          PopupMenuButton<_MoreAction>(
            tooltip: 'المزيد',
            icon: const Icon(Icons.more_vert, size: 20),
            onSelected: (action) => _handleMore(context, ref, action),
            itemBuilder: (context) => [
              const PopupMenuItem(value: _MoreAction.openFolder, child: Text('فتح مجلد مشروع')),
              const PopupMenuItem(value: _MoreAction.refresh, child: Text('تحديث المشروع')),
              const PopupMenuItem(value: _MoreAction.closeTab, child: Text('إغلاق التبويب الحالي')),
              if (project.hasProject)
                const PopupMenuItem(value: _MoreAction.managePackages, child: Text('إدارة الحزم (pubspec)')),
            ],
          ),
        ],
      ),
    );
  }

  void _handleMore(BuildContext context, WidgetRef ref, _MoreAction action) {
    switch (action) {
      case _MoreAction.openFolder:
        ref.read(projectProvider.notifier).openProjectFromDevice();
        break;
      case _MoreAction.refresh:
        ref.read(projectProvider.notifier).refreshProject();
        break;
      case _MoreAction.closeTab:
        final active = ref.read(editorTabsProvider).activePath;
        if (active != null) ref.read(editorTabsProvider.notifier).closeTab(active);
        break;
      case _MoreAction.managePackages:
        showPubspecDependenciesDialog(context, ref);
        break;
    }
  }
}

enum _MoreAction { openFolder, refresh, closeTab, managePackages }

class _EditorSegmentToggle extends StatelessWidget {
  final MainSegment segment;
  final ValueChanged<MainSegment> onChanged;
  const _EditorSegmentToggle({required this.segment, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: IdeColors.darkSurface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _segmentButton(context, 'المحرر', MainSegment.editor),
          _segmentButton(context, 'المعاينة', MainSegment.preview),
        ],
      ),
    );
  }

  Widget _segmentButton(BuildContext context, String label, MainSegment value) {
    final isActive = segment == value;
    return InkWell(
      onTap: () => onChanged(value),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? IdeColors.accentBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, color: isActive ? Colors.white : Colors.grey)),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final PreviewStatus status;
  const _StatusPill({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      PreviewStatus.running => (IdeColors.runGreen, 'يعمل'),
      PreviewStatus.error => (IdeColors.stopRed, 'خطأ'),
      PreviewStatus.idle => (Colors.grey, 'متوقف'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _RunButton extends ConsumerWidget {
  final PreviewStatus status;
  const _RunButton({required this.status});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRunning = status == PreviewStatus.running;
    return IconButton(
      tooltip: isRunning ? 'إيقاف التشغيل' : 'تشغيل المشروع',
      icon: Icon(
        isRunning ? Icons.stop_circle : Icons.play_circle_fill,
        color: isRunning ? IdeColors.stopRed : IdeColors.runGreen,
        size: 26,
      ),
      onPressed: () {
        if (isRunning) {
          ref.read(previewProvider.notifier).stop();
        } else {
          ref.read(previewProvider.notifier).run();
        }
      },
    );
  }
}
