// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:spacetimedb_sdk/codegen.dart';

class PartyInvite {
  PartyInvite({
    required this.id,
    required this.partyId,
    required this.fromCharacterId,
    required this.fromName,
    required this.toCharacterId,
    required this.createdAt,
    required this.expiresAt,
  });

  factory PartyInvite.fromJson(Map<String, dynamic> json) {
    return PartyInvite(
      id: Int64(json['id'] ?? 0),
      partyId: Int64(json['partyId'] ?? 0),
      fromCharacterId: Int64(json['fromCharacterId'] ?? 0),
      fromName: json['fromName'] ?? '',
      toCharacterId: Int64(json['toCharacterId'] ?? 0),
      createdAt: Int64(json['createdAt'] ?? 0),
      expiresAt: Int64(json['expiresAt'] ?? 0),
    );
  }

  final Int64 id;

  final Int64 partyId;

  final Int64 fromCharacterId;

  final String fromName;

  final Int64 toCharacterId;

  final Int64 createdAt;

  final Int64 expiresAt;

  void encodeBsatn(BsatnEncoder encoder) {
    encoder.writeU64(id);
    encoder.writeU64(partyId);
    encoder.writeU64(fromCharacterId);
    encoder.writeString(fromName);
    encoder.writeU64(toCharacterId);
    encoder.writeI64(createdAt);
    encoder.writeI64(expiresAt);
  }

  static PartyInvite decodeBsatn(BsatnDecoder decoder) {
    return PartyInvite(
      id: decoder.readU64(),
      partyId: decoder.readU64(),
      fromCharacterId: decoder.readU64(),
      fromName: decoder.readString(),
      toCharacterId: decoder.readU64(),
      createdAt: decoder.readI64(),
      expiresAt: decoder.readI64(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id.toInt(),
      'partyId': partyId.toInt(),
      'fromCharacterId': fromCharacterId.toInt(),
      'fromName': fromName,
      'toCharacterId': toCharacterId.toInt(),
      'createdAt': createdAt.toInt(),
      'expiresAt': expiresAt.toInt(),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PartyInvite &&
            id == other.id &&
            partyId == other.partyId &&
            fromCharacterId == other.fromCharacterId &&
            fromName == other.fromName &&
            toCharacterId == other.toCharacterId &&
            createdAt == other.createdAt &&
            expiresAt == other.expiresAt;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      id,
      partyId,
      fromCharacterId,
      fromName,
      toCharacterId,
      createdAt,
      expiresAt,
    ]);
  }

  @override
  String toString() {
    return 'PartyInvite(id: $id, partyId: $partyId, fromCharacterId: $fromCharacterId, fromName: $fromName, toCharacterId: $toCharacterId, createdAt: $createdAt, expiresAt: $expiresAt)';
  }

  PartyInvite copyWith({
    Int64? id,
    Int64? partyId,
    Int64? fromCharacterId,
    String? fromName,
    Int64? toCharacterId,
    Int64? createdAt,
    Int64? expiresAt,
  }) {
    return PartyInvite(
      id: id ?? this.id,
      partyId: partyId ?? this.partyId,
      fromCharacterId: fromCharacterId ?? this.fromCharacterId,
      fromName: fromName ?? this.fromName,
      toCharacterId: toCharacterId ?? this.toCharacterId,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }
}

class PartyInviteDecoder extends RowDecoder<PartyInvite> {
  @override
  PartyInvite decode(BsatnDecoder decoder) {
    return PartyInvite.decodeBsatn(decoder);
  }

  @override
  Int64? getPrimaryKey(PartyInvite row) {
    return row.id;
  }

  @override
  Map<String, dynamic>? toJson(PartyInvite row) {
    return row.toJson();
  }

  @override
  PartyInvite? fromJson(Map<String, dynamic> json) {
    return PartyInvite.fromJson(json);
  }

  @override
  bool get supportsJsonSerialization {
    return true;
  }
}
