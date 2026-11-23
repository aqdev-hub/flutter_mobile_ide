import '../data/models/editor_tab.dart';

class EditorTabsState {
  final List<EditorTab> tabs;
  final String? activePath;

  const EditorTabsState({this.tabs = const [], this.activePath});

  EditorTab? get activeTab {
    if (activePath == null) return null;
    for (final tab in tabs) {
      if (tab.path == activePath) return tab;
    }
    return null;
  }

  EditorTabsState copyWith({List<EditorTab>? tabs, String? activePath, bool clearActive = false}) {
    return EditorTabsState(
      tabs: tabs ?? this.tabs,
      activePath: clearActive ? null : (activePath ?? this.activePath),
    );
  }
}
