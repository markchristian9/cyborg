// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:spacetimedb_sdk/codegen.dart';

class Monster {
  Monster({
    required this.id,
    required this.spawnSlot,
    required this.kind,
    required this.level,
    required this.homeX,
    required this.homeY,
    required this.gridX,
    required this.gridY,
    required this.hp,
    required this.maxHp,
    required this.alive,
    required this.taggedBy,
    required this.taggedAt,
    required this.diedAt,
    required this.chunk,
    required this.posChunk,
    required this.faceX,
    required this.faceY,
    required this.lastAttackAt,
  });

  factory Monster.fromJson(Map<String, dynamic> json) {
    return Monster(
      id: Int64(json['id'] ?? 0),
      spawnSlot: json['spawnSlot'] ?? 0,
      kind: json['kind'] ?? '',
      level: json['level'] ?? 0,
      homeX: (json['homeX'] ?? 0.0).toDouble(),
      homeY: (json['homeY'] ?? 0.0).toDouble(),
      gridX: (json['gridX'] ?? 0.0).toDouble(),
      gridY: (json['gridY'] ?? 0.0).toDouble(),
      hp: json['hp'] ?? 0,
      maxHp: json['maxHp'] ?? 0,
      alive: json['alive'] ?? false,
      taggedBy: json['taggedBy'] == null ? null : Int64(json['taggedBy']),
      taggedAt: Int64(json['taggedAt'] ?? 0),
      diedAt: Int64(json['diedAt'] ?? 0),
      chunk: json['chunk'] ?? 0,
      posChunk: json['posChunk'] ?? 0,
      faceX: (json['faceX'] ?? 0.0).toDouble(),
      faceY: (json['faceY'] ?? 0.0).toDouble(),
      lastAttackAt: Int64(json['lastAttackAt'] ?? 0),
    );
  }

  final Int64 id;

  final int spawnSlot;

  final String kind;

  final int level;

  final double homeX;

  final double homeY;

  final double gridX;

  final double gridY;

  final int hp;

  final int maxHp;

  final bool alive;

  final Int64? taggedBy;

  final Int64 taggedAt;

  final Int64 diedAt;

  final int chunk;

  final int posChunk;

  final double faceX;

  final double faceY;

  final Int64 lastAttackAt;

  void encodeBsatn(BsatnEncoder encoder) {
    encoder.writeU64(id);
    encoder.writeU32(spawnSlot);
    encoder.writeString(kind);
    encoder.writeU32(level);
    encoder.writeF32(homeX);
    encoder.writeF32(homeY);
    encoder.writeF32(gridX);
    encoder.writeF32(gridY);
    encoder.writeI32(hp);
    encoder.writeI32(maxHp);
    encoder.writeBool(alive);
    encoder.writeOption<Int64>(taggedBy, (value) => encoder.writeU64(value));
    encoder.writeI64(taggedAt);
    encoder.writeI64(diedAt);
    encoder.writeU32(chunk);
    encoder.writeU32(posChunk);
    encoder.writeF32(faceX);
    encoder.writeF32(faceY);
    encoder.writeI64(lastAttackAt);
  }

  static Monster decodeBsatn(BsatnDecoder decoder) {
    return Monster(
      id: decoder.readU64(),
      spawnSlot: decoder.readU32(),
      kind: decoder.readString(),
      level: decoder.readU32(),
      homeX: decoder.readF32(),
      homeY: decoder.readF32(),
      gridX: decoder.readF32(),
      gridY: decoder.readF32(),
      hp: decoder.readI32(),
      maxHp: decoder.readI32(),
      alive: decoder.readBool(),
      taggedBy: decoder.readOption<Int64>(() => decoder.readU64()),
      taggedAt: decoder.readI64(),
      diedAt: decoder.readI64(),
      chunk: decoder.readU32(),
      posChunk: decoder.readU32(),
      faceX: decoder.readF32(),
      faceY: decoder.readF32(),
      lastAttackAt: decoder.readI64(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id.toInt(),
      'spawnSlot': spawnSlot,
      'kind': kind,
      'level': level,
      'homeX': homeX,
      'homeY': homeY,
      'gridX': gridX,
      'gridY': gridY,
      'hp': hp,
      'maxHp': maxHp,
      'alive': alive,
      'taggedBy': taggedBy?.toInt(),
      'taggedAt': taggedAt.toInt(),
      'diedAt': diedAt.toInt(),
      'chunk': chunk,
      'posChunk': posChunk,
      'faceX': faceX,
      'faceY': faceY,
      'lastAttackAt': lastAttackAt.toInt(),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Monster &&
            id == other.id &&
            spawnSlot == other.spawnSlot &&
            kind == other.kind &&
            level == other.level &&
            homeX == other.homeX &&
            homeY == other.homeY &&
            gridX == other.gridX &&
            gridY == other.gridY &&
            hp == other.hp &&
            maxHp == other.maxHp &&
            alive == other.alive &&
            taggedBy == other.taggedBy &&
            taggedAt == other.taggedAt &&
            diedAt == other.diedAt &&
            chunk == other.chunk &&
            posChunk == other.posChunk &&
            faceX == other.faceX &&
            faceY == other.faceY &&
            lastAttackAt == other.lastAttackAt;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      id,
      spawnSlot,
      kind,
      level,
      homeX,
      homeY,
      gridX,
      gridY,
      hp,
      maxHp,
      alive,
      taggedBy,
      taggedAt,
      diedAt,
      chunk,
      posChunk,
      faceX,
      faceY,
      lastAttackAt,
    ]);
  }

  @override
  String toString() {
    return 'Monster(id: $id, spawnSlot: $spawnSlot, kind: $kind, level: $level, homeX: $homeX, homeY: $homeY, gridX: $gridX, gridY: $gridY, hp: $hp, maxHp: $maxHp, alive: $alive, taggedBy: $taggedBy, taggedAt: $taggedAt, diedAt: $diedAt, chunk: $chunk, posChunk: $posChunk, faceX: $faceX, faceY: $faceY, lastAttackAt: $lastAttackAt)';
  }

  Monster copyWith({
    Int64? id,
    int? spawnSlot,
    String? kind,
    int? level,
    double? homeX,
    double? homeY,
    double? gridX,
    double? gridY,
    int? hp,
    int? maxHp,
    bool? alive,
    Int64? taggedBy,
    Int64? taggedAt,
    Int64? diedAt,
    int? chunk,
    int? posChunk,
    double? faceX,
    double? faceY,
    Int64? lastAttackAt,
  }) {
    return Monster(
      id: id ?? this.id,
      spawnSlot: spawnSlot ?? this.spawnSlot,
      kind: kind ?? this.kind,
      level: level ?? this.level,
      homeX: homeX ?? this.homeX,
      homeY: homeY ?? this.homeY,
      gridX: gridX ?? this.gridX,
      gridY: gridY ?? this.gridY,
      hp: hp ?? this.hp,
      maxHp: maxHp ?? this.maxHp,
      alive: alive ?? this.alive,
      taggedBy: taggedBy ?? this.taggedBy,
      taggedAt: taggedAt ?? this.taggedAt,
      diedAt: diedAt ?? this.diedAt,
      chunk: chunk ?? this.chunk,
      posChunk: posChunk ?? this.posChunk,
      faceX: faceX ?? this.faceX,
      faceY: faceY ?? this.faceY,
      lastAttackAt: lastAttackAt ?? this.lastAttackAt,
    );
  }
}

class MonsterDecoder extends RowDecoder<Monster> {
  @override
  Monster decode(BsatnDecoder decoder) {
    return Monster.decodeBsatn(decoder);
  }

  @override
  Int64? getPrimaryKey(Monster row) {
    return row.id;
  }

  @override
  Map<String, dynamic>? toJson(Monster row) {
    return row.toJson();
  }

  @override
  Monster? fromJson(Map<String, dynamic> json) {
    return Monster.fromJson(json);
  }

  @override
  bool get supportsJsonSerialization {
    return true;
  }
}
