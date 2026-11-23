import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../console/view/console_panel.dart';
import '../../preview/logic/problems_provider.dart';
import '../../preview/view/problems_panel.dart';

enum _BottomTab { problems, console }

class BottomPanel extends ConsumerStatefulWidget {
  const BottomPanel({super.key});

  @override
  ConsumerState<BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends ConsumerState<BottomPanel> {
  bool _expanded = false;
  _BottomTab _activeTab = _BottomTab.problems;

  void _selectTab(_BottomTab tab) {
    setState(() {
      if (_activeTab == tab && _expanded) {
        _expanded = false;
      } else {
        _activeTab = tab;
        _expanded = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final problemsCount = ref.watch(
      problemsProvider.select((m) => m.values.fold<int>(0, (sum, list) => sum + list.length)),
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: _expanded ? 220 : 32,
      decoration: const BoxDecoration(
        color: IdeColors.darkBg,
        border: Border(top: BorderSide(color: IdeColors.darkBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 32,
            child: Row(
              children: [
                _TabButton(
                  icon: problemsCount > 0 ? Icons.error_outline : Icons.check_circle_outline,
                  iconColor: problemsCount > 0 ? IdeColors.stopRed : Colors.grey,
                  label: problemsCount > 0 ? 'Problems ($problemsCount)' : 'Problems',
                  isActive: _expanded && _activeTab == _BottomTab.problems,
                  onTap: () => _selectTab(_BottomTab.problems),
                ),
                _TabButton(
                  icon: Icons.terminal,
                  iconColor: Colors.grey,
                  label: 'Output',
                  isActive: _expanded && _activeTab == _BottomTab.console,
                  onTap: () => _selectTab(_BottomTab.console),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(_expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up, size: 18),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
              ],
            ),
          ),
          if (_expanded)
            Expanded(
              child: _activeTab == _BottomTab.problems ? const ProblemsPanel() : const ConsolePanel(),
            ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _TabButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: isActive ? IdeColors.accentBlue : Colors.transparent, width: 2),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: iconColor),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
