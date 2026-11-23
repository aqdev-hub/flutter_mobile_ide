import 'package:flutter/material.dart';

/// محتوى صفحة واحدة من صفحات الترحيب. نستخدم أيقونات ورسومًا متجهية
/// (بدل صور فوتوغرافية مرفقة) حتى تُقاس بدقة على أي كثافة شاشة وتبقى
/// خفيفة تمامًا بلا اعتماديات أصول خارجية — وتُعطي مظهرًا نظيفًا واحترافيًا
/// يتماشى مع هوية أدوات المطوّرين.
class OnboardingPageData {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradientColors;

  const OnboardingPageData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradientColors,
  });
}

const List<OnboardingPageData> onboardingPages = [
  OnboardingPageData(
    icon: Icons.integration_instructions_rounded,
    title: 'مرحبًا بك في\nFlutter Mobile IDE',
    subtitle:
        'بيئة تطوير Flutter متكاملة، مصمَّمة خصيصًا للهاتف — افتح مشاريعك،'
        ' عدّل الكود، وشغّله دون الحاجة لجهاز كمبيوتر.',
    gradientColors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
  ),
  OnboardingPageData(
    icon: Icons.account_tree_rounded,
    title: 'شجرة مشروع كاملة\nومحرر احترافي',
    subtitle:
        'تصفّح ملفات مشروعك، أنشئ وأعد تسمية واحذف بحرّية، وعدّل الكود مع'
        ' تلوين نحوي وإغلاق تلقائي للأقواس وبحث فوري.',
    gradientColors: [Color(0xFF1D2B64), Color(0xFF2A4E6E), Color(0xFF3F6C93)],
  ),
  OnboardingPageData(
    icon: Icons.phone_iphone_rounded,
    title: 'معاينة حيّة وتفاعلية',
    subtitle:
        'شغّل شاشاتك وشاهدها تعمل فعليًا داخل إطار جهاز مصغّر: اضغط الأزرار،'
        ' تنقّل بين الصفحات، وجرّب واجهتك كما لو كانت تعمل على هاتف حقيقي.',
    gradientColors: [Color(0xFF134E5E), Color(0xFF1F7A5C), Color(0xFF71B280)],
  ),
];
