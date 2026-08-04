// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:spacetimedb_sdk/codegen.dart';

class LeaderboardEntry {
  LeaderboardEntry({
    required this.rank,
    required this.characterId,
    required this.name,
    required this.kind,
    required this.level,
    required this.xp,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      rank: json['rank'] ?? 0,
      characterId: Int64(json['characterId'] ?? 0),
      name: json['name'] ?? '',
      kind: json['kind'] ?? '',
      level: json['level'] ?? 0,
      xp: Int64(json['xp'] ?? 0),
    );
  }

  final int rank;

  final Int64 characterId;

  final String name;

  final String kind;

  final int level;

  final Int64 xp;

  void encodeBsatn(BsatnEncoder encoder) {
    encoder.writeU32(rank);
    encoder.writeU64(characterId);
    encoder.writeString(name);
    encoder.writeString(kind);
    encoder.writeU32(level);
    encoder.writeU64(xp);
  }

  static LeaderboardEntry decodeBsatn(BsatnDecoder decoder) {
    return LeaderboardEntry(
      rank: decoder.readU32(),
      characterId: decoder.readU64(),
      name: decoder.readString(),
      kind: decoder.readString(),
      level: decoder.readU32(),
      xp: decoder.readU64(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rank': rank,
      'characterId': characterId.toInt(),
      'name': name,
      'kind': kind,
      'level': level,
      'xp': xp.toInt(),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is LeaderboardEntry &&
            rank == other.rank &&
            characterId == other.characterId &&
            name == other.name &&
            kind == other.kind &&
            level == other.level &&
            xp == other.xp;
  }

  @override
  int get hashCode {
    return Object.hashAll([rank, characterId, name, kind, level, xp]);
  }

  @override
  String toString() {
    return 'LeaderboardEntry(rank: $rank, characterId: $characterId, name: $name, kind: $kind, level: $level, xp: $xp)';
  }

  LeaderboardEntry copyWith({
    int? rank,
    Int64? characterId,
    String? name,
    String? kind,
    int? level,
    Int64? xp,
  }) {
    return LeaderboardEntry(
      rank: rank ?? this.rank,
      characterId: characterId ?? this.characterId,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      level: level ?? this.level,
      xp: xp ?? this.xp,
    );
  }
}

class LeaderboardEntryDecoder extends RowDecoder<LeaderboardEntry> {
  @override
  LeaderboardEntry decode(BsatnDecoder decoder) {
    return LeaderboardEntry.decodeBsatn(decoder);
  }

  @override
  Int64? getPrimaryKey(LeaderboardEntry row) {
    return row.characterId;
  }

  @override
  Map<String, dynamic>? toJson(LeaderboardEntry row) {
    return row.toJson();
  }

  @override
  LeaderboardEntry? fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry.fromJson(json);
  }

  @override
  bool get supportsJsonSerialization {
    return true;
  }
}
