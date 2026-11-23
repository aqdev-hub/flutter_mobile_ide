import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../editor/logic/editor_tabs_provider.dart';
import '../logic/project_search_provider.dart';

class SearchPanel extends ConsumerStatefulWidget {
  const SearchPanel({super.key});

  @override
  ConsumerState<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends ConsumerState<SearchPanel> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // البحث أصبح عملية في الذاكرة بالكامل (فهرس مبني مسبقًا)، فتأخير بسيط
    // جدًا (200ms) كافٍ لتفادي إعادة البحث على كل حرف أثناء الكتابة السريعة
    // دون أي إحساس بالتأخر من طرف المستخدم.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      ref.read(projectSearchProvider.notifier).search(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final searchState = ref.watch(projectSearchProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'ابحث في ملفات المشروع...',
              prefixIcon: const Icon(Icons.search, size: 18),
              isDense: true,
              border: const OutlineInputBorder(),
              suffixIcon: searchState.isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            onChanged: _onChanged,
          ),
        ),
        if (searchState.isIndexing)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: Text('جارِ فهرسة ملفات المشروع...', style: TextStyle(fontSize: 11, color: Colors.grey)),
          )
        else if (searchState.query.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              '${searchState.results.length} نتيجة',
              style: const TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: searchState.results.length,
            itemBuilder: (context, index) {
              final match = searchState.results[index];
              return ListTile(
                dense: true,
                title: Text(
                  match.lineText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                subtitle: Text(
                  '${match.fileName} • السطر ${match.lineNumber}',
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                onTap: () {
                  ref.read(editorTabsProvider.notifier).revealPosition(
                        match.path,
                        match.fileName,
                        lineNumber: match.lineNumber,
                      );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
