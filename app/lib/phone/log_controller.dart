import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sippier_core/sippier_core.dart';

/// The most recent core log lines. The full log is in sippier.log.
class LogController extends Notifier<List<String>> {
  static const maxLines = 500;

  @override
  List<String> build() {
    final sub = SippierCore.instance.events
        .where((e) => e is LogEvent)
        .listen((e) => _add((e as LogEvent).text));
    ref.onDispose(sub.cancel);
    return const [];
  }

  void _add(String line) {
    final lines = state.length >= maxLines ? state.skip(100) : state;
    state = [...lines, line];
  }
}
