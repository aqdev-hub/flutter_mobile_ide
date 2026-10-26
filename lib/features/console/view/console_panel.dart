import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../logic/console_provider.dart';

class ConsolePanel extends ConsumerStatefulWidget {
  const ConsolePanel({super.key});

  @override
  ConsumerState<ConsolePanel> createState() => _ConsolePanelState();
}

class _ConsolePanelState extends ConsumerState<ConsolePanel> {
  // يُنشأ مرة واحدة ويُتلف مع اللوحة (كان يُنشأ في كل build دون dispose).
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(consoleProvider);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: IdeColors.darkBorder)),
          ),
          child: Row(
            children: [
              const Icon(Icons.terminal, size: 16),
              const SizedBox(width: 6),
              const Text('Output', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              IconButton(
                tooltip: 'مسح السجل',
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => ref.read(consoleProvider.notifier).clear(),
              ),
            ],
          ),
        ),
        Expanded(
          child: lines.isEmpty
              ? const Center(
                  child: Text('لا توجد رسائل بعد', style: TextStyle(color: Colors.grey, fontSize: 12)),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(8),
                  itemCount: lines.length,
                  itemBuilder: (context, index) {
                    final line = lines[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: SelectableText(
                        line.message,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: line.isError ? IdeColors.stopRed : Colors.grey.shade300,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
