import 'package:flutter/material.dart';

import '../../data/models/file_node.dart';

/// أيقونة صغيرة تُميّز نوع الملف بصريًا داخل الشجرة والتبويبات،
/// بنفس فكرة أيقونات الامتدادات الملوّنة في VS Code.
class FileIcon extends StatelessWidget {
  final FileNode node;
  const FileIcon({super.key, required this.node});

  @override
  Widget build(BuildContext context) {
    final (icon, color) = _resolve();
    return Icon(icon, size: 16, color: color);
  }

  (IconData, Color) _resolve() {
    if (node.isDirectory) {
      return (node.isExpanded ? Icons.folder_open : Icons.folder, const Color(0xFFDCB67A));
    }
    switch (node.extension) {
      case '.dart':
        return (Icons.code, const Color(0xFF42A5F5));
      case '.yaml':
      case '.yml':
        return (Icons.settings_suggest, const Color(0xFFCE93D8));
      case '.json':
        return (Icons.data_object, const Color(0xFFFFB74D));
      case '.md':
        return (Icons.description_outlined, Colors.grey);
      case '.png':
      case '.jpg':
      case '.jpeg':
      case '.svg':
        return (Icons.image_outlined, const Color(0xFF66BB6A));
      default:
        return (Icons.insert_drive_file_outlined, Colors.grey);
    }
  }
}
