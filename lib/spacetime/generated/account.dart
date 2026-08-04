// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:spacetimedb_sdk/codegen.dart';

class Account {
  Account({
    required this.id,
    required this.email,
    required this.createdAt,
    required this.lastLoginAt,
  });

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: Int64(json['id'] ?? 0),
      email: json['email'] ?? '',
      createdAt: Int64(json['createdAt'] ?? 0),
      lastLoginAt: Int64(json['lastLoginAt'] ?? 0),
    );
  }

  final Int64 id;

  final String email;

  final Int64 createdAt;

  final Int64 lastLoginAt;

  void encodeBsatn(BsatnEncoder encoder) {
    encoder.writeU64(id);
    encoder.writeString(email);
    encoder.writeI64(createdAt);
    encoder.writeI64(lastLoginAt);
  }

  static Account decodeBsatn(BsatnDecoder decoder) {
    return Account(
      id: decoder.readU64(),
      email: decoder.readString(),
      createdAt: decoder.readI64(),
      lastLoginAt: decoder.readI64(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id.toInt(),
      'email': email,
      'createdAt': createdAt.toInt(),
      'lastLoginAt': lastLoginAt.toInt(),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Account &&
            id == other.id &&
            email == other.email &&
            createdAt == other.createdAt &&
            lastLoginAt == other.lastLoginAt;
  }

  @override
  int get hashCode {
    return Object.hashAll([id, email, createdAt, lastLoginAt]);
  }

  @override
  String toString() {
    return 'Account(id: $id, email: $email, createdAt: $createdAt, lastLoginAt: $lastLoginAt)';
  }

  Account copyWith({
    Int64? id,
    String? email,
    Int64? createdAt,
    Int64? lastLoginAt,
  }) {
    return Account(
      id: id ?? this.id,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }
}

class AccountDecoder extends RowDecoder<Account> {
  @override
  Account decode(BsatnDecoder decoder) {
    return Account.decodeBsatn(decoder);
  }

  @override
  Int64? getPrimaryKey(Account row) {
    return row.id;
  }

  @override
  Map<String, dynamic>? toJson(Account row) {
    return row.toJson();
  }

  @override
  Account? fromJson(Map<String, dynamic> json) {
    return Account.fromJson(json);
  }

  @override
  bool get supportsJsonSerialization {
    return true;
  }
}
