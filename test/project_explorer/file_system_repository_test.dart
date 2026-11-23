import 'dart:io';

import 'package:flutter_mobile_ide/features/project_explorer/data/repositories/file_system_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  late FileSystemRepository repo;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ide_repo_test_');
    repo = FileSystemRepository();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  File makeFile(String relative, String content) {
    final file = File(p.join(tmp.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  test('moveEntry داخل نفس المجلد لا يفعل شيئًا ولا يحذف الملف', () async {
    final file = makeFile('a.txt', 'hello');
    final result = await repo.moveEntry(file.path, tmp.path);
    expect(result, isNull);
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync(), 'hello');
  });

  test('copyEntry في نفس المجلد ينشئ اسمًا فريدًا ولا يكتب فوق الأصل', () async {
    final file = makeFile('a.txt', 'hello');
    final copyPath = await repo.copyEntry(file.path, tmp.path);
    expect(p.basename(copyPath), 'a copy.txt');
    expect(File(copyPath).readAsStringSync(), 'hello');
    expect(file.readAsStringSync(), 'hello');

    final second = await repo.copyEntry(file.path, tmp.path);
    expect(p.basename(second), 'a copy 2.txt');
  });

  test('moveEntry ينقل الملف فعلًا إلى مجلد آخر', () async {
    final file = makeFile('a.txt', 'hello');
    final dest = Directory(p.join(tmp.path, 'sub'))..createSync();
    final newPath = await repo.moveEntry(file.path, dest.path);
    expect(newPath, p.join(dest.path, 'a.txt'));
    expect(file.existsSync(), isFalse);
    expect(File(newPath!).readAsStringSync(), 'hello');
  });

  test('moveEntry يرفض الكتابة فوق عنصر موجود ويُبقي المصدر سليمًا', () async {
    final file = makeFile('a.txt', 'source');
    makeFile('sub/a.txt', 'existing');
    final dest = Directory(p.join(tmp.path, 'sub'));
    await expectLater(repo.moveEntry(file.path, dest.path), throwsA(isA<FileSystemException>()));
    expect(file.readAsStringSync(), 'source');
    expect(File(p.join(dest.path, 'a.txt')).readAsStringSync(), 'existing');
  });

  test('لا يمكن نسخ أو نقل مجلد إلى داخل نفسه', () async {
    final dir = Directory(p.join(tmp.path, 'd'))..createSync();
    final sub = Directory(p.join(dir.path, 'sub'))..createSync();
    await expectLater(repo.copyEntry(dir.path, sub.path), throwsA(isA<FileSystemException>()));
    await expectLater(repo.moveEntry(dir.path, sub.path), throwsA(isA<FileSystemException>()));
    expect(dir.existsSync(), isTrue);
  });

  test('نقل مجلد يحمل محتواه كاملًا', () async {
    makeFile('d/x.txt', 'x');
    makeFile('d/inner/y.txt', 'y');
    final dest = Directory(p.join(tmp.path, 'target'))..createSync();
    final newPath = await repo.moveEntry(p.join(tmp.path, 'd'), dest.path);
    expect(File(p.join(newPath!, 'x.txt')).readAsStringSync(), 'x');
    expect(File(p.join(newPath, 'inner', 'y.txt')).readAsStringSync(), 'y');
    expect(Directory(p.join(tmp.path, 'd')).existsSync(), isFalse);
  });

  test('rename يرفض الكتابة فوق ملف موجود وأسماء بها فواصل مسار', () async {
    final a = makeFile('a.txt', 'a');
    makeFile('b.txt', 'b');
    await expectLater(repo.rename(a.path, 'b.txt'), throwsA(isA<FileSystemException>()));
    await expectLater(repo.rename(a.path, '../evil.txt'), throwsA(isA<FileSystemException>()));
    await expectLater(repo.rename(a.path, '   '), throwsA(isA<FileSystemException>()));
    expect(a.readAsStringSync(), 'a');
    expect(File(p.join(tmp.path, 'b.txt')).readAsStringSync(), 'b');
  });

  test('rename ينجح باسم جديد ويُرجع المسار الجديد', () async {
    final a = makeFile('a.txt', 'a');
    final newPath = await repo.rename(a.path, 'c.txt');
    expect(newPath, p.join(tmp.path, 'c.txt'));
    expect(File(newPath).readAsStringSync(), 'a');
    expect(a.existsSync(), isFalse);
  });
}
