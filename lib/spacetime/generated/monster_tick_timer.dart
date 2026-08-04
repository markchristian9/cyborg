// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:spacetimedb_sdk/codegen.dart';

class MonsterTickTimer {
  MonsterTickTimer({required this.scheduledId, required this.scheduledAt});

  factory MonsterTickTimer.fromJson(Map<String, dynamic> json) {
    return MonsterTickTimer(
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

  static MonsterTickTimer decodeBsatn(BsatnDecoder decoder) {
    return MonsterTickTimer(
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
        other is MonsterTickTimer &&
            scheduledId == other.scheduledId &&
            scheduledAt == other.scheduledAt;
  }

  @override
  int get hashCode {
    return Object.hashAll([scheduledId, scheduledAt]);
  }

  @override
  String toString() {
    return 'MonsterTickTimer(scheduledId: $scheduledId, scheduledAt: $scheduledAt)';
  }

  MonsterTickTimer copyWith({Int64? scheduledId, ScheduleAt? scheduledAt}) {
    return MonsterTickTimer(
      scheduledId: scheduledId ?? this.scheduledId,
      scheduledAt: scheduledAt ?? this.scheduledAt,
    );
  }
}

class MonsterTickTimerDecoder extends RowDecoder<MonsterTickTimer> {
  @override
  MonsterTickTimer decode(BsatnDecoder decoder) {
    return MonsterTickTimer.decodeBsatn(decoder);
  }

  @override
  Int64? getPrimaryKey(MonsterTickTimer row) {
    return row.scheduledId;
  }

  @override
  Map<String, dynamic>? toJson(MonsterTickTimer row) {
    return row.toJson();
  }

  @override
  MonsterTickTimer? fromJson(Map<String, dynamic> json) {
    return MonsterTickTimer.fromJson(json);
  }

  @override
  bool get supportsJsonSerialization {
    return true;
  }
}
