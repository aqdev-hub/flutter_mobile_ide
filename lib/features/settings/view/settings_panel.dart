import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../logic/settings_provider.dart';

class SettingsPanel extends ConsumerStatefulWidget {
  const SettingsPanel({super.key});

  @override
  ConsumerState<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends ConsumerState<SettingsPanel> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _nameController = TextEditingController(text: settings.gitAuthorName);
    _emailController = TextEditingController(text: settings.gitAuthorEmail);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('الإعدادات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        SwitchListTile(
          title: const Text('الوضع الليلي'),
          value: settings.isDarkMode,
          onChanged: (_) => notifier.toggleDarkMode(),
        ),
        SwitchListTile(
          title: const Text('التفاف الأسطر (Word Wrap)'),
          value: settings.wordWrap,
          onChanged: (_) => notifier.toggleWordWrap(),
        ),
        const SizedBox(height: 8),
        Text('حجم خط المحرر: ${settings.editorFontSize.toInt()}'),
        Slider(
          value: settings.editorFontSize,
          min: 10,
          max: 24,
          divisions: 14,
          label: settings.editorFontSize.toInt().toString(),
          onChanged: (value) => notifier.setFontSize(value),
        ),
        const Divider(height: 32),
        const Text('هوية Git', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text(
          'تُستخدَم هذه البيانات في كل عملية "commit" من تبويب Git.',
          style: TextStyle(fontSize: 11, color: Colors.grey),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'الاسم', isDense: true, border: OutlineInputBorder()),
          onSubmitted: (value) => notifier.setGitAuthorName(value.trim()),
          onTapOutside: (_) => notifier.setGitAuthorName(_nameController.text.trim()),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _emailController,
          decoration: const InputDecoration(labelText: 'البريد الإلكتروني', isDense: true, border: OutlineInputBorder()),
          keyboardType: TextInputType.emailAddress,
          onSubmitted: (value) => notifier.setGitAuthorEmail(value.trim()),
          onTapOutside: (_) => notifier.setGitAuthorEmail(_emailController.text.trim()),
        ),
      ],
    );
  }
}
