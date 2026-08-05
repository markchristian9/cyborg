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
    required this.nextHurtAt,
    required this.mp,
    required this.maxMp,
    required this.defense,
    required this.deaths,
    required this.invulnerableUntil,
    required this.lastDamagedAt,
    required this.subChunk,
    required this.lastAttackAt,
    required this.attackDirX,
    required this.attackDirY,
    required this.attackSkill,
    required this.facingX,
    required this.facingY,
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
      nextHurtAt: Int64(json['nextHurtAt'] ?? 0),
      mp: json['mp'] ?? 0,
      maxMp: json['maxMp'] ?? 0,
      defense: json['defense'] ?? 0,
      deaths: json['deaths'] ?? 0,
      invulnerableUntil: Int64(json['invulnerableUntil'] ?? 0),
      lastDamagedAt: Int64(json['lastDamagedAt'] ?? 0),
      subChunk: json['subChunk'] ?? 0,
      lastAttackAt: Int64(json['lastAttackAt'] ?? 0),
      attackDirX: (json['attackDirX'] ?? 0.0).toDouble(),
      attackDirY: (json['attackDirY'] ?? 0.0).toDouble(),
      attackSkill: json['attackSkill'] ?? 0,
      facingX: (json['facingX'] ?? 0.0).toDouble(),
      facingY: (json['facingY'] ?? 0.0).toDouble(),
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

  final Int64 nextHurtAt;

  final int mp;

  final int maxMp;

  final int defense;

  final int deaths;

  final Int64 invulnerableUntil;

  final Int64 lastDamagedAt;

  final int subChunk;

  final Int64 lastAttackAt;

  final double attackDirX;

  final double attackDirY;

  final int attackSkill;

  final double facingX;

  final double facingY;

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
    encoder.writeI64(nextHurtAt);
    encoder.writeI32(mp);
    encoder.writeI32(maxMp);
    encoder.writeI32(defense);
    encoder.writeU32(deaths);
    encoder.writeI64(invulnerableUntil);
    encoder.writeI64(lastDamagedAt);
    encoder.writeU32(subChunk);
    encoder.writeI64(lastAttackAt);
    encoder.writeF32(attackDirX);
    encoder.writeF32(attackDirY);
    encoder.writeU32(attackSkill);
    encoder.writeF32(facingX);
    encoder.writeF32(facingY);
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
      nextHurtAt: decoder.readI64(),
      mp: decoder.readI32(),
      maxMp: decoder.readI32(),
      defense: decoder.readI32(),
      deaths: decoder.readU32(),
      invulnerableUntil: decoder.readI64(),
      lastDamagedAt: decoder.readI64(),
      subChunk: decoder.readU32(),
      lastAttackAt: decoder.readI64(),
      attackDirX: decoder.readF32(),
      attackDirY: decoder.readF32(),
      attackSkill: decoder.readU32(),
      facingX: decoder.readF32(),
      facingY: decoder.readF32(),
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
      'nextHurtAt': nextHurtAt.toInt(),
      'mp': mp,
      'maxMp': maxMp,
      'defense': defense,
      'deaths': deaths,
      'invulnerableUntil': invulnerableUntil.toInt(),
      'lastDamagedAt': lastDamagedAt.toInt(),
      'subChunk': subChunk,
      'lastAttackAt': lastAttackAt.toInt(),
      'attackDirX': attackDirX,
      'attackDirY': attackDirY,
      'attackSkill': attackSkill,
      'facingX': facingX,
      'facingY': facingY,
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
            nextTeleportAt == other.nextTeleportAt &&
            nextHurtAt == other.nextHurtAt &&
            mp == other.mp &&
            maxMp == other.maxMp &&
            defense == other.defense &&
            deaths == other.deaths &&
            invulnerableUntil == other.invulnerableUntil &&
            lastDamagedAt == other.lastDamagedAt &&
            subChunk == other.subChunk &&
            lastAttackAt == other.lastAttackAt &&
            attackDirX == other.attackDirX &&
            attackDirY == other.attackDirY &&
            attackSkill == other.attackSkill &&
            facingX == other.facingX &&
            facingY == other.facingY;
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
      nextHurtAt,
      mp,
      maxMp,
      defense,
      deaths,
      invulnerableUntil,
      lastDamagedAt,
      subChunk,
      lastAttackAt,
      attackDirX,
      attackDirY,
      attackSkill,
      facingX,
      facingY,
    ]);
  }

  @override
  String toString() {
    return 'WorldPlayer(identity: $identity, characterId: $characterId, name: $name, kind: $kind, level: $level, gridX: $gridX, gridY: $gridY, hp: $hp, maxHp: $maxHp, alive: $alive, nextAttackAt: $nextAttackAt, lastMoveAt: $lastMoveAt, enteredAt: $enteredAt, nextTeleportAt: $nextTeleportAt, nextHurtAt: $nextHurtAt, mp: $mp, maxMp: $maxMp, defense: $defense, deaths: $deaths, invulnerableUntil: $invulnerableUntil, lastDamagedAt: $lastDamagedAt, subChunk: $subChunk, lastAttackAt: $lastAttackAt, attackDirX: $attackDirX, attackDirY: $attackDirY, attackSkill: $attackSkill, facingX: $facingX, facingY: $facingY)';
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
    Int64? nextHurtAt,
    int? mp,
    int? maxMp,
    int? defense,
    int? deaths,
    Int64? invulnerableUntil,
    Int64? lastDamagedAt,
    int? subChunk,
    Int64? lastAttackAt,
    double? attackDirX,
    double? attackDirY,
    int? attackSkill,
    double? facingX,
    double? facingY,
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
      nextHurtAt: nextHurtAt ?? this.nextHurtAt,
      mp: mp ?? this.mp,
      maxMp: maxMp ?? this.maxMp,
      defense: defense ?? this.defense,
      deaths: deaths ?? this.deaths,
      invulnerableUntil: invulnerableUntil ?? this.invulnerableUntil,
      lastDamagedAt: lastDamagedAt ?? this.lastDamagedAt,
      subChunk: subChunk ?? this.subChunk,
      lastAttackAt: lastAttackAt ?? this.lastAttackAt,
      attackDirX: attackDirX ?? this.attackDirX,
      attackDirY: attackDirY ?? this.attackDirY,
      attackSkill: attackSkill ?? this.attackSkill,
      facingX: facingX ?? this.facingX,
      facingY: facingY ?? this.facingY,
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
