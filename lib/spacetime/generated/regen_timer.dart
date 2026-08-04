// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:spacetimedb_sdk/codegen.dart';

class RegenTimer {
  RegenTimer({required this.scheduledId, required this.scheduledAt});

  factory RegenTimer.fromJson(Map<String, dynamic> json) {
    return RegenTimer(
      scheduledId: Int64(json['scheduledId'] ?? 0),
      scheduledAt: ScheduleAt.fromJson(
        Map<String, dynamic>.from(json['scheduledAt'] ?? {}),
      ),
    );
  }

  final Int64 scheduledId;

  final ScheduleAt scheduledAt;

  void encodeBsatn(BsatnEncoder encoder) {
    encoder.writeU64(scheduledId);
    scheduledAt.encodeBsatn(encoder);
  }

  static RegenTimer decodeBsatn(BsatnDecoder decoder) {
    return RegenTimer(
      scheduledId: decoder.readU64(),
      scheduledAt: ScheduleAt.decodeBsatn(decoder),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'scheduledId': scheduledId.toInt(),
      'scheduledAt': scheduledAt.toJson(),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is RegenTimer &&
            scheduledId == other.scheduledId &&
            scheduledAt == other.scheduledAt;
  }

  @override
  int get hashCode {
    return Object.hashAll([scheduledId, scheduledAt]);
  }

  @override
  String toString() {
    return 'RegenTimer(scheduledId: $scheduledId, scheduledAt: $scheduledAt)';
  }

  RegenTimer copyWith({Int64? scheduledId, ScheduleAt? scheduledAt}) {
    return RegenTimer(
      scheduledId: scheduledId ?? this.scheduledId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
    );
  }
}

class RegenTimerDecoder extends RowDecoder<RegenTimer> {
  @override
  RegenTimer decode(BsatnDecoder decoder) {
    return RegenTimer.decodeBsatn(decoder);
  }

  @override
  Int64? getPrimaryKey(RegenTimer row) {
    return row.scheduledId;
  }

  @override
  Map<String, dynamic>? toJson(RegenTimer row) {
    return row.toJson();
  }

  @override
  RegenTimer? fromJson(Map<String, dynamic> json) {
    return RegenTimer.fromJson(json);
  }

  @override
  bool get supportsJsonSerialization {
    return true;
  }
}
