import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../console/logic/console_provider.dart';
import '../data/models/file_node.dart';
import '../data/models/recent_project.dart';
import '../data/repositories/file_system_repository.dart';
import 'project_state.dart';

final fileSystemRepositoryProvider = Provider((ref) => FileSystemRepository());

final projectProvider =
    StateNotifierProvider<ProjectNotifier, ProjectState>((ref) {
  return ProjectNotifier(ref, ref.read(fileSystemRepositoryProvider));
});

/// Notifier وحيد لكل ما يخص شجرة المشروع.
///
/// جمعنا فتح المشروع + CRUD + الحافظة + المشاريع الحديثة + إنشاء مشروع جديد
/// في notifier واحد (بدل تفتيتها) لأنها كلها تُعدّل نفس مصدر الحقيقة
/// (الشجرة الجذرية + قائمة المشاريع المرتبطة بها) وتتغيّر معًا؛ حسب قاعدة
/// "نجمّع ما يتغيّر معًا" في المعمارية المعتمدة.
class ProjectNotifier extends StateNotifier<ProjectState> {
  final Ref _ref;
  final FileSystemRepository _repo;

  static const _recentProjectsKey = 'project.recent_list';
  static const _maxRecentProjects = 10;

  ProjectNotifier(this._ref, this._repo) : super(const ProjectState()) {
    // نبدأ تحميل قائمة المشاريع الحديثة، ثم نحاول استعادة آخر مشروع فورًا
    // بدون أي تفاعل من المستخدم — إن فشلت الاستعادة (صلاحية غير ممنوحة،
    // أو المجلد لم يعد موجودًا) يبقى المستخدم ببساطة في حالة "لا مشروع
    // مفتوح" المعتادة، فيختار يدويًا من القائمة أو يفتح/ينشئ مشروعًا.
    _initRecentProjectsAndRestore();
  }

  void _log(String message, {bool isError = false}) {
    _ref.read(consoleProvider.notifier).log(message, isError: isError);
  }

  // ------------------------- المشاريع الحديثة -------------------------

  Future<void> _initRecentProjectsAndRestore() async {
    await _loadRecentProjects();
    await restoreLastProjectIfAvailable();
  }

  Future<void> _loadRecentProjects() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_recentProjectsKey) ?? [];
      final list = <RecentProject>[];
      for (final entry in raw) {
        try {
          list.add(RecentProject.decode(entry));
        } catch (_) {
          // عنصر تالف في التخزين المحلي (تنسيق قديم مثلًا) — نتجاهله بدل
          // إفشال تحميل بقية القائمة.
        }
      }
      state = state.copyWith(recentProjects: list);
    } catch (e) {
      _log('تعذّر تحميل قائمة المشاريع الحديثة: $e', isError: true);
    }
  }

  Future<void> _saveRecentProjects() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _recentProjectsKey,
      state.recentProjects.map((e) => e.encode()).toList(),
    );
  }

  Future<void> _addToRecent(String path, String name) async {
    final updated = [
      RecentProject(path: path, name: name, lastOpenedAt: DateTime.now()),
      ...state.recentProjects.where((p) => p.path != path),
    ];
    final capped = updated.length > _maxRecentProjects ? updated.sublist(0, _maxRecentProjects) : updated;
    state = state.copyWith(recentProjects: capped);
    await _saveRecentProjects();
  }

  Future<void> removeFromRecent(String path) async {
    state = state.copyWith(recentProjects: state.recentProjects.where((p) => p.path != path).toList());
    await _saveRecentProjects();
  }

  /// يُستدعى تلقائيًا عند إنشاء الـ notifier (أي عند أول بناء لواجهة تعتمد
  /// على [projectProvider], عادة AppShell). لا يطلب أي صلاحية جديدة من
  /// المستخدم هنا عمدًا — فقط يتحقق إن كانت الصلاحية *ممنوحة أصلًا* من فتح
  /// سابق، حتى لا نُفاجئ المستخدم بمربع صلاحيات فور فتح التطبيق.
  Future<void> restoreLastProjectIfAvailable() async {
    if (state.recentProjects.isEmpty) return;
    if (Platform.isAndroid) {
      final status = await Permission.manageExternalStorage.status;
      if (!status.isGranted) return;
    }

    final last = state.recentProjects.first;
    final dir = Directory(last.path);
    if (!await dir.exists()) {
      _log('تعذّرت استعادة آخر مشروع: المجلد لم يعد موجودًا (${last.path})', isError: true);
      await removeFromRecent(last.path);
      return;
    }

    await openProjectAtPath(last.path);
  }

  // ------------------------- فتح مشروع -------------------------

  /// يفتح منتقي المجلدات الأصلي للجهاز، ثم يبني الشجرة.
  ///
  /// على أندرويد 11+ (Scoped Storage) لا يمكن قراءة/كتابة ملفات خارج مجلد
  /// التطبيق الخاص إلا بعد منح صلاحية "الوصول لكل الملفات" صراحةً — نطلبها
  /// هنا أولًا؛ بدونها تنجح عملية اختيار المجلد بصريًا لكن كل قراءة/كتابة
  /// لاحقة تفشل بصمت، وهو بالضبط سبب ظهور "مجلدات فارغة" بدون هذا الطلب.
  Future<void> openProjectFromDevice() async {
    final granted = await ensureStoragePermission();
    if (!granted) return;

    final selectedPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'اختر مجلد مشروع Flutter',
    );
    if (selectedPath == null) return; // المستخدم ألغى الاختيار
    await openProjectAtPath(selectedPath);
  }

  /// يطلب صلاحية [Permission.manageExternalStorage] (الوصول لكل الملفات).
  /// إن رُفضت نهائيًا (denied forever) نوجّه المستخدم لإعدادات التطبيق مباشرة
  /// بدل تكرار طلب لا يظهر له أثر على الشاشة.
  ///
  /// عامّة (وليست خاصة) لأنها تُستخدم أيضًا من تدفّق "إنشاء مشروع جديد" قبل
  /// اختيار مكان الحفظ — نفس شرط الوصول ينطبق على الحالتين.
  Future<bool> ensureStoragePermission() async {
    if (!Platform.isAndroid) return true;

    var status = await Permission.manageExternalStorage.status;
    if (status.isGranted) return true;

    status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;

    if (status.isPermanentlyDenied) {
      _log('الصلاحية مرفوضة بشكل دائم — سيتم فتح إعدادات التطبيق', isError: true);
      await openAppSettings();
    } else {
      state = state.copyWith(
        errorMessage: 'يحتاج التطبيق صلاحية "الوصول لكل الملفات" لهذه العملية. فعّلها ثم أعد المحاولة.',
      );
      _log('تم رفض صلاحية الوصول للملفات', isError: true);
    }
    return false;
  }

  Future<void> openProjectAtPath(String path) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final root = await _repo.buildTree(path);
      state = state.copyWith(root: root, isLoading: false, clearError: true);
      _log('تم فتح المشروع: $path');
      await _addToRecent(path, root.name);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      _log('فشل فتح المشروع: $e', isError: true);
    }
  }

  Future<void> refreshProject() async {
    if (state.root == null) return;
    await openProjectAtPath(state.root!.path);
  }

  /// يُغلق عرض المشروع الحالي (بدون حذف أي ملف فعلي وبدون إزالته من قائمة
  /// المشاريع الحديثة) — فقط يعيد شجرة الملفات لحالة "لا مشروع مفتوح" حتى
  /// يظهر للمستخدم قائمة المشاريع الحديثة ليختار منها أو يفتح/ينشئ غيره.
  void closeCurrentProjectView() {
    state = state.copyWith(clearRoot: true, clearError: true);
  }

  // ------------------------- إنشاء مشروع جديد -------------------------

  /// ينشئ بنية مشروع Flutter دنيا وصالحة (شبيهة بمخرجات `flutter create`
  /// المُبسَّطة): `lib/main.dart` بمحتوى قابل للمعاينة فورًا ضمن حدود
  /// المُفسِّر الحالي (راجع README قسم 4)، و`pubspec.yaml` أساسي — ثم يفتحه
  /// مباشرة.
  Future<void> createNewProject({required String parentPath, required String projectName}) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final projectPath = p.join(parentPath, projectName);
      final projectDir = Directory(projectPath);
      if (await projectDir.exists()) {
        throw FileSystemException('يوجد مجلد بهذا الاسم مسبقًا في هذا الموقع', projectPath);
      }

      final libDir = Directory(p.join(projectPath, 'lib'));
      await libDir.create(recursive: true);

      final mainFile = File(p.join(libDir.path, 'main.dart'));
      await mainFile.writeAsString(_newProjectMainDartTemplate);

      final pubspecFile = File(p.join(projectPath, 'pubspec.yaml'));
      await pubspecFile.writeAsString(_newProjectPubspecTemplate(projectName));

      _log('تم إنشاء المشروع الجديد: $projectName');
      await openProjectAtPath(projectPath);
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      _log('تعذّر إنشاء المشروع: $e', isError: true);
    }
  }

  // ------------------------- شجرة الملفات (CRUD) -------------------------
  // بلا تغيير عن النسخة السابقة.

  FileNode _mapTree(FileNode node, String targetPath, FileNode Function(FileNode) transform) {
    if (node.path == targetPath) return transform(node);
    if (!node.isDirectory) return node;
    return node.copyWith(
      children: [for (final c in node.children) _mapTree(c, targetPath, transform)],
    );
  }

  void toggleExpanded(String path) {
    final root = state.root;
    if (root == null) return;
    state = state.copyWith(root: _mapTree(root, path, (n) {
      return n.copyWith(isExpanded: !n.isExpanded);
    }));
  }

  Future<void> createFile(String parentPath, String fileName) async {
    try {
      await _repo.createFile(parentPath, fileName);
      _log('تم إنشاء الملف: $fileName');
      await refreshProject();
    } catch (e) {
      _log('تعذّر إنشاء الملف: $e', isError: true);
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<void> createDirectory(String parentPath, String dirName) async {
    try {
      await _repo.createDirectory(parentPath, dirName);
      _log('تم إنشاء المجلد: $dirName');
      await refreshProject();
    } catch (e) {
      _log('تعذّر إنشاء المجلد: $e', isError: true);
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<void> rename(String path, String newName) async {
    try {
      await _repo.rename(path, newName);
      _log('تمت إعادة التسمية إلى: $newName');
      await refreshProject();
    } catch (e) {
      _log('تعذّرت إعادة التسمية: $e', isError: true);
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  Future<void> delete(String path, {required bool isDirectory}) async {
    try {
      await _repo.delete(path, isDirectory: isDirectory);
      _log('تم الحذف: $path');
      await refreshProject();
    } catch (e) {
      _log('تعذّر الحذف: $e', isError: true);
      state = state.copyWith(errorMessage: e.toString());
    }
  }

  void copyToClipboard(String path, {required bool isDirectory}) {
    state = state.copyWith(
      clipboard: ClipboardEntry(path: path, isDirectory: isDirectory, operation: ClipboardOperation.copy),
    );
    _log('تم النسخ إلى الحافظة');
  }

  void cutToClipboard(String path, {required bool isDirectory}) {
    state = state.copyWith(
      clipboard: ClipboardEntry(path: path, isDirectory: isDirectory, operation: ClipboardOperation.cut),
    );
    _log('تم القص إلى الحافظة');
  }

  Future<void> pasteInto(String destDirPath) async {
    final clip = state.clipboard;
    if (clip == null) return;
    try {
      await _repo.copyEntry(clip.path, destDirPath);
      if (clip.operation == ClipboardOperation.cut) {
        await _repo.delete(clip.path, isDirectory: clip.isDirectory);
      }
      state = state.copyWith(clearClipboard: true);
      _log('تم اللصق في: $destDirPath');
      await refreshProject();
    } catch (e) {
      _log('تعذّر اللصق: $e', isError: true);
      state = state.copyWith(errorMessage: e.toString());
    }
  }
}

// ------------------------- قوالب المشروع الجديد -------------------------

/// محتوى lib/main.dart الابتدائي — مكتوب عمدًا ضمن "المجموعة الجزئية من
/// Dart" التي يفهمها المُفسِّر الحالي (StatefulWidget/State قياسي، setState
/// بسيط، لا حلقات ولا دوال مساعدة خارج build) حتى يعمل زر "▶ تشغيل" فورًا
/// على مشروع جديد دون أي تعديل. راجع README قسم 4 لحدود الدعم الكاملة.
const String _newProjectMainDartTemplate = '''
import 'package:flutter/material.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'تطبيق جديد',
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _counter = 0;

  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('تطبيق جديد'),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('عدد الضغطات:'),
            Text('\$_counter'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            _counter = _counter + 1;
          });
        },
        child: Icon(Icons.add),
      ),
    );
  }
}
''';

String _newProjectPubspecTemplate(String projectName) => '''
name: $projectName
description: A new Flutter project.
publish_to: "none"
version: 0.1.0

environment:
  sdk: ">=3.3.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
''';
