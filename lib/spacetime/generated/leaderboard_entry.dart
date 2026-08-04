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
    required this.totalXp,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      rank: json['rank'] ?? 0,
      characterId: Int64(json['characterId'] ?? 0),
      name: json['name'] ?? '',
      kind: json['kind'] ?? '',
      level: json['level'] ?? 0,
      xp: json['xp'] ?? 0,
      totalXp: json['totalXp'] ?? 0,
    );
  }

  final int rank;

  final Int64 characterId;

  final String name;

  final String kind;

  final int level;

  final int xp;

  final int totalXp;

  void encodeBsatn(BsatnEncoder encoder) {
    encoder.writeU32(rank);
    encoder.writeU64(characterId);
    encoder.writeString(name);
    encoder.writeString(kind);
    encoder.writeU32(level);
    encoder.writeU32(xp);
    encoder.writeU32(totalXp);
  }

  static LeaderboardEntry decodeBsatn(BsatnDecoder decoder) {
    return LeaderboardEntry(
      rank: decoder.readU32(),
      characterId: decoder.readU64(),
      name: decoder.readString(),
      kind: decoder.readString(),
      level: decoder.readU32(),
      xp: decoder.readU32(),
      totalXp: decoder.readU32(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rank': rank,
      'characterId': characterId.toInt(),
      'name': name,
      'kind': kind,
      'level': level,
      'xp': xp,
      'totalXp': totalXp,
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
            xp == other.xp &&
            totalXp == other.totalXp;
  }

  @override
  int get hashCode {
    return Object.hashAll([rank, characterId, name, kind, level, xp, totalXp]);
  }

  @override
  String toString() {
    return 'LeaderboardEntry(rank: $rank, characterId: $characterId, name: $name, kind: $kind, level: $level, xp: $xp, totalXp: $totalXp)';
  }

  LeaderboardEntry copyWith({
    int? rank,
    Int64? characterId,
    String? name,
    String? kind,
    int? level,
    int? xp,
    int? totalXp,
  }) {
    return LeaderboardEntry(
      rank: rank ?? this.rank,
      characterId: characterId ?? this.characterId,
      name: name ?? this.name,
      kind: kind ?? this.kind,
      level: level ?? this.level,
      xp: xp ?? this.xp,
      totalXp: totalXp ?? this.totalXp,
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
