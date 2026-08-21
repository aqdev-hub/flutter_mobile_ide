import 'package:equatable/equatable.dart';

import '../data/models/file_node.dart';
import '../data/models/recent_project.dart';

enum ClipboardOperation { copy, cut }

class ClipboardEntry extends Equatable {
  final String path;
  final bool isDirectory;
  final ClipboardOperation operation;

  const ClipboardEntry({
    required this.path,
    required this.isDirectory,
    required this.operation,
  });

  @override
  List<Object?> get props => [path, isDirectory, operation];
}

class ProjectState extends Equatable {
  final FileNode? root;
  final bool isLoading;
  final String? errorMessage;
  final ClipboardEntry? clipboard;
  // جديد: قائمة "مشاريع حديثة" — مستقلة عن root (تبقى معبّأة حتى لو لم
  // يُفتح أي مشروع حاليًا، لتُعرض في شاشة/لوحة الاستكشاف الفارغة).
  final List<RecentProject> recentProjects;

  const ProjectState({
    this.root,
    this.isLoading = false,
    this.errorMessage,
    this.clipboard,
    this.recentProjects = const [],
  });

  bool get hasProject => root != null;

  ProjectState copyWith({
    FileNode? root,
    bool clearRoot = false,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
    ClipboardEntry? clipboard,
    bool clearClipboard = false,
    List<RecentProject>? recentProjects,
  }) {
    return ProjectState(
      root: clearRoot ? null : (root ?? this.root),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      clipboard: clearClipboard ? null : (clipboard ?? this.clipboard),
      recentProjects: recentProjects ?? this.recentProjects,
    );
  }

  @override
  List<Object?> get props => [root, isLoading, errorMessage, clipboard, recentProjects];
}
