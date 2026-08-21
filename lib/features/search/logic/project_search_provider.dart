import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../project_explorer/data/models/file_node.dart';
import '../../project_explorer/logic/project_provider.dart';
import '../../project_explorer/logic/project_state.dart';

class SearchMatch {
  final String path;
  final String fileName;
  final int lineNumber;
  final String lineText;

  const SearchMatch({
    required this.path,
    required this.fileName,
    required this.lineNumber,
    required this.lineText,
  });
}

/// مدخلة فهرس واحدة: محتوى ملف مُقسَّم مسبقًا إلى أسطر، جاهز للبحث فورًا
/// بدون أي قراءة قرص إضافية.
class _IndexEntry {
  final String path;
  final String fileName;
  final List<String> lines;
  const _IndexEntry({required this.path, required this.fileName, required this.lines});
}

class SearchState {
  final String query;
  final List<SearchMatch> results;
  final bool isSearching;
  // جديد: تُبنى الفهرسة بشكل غير متزامن؛ الواجهة يمكنها إظهار مؤشر بسيط
  // ("جارِ فهرسة المشروع...") بدل الظهور بنتائج بحث ناقصة بصمت.
  final bool isIndexing;

  const SearchState({
    this.query = '',
    this.results = const [],
    this.isSearching = false,
    this.isIndexing = false,
  });

  SearchState copyWith({String? query, List<SearchMatch>? results, bool? isSearching, bool? isIndexing}) {
    return SearchState(
      query: query ?? this.query,
      results: results ?? this.results,
      isSearching: isSearching ?? this.isSearching,
      isIndexing: isIndexing ?? this.isIndexing,
    );
  }
}

final projectSearchProvider =
    StateNotifierProvider<ProjectSearchNotifier, SearchState>((ref) {
  return ProjectSearchNotifier(ref);
});

/// بحث نصّي عبر فهرس في الذاكرة (path → أسطر) بدل قراءة كل ملفات المشروع
/// من القرص في كل عملية بحث.
///
/// **متى تُعاد الفهرسة الكاملة**: فقط عندما تتغيّر *مجموعة مسارات الملفات*
/// فعليًا (فتح مشروع جديد، إنشاء/حذف/إعادة تسمية/لصق) — نقارن "بصمة"
/// المسارات بين الشجرة القديمة والجديدة بدل مقارنة مرجع الكائن مباشرة،
/// لأن حتى طيّ/توسيع مجلد واحد في الشجرة (`toggleExpanded`) ينتج كائن شجرة
/// **جديد** أيضًا (نمط إعادة البناء غير القابل للتغيير المتّبع في
/// [ProjectNotifier])، ولا daعي لإعادة فهرسة كامل المشروع لمجرد ذلك.
///
/// **متى يُحدَّث ملف واحد فقط**: عند الحفظ من المحرر — عبر [indexFile]،
/// تُستدعى من [EditorTabsNotifier] بعد كل حفظ ناجح، دون لمس بقية الفهرس.
class ProjectSearchNotifier extends StateNotifier<SearchState> {
  final Ref _ref;
  final Map<String, _IndexEntry> _index = {};

  ProjectSearchNotifier(this._ref) : super(const SearchState()) {
    // فهرسة أولية إن كان هناك مشروع مفتوح أصلًا وقت إنشاء هذا الـ notifier
    // (مثلًا: المستخدم فتح تبويب البحث بعد فتح المشروع بوقت).
    unawaited(_rebuildIndex(_ref.read(projectProvider).root));

    _ref.listen<ProjectState>(projectProvider, (previous, next) {
      final prevRoot = previous?.root;
      final nextRoot = next.root;
      if (nextRoot == null) {
        if (prevRoot != null) _index.clear();
        return;
      }
      if (_samePathSet(prevRoot, nextRoot)) return; // لا تغيير فعلي في الملفات — تجاهل (مثل toggleExpanded)
      unawaited(_rebuildIndex(nextRoot));
    });
  }

  bool _samePathSet(FileNode? prevRoot, FileNode nextRoot) {
    if (prevRoot == null) return false;
    if (prevRoot.path != nextRoot.path) return false;
    final prevPaths = _collectFilePaths(prevRoot).toSet();
    final nextPaths = _collectFilePaths(nextRoot).toSet();
    return prevPaths.length == nextPaths.length && prevPaths.containsAll(nextPaths);
  }

  List<String> _collectFilePaths(FileNode node) {
    if (node.isFile) return [node.path];
    return [for (final child in node.children) ..._collectFilePaths(child)];
  }

  Future<void> _rebuildIndex(FileNode? root) async {
    _index.clear();
    if (root == null) return;

    state = state.copyWith(isIndexing: true);
    final repo = _ref.read(fileSystemRepositoryProvider);

    Future<void> visit(FileNode node) async {
      if (node.isDirectory) {
        for (final child in node.children) {
          await visit(child);
        }
        return;
      }
      // نقتصر على الامتدادات النصية المعروفة (نفس القائمة المستخدمة لفتح
      // الملفات في المحرر) — يتجنّب هذا محاولات قراءة ملفات ثنائية (صور...)
      // ستفشل أو تهدر وقتًا دون أي فائدة بحثية.
      if (!AppConstants.editableExtensions.contains(node.extension)) return;
      try {
        final content = await repo.readFile(node.path);
        _index[node.path] = _IndexEntry(path: node.path, fileName: node.name, lines: content.split('\n'));
      } catch (_) {
        // ملف تعذّرت قراءته (صلاحيات، أو ليس نصًا فعليًا رغم امتداده) — يُستبعد من الفهرس بصمت.
      }
    }

    await visit(root);
    state = state.copyWith(isIndexing: false);

    // إن كان هناك استعلام بحث نشط، أعد تشغيله على الفهرس الجديد فورًا حتى
    // لا تبقى النتائج معروضة من فهرس قديم بعد تغيّر الملفات.
    if (state.query.trim().isNotEmpty) {
      search(state.query);
    }
  }

  /// يُحدِّث محتوى ملف واحد في الفهرس فقط — يُستدعى بعد كل حفظ ناجح من
  /// المحرر، دون الحاجة لإعادة فهرسة كامل المشروع.
  void indexFile(String path, String fileName, String content) {
    if (!AppConstants.editableExtensions.contains(_extensionOf(fileName))) return;
    _index[path] = _IndexEntry(path: path, fileName: fileName, lines: content.split('\n'));
    if (state.query.trim().isNotEmpty) {
      search(state.query);
    }
  }

  String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    return dot <= 0 ? '' : fileName.substring(dot);
  }

  /// بحث فوري بالكامل من الذاكرة — لا قراءة قرص هنا إطلاقًا، لذا آمن
  /// استدعاؤه على كل ضغطة مفتاح (مع تأخير بسيط من طرف الواجهة نفسها).
  void search(String query) {
    state = state.copyWith(query: query, isSearching: true);
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      state = state.copyWith(results: [], isSearching: false);
      return;
    }

    final lowerQuery = trimmed.toLowerCase();
    final matches = <SearchMatch>[];
    for (final entry in _index.values) {
      final lines = entry.lines;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].toLowerCase().contains(lowerQuery)) {
          matches.add(SearchMatch(
            path: entry.path,
            fileName: entry.fileName,
            lineNumber: i + 1,
            lineText: lines[i].trim(),
          ));
        }
      }
    }
    state = state.copyWith(results: matches, isSearching: false);
  }
}
