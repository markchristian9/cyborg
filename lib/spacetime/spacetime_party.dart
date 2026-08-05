import 'package:flutter/foundation.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart';

import '../game/net/party_session.dart';
import 'cyborg_connection.dart';
import 'generated/client.dart';
import 'generated/party.dart' as gen;
import 'generated/party_invite.dart' as gen;
import 'generated/party_member.dart' as gen;

/// SpacetimeDB 의 파티 표로 멤버십을 주고받는 구현.
///
/// [SpacetimeWorldPresence] 와 같은 모양으로 만들었다 — 구독을 열고 닫는 방식,
/// 세대 번호로 늦게 도착한 응답을 막는 방식이 같다. 두 창구가 같은 규칙으로
/// 움직여야 한쪽만 이상하게 도는 상태가 생기지 않는다.
///
/// **좌표와 체력은 여기로 오지 않는다.** 서버의 파티 view 는 멤버십만 싣고,
/// 화면에 필요한 위치·생사는 이미 구독 중인 `world_player` 에서 온다. 파티 목록이
/// 좌표를 담았다면 누가 한 걸음 옮길 때마다 목록 전체가 파티원 전원에게 다시
/// 밀려왔을 것이다.
class SpacetimePartySession extends PartySession {
  SpacetimePartySession(this._client);

  final SpacetimeDbClient _client;

  int? _querySetId;
  bool _subscribing = false;

  /// 열고 닫을 때마다 오르는 번호. 늦게 도착한 구독 완료가 이미 떠난 화면에
  /// 남지 않도록 막는다.
  int _generation = 0;

  ValueListenable<List<gen.PartyMember>> get _memberRows =>
      _client.myPartyMembers.rows;

  ValueListenable<List<gen.PartyInvite>> get _inviteRows =>
      _client.myPartyInvites.rows;

  @override
  bool get isAvailable => _querySetId != null;

  /// 파티·멤버·초대 중 어느 하나라도 바뀌면 화면을 다시 맞춘다.
  ///
  /// **`my_party` 를 빼면 안 된다.** 예전에는 "파티가 생기거나 사라지면 멤버
  /// 목록도 함께 바뀐다" 는 이유로 뺐는데, 이끌기 상태가 `Party` 행에만 있으므로
  /// 그 전제가 깨졌다 — 누가 이끌기를 시작해도 멤버 행은 그대로다.
  @override
  Listenable get changes =>
      Listenable.merge([_partyRows, _memberRows, _inviteRows]);

  ValueListenable<List<gen.Party>> get _partyRows => _client.party.rows;

  @override
  Future<void> attach() async {
    final generation = ++_generation;
    if (_querySetId != null || _subscribing) return;

    _subscribing = true;
    try {
      final id = await _client.subscriptions.subscribe(kPartySubscriptions);
      if (generation != _generation) {
        _client.subscriptions.unsubscribe(id);
        return;
      }
      _querySetId = id;
    } on SpacetimeDbException {
      // 연결이 끊겼다. 파티 없이도 게임은 그대로 돌아간다.
    } finally {
      _subscribing = false;
    }
  }

  @override
  void detach() {
    // 구독만 닫는다. 파티에서 빠지는 것은 `leave_world`·`on_disconnect` 가 서버에서
    // 처리하므로 여기서 탈퇴를 따로 부르면 같은 일을 두 번 하는 셈이다.
    _generation++;
    final id = _querySetId;
    if (id != null) {
      _querySetId = null;
      _client.subscriptions.unsubscribe(id);
    }
  }

  @override
  int? get selfCharacterId => _client.mySession?.selectedCharacterId?.toInt();

  gen.Party? get _party => _client.myParty;

  @override
  bool get inParty => _party != null;

  @override
  int? get leaderCharacterId => _party?.leaderCharacterId.toInt();

  @override
  int? get huntLeadCharacterId => _party?.huntLeadCharacterId?.toInt();

  @override
  int get huntLeadSeq => _party?.huntLeadSeq.toInt() ?? 0;

  @override
  List<PartyMemberInfo> get members {
    final leader = leaderCharacterId;
    return [
      for (final row in _memberRows.value)
        PartyMemberInfo(
          characterId: row.characterId.toInt(),
          isLeader: leader != null && row.characterId.toInt() == leader,
          followingCharacterId: row.followingCharacterId?.toInt(),
        ),
    ];
  }

  @override
  List<PartyInviteInfo> get invites => [
        for (final row in _inviteRows.value)
          PartyInviteInfo(
            id: row.id.toInt(),
            fromCharacterId: row.fromCharacterId.toInt(),
            fromName: row.fromName,
            expiresAt: _timestampToDate(row.expiresAt),
          ),
      ];

  @override
  Future<void> invite(int targetCharacterId) =>
      _call(() => _client.reducers.inviteToParty(
            targetCharacterId: Int64(targetCharacterId),
          ));

  @override
  Future<void> accept(int inviteId) =>
      _call(() => _client.reducers.acceptInvite(inviteId: Int64(inviteId)));

  @override
  Future<void> decline(int inviteId) =>
      _call(() => _client.reducers.declineInvite(inviteId: Int64(inviteId)));

  @override
  Future<void> leave() => _call(() => _client.reducers.leaveParty());

  @override
  Future<void> setFollowing(bool following) =>
      _call(() => _client.reducers.setFollowing(following: following));

  @override
  Future<void> startHuntLead() =>
      _call(() => _client.reducers.startHuntLead());

  @override
  Future<void> stopHuntLead() => _call(() => _client.reducers.stopHuntLead());

  @override
  Future<void> acceptHuntLead(int leadSeq) =>
      _call(() => _client.reducers.acceptHuntLead(leadSeq: Int64(leadSeq)));

  @override
  Future<void> inviteNearby() => _call(() => _client.reducers.inviteNearby());

  @override
  Future<void> disband() => _call(() => _client.reducers.disbandParty());

  @override
  Future<void> kick(int targetCharacterId) =>
      _call(() => _client.reducers.kickMember(
            targetCharacterId: Int64(targetCharacterId),
          ));

  @override
  Future<void> promote(int targetCharacterId) =>
      _call(() => _client.reducers.promoteLeader(
            targetCharacterId: Int64(targetCharacterId),
          ));

  /// reducer 를 부르고 거절 사유를 그대로 올려 보낸다.
  ///
  /// 삼키지 않는 이유는 파티의 실패가 **사람에게 설명되어야 하는 실패**이기
  /// 때문이다. "상대가 이미 다른 파티에 있다" 같은 사유를 서버가 문장으로 주는데,
  /// 여기서 지워 버리면 화면은 아무 일도 일어나지 않은 것처럼 보인다. 좌표 보고와
  /// 다른 점이 이것이다 — 그쪽은 다음 주기가 따라잡지만 초대는 그렇지 않다.
  Future<void> _call(Future<TransactionResult> Function() reducer) async {
    await reducer();
  }

  /// 서버 시각(마이크로초)을 [DateTime] 으로 옮긴다.
  static DateTime _timestampToDate(Int64 micros) =>
      DateTime.fromMicrosecondsSinceEpoch(micros.toInt(), isUtc: true);
}
