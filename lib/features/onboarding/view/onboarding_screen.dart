import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../project_explorer/logic/project_provider.dart';
import '../../project_explorer/view/dialogs/create_project_dialog.dart';
import '../../settings/logic/settings_provider.dart';
import '../data/onboarding_page_data.dart';

/// شاشة الترحيب الأولى: تُعرَض مرة واحدة فقط قبل الدخول إلى بيئة العمل
/// الرئيسية. مصمَّمة بأسلوب بصري متدرّج (gradient) لكل صفحة، مع أيقونة
/// مركزية كبيرة، عنوان، نص توضيحي، مؤشر صفحات، وزرَّي "تخطّي"/"التالي"
/// وفي الصفحة الأخيرة: "فتح مشروع من الجهاز" أو "إنشاء مشروع جديد".
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _finish() {
    ref.read(settingsProvider.notifier).markOnboardingSeen();
  }

  void _finishAndOpenProject() {
    _finish();
    ref.read(projectProvider.notifier).openProjectFromDevice();
  }

  Future<void> _finishAndCreateNewProject() async {
    _finish();
    if (!mounted) return;
    await runCreateNewProjectFlow(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    final page = onboardingPages[_currentPage];
    final isLast = _currentPage == onboardingPages.length - 1;

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 400),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: page.gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextButton(
                    onPressed: isLast ? null : _finish,
                    child: Text(
                      isLast ? '' : 'تخطّي',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: onboardingPages.length,
                  onPageChanged: (index) => setState(() => _currentPage = index),
                  itemBuilder: (context, index) => _OnboardingPageView(data: onboardingPages[index]),
                ),
              ),
              _PageIndicator(count: onboardingPages.length, currentIndex: _currentPage),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: () {
                      if (isLast) {
                        _finishAndOpenProject();
                      } else {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOut,
                        );
                      }
                    },
                    child: Text(
                      isLast ? 'فتح مشروع من الجهاز' : 'التالي',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ),
              if (isLast) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.6)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      onPressed: _finishAndCreateNewProject,
                      child: const Text('إنشاء مشروع جديد', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _finish,
                  child: Text('المتابعة بدون فتح مشروع الآن',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13)),
                ),
              ] else
                const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPageView extends StatelessWidget {
  final OnboardingPageData data;
  const _OnboardingPageView({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.25), width: 1.5),
            ),
            child: Icon(data.icon, size: 64, color: Colors.white),
          ),
          const SizedBox(height: 40),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            data.subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 15, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  final int count;
  final int currentIndex;
  const _PageIndicator({required this.count, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: i == currentIndex ? 22 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == currentIndex ? Colors.white : Colors.white.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}
