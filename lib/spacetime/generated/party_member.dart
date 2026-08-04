// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:spacetimedb_sdk/codegen.dart';

class PartyMember {
  PartyMember({
    required this.characterId,
    required this.partyId,
    required this.joinedAt,
    required this.followingCharacterId,
  });

  factory PartyMember.fromJson(Map<String, dynamic> json) {
    return PartyMember(
      characterId: Int64(json['characterId'] ?? 0),
      partyId: Int64(json['partyId'] ?? 0),
      joinedAt: Int64(json['joinedAt'] ?? 0),
      followingCharacterId: json['followingCharacterId'] == null
          ? null
          : Int64(json['followingCharacterId']),
    );
  }

  final Int64 characterId;

  final Int64 partyId;

  final Int64 joinedAt;

  final Int64? followingCharacterId;

  void encodeBsatn(BsatnEncoder encoder) {
    encoder.writeU64(characterId);
    encoder.writeU64(partyId);
    encoder.writeI64(joinedAt);
    encoder.writeOption<Int64>(
      followingCharacterId,
      (value) => encoder.writeU64(value),
    );
  }

  static PartyMember decodeBsatn(BsatnDecoder decoder) {
    return PartyMember(
      characterId: decoder.readU64(),
      partyId: decoder.readU64(),
      joinedAt: decoder.readI64(),
      followingCharacterId: decoder.readOption<Int64>(() => decoder.readU64()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'characterId': characterId.toInt(),
      'partyId': partyId.toInt(),
      'joinedAt': joinedAt.toInt(),
      'followingCharacterId': followingCharacterId?.toInt(),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PartyMember &&
            characterId == other.characterId &&
            partyId == other.partyId &&
            joinedAt == other.joinedAt &&
            followingCharacterId == other.followingCharacterId;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      characterId,
      partyId,
      joinedAt,
      followingCharacterId,
    ]);
  }

  @override
  String toString() {
    return 'PartyMember(characterId: $characterId, partyId: $partyId, joinedAt: $joinedAt, followingCharacterId: $followingCharacterId)';
  }

  PartyMember copyWith({
    Int64? characterId,
    Int64? partyId,
    Int64? joinedAt,
    Int64? followingCharacterId,
  }) {
    return PartyMember(
      characterId: characterId ?? this.characterId,
      partyId: partyId ?? this.partyId,
      joinedAt: joinedAt ?? this.joinedAt,
      followingCharacterId: followingCharacterId ?? this.followingCharacterId,
    );
  }
}

class PartyMemberDecoder extends RowDecoder<PartyMember> {
  @override
  PartyMember decode(BsatnDecoder decoder) {
    return PartyMember.decodeBsatn(decoder);
  }

  @override
  Int64? getPrimaryKey(PartyMember row) {
    return row.characterId;
  }

  @override
  Map<String, dynamic>? toJson(PartyMember row) {
    return row.toJson();
  }

  @override
  PartyMember? fromJson(Map<String, dynamic> json) {
    return PartyMember.fromJson(json);
  }

  @override
  bool get supportsJsonSerialization {
    return true;
  }
}
