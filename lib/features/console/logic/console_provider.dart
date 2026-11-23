import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConsoleLine extends Equatable {
  final String message;
  final bool isError;
  final DateTime timestamp;

  ConsoleLine(this.message, {this.isError = false}) : timestamp = DateTime.now();

  @override
  List<Object?> get props => [message, isError, timestamp];
}

final consoleProvider =
    StateNotifierProvider<ConsoleNotifier, List<ConsoleLine>>((ref) {
  return ConsoleNotifier();
});

/// سجلّ رسائل بسيط (append-only) تُغذّيه كل الـ features الأخرى.
/// وضعناه كـ feature مستقل صغير لأنه "ناقل رسائل" مشترك بين المشروع/المحرر/المعاينة،
/// وليس منطقًا خاصًا بأي واحدة منها.
class ConsoleNotifier extends StateNotifier<List<ConsoleLine>> {
  ConsoleNotifier() : super([]);

  static const int _maxLines = 500;

  void log(String message, {bool isError = false}) {
    final updated = [...state, ConsoleLine(message, isError: isError)];
    state = updated.length > _maxLines
        ? updated.sublist(updated.length - _maxLines)
        : updated;
  }

  void clear() => state = [];
}
