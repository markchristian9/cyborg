import 'package:actionrpg/game/net/party_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 서버 없이 파티 상태만 흉내 낸다.
///
/// [PartySession] 이 abstract 이고 모든 것에 기본 구현이 있어 상속만으로 된다 —
/// 서버 구현이나 SpacetimeDB 를 한 줄도 건드리지 않고 파생 규칙을 검사할 수 있다.
class _FakeParty extends PartySession {
  _FakeParty({
    this.selfId,
    this.leaderId,
    this.huntLeadId,
    this.seq = 0,
    this.memberList = const [],
    this.inviteList = const [],
  });

  final int? selfId;
  final int? leaderId;
  final int? huntLeadId;
  final int seq;

  // 이름이 `members`·`invites` 가 아닌 것은 그쪽을 getter 로 덮어써야 하기
  // 때문이다. 필드와 getter 가 같은 이름일 수는 없다.
  final List<PartyMemberInfo> memberList;
  final List<PartyInviteInfo> inviteList;

  @override
  int? get selfCharacterId => selfId;

  @override
  int? get leaderCharacterId => leaderId;

  @override
  bool get inParty => leaderId != null;

  @override
  List<PartyMemberInfo> get members => memberList;

  @override
  List<PartyInviteInfo> get invites => inviteList;

  @override
  int? get huntLeadCharacterId => huntLeadId;

  @override
  int get huntLeadSeq => seq;

  @override
  Listenable get changes => Listenable.merge(const []);
}

PartyMemberInfo _member(int id, {bool leader = false, int? following}) =>
    PartyMemberInfo(
      characterId: id,
      isLeader: leader,
      followingCharacterId: following,
    );

void main() {
  group('파티 — 내가 누구인가', () {
    test('파티장 번호가 내 번호와 같으면 내가 파티장이다', () {
      final party = _FakeParty(selfId: 5, leaderId: 5);
      expect(party.isLeader, isTrue);
    });

    test('파티장이 남이면 나는 파티장이 아니다', () {
      final party = _FakeParty(selfId: 5, leaderId: 9);
      expect(party.isLeader, isFalse);
    });

    test('캐릭터를 고르지 않았으면 파티장일 수 없다', () {
      // 둘 다 null 이라고 "같다" 로 읽으면 아무도 아닌 상태가 파티장이 된다.
      final party = _FakeParty(selfId: null, leaderId: null);
      expect(party.isLeader, isFalse);
    });
  });

  group('파티 — 내가 따라가고 있는가', () {
    test('내 줄의 추종 상태를 읽는다', () {
      final party = _FakeParty(
        selfId: 5,
        leaderId: 9,
        memberList: [_member(9, leader: true), _member(5, following: 9)],
      );
      expect(party.isFollowing, isTrue);
    });

    test('남이 따라가는 것은 내 상태가 아니다', () {
      final party = _FakeParty(
        selfId: 5,
        leaderId: 9,
        memberList: [_member(9, leader: true), _member(7, following: 9), _member(5)],
      );
      expect(party.isFollowing, isFalse);
    });

    test('목록에 내가 없으면 따라가는 중이 아니다', () {
      final party = _FakeParty(
        selfId: 5,
        leaderId: 9,
        memberList: [_member(9, leader: true)],
      );
      expect(party.isFollowing, isFalse);
    });
  });

  group('파티 — 파티장과 이끄는 사람은 다른 축이다', () {
    test('파티장이 아니어도 이끌 수 있다', () {
      final party = _FakeParty(selfId: 5, leaderId: 9, huntLeadId: 5);
      expect(party.isLeader, isFalse, reason: '파티를 만든 사람은 9 다');
      expect(party.isHuntLeading, isTrue, reason: '앞장서는 사람은 5 다');
    });

    test('파티장이면서 남을 따라갈 수 있다', () {
      final party = _FakeParty(
        selfId: 9,
        leaderId: 9,
        huntLeadId: 5,
        memberList: [_member(9, leader: true, following: 5), _member(5)],
      );
      expect(party.isLeader, isTrue);
      expect(party.isHuntLeading, isFalse);
      expect(party.isFollowing, isTrue);
    });

    test('아무도 이끌지 않으면 참여할 것도 없다', () {
      final party = _FakeParty(selfId: 5, leaderId: 9);
      expect(party.hasHuntLead, isFalse);
      expect(party.canJoinHuntLead, isFalse);
    });

    test('남이 이끌고 내가 안 따라가면 참여할 수 있다', () {
      final party = _FakeParty(
        selfId: 5,
        leaderId: 9,
        huntLeadId: 9,
        memberList: [_member(9, leader: true), _member(5)],
      );
      expect(party.canJoinHuntLead, isTrue);
    });

    test('이미 따라가는 중이면 참여 버튼은 필요 없다', () {
      final party = _FakeParty(
        selfId: 5,
        leaderId: 9,
        huntLeadId: 9,
        memberList: [_member(9, leader: true), _member(5, following: 9)],
      );
      expect(party.canJoinHuntLead, isFalse);
    });

    test('내가 이끄는 중이면 내 이끌기에 참여하지 않는다', () {
      final party = _FakeParty(
        selfId: 5,
        leaderId: 9,
        huntLeadId: 5,
        memberList: [_member(9, leader: true), _member(5)],
      );
      expect(party.canJoinHuntLead, isFalse);
    });
  });

  group('파티 — 정원', () {
    test('서버와 같은 열두 명이다', () {
      // 이 값이 서버 `MAX_PARTY_SIZE` 와 어긋나면 화면과 서버가 다른 답을 낸다.
      expect(kMaxPartySize, 12);
    });

    test('정원을 채우면 자리가 없다', () {
      final party = _FakeParty(
        selfId: 1,
        leaderId: 1,
        memberList: [for (var i = 0; i < kMaxPartySize; i++) _member(i)],
      );
      expect(party.isFull, isTrue);
    });

    test('한 자리가 비면 아직 받을 수 있다', () {
      final party = _FakeParty(
        selfId: 1,
        leaderId: 1,
        memberList: [for (var i = 0; i < kMaxPartySize - 1; i++) _member(i)],
      );
      expect(party.isFull, isFalse);
    });
  });

  group('초대 — 만료', () {
    final expires = DateTime.utc(2026, 8, 5, 12, 0, 20);

    PartyInviteInfo invite() => PartyInviteInfo(
          id: 1,
          fromCharacterId: 3,
          fromName: '앨리스',
          expiresAt: expires,
        );

    test('만료 전에는 살아 있다', () {
      expect(invite().isExpiredAt(DateTime.utc(2026, 8, 5, 12, 0, 19)), isFalse);
    });

    test('만료 시각에 닿으면 끝난 것으로 본다', () {
      // 경계를 "지나야" 만료로 치면 그 순간의 초대가 수락 가능해 보이는데,
      // 서버는 이미 거절한다.
      expect(invite().isExpiredAt(expires), isTrue);
    });

    test('만료 뒤에는 끝난 것이다', () {
      expect(invite().isExpiredAt(DateTime.utc(2026, 8, 5, 12, 0, 21)), isTrue);
    });
  });

  group('파티 — 서버가 없을 때', () {
    test('파티가 없는 것과 같은 모습이다', () {
      const party = OfflinePartySession();
      expect(party.inParty, isFalse);
      expect(party.members, isEmpty);
      expect(party.invites, isEmpty);
      expect(party.isFollowing, isFalse);
      expect(party.isLeader, isFalse);
      expect(party.isAvailable, isFalse);
    });

    test('아무 요청이나 불러도 터지지 않는다', () async {
      const party = OfflinePartySession();
      await party.attach();
      await party.invite(1);
      await party.accept(1);
      await party.decline(1);
      await party.leave();
      await party.disband();
      await party.kick(1);
      await party.promote(1);
      await party.setFollowing(true);
      party.detach();
    });
  });
}
