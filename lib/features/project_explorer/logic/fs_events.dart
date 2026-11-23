import 'package:flutter_riverpod/flutter_riverpod.dart';

enum FsChangeType { renamed, deleted }

/// حدث تغيير فعلي في نظام الملفات (إعادة تسمية/نقل/حذف) تُصدره
/// [ProjectNotifier] ليستمع له من يحتاج مواكبته (مثل تبويبات المحرر) دون أن
/// يعرف أحدهما الآخر مباشرةً — نفس مبدأ الفصل بين الـ providers المتّبع.
///
/// النقل ("قص ولصق") يُصدَر كحدث [FsChangeType.renamed] من المسار القديم إلى
/// الجديد، لأنه من ناحية التبويبات المفتوحة نفس الأثر تمامًا.
class FsChange {
  final FsChangeType type;
  final String oldPath;
  final String? newPath;

  const FsChange._(this.type, this.oldPath, this.newPath);

  factory FsChange.renamed(String oldPath, String newPath) => FsChange._(FsChangeType.renamed, oldPath, newPath);

  factory FsChange.deleted(String path) => FsChange._(FsChangeType.deleted, path, null);
}

/// آخر حدث تغيير. كل حدث كائن جديد، فيصل كل مستمع حتى لو تكررت المسارات.
final fsChangeProvider = StateProvider<FsChange?>((ref) => null);
