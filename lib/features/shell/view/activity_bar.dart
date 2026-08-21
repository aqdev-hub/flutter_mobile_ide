import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

enum SidebarPanel { explorer, search, git, settings }

class ActivityBar extends StatelessWidget {
  final SidebarPanel active;
  final ValueChanged<SidebarPanel> onChanged;

  const ActivityBar({super.key, required this.active, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      decoration: const BoxDecoration(
        color: IdeColors.darkSidebar,
        border: Border(right: BorderSide(color: IdeColors.darkBorder)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _item(Icons.folder_copy_outlined, SidebarPanel.explorer, 'مستكشف المشروع'),
          _item(Icons.search, SidebarPanel.search, 'بحث'),
          _item(Icons.source_outlined, SidebarPanel.git, 'Git'),
          const Spacer(),
          _item(Icons.settings_outlined, SidebarPanel.settings, 'الإعدادات'),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _item(IconData icon, SidebarPanel panel, String tooltip) {
    final isActive = active == panel;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => onChanged(panel),
        child: Container(
          width: 48,
          height: 44,
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: isActive ? IdeColors.accentBlue : Colors.transparent, width: 2)),
          ),
          child: Icon(icon, size: 20, color: isActive ? Colors.white : Colors.grey),
        ),
      ),
    );
  }
}
