import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../console/logic/console_provider.dart';
import '../../project_explorer/logic/project_provider.dart';
import '../../project_explorer/logic/project_state.dart';
import 'git_service.dart';

enum GitPanelStatus { noProject, notARepo, loading, ready, error }

class GitState {
  final GitPanelStatus status;
  final List<String> stagedFiles;
  final List<String> modifiedFiles;
  final String? errorMessage;
  final String? lastCommitHash;

  const GitState({
    this.status = GitPanelStatus.noProject,
    this.stagedFiles = const [],
    this.modifiedFiles = const [],
    this.errorMessage,
    this.lastCommitHash,
  });

  GitState copyWith({
    GitPanelStatus? status,
    List<String>? stagedFiles,
    List<String>? modifiedFiles,
    String? errorMessage,
    bool clearError = false,
    String? lastCommitHash,
  }) {
    return GitState(
      status: status ?? this.status,
      stagedFiles: stagedFiles ?? this.stagedFiles,
      modifiedFiles: modifiedFiles ?? this.modifiedFiles,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      lastCommitHash: lastCommitHash ?? this.lastCommitHash,
    );
  }
}

final gitProvider = StateNotifierProvider<GitNotifier, GitState>((ref) {
  return GitNotifier(ref);
});

/// يدير حالة تبويب Git: يتحقق تلقائيًا من وجود `.git` عند فتح/تغيير
/// المشروع، ويعرض status/stage/commit عبر [GitService] (النطاق المحلي
/// فقط في هذا الإصدار — لا push/pull بعد، راجع التوثيق في GitService حول
/// حدود مكتبة git_on_dart الحالية).
class GitNotifier extends StateNotifier<GitState> {
  final Ref _ref;
  final GitService _service = GitService();

  GitNotifier(this._ref) : super(const GitState()) {
    _checkRepo(_ref.read(projectProvider).root?.path);
    _ref.listen<ProjectState>(projectProvider, (previous, next) {
      if (previous?.root?.path != next.root?.path) {
        _checkRepo(next.root?.path);
      }
    });
  }

  void _log(String message, {bool isError = false}) {
    _ref.read(consoleProvider.notifier).log(message, isError: isError);
  }

  Future<void> _checkRepo(String? projectPath) async {
    if (projectPath == null) {
      state = const GitState(status: GitPanelStatus.noProject);
      return;
    }
    state = state.copyWith(status: GitPanelStatus.loading, clearError: true);
    final exists = await _service.hasGitDir(projectPath);
    if (!exists) {
      state = state.copyWith(status: GitPanelStatus.notARepo, stagedFiles: [], modifiedFiles: []);
      return;
    }
    await refreshStatus();
  }

  Future<void> initRepository() async {
    final projectPath = _ref.read(projectProvider).root?.path;
    if (projectPath == null) return;
    state = state.copyWith(status: GitPanelStatus.loading, clearError: true);
    try {
      await _service.init(projectPath);
      _log('تم تهيئة مستودع Git جديد في المشروع.');
      await refreshStatus();
    } catch (e) {
      state = state.copyWith(status: GitPanelStatus.error, errorMessage: e.toString());
      _log('تعذّر تهيئة مستودع Git: $e', isError: true);
    }
  }

  Future<void> refreshStatus() async {
    final projectPath = _ref.read(projectProvider).root?.path;
    if (projectPath == null) {
      state = const GitState(status: GitPanelStatus.noProject);
      return;
    }
    state = state.copyWith(status: GitPanelStatus.loading, clearError: true);
    try {
      await _service.open(projectPath);
      final snapshot = await _service.getStatus();
      state = GitState(
        status: GitPanelStatus.ready,
        stagedFiles: snapshot.staged,
        modifiedFiles: snapshot.modified,
      );
    } catch (e) {
      state = state.copyWith(status: GitPanelStatus.error, errorMessage: e.toString());
      _log('تعذّر تحديث حالة Git: $e', isError: true);
    }
  }

  Future<void> stageFile(String relativePath) async {
    try {
      await _service.stageFiles([relativePath]);
      await refreshStatus();
    } catch (e) {
      _log('تعذّر إضافة $relativePath: $e', isError: true);
    }
  }

  Future<void> stageAll() async {
    if (state.modifiedFiles.isEmpty) return;
    try {
      await _service.stageFiles(state.modifiedFiles);
      await refreshStatus();
    } catch (e) {
      _log('تعذّرت إضافة كل الملفات: $e', isError: true);
    }
  }

  Future<bool> commit(String message, {required String authorName, required String authorEmail}) async {
    if (message.trim().isEmpty) {
      _log('لا يمكن الالتزام برسالة فارغة', isError: true);
      return false;
    }
    if (authorName.trim().isEmpty || authorEmail.trim().isEmpty) {
      _log('عرّف اسمك وبريدك الإلكتروني في الإعدادات أولًا لاستخدام Git', isError: true);
      return false;
    }
    try {
      final hash = await _service.commit(
        message: message.trim(),
        authorName: authorName.trim(),
        authorEmail: authorEmail.trim(),
      );
      state = state.copyWith(lastCommitHash: hash);
      _log('تم الالتزام (commit): $hash');
      await refreshStatus();
      return true;
    } catch (e) {
      _log('تعذّر تنفيذ commit: $e', isError: true);
      return false;
    }
  }
}
