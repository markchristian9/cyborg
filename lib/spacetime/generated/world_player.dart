// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:spacetimedb_sdk/codegen.dart';

class WorldPlayer {
  WorldPlayer({
    required this.identity,
    required this.characterId,
    required this.name,
    required this.kind,
    required this.level,
    required this.gridX,
    required this.gridY,
    required this.hp,
    required this.maxHp,
    required this.alive,
    required this.nextAttackAt,
    required this.lastMoveAt,
    required this.enteredAt,
    required this.nextTeleportAt,
  });

  factory WorldPlayer.fromJson(Map<String, dynamic> json) {
    return WorldPlayer(
      identity: Identity.fromJson(json['identity'] ?? ''),
      characterId: Int64(json['characterId'] ?? 0),
      name: json['name'] ?? '',
      kind: json['kind'] ?? '',
      level: json['level'] ?? 0,
      gridX: (json['gridX'] ?? 0.0).toDouble(),
      gridY: (json['gridY'] ?? 0.0).toDouble(),
      hp: json['hp'] ?? 0,
      maxHp: json['maxHp'] ?? 0,
      alive: json['alive'] ?? false,
      nextAttackAt: Int64(json['nextAttackAt'] ?? 0),
      lastMoveAt: Int64(json['lastMoveAt'] ?? 0),
      enteredAt: Int64(json['enteredAt'] ?? 0),
      nextTeleportAt: Int64(json['nextTeleportAt'] ?? 0),
    );
  }

  final Identity identity;

  final Int64 characterId;

  final String name;

  final String kind;

  final int level;

  final double gridX;

  final double gridY;

  final int hp;

  final int maxHp;

  final bool alive;

  final Int64 nextAttackAt;

  final Int64 lastMoveAt;

  final Int64 enteredAt;

  final Int64 nextTeleportAt;

  void encodeBsatn(BsatnEncoder encoder) {
    encoder.writeIdentity(identity);
    encoder.writeU64(characterId);
    encoder.writeString(name);
    encoder.writeString(kind);
    encoder.writeU32(level);
    encoder.writeF32(gridX);
    encoder.writeF32(gridY);
    encoder.writeI32(hp);
    encoder.writeI32(maxHp);
    encoder.writeBool(alive);
    encoder.writeI64(nextAttackAt);
    encoder.writeI64(lastMoveAt);
    encoder.writeI64(enteredAt);
    encoder.writeI64(nextTeleportAt);
  }

  static WorldPlayer decodeBsatn(BsatnDecoder decoder) {
    return WorldPlayer(
      identity: decoder.readIdentity(),
      characterId: decoder.readU64(),
      name: decoder.readString(),
      kind: decoder.readString(),
      level: decoder.readU32(),
      gridX: decoder.readF32(),
      gridY: decoder.readF32(),
      hp: decoder.readI32(),
      maxHp: decoder.readI32(),
      alive: decoder.readBool(),
      nextAttackAt: decoder.readI64(),
      lastMoveAt: decoder.readI64(),
      enteredAt: decoder.readI64(),
      nextTeleportAt: decoder.readI64(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'identity': identity.toJson(),
      'characterId': characterId.toInt(),
      'name': name,
      'kind': kind,
      'level': level,
      'gridX': gridX,
      'gridY': gridY,
      'hp': hp,
      'maxHp': maxHp,
      'alive': alive,
      'nextAttackAt': nextAttackAt.toInt(),
      'lastMoveAt': lastMoveAt.toInt(),
      'enteredAt': enteredAt.toInt(),
      'nextTeleportAt': nextTeleportAt.toInt(),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is WorldPlayer &&
            identity == other.identity &&
            characterId == other.characterId &&
            name == other.name &&
            kind == other.kind &&
            level == other.level &&
            gridX == other.gridX &&
            gridY == other.gridY &&
            hp == other.hp &&
            maxHp == other.maxHp &&
            alive == other.alive &&
            nextAttackAt == other.nextAttackAt &&
            lastMoveAt == other.lastMoveAt &&
            enteredAt == other.enteredAt &&
            nextTeleportAt == other.nextTeleportAt;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      identity,
      characterId,
      name,
      kind,
      level,
      gridX,
      gridY,
      hp,
      maxHp,
      alive,
      nextAttackAt,
      lastMoveAt,
      enteredAt,
      nextTeleportAt,
    ]);
  }

  @override
  String toString() {
    return 'WorldPlayer(identity: $identity, characterId: $characterId, name: $name, kind: $kind, level: $level, gridX: $gridX, gridY: $gridY, hp: $hp, maxHp: $maxHp, alive: $alive, nextAttackAt: $nextAttackAt, lastMoveAt: $lastMoveAt, enteredAt: $enteredAt, nextTeleportAt: $nextTeleportAt)';
  }

  WorldPlayer copyWith({
    Identity? identity,
    Int64? characterId,
    String? name,
    String? kind,
    int? level,
    double? gridX,
    double? gridY,
    int? hp,
    int? maxHp,
    bool? alive,
    Int64? nextAttackAt,
    Int64? lastMoveAt,
    Int64? enteredAt,
    Int64? nextTeleportAt,
  }) {
    return WorldPlayer(
      identity: identity ?? this.identity,
      characterId: characterId ?? this.characterId,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      level: level ?? this.level,
      gridX: gridX ?? this.gridX,
      gridY: gridY ?? this.gridY,
      hp: hp ?? this.hp,
      maxHp: maxHp ?? this.maxHp,
      alive: alive ?? this.alive,
      nextAttackAt: nextAttackAt ?? this.nextAttackAt,
      lastMoveAt: lastMoveAt ?? this.lastMoveAt,
      enteredAt: enteredAt ?? this.enteredAt,
      nextTeleportAt: nextTeleportAt ?? this.nextTeleportAt,
    );
  }
}

class WorldPlayerDecoder extends RowDecoder<WorldPlayer> {
  @override
  WorldPlayer decode(BsatnDecoder decoder) {
    return WorldPlayer.decodeBsatn(decoder);
  }

  @override
  Identity? getPrimaryKey(WorldPlayer row) {
    return row.identity;
  }

  @override
  Map<String, dynamic>? toJson(WorldPlayer row) {
    return row.toJson();
  }

  @override
  WorldPlayer? fromJson(Map<String, dynamic> json) {
    return WorldPlayer.fromJson(json);
  }

  @override
  bool get supportsJsonSerialization {
    return true;
  }
}
