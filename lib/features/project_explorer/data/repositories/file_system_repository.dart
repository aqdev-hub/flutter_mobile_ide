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

  Future<String> rename(String oldPath, String newName) async {
    final parent = p.dirname(oldPath);
    final newPath = p.join(parent, newName);
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

  /// نسخ فعلي لملف أو مجلد إلى وجهة جديدة (يُستخدم لعمليتي "نسخ" و"قص").
  Future<String> copyEntry(String sourcePath, String destDirPath) async {
    final name = p.basename(sourcePath);
    final destPath = p.join(destDirPath, name);
    final type = FileSystemEntity.typeSync(sourcePath);

    if (type == FileSystemEntityType.directory) {
      await _copyDirectoryRecursive(Directory(sourcePath), Directory(destPath));
    } else {
      await File(sourcePath).copy(destPath);
    }
    return destPath;
  }

  Future<void> _copyDirectoryRecursive(Directory source, Directory dest) async {
    await dest.create(recursive: true);
    await for (final entity in source.list()) {
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
