import 'package:equatable/equatable.dart';

enum FileNodeType { file, directory }

/// يمثّل ملفًا أو مجلدًا واحدًا داخل شجرة المشروع.
///
/// نبنيها كشجرة غير قابلة للتغيير (immutable) — أي تعديل (إنشاء/حذف/إعادة تسمية)
/// يُنتج نسخة جديدة من الشجرة عبر [FileSystemRepository]. هذا يجعل مصدر الحقيقة
/// الوحيد هو نظام الملفات الفعلي على القرص، وشجرة الواجهة مجرد "انعكاس" له،
/// فتجنّبنا حالات تعارض بين ما يظهر للمستخدم وما هو موجود فعليًا.
class FileNode extends Equatable {
  final String path;
  final String name;
  final FileNodeType type;
  final List<FileNode> children;
  final bool isExpanded;

  const FileNode({
    required this.path,
    required this.name,
    required this.type,
    this.children = const [],
    this.isExpanded = false,
  });

  bool get isDirectory => type == FileNodeType.directory;
  bool get isFile => type == FileNodeType.file;

  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == 0) return '';
    return name.substring(dot);
  }

  FileNode copyWith({
    String? path,
    String? name,
    FileNodeType? type,
    List<FileNode>? children,
    bool? isExpanded,
  }) {
    return FileNode(
      path: path ?? this.path,
      name: name ?? this.name,
      type: type ?? this.type,
      children: children ?? this.children,
      isExpanded: isExpanded ?? this.isExpanded,
    );
  }

  @override
  List<Object?> get props => [path, name, type, children, isExpanded];
}
