// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:spacetimedb_sdk/codegen.dart';

class Party {
  Party({
    required this.id,
    required this.leaderCharacterId,
    required this.createdAt,
    required this.huntLeadCharacterId,
    required this.huntLeadSeq,
  });

  factory Party.fromJson(Map<String, dynamic> json) {
    return Party(
      id: Int64(json['id'] ?? 0),
      leaderCharacterId: Int64(json['leaderCharacterId'] ?? 0),
      createdAt: Int64(json['createdAt'] ?? 0),
      huntLeadCharacterId: json['huntLeadCharacterId'] == null
          ? null
          : Int64(json['huntLeadCharacterId']),
      huntLeadSeq: Int64(json['huntLeadSeq'] ?? 0),
    );
  }

  final Int64 id;

  final Int64 leaderCharacterId;

  final Int64 createdAt;

  final Int64? huntLeadCharacterId;

  final Int64 huntLeadSeq;

  void encodeBsatn(BsatnEncoder encoder) {
    encoder.writeU64(id);
    encoder.writeU64(leaderCharacterId);
    encoder.writeI64(createdAt);
    encoder.writeOption<Int64>(
      huntLeadCharacterId,
      (value) => encoder.writeU64(value),
    );
    encoder.writeU64(huntLeadSeq);
  }

  static Party decodeBsatn(BsatnDecoder decoder) {
    return Party(
      id: decoder.readU64(),
      leaderCharacterId: decoder.readU64(),
      createdAt: decoder.readI64(),
      huntLeadCharacterId: decoder.readOption<Int64>(() => decoder.readU64()),
      huntLeadSeq: decoder.readU64(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id.toInt(),
      'leaderCharacterId': leaderCharacterId.toInt(),
      'createdAt': createdAt.toInt(),
      'huntLeadCharacterId': huntLeadCharacterId?.toInt(),
      'huntLeadSeq': huntLeadSeq.toInt(),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Party &&
            id == other.id &&
            leaderCharacterId == other.leaderCharacterId &&
            createdAt == other.createdAt &&
            huntLeadCharacterId == other.huntLeadCharacterId &&
            huntLeadSeq == other.huntLeadSeq;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      id,
      leaderCharacterId,
      createdAt,
      huntLeadCharacterId,
      huntLeadSeq,
    ]);
  }

  @override
  String toString() {
    return 'Party(id: $id, leaderCharacterId: $leaderCharacterId, createdAt: $createdAt, huntLeadCharacterId: $huntLeadCharacterId, huntLeadSeq: $huntLeadSeq)';
  }

  Party copyWith({
    Int64? id,
    Int64? leaderCharacterId,
    Int64? createdAt,
    Int64? huntLeadCharacterId,
    Int64? huntLeadSeq,
  }) {
    return Party(
      id: id ?? this.id,
      leaderCharacterId: leaderCharacterId ?? this.leaderCharacterId,
      createdAt: createdAt ?? this.createdAt,
      huntLeadCharacterId: huntLeadCharacterId ?? this.huntLeadCharacterId,
      huntLeadSeq: huntLeadSeq ?? this.huntLeadSeq,
    );
  }
}

class PartyDecoder extends RowDecoder<Party> {
  @override
  Party decode(BsatnDecoder decoder) {
    return Party.decodeBsatn(decoder);
  }

  @override
  Int64? getPrimaryKey(Party row) {
    return row.id;
  }

  @override
  Map<String, dynamic>? toJson(Party row) {
    return row.toJson();
  }

  @override
  Party? fromJson(Map<String, dynamic> json) {
    return Party.fromJson(json);
  }

  @override
  bool get supportsJsonSerialization {
    return true;
  }
}
