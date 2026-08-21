import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../console/logic/console_provider.dart';
import '../../project_explorer/data/models/file_node.dart';
import '../../project_explorer/logic/project_provider.dart';
import 'dart_subset_ast.dart';
import 'preview_engine.dart';
import 'widget_interpreter.dart';

enum PreviewStatus { idle, running, error }

class PreviewState {
  final PreviewStatus status;
  final Interpreter? interpreter;
  final Expr? rootExpr;
  final String? errorMessage;
  final int rebuildTick; // يتغيّر عند كل rebuild لإجبار الواجهة على إعادة الرسم

  const PreviewState({
    this.status = PreviewStatus.idle,
    this.interpreter,
    this.rootExpr,
    this.errorMessage,
    this.rebuildTick = 0,
  });

  PreviewState copyWith({
    PreviewStatus? status,
    Interpreter? interpreter,
    Expr? rootExpr,
    String? errorMessage,
    bool clearError = false,
    int? rebuildTick,
  }) {
    return PreviewState(
      status: status ?? this.status,
      interpreter: interpreter ?? this.interpreter,
      rootExpr: rootExpr ?? this.rootExpr,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      rebuildTick: rebuildTick ?? this.rebuildTick,
    );
  }
}

final previewProvider = StateNotifierProvider<PreviewNotifier, PreviewState>((ref) {
  return PreviewNotifier(ref);
});

/// **رجوع متعمَّد عن محرّك dart_eval** — راجع التعليق التوضيحي في
/// preview_engine.dart لتفاصيل السبب (خلل جوهري موثَّق في flutter_eval يمنع
/// تنفيذ أي صنف مستخدم يرث من StatelessWidget/StatefulWidget). هذا هو
/// المحرّك اليدوي المستقر السابق: يُدير دورة حياة "التشغيل"، ويُعيد استخدام
/// نفس [Interpreter] لكل عمليات rebuild اللاحقة (setState) حتى تبقى حالة
/// الشاشات محفوظة أثناء الجلسة.
class PreviewNotifier extends StateNotifier<PreviewState> {
  final Ref _ref;
  PreviewNotifier(this._ref) : super(const PreviewState());

  Future<void> run() async {
    final project = _ref.read(projectProvider);
    final root = project.root;
    if (root == null) {
      state = state.copyWith(status: PreviewStatus.error, errorMessage: 'لا يوجد مشروع مفتوح.');
      return;
    }

    _ref.read(consoleProvider.notifier).log('▶ جارِ تشغيل المشروع...');

    final repo = _ref.read(fileSystemRepositoryProvider);
    final dartFiles = <String, String>{};
    String? mainPath;

    Future<void> visit(FileNode node) async {
      if (node.isDirectory) {
        for (final child in node.children) {
          await visit(child);
        }
        return;
      }
      if (node.extension == '.dart') {
        try {
          dartFiles[node.path] = await repo.readFile(node.path);
          if (node.name == 'main.dart') mainPath = node.path;
        } catch (e) {
          _ref.read(consoleProvider.notifier).log('تعذّرت قراءة ${node.name}: $e', isError: true);
        }
      }
    }

    await visit(root);

    if (mainPath == null) {
      state = state.copyWith(
        status: PreviewStatus.error,
        errorMessage: 'لم يتم العثور على ملف main.dart داخل المشروع.',
      );
      _ref.read(consoleProvider.notifier).log('فشل التشغيل: main.dart غير موجود', isError: true);
      return;
    }

    final result = PreviewEngine().build(dartFilesByPath: dartFiles, mainFilePath: mainPath!);
    if (result.hasError || result.rootExpr == null) {
      state = state.copyWith(status: PreviewStatus.error, errorMessage: result.errorMessage);
      _ref.read(consoleProvider.notifier).log('فشل التشغيل: ${result.errorMessage}', isError: true);
      return;
    }

    final interpreter = Interpreter(
      classRegistry: result.classRegistry,
      log: (msg, {isError = false}) => _ref.read(consoleProvider.notifier).log(msg, isError: isError),
      onStateChanged: requestRebuild,
    );

    state = PreviewState(
      status: PreviewStatus.running,
      interpreter: interpreter,
      rootExpr: result.rootExpr,
    );
    _ref.read(consoleProvider.notifier).log('✅ تم التشغيل بنجاح — ${result.classRegistry.length} صنف مكتشَف.');
  }

  /// يُستدعى من داخل المُفسِّر عند setState — يزيد عدّاد rebuild لإجبار
  /// الواجهة (PreviewPanel) على إعادة تنفيذ build وإظهار الحالة الجديدة.
  void requestRebuild() {
    state = state.copyWith(rebuildTick: state.rebuildTick + 1);
  }

  void stop() {
    state = const PreviewState(status: PreviewStatus.idle);
    _ref.read(consoleProvider.notifier).log('⏹ تم إيقاف المعاينة.');
  }

  Future<void> restart() async {
    stop();
    await run();
  }
}
