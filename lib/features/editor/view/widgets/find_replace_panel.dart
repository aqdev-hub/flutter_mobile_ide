import 'package:flutter/material.dart';
import 'package:flutter_code_editor/flutter_code_editor.dart';

import '../../../../core/theme/app_theme.dart';

/// شريط بحث/استبدال مصغّر يعمل مباشرة على [CodeController] الخاص بالتبويب
/// النشط، دون الحاجة لفتح شاشة منفصلة — يبقي المستخدم في سياق الكود نفسه.
class FindReplacePanel extends StatefulWidget {
  final CodeController controller;
  final VoidCallback onClose;

  const FindReplacePanel({super.key, required this.controller, required this.onClose});

  @override
  State<FindReplacePanel> createState() => _FindReplacePanelState();
}

class _FindReplacePanelState extends State<FindReplacePanel> {
  final _findController = TextEditingController();
  final _replaceController = TextEditingController();
  List<int> _matchOffsets = [];
  int _currentMatch = -1;

  void _runSearch() {
    final query = _findController.text;
    final text = widget.controller.fullText;
    final offsets = <int>[];
    if (query.isNotEmpty) {
      int start = 0;
      while (true) {
        final index = text.indexOf(query, start);
        if (index == -1) break;
        offsets.add(index);
        start = index + query.length;
      }
    }
    setState(() {
      _matchOffsets = offsets;
      _currentMatch = offsets.isEmpty ? -1 : 0;
    });
    _selectCurrentMatch();
  }

  void _selectCurrentMatch() {
    if (_currentMatch == -1 || _matchOffsets.isEmpty) return;
    final offset = _matchOffsets[_currentMatch];
    final length = _findController.text.length;
    widget.controller.selection = TextSelection(baseOffset: offset, extentOffset: offset + length);
  }

  void _next() {
    if (_matchOffsets.isEmpty) return;
    setState(() => _currentMatch = (_currentMatch + 1) % _matchOffsets.length);
    _selectCurrentMatch();
  }

  void _previous() {
    if (_matchOffsets.isEmpty) return;
    setState(() => _currentMatch = (_currentMatch - 1 + _matchOffsets.length) % _matchOffsets.length);
    _selectCurrentMatch();
  }

  void _replaceCurrent() {
    if (_currentMatch == -1 || _matchOffsets.isEmpty) return;
    final text = widget.controller.fullText;
    final offset = _matchOffsets[_currentMatch];
    final findLength = _findController.text.length;
    final newText = text.replaceRange(offset, offset + findLength, _replaceController.text);
    widget.controller.text = newText;
    _runSearch();
  }

  void _replaceAll() {
    if (_findController.text.isEmpty) return;
    final newText = widget.controller.fullText.replaceAll(_findController.text, _replaceController.text);
    widget.controller.text = newText;
    _runSearch();
  }

  @override
  void dispose() {
    _findController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: const BoxDecoration(
        color: IdeColors.darkSurface,
        border: Border(bottom: BorderSide(color: IdeColors.darkBorder)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _findController,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'بحث', isDense: true),
                  onChanged: (_) => _runSearch(),
                ),
              ),
              Text(
                _matchOffsets.isEmpty ? '0/0' : '${_currentMatch + 1}/${_matchOffsets.length}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
              IconButton(icon: const Icon(Icons.keyboard_arrow_up, size: 18), onPressed: _previous),
              IconButton(icon: const Icon(Icons.keyboard_arrow_down, size: 18), onPressed: _next),
              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: widget.onClose),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _replaceController,
                  decoration: const InputDecoration(hintText: 'استبدال بـ', isDense: true),
                ),
              ),
              TextButton(onPressed: _replaceCurrent, child: const Text('استبدال')),
              TextButton(onPressed: _replaceAll, child: const Text('استبدال الكل')),
            ],
          ),
        ],
      ),
    );
  }
}
