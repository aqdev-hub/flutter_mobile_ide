import 'dart:io';

import 'package:git_on_dart/git_on_dart.dart';

/// يعزل كل التعامل مع حزمة git_on_dart الخارجية في مكان واحد — بنفس مبدأ
/// [FileSystemRepository] لِـ dart:io: أي تغيير مستقبلي في المكتبة (أو
/// استبدالها بأخرى) يبقى معزولًا هنا فقط، بدون لمس بقية طبقة الحالة/الواجهة.
///
/// ⚠️ **تنبيه أمانة تقنية**: بعض التوقيعات هنا **مؤكَّدة فعليًا** عبر
/// الإكمال التلقائي في VS Code على جهازكم (`StatusOperation.status()`,
/// `AddOperation.add()`/`.addAll()`)، وبعضها الآخر **لا يزال تخمينًا غير
/// مؤكَّد** بانتظار نفس التحقق: حقول `RepositoryStatus` (`.staged`/
/// `.modified`)، وتوقيع `CommitOperation.commit()` بالكامل، وحقول الكائن
/// الذي يُعيده (افترضتُ `.hash` هنا). كل ما هو غير مؤكَّد مُعلَّم بوضوح
/// أسفله بتعليق مستقل.
class GitStatusSnapshot {
  final List<String> staged;
  final List<String> modified;
  const GitStatusSnapshot({required this.staged, required this.modified});
}

class GitOperationException implements Exception {
  final String message;
  GitOperationException(this.message);
  @override
  String toString() => message;
}

class GitService {
  GitRepository? _repo;
  String? _openedPath;

  bool get isOpen => _repo != null;

  /// يتحقق أولًا هل مجلد `.git` موجود فعليًا (بدل الاعتماد فقط على استثناء
  /// المكتبة عند open) — تشخيص أوضح لحالة "لا يوجد مستودع بعد" في الواجهة.
  Future<bool> hasGitDir(String projectPath) {
    return Directory('$projectPath/.git').exists();
  }

  Future<void> open(String projectPath) async {
    if (_repo != null && _openedPath == projectPath) return; // مفتوح أصلًا لنفس المشروع
    try {
      _repo = await GitRepository.open(projectPath);
      _openedPath = projectPath;
    } catch (e) {
      _repo = null;
      _openedPath = null;
      throw GitOperationException('تعذّر فتح مستودع Git: $e');
    }
  }

  Future<void> init(String projectPath) async {
    try {
      _repo = await GitRepository.init(projectPath);
      _openedPath = projectPath;
    } catch (e) {
      throw GitOperationException('تعذّر تهيئة مستودع Git جديد: $e');
    }
  }

  Future<GitStatusSnapshot> getStatus() async {
    final repo = _repo;
    if (repo == null) throw GitOperationException('لا يوجد مستودع Git مفتوح.');
    try {
      final status = await StatusOperation(repo).status();
      // 'staged' كانت صحيحة (لم تظهر في رسالة الخطأ) — 'modified' فقط كانت
      // خاطئة. المصطلح المقابل القياسي في Git هو "staged" مقابل "unstaged"
      // (وليس "modified")، فجرّبنا unstaged كأفضل تخمين منطقي. إن ظهر خطأ
      // "unstaged غير معرَّف"، بدّلوا فقط الكلمة `unstaged` في السطرين
      // التاليين بالاسم الذي يقترحه VS Code تلقائيًا عند كتابة `status.`.
      return GitStatusSnapshot(
        staged: [for (final entry in status.staged) entry.toString()],
        modified: [for (final entry in status.unstaged) entry.toString()],
      );
    } catch (e) {
      throw GitOperationException('تعذّرت قراءة حالة Git: $e');
    }
  }

  Future<void> stageFiles(List<String> relativePaths) async {
    final repo = _repo;
    if (repo == null) throw GitOperationException('لا يوجد مستودع Git مفتوح.');
    if (relativePaths.isEmpty) return;
    try {
      await AddOperation(repo).add(relativePaths);
    } catch (e) {
      throw GitOperationException('تعذّرت إضافة الملفات: $e');
    }
  }

  /// يستخدم AddOperation.addAll() المُدمَجة في المكتبة نفسها (أسرع وأدق من
  /// تمرير كل المسارات المُعدَّلة يدويًا لِـ [stageFiles]).
  Future<void> stageAllChanges() async {
    final repo = _repo;
    if (repo == null) throw GitOperationException('لا يوجد مستودع Git مفتوح.');
    try {
      await AddOperation(repo).addAll();
    } catch (e) {
      throw GitOperationException('تعذّرت إضافة كل الملفات: $e');
    }
  }

  Future<String> commit({
    required String message,
    required String authorName,
    required String authorEmail,
  }) async {
    final repo = _repo;
    if (repo == null) throw GitOperationException('لا يوجد مستودع Git مفتوح.');
    try {
      // ⚠️ لم يصلني بعد تأكيد فعلي (لقطة شاشة) لتوقيع commit() الحقيقي —
      // هذا تخمين مبني على نمط بقية الحزمة (message موضعي + author مسمّى)،
      // غير مُتحقَّق منه. إن فشل، أرسل لقطة `CommitOperation(repo).` مثل
      // اللقطتين السابقتين. نفس الأمر لـ `commit.hash` أدناه — اسم الحقل
      // الفعلي على الكائن المُعاد غير مؤكَّد.
      final commit = await CommitOperation(repo).commit(
        message,
        author: GitAuthor(name: authorName, email: authorEmail, timestamp: DateTime.now()),
      );
      return commit.hash;
    } on GitOperationException {
      rethrow;
    } catch (e) {
      throw GitOperationException('تعذّر تنفيذ commit: $e');
    }
  }
}
