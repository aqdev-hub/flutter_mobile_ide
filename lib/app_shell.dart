import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'features/editor/logic/editor_tabs_provider.dart';
import 'features/editor/view/widgets/code_editor_widget.dart';
import 'features/editor/view/widgets/find_replace_panel.dart';
import 'features/editor/view/widgets/tab_bar_view.dart';
import 'features/git/view/git_panel.dart';
import 'features/preview/view/preview_panel.dart';
import 'features/project_explorer/logic/project_provider.dart';
import 'features/project_explorer/logic/project_state.dart';
import 'features/project_explorer/view/widgets/file_tree_view.dart';
import 'features/search/view/search_panel.dart';
import 'features/settings/view/settings_panel.dart';
import 'features/shell/view/activity_bar.dart';
import 'features/shell/view/bottom_panel.dart';
import 'features/shell/view/top_bar.dart';

/// نقطة تجميع الواجهة الرئيسية لبيئة العمل بعد شاشة الترحيب.
/// لا تحوي منطقًا خاصًا بها؛ فقط تُرتّب الأجزاء الجاهزة من كل feature —
/// حسب مبدأ فصل التنسيق (composition) عن المنطق.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _sidebarVisible = true;
  SidebarPanel _sidebarPanel = SidebarPanel.explorer;
  MainSegment _mainSegment = MainSegment.editor;
  bool _findOpen = false;

  @override
  Widget build(BuildContext context) {
    final tabsState = ref.watch(editorTabsProvider);
    final activeTab = tabsState.activeTab;

    // نعرض أي خطأ في المشروع (فتح مجلد، إنشاء/حذف/إعادة تسمية) كـ SnackBar
    // فوري، بدل ترك المستخدم يظن أن شيئًا لم يحدث لمجرد أن لوحة الكونسول
    // السفلية مطوية افتراضيًا.
    ref.listen<ProjectState>(projectProvider, (previous, next) {
      if (next.errorMessage != null && next.errorMessage != previous?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: IdeColors.stopRed,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            TopBar(
              sidebarVisible: _sidebarVisible,
              onToggleSidebar: () => setState(() => _sidebarVisible = !_sidebarVisible),
              segment: _mainSegment,
              onSegmentChanged: (segment) => setState(() => _mainSegment = segment),
              onToggleFind: () => setState(() => _findOpen = !_findOpen),
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ActivityBar(
                    active: _sidebarPanel,
                    onChanged: (panel) {
                      setState(() {
                        if (_sidebarPanel == panel && _sidebarVisible) {
                          _sidebarVisible = false;
                        } else {
                          _sidebarPanel = panel;
                          _sidebarVisible = true;
                        }
                      });
                    },
                  ),
                  if (_sidebarVisible)
                    Container(
                      width: AppConstants.sidebarWidth,
                      decoration: const BoxDecoration(
                        color: IdeColors.darkSidebar,
                        border: Border(right: BorderSide(color: IdeColors.darkBorder)),
                      ),
                      child: switch (_sidebarPanel) {
                        SidebarPanel.explorer => const FileTreeView(),
                        SidebarPanel.search => const SearchPanel(),
                        SidebarPanel.git => const GitPanel(),
                        SidebarPanel.settings => const SettingsPanel(),
                      },
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_mainSegment == MainSegment.editor) ...[
                          const EditorTabBar(),
                          if (_findOpen && activeTab != null)
                            FindReplacePanel(
                              controller: activeTab.controller,
                              onClose: () => setState(() => _findOpen = false),
                            ),
                          Expanded(
                            child: activeTab == null
                                ? const _NoFileOpen()
                                : CodeEditorWidget(key: ValueKey(activeTab.path), tab: activeTab),
                          ),
                        ] else
                          const Expanded(child: PreviewPanel()),
                        const BottomPanel(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoFileOpen extends StatelessWidget {
  const _NoFileOpen();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.description_outlined, size: 40, color: Colors.grey),
          SizedBox(height: 12),
          Text('افتح ملفًا من شجرة المشروع للبدء بالتحرير', style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }
}
