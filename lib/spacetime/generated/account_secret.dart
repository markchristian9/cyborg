// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:spacetimedb_sdk/codegen.dart';

class AccountSecret {
  AccountSecret({
    required this.accountId,
    required this.passwordHash,
    required this.passwordSalt,
  });

  factory AccountSecret.fromJson(Map<String, dynamic> json) {
    return AccountSecret(
      accountId: Int64(json['accountId'] ?? 0),
      passwordHash: json['passwordHash'] ?? '',
      passwordSalt: json['passwordSalt'] ?? '',
    );
  }

  final Int64 accountId;

  final String passwordHash;

  final String passwordSalt;

  void encodeBsatn(BsatnEncoder encoder) {
    encoder.writeU64(accountId);
    encoder.writeString(passwordHash);
    encoder.writeString(passwordSalt);
  }

  static AccountSecret decodeBsatn(BsatnDecoder decoder) {
    return AccountSecret(
      accountId: decoder.readU64(),
      passwordHash: decoder.readString(),
      passwordSalt: decoder.readString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accountId': accountId.toInt(),
      'passwordHash': passwordHash,
      'passwordSalt': passwordSalt,
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AccountSecret &&
            accountId == other.accountId &&
            passwordHash == other.passwordHash &&
            passwordSalt == other.passwordSalt;
  }

  @override
  int get hashCode {
    return Object.hashAll([accountId, passwordHash, passwordSalt]);
  }

  @override
  String toString() {
    return 'AccountSecret(accountId: $accountId, passwordHash: $passwordHash, passwordSalt: $passwordSalt)';
  }

  AccountSecret copyWith({
    Int64? accountId,
    String? passwordHash,
    String? passwordSalt,
  }) {
    return AccountSecret(
      accountId: accountId ?? this.accountId,
      passwordHash: passwordHash ?? this.passwordHash,
      passwordSalt: passwordSalt ?? this.passwordSalt,
    );
  }
}

class AccountSecretDecoder extends RowDecoder<AccountSecret> {
  @override
  AccountSecret decode(BsatnDecoder decoder) {
    return AccountSecret.decodeBsatn(decoder);
  }

  @override
  Int64? getPrimaryKey(AccountSecret row) {
    return row.accountId;
  }

  @override
  Map<String, dynamic>? toJson(AccountSecret row) {
    return row.toJson();
  }

  @override
  AccountSecret? fromJson(Map<String, dynamic> json) {
    return AccountSecret.fromJson(json);
  }

  @override
  bool get supportsJsonSerialization {
    return true;
  }
}
