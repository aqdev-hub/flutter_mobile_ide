import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../../core/constants/app_constants.dart';
import '../models/file_node.dart';

/// كل تفاعل مع dart:io (قراءة/كتابة/حذف/نسخ ملفات فعلية) يمرّ من هنا فقط.
///
/// عزل هذا في repository مستقل (بدل استدعاء dart:io مباشرة من الـ providers)
/// يعني أن أي منطق واجهة (شجرة الملفات، المحرر) لا يعرف كيف تُقرأ الملفات فعليًا،
/// وإذا احتجنا لاحقًا مصدرًا آخر (مثل مزامنة سحابية) نستبدل هذا الملف فقط.
class FileSystemRepository {
  /// يبني الشجرة كاملة بشكل متزامن أول مرة (مجلد المشروع عادة صغير/متوسط الحجم
  /// كما ذكر المستخدم، فالقراءة الكاملة مقبولة الأداء هنا).
  Future<FileNode> buildTree(String rootPath) async {
    final rootDir = Directory(rootPath);
    if (!await rootDir.exists()) {
      throw FileSystemException('المجلد غير موجود', rootPath);
    }
    final children = await _readChildren(rootDir);
    return FileNode(
      path: rootPath,
      name: p.basename(rootPath),
      type: FileNodeType.directory,
      children: children,
      isExpanded: true,
    );
  }

  Future<List<FileNode>> _readChildren(Directory dir) async {
    final entries = <FileSystemEntity>[];
    try {
      entries.addAll(await dir.list().toList());
    } on FileSystemException catch (e) {
      // مجلد بدون صلاحية قراءة مثلًا: لا نكسر الشجرة كاملة، نعيد قائمة فارغة له.
      // ignore: avoid_print
      print('تعذّرت قراءة ${dir.path}: ${e.message}');
      return [];
    }

    final nodes = <FileNode>[];
    for (final entity in entries) {
      final name = p.basename(entity.path);
      if (AppConstants.ignoredEntries.contains(name)) continue;
      if (name.startsWith('.') && name != '.gitignore') continue;

      if (entity is Directory) {
        final children = await _readChildren(entity);
        nodes.add(FileNode(
          path: entity.path,
          name: name,
          type: FileNodeType.directory,
          children: children,
        ));
      } else if (entity is File) {
        nodes.add(FileNode(
          path: entity.path,
          name: name,
          type: FileNodeType.file,
        ));
      }
    }

    // المجلدات أولًا ثم الملفات، وكل مجموعة أبجديًا — سلوك مألوف من VS Code.
    nodes.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return nodes;
  }

  Future<String> readFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('الملف غير موجود', path);
    }
    return file.readAsString();
  }

  Future<void> writeFile(String path, String content) async {
    final file = File(path);
    await file.writeAsString(content);
  }

  Future<String> createFile(String parentDirPath, String fileName) async {
    final newPath = p.join(parentDirPath, fileName);
    final file = File(newPath);
    if (await file.exists()) {
      throw FileSystemException('يوجد ملف بنفس الاسم مسبقًا', newPath);
    }
    await file.create(recursive: true);
    return newPath;
  }

  Future<String> createDirectory(String parentDirPath, String dirName) async {
    final newPath = p.join(parentDirPath, dirName);
    final dir = Directory(newPath);
    if (await dir.exists()) {
      throw FileSystemException('يوجد مجلد بنفس الاسم مسبقًا', newPath);
    }
    await dir.create(recursive: true);
    return newPath;
  }

  /// يعيد تسمية ملف/مجلد داخل نفس المجلد الأب ويُرجع المسار الجديد.
  ///
  /// **إصلاح**: كانت `File.rename` تكتب فوق أي ملف موجود بالاسم الجديد بصمت
  /// (سلوك POSIX الافتراضي)، فتضيع بيانات الملف القديم. الآن نرفض ذلك صراحةً،
  /// ونرفض أيضًا الأسماء الفارغة أو المحتوية على فواصل مسار.
  Future<String> rename(String oldPath, String newName) async {
    final name = newName.trim();
    if (name.isEmpty || name == '.' || name == '..' || name.contains('/') || name.contains('\\')) {
      throw FileSystemException('اسم غير صالح', oldPath);
    }
    final newPath = p.join(p.dirname(oldPath), name);
    if (p.equals(oldPath, newPath)) return oldPath;
    if (await _exists(newPath)) {
      throw FileSystemException('يوجد عنصر بنفس الاسم مسبقًا', newPath);
    }
    if (FileSystemEntity.typeSync(oldPath) == FileSystemEntityType.directory) {
      await Directory(oldPath).rename(newPath);
    } else {
      await File(oldPath).rename(newPath);
    }
    return newPath;
  }

  Future<void> delete(String path, {required bool isDirectory}) async {
    if (isDirectory) {
      await Directory(path).delete(recursive: true);
    } else {
      await File(path).delete();
    }
  }

  // ------------------------- نسخ / نقل -------------------------

  /// نسخ فعلي لملف أو مجلد إلى مجلد وجهة، ويُرجع المسار الجديد.
  ///
  /// **إصلاح**: لا يكتب فوق أي عنصر موجود أبدًا — إن وُجد الاسم نفسه في
  /// الوجهة (ومنه اللصق في نفس المجلد) يُنشأ اسم فريد ("name copy.ext"،
  /// "name copy 2.ext"...). ويرفض نسخ مجلد إلى داخل نفسه (كان ينسخ بلا نهاية).
  Future<String> copyEntry(String sourcePath, String destDirPath) async {
    await _assertValidTransfer(sourcePath, destDirPath);
    final destPath = await _uniqueDestPath(destDirPath, p.basename(sourcePath));
    await _copyInto(sourcePath, destPath);
    return destPath;
  }

  /// نقل ("قص ولصق") ملف أو مجلد إلى مجلد وجهة، ويُرجع المسار الجديد، أو
  /// `null` إن كانت الوجهة هي نفس المجلد الحالي (لا شيء للنقل).
  ///
  /// **إصلاح**: كان "القص" ينسخ ثم يحذف المصدر؛ وعند اللصق في نفس المجلد
  /// يكون المصدر هو الوجهة نفسها فيُحذف العنصر الوحيد نهائيًا. الآن نستخدم
  /// `rename` (ذرّية على نفس القرص)، وإن فشلت عبر أقراص مختلفة ننسخ أولًا ثم
  /// نحذف المصدر **فقط بعد نجاح النسخ كاملة**. ولا نكتب فوق عنصر موجود.
  Future<String?> moveEntry(String sourcePath, String destDirPath) async {
    final destPath = p.join(destDirPath, p.basename(sourcePath));
    if (p.equals(sourcePath, destPath)) return null;

    await _assertValidTransfer(sourcePath, destDirPath);
    if (await _exists(destPath)) {
      throw FileSystemException('يوجد عنصر بنفس الاسم في مجلد الوجهة', destPath);
    }

    final isDir = FileSystemEntity.typeSync(sourcePath) == FileSystemEntityType.directory;
    try {
      if (isDir) {
        await Directory(sourcePath).rename(destPath);
      } else {
        await File(sourcePath).rename(destPath);
      }
    } on FileSystemException {
      await _copyInto(sourcePath, destPath);
      await delete(sourcePath, isDirectory: isDir);
    }
    return destPath;
  }

  Future<void> _assertValidTransfer(String sourcePath, String destDirPath) async {
    final sourceType = FileSystemEntity.typeSync(sourcePath);
    if (sourceType == FileSystemEntityType.notFound) {
      throw FileSystemException('العنصر المصدر لم يعد موجودًا', sourcePath);
    }
    if (!await Directory(destDirPath).exists()) {
      throw FileSystemException('مجلد الوجهة غير موجود', destDirPath);
    }
    if (sourceType == FileSystemEntityType.directory &&
        (p.equals(sourcePath, destDirPath) || p.isWithin(sourcePath, destDirPath))) {
      throw FileSystemException(
        'لا يمكن نسخ/نقل مجلد إلى داخل نفسه أو داخل أحد مجلداته الفرعية',
        destDirPath,
      );
    }
  }

  Future<bool> _exists(String path) async {
    return await FileSystemEntity.type(path, followLinks: false) != FileSystemEntityType.notFound;
  }

  Future<String> _uniqueDestPath(String destDirPath, String name) async {
    var candidate = p.join(destDirPath, name);
    if (!await _exists(candidate)) return candidate;

    final ext = p.extension(name);
    final base = p.basenameWithoutExtension(name);
    var index = 1;
    while (true) {
      final suffix = index == 1 ? ' copy' : ' copy $index';
      candidate = p.join(destDirPath, '$base$suffix$ext');
      if (!await _exists(candidate)) return candidate;
      index++;
    }
  }

  Future<void> _copyInto(String sourcePath, String destPath) async {
    if (FileSystemEntity.typeSync(sourcePath) == FileSystemEntityType.directory) {
      await _copyDirectoryRecursive(Directory(sourcePath), Directory(destPath));
    } else {
      await File(sourcePath).copy(destPath);
    }
  }

  Future<void> _copyDirectoryRecursive(Directory source, Directory dest) async {
    await dest.create(recursive: true);
    // followLinks: false لتفادي الدوران اللانهائي عند وجود روابط رمزية دائرية؛
    // الروابط نفسها تُتخطّى (ليست File ولا Directory هنا).
    await for (final entity in source.list(followLinks: false)) {
      final name = p.basename(entity.path);
      final newPath = p.join(dest.path, name);
      if (entity is Directory) {
        await _copyDirectoryRecursive(entity, Directory(newPath));
      } else if (entity is File) {
        await entity.copy(newPath);
      }
    }
  }
}
