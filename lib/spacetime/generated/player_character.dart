// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:spacetimedb_sdk/codegen.dart';

class PlayerCharacter {
  PlayerCharacter({
    required this.id,
    required this.accountId,
    required this.name,
    required this.kind,
    required this.level,
    required this.xp,
    required this.createdAt,
    required this.lastPlayedAt,
  });

  factory PlayerCharacter.fromJson(Map<String, dynamic> json) {
    return PlayerCharacter(
      id: Int64(json['id'] ?? 0),
      accountId: Int64(json['accountId'] ?? 0),
      name: json['name'] ?? '',
      kind: json['kind'] ?? '',
      level: json['level'] ?? 0,
      xp: Int64(json['xp'] ?? 0),
      createdAt: Int64(json['createdAt'] ?? 0),
      lastPlayedAt: Int64(json['lastPlayedAt'] ?? 0),
    );
  }

  final Int64 id;

  final Int64 accountId;

  final String name;

  final String kind;

  final int level;

  final Int64 xp;

  final Int64 createdAt;

  final Int64 lastPlayedAt;

  void encodeBsatn(BsatnEncoder encoder) {
    encoder.writeU64(id);
    encoder.writeU64(accountId);
    encoder.writeString(name);
    encoder.writeString(kind);
    encoder.writeU32(level);
    encoder.writeU64(xp);
    encoder.writeI64(createdAt);
    encoder.writeI64(lastPlayedAt);
  }

  static PlayerCharacter decodeBsatn(BsatnDecoder decoder) {
    return PlayerCharacter(
      id: decoder.readU64(),
      accountId: decoder.readU64(),
      name: decoder.readString(),
      kind: decoder.readString(),
      level: decoder.readU32(),
      xp: decoder.readU64(),
      createdAt: decoder.readI64(),
      lastPlayedAt: decoder.readI64(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id.toInt(),
      'accountId': accountId.toInt(),
      'name': name,
      'kind': kind,
      'level': level,
      'xp': xp.toInt(),
      'createdAt': createdAt.toInt(),
      'lastPlayedAt': lastPlayedAt.toInt(),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlayerCharacter &&
            id == other.id &&
            accountId == other.accountId &&
            name == other.name &&
            kind == other.kind &&
            level == other.level &&
            xp == other.xp &&
            createdAt == other.createdAt &&
            lastPlayedAt == other.lastPlayedAt;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      id,
      accountId,
      name,
      kind,
      level,
      xp,
      createdAt,
      lastPlayedAt,
    ]);
  }

  @override
  String toString() {
    return 'PlayerCharacter(id: $id, accountId: $accountId, name: $name, kind: $kind, level: $level, xp: $xp, createdAt: $createdAt, lastPlayedAt: $lastPlayedAt)';
  }

  PlayerCharacter copyWith({
    Int64? id,
    Int64? accountId,
    String? name,
    String? kind,
    int? level,
    Int64? xp,
    Int64? createdAt,
    Int64? lastPlayedAt,
  }) {
    return PlayerCharacter(
      id: id ?? this.id,
      accountId: accountId ?? this.accountId,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      level: level ?? this.level,
      xp: xp ?? this.xp,
      createdAt: createdAt ?? this.createdAt,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
    );
  }
}

class PlayerCharacterDecoder extends RowDecoder<PlayerCharacter> {
  @override
  PlayerCharacter decode(BsatnDecoder decoder) {
    return PlayerCharacter.decodeBsatn(decoder);
  }

  @override
  Int64? getPrimaryKey(PlayerCharacter row) {
    return row.id;
  }

  @override
  Map<String, dynamic>? toJson(PlayerCharacter row) {
    return row.toJson();
  }

  @override
  PlayerCharacter? fromJson(Map<String, dynamic> json) {
    return PlayerCharacter.fromJson(json);
  }

  @override
  bool get supportsJsonSerialization {
    return true;
  }
}
