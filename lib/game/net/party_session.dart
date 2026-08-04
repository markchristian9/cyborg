import 'package:flutter/foundation.dart';

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

  /// 나에게 온 초대.
  List<PartyInviteInfo> get invites => const [];

  /// 내 캐릭터 식별자. 파티에 들어가기 전에는 null 일 수 있다.
  int? get selfCharacterId => null;

  /// 내가 파티장인가.
  bool get isLeader {
    final self = selfCharacterId;
    return self != null && self == leaderCharacterId;
  }

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

  /// 월드에 있는 다른 사람을 초대한다. 파티가 없으면 서버가 만들어 준다.
  Future<void> invite(int targetCharacterId) async {}

  /// 받은 초대를 수락한다.
  Future<void> accept(int inviteId) async {}

  /// 받은 초대를 거절한다.
  Future<void> decline(int inviteId) async {}

  /// 파티에서 나간다.
  Future<void> leave() async {}

  /// 파티장을 따라다니겠다고 알리거나 그만둔다.
  Future<void> setFollowing(bool following) async {}
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
