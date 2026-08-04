// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:spacetimedb_sdk/codegen.dart';

class MonsterAiTimer {
  MonsterAiTimer({required this.scheduledId, required this.scheduledAt});

  factory MonsterAiTimer.fromJson(Map<String, dynamic> json) {
    return MonsterAiTimer(
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

  static MonsterAiTimer decodeBsatn(BsatnDecoder decoder) {
    return MonsterAiTimer(
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
        other is MonsterAiTimer &&
            scheduledId == other.scheduledId &&
            scheduledAt == other.scheduledAt;
  }

  @override
  int get hashCode {
    return Object.hashAll([scheduledId, scheduledAt]);
  }

  @override
  String toString() {
    return 'MonsterAiTimer(scheduledId: $scheduledId, scheduledAt: $scheduledAt)';
  }

  MonsterAiTimer copyWith({Int64? scheduledId, ScheduleAt? scheduledAt}) {
    return MonsterAiTimer(
      scheduledId: scheduledId ?? this.scheduledId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
    );
  }
}

class MonsterAiTimerDecoder extends RowDecoder<MonsterAiTimer> {
  @override
  MonsterAiTimer decode(BsatnDecoder decoder) {
    return MonsterAiTimer.decodeBsatn(decoder);
  }

  @override
  Int64? getPrimaryKey(MonsterAiTimer row) {
    return row.scheduledId;
  }

  @override
  Map<String, dynamic>? toJson(MonsterAiTimer row) {
    return row.toJson();
  }

  @override
  MonsterAiTimer? fromJson(Map<String, dynamic> json) {
    return MonsterAiTimer.fromJson(json);
  }

  @override
  bool get supportsJsonSerialization {
    return true;
  }
}
