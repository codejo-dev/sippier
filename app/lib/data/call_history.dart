import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

class CallRecord {
  const CallRecord({
    required this.peerUri,
    required this.peerName,
    required this.accountId,
    required this.incoming,
    required this.startedAt,
    required this.endedAt,
    this.connectedAt,
    this.reason = '',
  });

  factory CallRecord.fromJson(Map<String, dynamic> json) => CallRecord(
    peerUri: json['peerUri'] as String,
    peerName: json['peerName'] as String? ?? '',
    accountId: json['accountId'] as String? ?? '',
    incoming: json['incoming'] as bool,
    startedAt: DateTime.parse(json['startedAt'] as String),
    endedAt: DateTime.parse(json['endedAt'] as String),
    connectedAt: json['connectedAt'] == null
        ? null
        : DateTime.parse(json['connectedAt'] as String),
    reason: json['reason'] as String? ?? '',
  );

  final String peerUri;
  final String peerName;
  final String accountId;
  final bool incoming;
  final DateTime startedAt;
  final DateTime endedAt;
  final DateTime? connectedAt;
  final String reason;

  bool get missed => incoming && connectedAt == null;

  Duration get duration =>
      connectedAt == null ? Duration.zero : endedAt.difference(connectedAt!);

  Map<String, dynamic> toJson() => {
    'peerUri': peerUri,
    'peerName': peerName,
    'accountId': accountId,
    'incoming': incoming,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    if (connectedAt != null) 'connectedAt': connectedAt!.toIso8601String(),
    'reason': reason,
  };
}

/// The last [maxRecords] calls, newest first, in `<app support>/history.json`.
class CallHistory extends Notifier<List<CallRecord>> {
  static const maxRecords = 200;

  File get _file => File('${ref.read(appDirProvider)}/history.json');

  @override
  List<CallRecord> build() {
    if (!_file.existsSync()) return const [];
    try {
      return [
        for (final r in jsonDecode(_file.readAsStringSync()) as List)
          CallRecord.fromJson(r as Map<String, dynamic>),
      ];
    } on FormatException {
      return const [];
    }
  }

  void add(CallRecord record) {
    state = [record, ...state.take(maxRecords - 1)];
    _save();
  }

  void clear() {
    state = const [];
    _save();
  }

  Future<void> _save() async {
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsString(jsonEncode([for (final r in state) r.toJson()]));
    await tmp.rename(_file.path);
  }
}
