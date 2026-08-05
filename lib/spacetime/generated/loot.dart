// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:spacetimedb_sdk/codegen.dart';

class Loot {
  Loot({
    required this.id,
    required this.kind,
    required this.amount,
    required this.gridX,
    required this.gridY,
    required this.chunk,
    required this.reservedUntil,
    required this.reservedFor,
    required this.droppedAt,
  });

  factory Loot.fromJson(Map<String, dynamic> json) {
    return Loot(
      id: Int64(json['id'] ?? 0),
      kind: json['kind'] ?? '',
      amount: json['amount'] ?? 0,
      gridX: (json['gridX'] ?? 0.0).toDouble(),
      gridY: (json['gridY'] ?? 0.0).toDouble(),
      chunk: json['chunk'] ?? 0,
      reservedUntil: Int64(json['reservedUntil'] ?? 0),
      reservedFor: json['reservedFor'] == null
          ? null
          : Int64(json['reservedFor']),
      droppedAt: Int64(json['droppedAt'] ?? 0),
    );
  }

  final Int64 id;

  final String kind;

  final int amount;

  final double gridX;

  final double gridY;

  final int chunk;

  final Int64 reservedUntil;

  final Int64? reservedFor;

  final Int64 droppedAt;

  void encodeBsatn(BsatnEncoder encoder) {
    encoder.writeU64(id);
    encoder.writeString(kind);
    encoder.writeU32(amount);
    encoder.writeF32(gridX);
    encoder.writeF32(gridY);
    encoder.writeU32(chunk);
    encoder.writeI64(reservedUntil);
    encoder.writeOption<Int64>(reservedFor, (value) => encoder.writeU64(value));
    encoder.writeI64(droppedAt);
  }

  static Loot decodeBsatn(BsatnDecoder decoder) {
    return Loot(
      id: decoder.readU64(),
      kind: decoder.readString(),
      amount: decoder.readU32(),
      gridX: decoder.readF32(),
      gridY: decoder.readF32(),
      chunk: decoder.readU32(),
      reservedUntil: decoder.readI64(),
      reservedFor: decoder.readOption<Int64>(() => decoder.readU64()),
      droppedAt: decoder.readI64(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id.toInt(),
      'kind': kind,
      'amount': amount,
      'gridX': gridX,
      'gridY': gridY,
      'chunk': chunk,
      'reservedUntil': reservedUntil.toInt(),
      'reservedFor': reservedFor?.toInt(),
      'droppedAt': droppedAt.toInt(),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Loot &&
            id == other.id &&
            kind == other.kind &&
            amount == other.amount &&
            gridX == other.gridX &&
            gridY == other.gridY &&
            chunk == other.chunk &&
            reservedUntil == other.reservedUntil &&
            reservedFor == other.reservedFor &&
            droppedAt == other.droppedAt;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      id,
      kind,
      amount,
      gridX,
      gridY,
      chunk,
      reservedUntil,
      reservedFor,
      droppedAt,
    ]);
  }

  @override
  String toString() {
    return 'Loot(id: $id, kind: $kind, amount: $amount, gridX: $gridX, gridY: $gridY, chunk: $chunk, reservedUntil: $reservedUntil, reservedFor: $reservedFor, droppedAt: $droppedAt)';
  }

  Loot copyWith({
    Int64? id,
    String? kind,
    int? amount,
    double? gridX,
    double? gridY,
    int? chunk,
    Int64? reservedUntil,
    Int64? reservedFor,
    Int64? droppedAt,
  }) {
    return Loot(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      amount: amount ?? this.amount,
      gridX: gridX ?? this.gridX,
      gridY: gridY ?? this.gridY,
      chunk: chunk ?? this.chunk,
      reservedUntil: reservedUntil ?? this.reservedUntil,
      reservedFor: reservedFor ?? this.reservedFor,
      droppedAt: droppedAt ?? this.droppedAt,
    );
  }
}

class LootDecoder extends RowDecoder<Loot> {
  @override
  Loot decode(BsatnDecoder decoder) {
    return Loot.decodeBsatn(decoder);
  }

  @override
  Int64? getPrimaryKey(Loot row) {
    return row.id;
  }

  @override
  Map<String, dynamic>? toJson(Loot row) {
    return row.toJson();
  }

  @override
  Loot? fromJson(Map<String, dynamic> json) {
    return Loot.fromJson(json);
  }

  @override
  bool get supportsJsonSerialization {
    return true;
  }
}
