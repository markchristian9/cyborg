// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:spacetimedb_sdk/codegen.dart';

class MonsterKill {
  MonsterKill({
    required this.id,
    required this.characterId,
    required this.characterName,
    required this.monsterKind,
    required this.monsterLevel,
    required this.xpAwarded,
    required this.lastHitBy,
    required this.killedAt,
  });

  factory MonsterKill.fromJson(Map<String, dynamic> json) {
    return MonsterKill(
      id: Int64(json['id'] ?? 0),
      characterId: Int64(json['characterId'] ?? 0),
      characterName: json['characterName'] ?? '',
      monsterKind: json['monsterKind'] ?? '',
      monsterLevel: json['monsterLevel'] ?? 0,
      xpAwarded: json['xpAwarded'] ?? 0,
      lastHitBy: json['lastHitBy'] == null ? null : Int64(json['lastHitBy']),
      killedAt: Int64(json['killedAt'] ?? 0),
    );
  }

  final Int64 id;

  final Int64 characterId;

  final String characterName;

  final String monsterKind;

  final int monsterLevel;

  final int xpAwarded;

  final Int64? lastHitBy;

  final Int64 killedAt;

  void encodeBsatn(BsatnEncoder encoder) {
    encoder.writeU64(id);
    encoder.writeU64(characterId);
    encoder.writeString(characterName);
    encoder.writeString(monsterKind);
    encoder.writeU32(monsterLevel);
    encoder.writeU32(xpAwarded);
    encoder.writeOption<Int64>(lastHitBy, (value) => encoder.writeU64(value));
    encoder.writeI64(killedAt);
  }

  static MonsterKill decodeBsatn(BsatnDecoder decoder) {
    return MonsterKill(
      id: decoder.readU64(),
      characterId: decoder.readU64(),
      characterName: decoder.readString(),
      monsterKind: decoder.readString(),
      monsterLevel: decoder.readU32(),
      xpAwarded: decoder.readU32(),
      lastHitBy: decoder.readOption<Int64>(() => decoder.readU64()),
      killedAt: decoder.readI64(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id.toInt(),
      'characterId': characterId.toInt(),
      'characterName': characterName,
      'monsterKind': monsterKind,
      'monsterLevel': monsterLevel,
      'xpAwarded': xpAwarded,
      'lastHitBy': lastHitBy?.toInt(),
      'killedAt': killedAt.toInt(),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is MonsterKill &&
            id == other.id &&
            characterId == other.characterId &&
            characterName == other.characterName &&
            monsterKind == other.monsterKind &&
            monsterLevel == other.monsterLevel &&
            xpAwarded == other.xpAwarded &&
            lastHitBy == other.lastHitBy &&
            killedAt == other.killedAt;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      id,
      characterId,
      characterName,
      monsterKind,
      monsterLevel,
      xpAwarded,
      lastHitBy,
      killedAt,
    ]);
  }

  @override
  String toString() {
    return 'MonsterKill(id: $id, characterId: $characterId, characterName: $characterName, monsterKind: $monsterKind, monsterLevel: $monsterLevel, xpAwarded: $xpAwarded, lastHitBy: $lastHitBy, killedAt: $killedAt)';
  }

  MonsterKill copyWith({
    Int64? id,
    Int64? characterId,
    String? characterName,
    String? monsterKind,
    int? monsterLevel,
    int? xpAwarded,
    Int64? lastHitBy,
    Int64? killedAt,
  }) {
    return MonsterKill(
      id: id ?? this.id,
      characterId: characterId ?? this.characterId,
      characterName: characterName ?? this.characterName,
      monsterKind: monsterKind ?? this.monsterKind,
      monsterLevel: monsterLevel ?? this.monsterLevel,
      xpAwarded: xpAwarded ?? this.xpAwarded,
      lastHitBy: lastHitBy ?? this.lastHitBy,
      killedAt: killedAt ?? this.killedAt,
    );
  }
}

class MonsterKillDecoder extends RowDecoder<MonsterKill> {
  @override
  MonsterKill decode(BsatnDecoder decoder) {
    return MonsterKill.decodeBsatn(decoder);
  }

  @override
  Int64? getPrimaryKey(MonsterKill row) {
    return row.id;
  }

  @override
  Map<String, dynamic>? toJson(MonsterKill row) {
    return row.toJson();
  }

  @override
  MonsterKill? fromJson(Map<String, dynamic> json) {
    return MonsterKill.fromJson(json);
  }

  @override
  bool get supportsJsonSerialization {
    return true;
  }
}
