import 'dart:convert';

/// يمثّل مدخلة واحدة في قائمة "المشاريع الحديثة" — يُخزَّن كل عنصر كسلسلة
/// JSON داخل SharedPreferences، حتى نحتفظ بالاسم والمسار وآخر وقت فتح دون
/// الحاجة لإعادة قراءة القرص فقط لعرض القائمة في الواجهة.
class RecentProject {
  final String path;
  final String name;
  final DateTime lastOpenedAt;

  const RecentProject({
    required this.path,
    required this.name,
    required this.lastOpenedAt,
  });

  Map<String, dynamic> toMap() => {
        'path': path,
        'name': name,
        'lastOpenedAt': lastOpenedAt.toIso8601String(),
      };

  factory RecentProject.fromMap(Map<String, dynamic> map) => RecentProject(
        path: map['path'] as String,
        name: map['name'] as String,
        lastOpenedAt: DateTime.tryParse(map['lastOpenedAt'] as String? ?? '') ?? DateTime.now(),
      );

  String encode() => jsonEncode(toMap());

  static RecentProject decode(String raw) => RecentProject.fromMap(jsonDecode(raw) as Map<String, dynamic>);
}
