import 'package:flutter/foundation.dart';

/// 한 파티의 최대 인원.
///
/// **서버 `party.rs` 의 `MAX_PARTY_SIZE` 와 같아야 한다.** 판정은 서버가 하므로
/// 이 값이 크면 화면에서 초대해 놓고 서버에 거절당하고, 작으면 들어갈 수 있는
/// 사람을 화면이 먼저 막는다. 둘 중 무엇도 사용자에게는 고장으로 보인다.
const int kMaxPartySize = 12;

/// 파티에 속한 한 사람.
///
/// 이름도 레벨도 좌표도 없다. **일부러다.** 서버의 파티 view 는 멤버십만 실어
/// 보내고, 화면에 필요한 나머지는 이미 구독 중인 월드 정보에서 `characterId` 로
/// 맞춰 온다([WorldPresence.others]). 파티 목록이 좌표를 담으면 누군가 한 걸음
/// 옮길 때마다 파티원 전원에게 목록 전체가 다시 밀려온다.
class PartyMemberInfo {
  const PartyMemberInfo({
    required this.characterId,
    required this.isLeader,
    this.followingCharacterId,
  });

  /// 캐릭터 식별자. 월드 정보와 맞춰 보는 열쇠다.
  final int characterId;

  /// 이 사람이 파티장인가.
  final bool isLeader;

  /// 이 사람이 따라다니고 있는 상대. 따라가지 않으면 null.
  final int? followingCharacterId;

  bool get isFollowing => followingCharacterId != null;
}

/// 아직 답하지 않은 초대 하나.
class PartyInviteInfo {
  const PartyInviteInfo({
    required this.id,
    required this.fromCharacterId,
    required this.fromName,
    required this.expiresAt,
  });

  /// 수락·거절할 때 그대로 돌려보내는 값.
  ///
  /// "어느 초대인지" 를 못 박기 위해 있다. 거절한 직후 새 초대가 도착하는 사이에
  /// 화면이 예전 것을 누르면, 이 값이 없을 때는 엉뚱한 파티에 들어간다.
  final int id;

  final int fromCharacterId;

  /// 초대한 사람 이름. 서버가 초대 시점에 담아 보낸다.
  final String fromName;

  /// 이 시각이 지나면 서버가 받아 주지 않는다.
  ///
  /// 화면에서 지워야 할 때를 알기 위한 값일 뿐이다. 만료를 실제로 **판정**하는
  /// 것은 서버이므로, 기기 시계를 되돌려도 지난 초대를 되살릴 수는 없다.
  final DateTime expiresAt;

  bool isExpiredAt(DateTime now) => !now.isBefore(expiresAt);
}

/// 파티를 맺고 따라다니겠다는 의사를 서버에 알리는 창구.
///
/// [WorldPresence] 와 같은 모양으로 만들었다 — 게임은 이 인터페이스만 알고 있으므로
/// 서버에 붙지 않아도 그대로 돌아가고, 시험할 때는 상속만으로 가짜를 끼울 수 있다.
///
/// **여기에는 "따라 걷는" 동작이 없다.** 이 창구가 하는 일은 누가 파티원이고 누가
/// 따라가기로 했는지를 주고받는 것뿐이고, 실제로 리더 쪽으로 걸어가 주변을
/// 사냥하는 판단은 [PartyFollowController] 가 한다. 서버에 매 프레임 돌아가는
/// 시뮬레이션이 없어서 그렇다 — 서버는 좌표를 받아 적을 뿐 누구를 어디로 밀어
/// 주지 않는다.
abstract class PartySession {
  const PartySession();

  /// 내가 파티에 속해 있는가.
  bool get inParty => false;

  /// 파티장의 캐릭터 식별자. 파티가 없으면 null.
  int? get leaderCharacterId => null;

  /// 나를 포함한 파티원 전원.
  List<PartyMemberInfo> get members => const [];

  /// 자리가 다 찼는가.
  bool get isFull => members.length >= kMaxPartySize;

  /// 나에게 온 초대.
  List<PartyInviteInfo> get invites => const [];

  /// 내 캐릭터 식별자. 파티에 들어가기 전에는 null 일 수 있다.
  int? get selfCharacterId => null;

  /// 내가 파티장인가 — **파티를 만든 사람**인가.
  ///
  /// 사냥을 이끄는 것과는 다른 축이다([isHuntLeading]). 파티장은 누가 파티에
  /// 있는지를 정하고, 이끄는 사람은 어디로 갈지를 정한다.
  bool get isLeader {
    final self = selfCharacterId;
    return self != null && self == leaderCharacterId;
  }

  /// 지금 사냥을 이끄는 사람. 아무도 이끌지 않으면 null.
  int? get huntLeadCharacterId => null;

  /// 지금 이끌기의 번호. 참여할 때 그대로 돌려보내 어느 이끌기인지 못 박는다.
  int get huntLeadSeq => 0;

  /// 누군가 이끌고 있는가.
  bool get hasHuntLead => huntLeadCharacterId != null;

  /// 내가 이끌고 있는가.
  bool get isHuntLeading {
    final self = selfCharacterId;
    return self != null && self == huntLeadCharacterId;
  }

  /// 이끌기가 열려 있는데 내가 아직 참여하지 않았는가.
  ///
  /// 이 값이 참일 때 화면에 "추종" 버튼을 보여 준다.
  bool get canJoinHuntLead => hasHuntLead && !isHuntLeading && !isFollowing;

  /// 내가 따라다니기로 한 상태인가.
  bool get isFollowing {
    final self = selfCharacterId;
    if (self == null) return false;
    for (final member in members) {
      if (member.characterId == self) return member.isFollowing;
    }
    return false;
  }

  /// 파티 상태가 바뀔 때 알리는 신호.
  Listenable get changes;

  /// 서버에 연결되어 있는지.
  bool get isAvailable => false;

  /// 파티 소식을 받기 시작한다. 월드에 들어갈 때 부른다.
  Future<void> attach() async {}

  /// 파티 소식 받기를 멈춘다. 월드에서 나갈 때 부른다.
  ///
  /// 구독만 닫는다. **파티에서 빠지는 것은 서버가 한다** — 월드를 떠나면 파티도
  /// 함께 끝나므로 여기서 따로 탈퇴를 부를 필요가 없다.
  void detach() {}

  /// 월드에 있는 다른 사람을 초대한다. 파티가 없으면 서버가 만들어 준다.
  Future<void> invite(int targetCharacterId) async {}

  /// 주변에 있는 요원을 한 번에 부른다.
  ///
  /// 이미 파티가 있는 사람은 빼고 보낸다 — 거절할 수밖에 없는 초대를 보내면
  /// 받는 쪽에는 광고와 구별되지 않고, 보내는 쪽은 "왜 다들 거절하지" 라고
  /// 오해한다. 어디까지가 주변인지는 서버가 정한다.
  Future<void> inviteNearby() async {}

  /// 받은 초대를 수락한다.
  Future<void> accept(int inviteId) async {}

  /// 받은 초대를 거절한다.
  Future<void> decline(int inviteId) async {}

  /// 파티에서 나간다.
  Future<void> leave() async {}

  /// 파티를 해산한다. 파티장만 할 수 있다.
  Future<void> disband() async {}

  /// 파티원을 내보낸다. 파티장만 할 수 있다.
  Future<void> kick(int targetCharacterId) async {}

  /// 파티장 자리를 넘긴다. 파티장만 할 수 있다.
  Future<void> promote(int targetCharacterId) async {}

  /// 따라가기를 그만둔다.
  ///
  /// 시작하는 쪽은 [acceptHuntLead] 다 — 어느 이끌기에 참여하는지 밝혀야 하므로
  /// 참·거짓만으로는 정할 수 없다.
  Future<void> setFollowing(bool following) async {}

  /// 사냥을 이끌기 시작한다. 파티원이면 누구나 할 수 있다.
  Future<void> startHuntLead() async {}

  /// 이끌기를 그만둔다. 이끄는 본인만 할 수 있다.
  Future<void> stopHuntLead() async {}

  /// 진행 중인 이끌기에 참여한다.
  ///
  /// [leadSeq] 를 함께 보내는 이유는 화면에 떠 있던 버튼이 오래된 것일 수 있기
  /// 때문이다. 그 사이 이끄는 사람이 바뀌었다면 서버가 거절한다.
  Future<void> acceptHuntLead(int leadSeq) async {}
}

/// 서버가 없을 때 쓰는 빈 구현.
///
/// 파티가 없는 것과 서버에 붙지 않은 것이 화면에서 같은 모습이 된다.
class OfflinePartySession extends PartySession {
  const OfflinePartySession();

  @override
  Listenable get changes => _never;

  /// 영영 바뀌지 않으므로 아무에게도 알리지 않는 신호를 준다.
  static final Listenable _never = Listenable.merge(const []);
}
