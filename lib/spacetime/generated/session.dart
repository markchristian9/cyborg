// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:spacetimedb_sdk/codegen.dart';

class Session {
  Session({
    required this.identity,
    required this.accountId,
    required this.selectedCharacterId,
    required this.loggedInAt,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      identity: Identity.fromJson(json['identity'] ?? ''),
      accountId: Int64(json['accountId'] ?? 0),
      selectedCharacterId: json['selectedCharacterId'] == null
          ? null
          : Int64(json['selectedCharacterId']),
      loggedInAt: Int64(json['loggedInAt'] ?? 0),
    );
  }

  final Identity identity;

  final Int64 accountId;

  final Int64? selectedCharacterId;

  final Int64 loggedInAt;

  void encodeBsatn(BsatnEncoder encoder) {
    encoder.writeIdentity(identity);
    encoder.writeU64(accountId);
    encoder.writeOption<Int64>(
      selectedCharacterId,
      (value) => encoder.writeU64(value),
    );
    encoder.writeI64(loggedInAt);
  }

  static Session decodeBsatn(BsatnDecoder decoder) {
    return Session(
      identity: decoder.readIdentity(),
      accountId: decoder.readU64(),
      selectedCharacterId: decoder.readOption<Int64>(() => decoder.readU64()),
      loggedInAt: decoder.readI64(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'identity': identity.toJson(),
      'accountId': accountId.toInt(),
      'selectedCharacterId': selectedCharacterId?.toInt(),
      'loggedInAt': loggedInAt.toInt(),
    };
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Session &&
            identity == other.identity &&
            accountId == other.accountId &&
            selectedCharacterId == other.selectedCharacterId &&
            loggedInAt == other.loggedInAt;
  }

  @override
  int get hashCode {
    return Object.hashAll([
      identity,
      accountId,
      selectedCharacterId,
      loggedInAt,
    ]);
  }

  @override
  String toString() {
    return 'Session(identity: $identity, accountId: $accountId, selectedCharacterId: $selectedCharacterId, loggedInAt: $loggedInAt)';
  }

  Session copyWith({
    Identity? identity,
    Int64? accountId,
    Int64? selectedCharacterId,
    Int64? loggedInAt,
  }) {
    return Session(
      identity: identity ?? this.identity,
      accountId: accountId ?? this.accountId,
      selectedCharacterId: selectedCharacterId ?? this.selectedCharacterId,
      loggedInAt: loggedInAt ?? this.loggedInAt,
    );
  }
}

class SessionDecoder extends RowDecoder<Session> {
  @override
  Session decode(BsatnDecoder decoder) {
    return Session.decodeBsatn(decoder);
  }

  @override
  Identity? getPrimaryKey(Session row) {
    return row.identity;
  }

  @override
  Map<String, dynamic>? toJson(Session row) {
    return row.toJson();
  }

  @override
  Session? fromJson(Map<String, dynamic> json) {
    return Session.fromJson(json);
  }

  @override
  bool get supportsJsonSerialization {
    return true;
  }
}
