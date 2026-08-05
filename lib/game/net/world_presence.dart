import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';

/// 같은 월드에 있는 다른 요원 한 명.
///
/// 서버가 보내는 타입을 그대로 쓰지 않고 게임 쪽 표현으로 옮겨 담는다. 그래야
/// 렌더 코드가 SpacetimeDB 생성 코드를 몰라도 되고, 백엔드가 바뀌어도 화면은
/// 그대로 남는다.
class RemotePlayer {
  RemotePlayer({
    required this.characterId,
    required this.name,
    required this.kind,
    required this.level,
    required this.grid,
    required this.alive,
    required this.hp,
    required this.maxHp,
    this.lastAttackAtMicros = 0,
    Vector2? attackDir,
    this.attackSkill = AttackSkill.none,
    Vector2? facing,
  })  : attackDir = attackDir ?? Vector2.zero(),
        facing = facing ?? Vector2.zero();

  /// 캐릭터 식별자. 같은 사람을 프레임마다 다시 찾는 열쇠다.
  final int characterId;

  final String name;

  /// 캐릭터 외형(`male_cyborg` · `female_cyborg`).
  final String kind;

  final int level;

  /// 타일 단위의 논리 위치.
  final Vector2 grid;

  final bool alive;

  /// 남의 체력. **PK 가 허용되므로 이것이 보여야 한다** — 상대가 얼마나 버티는지
  /// 모르면 덤빌지 물러설지 판단할 수 없고, 몹에게 쫓기는 동료를 알아볼 수도 없다.
  final int hp;
  final int maxHp;

  /// 마지막으로 공격을 휘두른 시각(서버 기준 마이크로초).
  ///
  /// 이 값이 **바뀌는 것**을 보고 공격 동작을 한 번 재생한다. 절대 시각으로
  /// 비교하지 않는 이유는 기기 시계가 서버와 어긋나기 때문이다 — 몇 초만 밀려도
  /// 모든 공격이 "너무 오래된 것" 으로 걸러지거나 매 프레임 다시 재생된다.
  final int lastAttackAtMicros;

  /// 그 공격이 향한 방향(정규화된 그리드 벡터). 서버가 계산한 값이다.
  final Vector2 attackDir;

  /// 무엇으로 쳤는지. [AttackSkill] 의 값과 같다.
  final int attackSkill;

  /// 바라보는 방향(정규화된 그리드 벡터).
  ///
  /// **멈춰 있을 때 필요한 값이다.** 좌표가 그대로면 움직임에서 방향을 뽑을 수
  /// 없어, 남의 화면에서는 마지막으로 걸었던 쪽을 계속 바라보게 된다.
  final Vector2 facing;

  double get hpRatio => maxHp <= 0 ? 0 : (hp / maxHp).clamp(0.0, 1.0);
}

/// [RemotePlayer.attackSkill] 의 값. 서버 `world.rs` 의 `ATTACK_SKILL_*` 와 같다.
///
/// 번호가 어긋나면 남의 화면에서 스킬이 기본 공격으로 보이거나 그 반대가 된다.
abstract final class AttackSkill {
  /// 기본 공격.
  static const int none = 0;

  /// 플라즈마.
  static const int plasma = 1;
}

/// 서버가 확정한 **내 몸**의 상태.
///
/// 체력·마력·사망은 이제 서버가 정한다. 클라이언트는 이 값을 그리고, 다음 갱신이
/// 올 때까지의 사이만 예측으로 메운다 — 예측은 화면을 부드럽게 하려는 것이지
/// 판정이 아니다. 그래서 여기 값과 어긋나면 **언제나 여기가 맞다.**
///
/// 이걸 받아 오지 않으면 화면의 체력은 가득 찬 채인데 서버에서는 이미 쓰러져
/// 안전지대로 옮겨진, 두 세계가 어긋난 상태가 된다.
class MyWorldState {
  const MyWorldState({
    required this.grid,
    required this.hp,
    required this.maxHp,
    required this.mp,
    required this.maxMp,
    required this.alive,
    required this.deaths,
    this.lastDamagedAtMicros = 0,
  });

  /// 서버가 확정한 내 좌표. 예측 위치를 여기로 수렴시킨다.
  final Vector2 grid;

  final int hp;
  final int maxHp;
  final int mp;
  final int maxMp;
  final bool alive;

  /// 지금까지 쓰러진 횟수.
  ///
  /// 사망은 상태가 아니라 **사건**이다 — 쓰러지면 곧바로 안전지대에서 다시
  /// 일어서므로 `alive` 가 내려가 있는 순간을 구독으로 보리라 기대할 수 없다.
  /// 이 수가 **오르는 것**을 보고 사망 연출을 시작한다.
  final int deaths;

  /// 마지막으로 피해를 입은 서버 시각(마이크로초).
  ///
  /// **피격도 사망과 같은 사건이다.** 체력 숫자만 받아 적으면 맞았는지 회복
  /// 중인지 구별되지 않아, 화면에서는 아무 일도 없이 게이지만 줄어든다. 이 값이
  /// **바뀌는 것**을 보고 피격 연출을 한 번 낸다.
  ///
  /// 서버에 이미 있던 열이다(안전지대 회복 대기의 기준). 새 스키마를 만들 이유가
  /// 없었고, 클라이언트가 읽지 않고 있었을 뿐이다.
  final int lastDamagedAtMicros;
}

/// 서버가 관리하는 몬스터 한 기.
///
/// **이 값이 진실이다.** 클라이언트가 따로 만들어 낸 몹은 없다 — 있으면 A 가
/// 잡은 몹이 B 화면에 살아 있게 되고, 그 순간 파티도 협업 레이드도 성립하지
/// 않는다.
class ServerMonster {
  ServerMonster({
    required this.id,
    required this.level,
    required this.grid,
    required this.hp,
    required this.maxHp,
    required this.alive,
    required this.taggedByMe,
    Vector2? facing,
    this.lastAttackAtMicros = 0,
  }) : facing = facing ?? Vector2.zero();

  /// 서버가 부여한 번호. 공격할 때 이 값을 보낸다.
  final int id;

  /// 1~200. 클라이언트 도감이 이 값으로 종과 생김새를 찾는다.
  final int level;

  final Vector2 grid;
  final int hp;
  final int maxHp;
  final bool alive;

  /// 내가 선점한 몹인지. 크레딧이 나에게 오는지를 화면에 표시하는 데 쓴다.
  final bool taggedByMe;

  /// 바라보는 방향. 사거리 안에 붙어 때리는 몹은 좌표가 멈추므로, 이 값이
  /// 없으면 화면마다 다른 쪽을 보고 있게 된다.
  final Vector2 facing;

  /// 마지막으로 후려친 서버 시각(마이크로초).
  ///
  /// 이 값이 **바뀌는 것**을 보고 타격 동작을 한 번 재생한다. 없으면 몹은
  /// 조용히 다가와 서 있고 사람의 체력만 줄어든다.
  final int lastAttackAtMicros;

  double get hpRatio => maxHp <= 0 ? 0 : (hp / maxHp).clamp(0.0, 1.0);
}

/// 바닥에 떨어져 있는 전리품 하나. **서버가 정한 것**이다.
///
/// 무엇이 떨어졌는지가 모두에게 같아야 하는 이유는 분배 때문이다. 각자 굴리면
/// 같은 몹을 잡고도 서로 다른 것을 보게 되어, 누가 무엇을 가져갔는지를 두고
/// 이야기할 수조차 없다.
class ServerLoot {
  ServerLoot({
    required this.id,
    required this.kind,
    required this.amount,
    required this.grid,
    required this.reservedForMe,
    required this.reservedForOther,
  });

  /// 서버가 부여한 번호. 주울 때 이 값을 보낸다.
  final int id;

  /// 클라이언트 `PickupKind` 의 이름. 모르는 값이면 그리지 않는다.
  final String kind;

  final int amount;
  final Vector2 grid;

  /// 내가 선점한 몹에서 나왔고 아직 우선권이 살아 있는지.
  final bool reservedForMe;

  /// 남의 우선권이 아직 살아 있는지. 지금 주우려 해도 서버가 거절한다.
  final bool reservedForOther;
}

/// 월드에 누가 함께 있는지 알려 주고, 내 위치를 알리는 창구.
///
/// 게임은 이 인터페이스만 알고 있으므로 서버에 붙지 않아도 그대로 돌아간다 —
/// 그때는 [isAvailable] 이 false 이고 [others] 가 비어 있을 뿐이다. 혼자
/// 플레이하는 것과 아무도 접속하지 않은 월드는 화면에서 같은 모습이다.
abstract class WorldPresence {
  const WorldPresence();

  /// 월드에 들어간다. 게임을 시작할 때 한 번 부른다.
  ///
  /// [grid] 는 **내 몸이 실제로 선 자리**다. 이걸 넘기지 않으면 서버가 임의의
  /// 지점(월드 중심)에 나를 세우고, 그 어긋남은 속도 상한 때문에 몇 초에 걸쳐
  /// 천천히 좁혀진다 — 그동안 남의 화면에서 나는 엉뚱한 곳에 있거나 보이지도
  /// 않는다.
  Future<void> enter(Vector2 grid) async {}

  /// 월드에서 나온다. 게임을 접을 때 부른다.
  void leave() {}

  /// 내 위치와 **바라보는 방향**을 알린다.
  ///
  /// 매 프레임 불러도 되며 실제 전송 빈도는 구현이 정한다. 방향을 함께 보내는
  /// 이유는 멈춰 선 동안에도 몸을 돌리는 일이 남의 화면에 보여야 하기
  /// 때문이다 — 좌표만 보내면 그 동작이 통째로 사라진다.
  void report(Vector2 grid, Vector2 facing) {}

  /// 나를 뺀 다른 요원들. 서버에 붙지 않았으면 빈 목록이다.
  List<RemotePlayer> get others => const [];

  /// 서버가 관리하는 몬스터. 서버에 붙지 않았으면 빈 목록이다.
  List<ServerMonster> get monsters => const [];

  /// 바닥에 놓인 전리품. 서버에 붙지 않았으면 빈 목록이다.
  List<ServerLoot> get loots => const [];

  /// 전리품을 줍는다. 성공하면 `true`.
  ///
  /// 결과를 **기다려서** 판정한다. 몬스터를 때릴 때와 다른 점인데, 전리품은
  /// 하나뿐이라 두 사람이 동시에 손을 뻗으면 한 명은 반드시 빈손이기 때문이다.
  /// 낙관적으로 처리하면 둘 다 획득 연출을 보고, 그중 하나는 거짓이 된다.
  Future<bool> pickLoot(int lootId) async => false;


  /// 몬스터를 때린다. 사거리·쿨다운·선점·보상은 **전부 서버가 판정한다.**
  ///
  /// 클라이언트는 "누구를 때리려 했는가" 만 말하고, 그 결과는 표가 바뀌는 것으로
  /// 돌아온다. 여기서 체력을 미리 깎아 두면 서버가 거절했을 때 화면과 서버가
  /// 어긋나고, 그 어긋남은 "분명히 때렸는데 안 죽는" 형태로 나타난다.
  void attack(int monsterId) {}

  /// 스킬을 쓴다. **마력·쿨다운·사거리·피해를 전부 서버가 정한다.**
  ///
  /// 마력을 여기서 미리 깎지 않는다 — 서버가 거절하면 쓰지도 않은 마력이 사라진다.
  void castSkill(String skillId, int monsterId) {}

  /// 다른 요원을 때린다(PK). 안전지대 면역·사거리·쿨다운은 서버가 본다.
  void attackPlayer(int targetCharacterId) {}

  /// 서버가 확정한 내 전투 상태. 월드에 들어가 있지 않으면 `null`.
  MyWorldState? get me => null;

  /// 서버가 기록한 내 누적 경험치. 모르면 `null`.
  ///
  /// **서버가 모는 몹을 잡으면 경험치는 서버에서만 오른다**(`award_kill`).
  /// 클라이언트는 그 몹에 로컬 경험치를 주지 않으므로(이중 지급이 되고, 크레딧은
  /// 막타가 아니라 선점자에게 가므로), 이 값을 읽어 오지 않으면 사냥을 아무리
  /// 해도 화면의 레벨과 경험치 바가 출격 시점에 멈춰 있다.
  int? get serverTotalXp => null;

  /// 다른 요원의 목록이나 위치가 바뀔 때 알리는 신호.
  Listenable get changes;

  /// 월드에 연결되어 있는지.
  bool get isAvailable => false;

  /// 이 사람은 멀어져도 계속 보이게 한다. null 이면 그런 사람이 없다.
  ///
  /// 주변만 받아 오는 구독에서는 멀어진 사람이 목록에서 사라지는데, 화면은 그것을
  /// "월드에서 나갔다" 와 구별할 수 없다. 따라다니는 상대에게는 그 구별이
  /// 필요하므로 한 명만 예외로 둔다.
  void watchCharacter(int? characterId) {}
}

/// 서버가 없을 때 쓰는 빈 구현.
class OfflineWorldPresence extends WorldPresence {
  const OfflineWorldPresence();

  @override
  Listenable get changes => _never;

  /// 영영 바뀌지 않으므로 아무에게도 알리지 않는 신호를 준다.
  static final Listenable _never = Listenable.merge(const []);
}
