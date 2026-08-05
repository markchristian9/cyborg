import 'package:flame/components.dart';

/// 따라갈 상대의 지금 모습.
///
/// 게임 객체도 서버 타입도 아닌 작은 값이다. 이 클래스가 [RemotePlayer] 를 직접
/// 알지 않게 한 이유는 두 가지다 — 시험할 때 좌표만 있는 가짜를 쓸 수 있고,
/// 원격 플레이어를 어떻게 받아 오는지가 바뀌어도 판단 규칙은 그대로 남는다.
class FollowTarget {
  const FollowTarget({
    required this.characterId,
    required this.grid,
    required this.alive,
  });

  final int characterId;

  /// 타일 단위의 논리 위치.
  final Vector2 grid;

  final bool alive;
}

/// 추종이 이번 프레임에 내린 판단.
enum PartyFollowAction {
  /// 따라가는 중이 아니다. 아무것도 하지 않는다.
  none,

  /// 따라갈 상대를 찾을 수 없다. 추종을 끊어야 한다.
  lost,

  /// 상대가 쓰러져 있다. 사냥 중심을 옮기지 않고 하던 것을 잇는다.
  hold,

  /// 너무 멀다. 사냥을 접고 상대에게 곧장 걸어간다.
  rejoin,

  /// 따라붙은 거리다. 사냥 중심을 상대 위치로 옮긴다.
  anchor,
}

/// [PartyFollowController.update] 가 돌려주는 한 프레임분 지시.
///
/// 컨트롤러는 게임 객체를 직접 건드리지 않고 이 값만 돌려준다. 실제로 걷게 하거나
/// 사냥 중심을 옮기는 것은 호출부의 몫이다 — `AutoHuntController` 와 같은 방식이며,
/// 그래서 Flame 을 띄우지 않고도 판단만 따로 검사할 수 있다.
class PartyFollowDecision {
  const PartyFollowDecision(this.action, {this.destination, this.message});

  final PartyFollowAction action;

  /// 걸어갈, 또는 사냥 중심으로 삼을 그리드 좌표.
  /// [PartyFollowAction.rejoin] 과 [PartyFollowAction.anchor] 에서만 채워진다.
  final Vector2? destination;

  /// 사람에게 보여 줄 한 줄. 추종이 끊길 때처럼 이유를 알려야 할 때만 채워진다.
  final String? message;
}

/// 파티장을 따라다니며 그 주변을 사냥하게 하는 판단 규칙.
///
/// ## 왜 따로 걷는 코드를 만들지 않는가
///
/// 추종의 실체는 **자동 사냥의 중심을 상대에게 옮기는 것**이다. 중심이 따라
/// 움직이면 기존 자동 사냥이 알아서 그 주변 몬스터를 잡고, 사냥감이 없으면 중심
/// 쪽으로 돌아온다. 형제 게임 라리엔도 같은 결론에 도달했다(`docs/party.md`
/// §10.5.3 — "별도 추종 이동 로직을 새로 짜지 않는다").
///
/// 다만 라리엔은 서버가 30Hz 로 모든 캐릭터를 시뮬레이션하므로 그 갱신을 서버가
/// 한다. 여기서는 서버가 좌표를 받아 적을 뿐이라 클라이언트가 판단한다.
///
/// ## 판단 순서가 이 순서인 이유
///
/// **거리 판정이 사냥보다 먼저다.** 멀어졌을 때 사냥을 계속하면 상대는 계속
/// 멀어지고, 그 사이 사냥 중심은 이미 화면 밖 좌표를 가리킨다. 라리엔이 이 순서를
/// 뒤집었다가 입구에서 좌우로 왕복하는 문제를 겪었다.
///
/// ## 못 하는 것
///
/// 이 게임에는 경로 탐색이 없다. 벽 너머에 있는 상대에게는 영영 닿지 못하므로,
/// 다가가는 진전이 멈춘 채 [rejoinTimeout] 이 지나면 추종을 포기한다. 억지로
/// 붙이려 하는 대신 사람에게 놓쳤다고 알리는 편이 정직하다.
class PartyFollowController {
  /// 이 거리(타일)보다 멀어지면 사냥을 접고 따라붙는 것을 우선한다.
  ///
  /// 자동 사냥의 최대 반경(10 m)보다 넉넉히 잡는다. 반경과 비슷하게 두면 상대가
  /// 사냥터 가장자리를 걷기만 해도 추종과 사냥이 매 프레임 뒤바뀐다.
  static const double rejoinDistanceTiles = 25.0;

  /// 따라붙었다고 보고 사냥을 다시 여는 거리(타일).
  ///
  /// 접는 기준([rejoinDistanceTiles])보다 가깝게 둔다. 두 기준이 같으면 경계에
  /// 걸친 채로 사냥과 복귀를 반복한다.
  static const double resumeDistanceTiles = 18.0;

  /// 이 거리(타일)를 넘어서면 따라붙기를 시도하지도 않는다.
  ///
  /// 쓰러졌다 안전지대에서 되살아났을 때가 이 경우다. 상대가 월드 반대편 사냥터에
  /// 있으면 수백 타일을 아무 대비 없이 가로질러야 하고, 그 길에 다시 쓰러진다.
  /// 자동 사냥이 죽었을 때 스스로 꺼지는 것과 같은 이유다.
  static const double giveUpDistanceTiles = 120.0;

  /// 따라붙지 못한 채 이 시간(초)이 지나면 포기한다.
  ///
  /// 다가가는 동안에는 시계가 돌지 않는다([_progressEpsilonTiles]) — 멀리 있는
  /// 상대에게 오래 걸어가는 것은 정상이고, 막힌 것과는 다르다.
  static const double rejoinTimeout = 8.0;

  /// 상대를 못 찾은 채 이만큼(초)까지는 기다린다.
  ///
  /// 목록에서 잠깐 사라지는 것과 정말 떠난 것은 다르다. 주변만 받아 오는 구독은
  /// 상대가 경계를 넘을 때 다시 걸리는데, 그 왕복 동안 한두 프레임은 비어 있다.
  /// 유예가 없으면 그 순간을 "월드에서 사라졌다" 로 읽어 추종이 끊긴다.
  static const double missingGrace = 1.5;

  /// 이만큼(타일) 가까워지면 "다가가고 있다" 고 본다.
  ///
  /// 0 으로 두면 좌표가 미세하게 흔들리는 것만으로 진전으로 쳐서, 벽에 붙어
  /// 제자리걸음을 해도 영영 포기하지 않는다.
  static const double _progressEpsilonTiles = 0.5;

  /// 따라붙지 못한 채 흐른 시간.
  double _rejoinTime = 0;

  /// 여태 가장 가까웠던 거리. 진전을 재는 기준이다.
  double _bestDistance = double.infinity;

  /// 지금 따라붙는 중(사냥을 접은 상태)인가.
  bool _rejoining = false;

  /// 상대를 못 찾은 채 흐른 시간.
  double _missingTime = 0;

  /// 지금 따라가고 있는 상대.
  ///
  /// 상대가 바뀌었는지 보려고 들고 있다. 파티장이 자리를 넘기면 따라갈 사람이
  /// 바뀌는데, 그때 이전 사람에게 다가가던 기록을 그대로 쓰면 새 사람이 그보다
  /// 멀다는 이유만으로 "진전이 없다" 로 읽혀 곧바로 놓친 것이 된다.
  int? _targetId;

  /// 지금 따라붙는 중인가. 화면에 상태를 보여 줄 때 쓴다.
  bool get isRejoining => _rejoining;

  /// 추종을 처음부터 다시 시작한다.
  ///
  /// 상대가 바뀌거나 추종을 껐다 켤 때 부른다. 이전 상대에게 다가가던 기록이
  /// 남아 있으면, 새 상대를 향해 걷기 시작하자마자 "진전이 없다" 로 읽혀 곧바로
  /// 포기한다.
  void reset() {
    _rejoinTime = 0;
    _bestDistance = double.infinity;
    _rejoining = false;
    _targetId = null;
    _missingTime = 0;
  }

  /// 내가 순간이동했다고 알린다 — 쓰러졌다 안전지대에서 되살아났을 때.
  ///
  /// 따라갈 상대는 그대로이므로 [reset] 은 지나치다. 지워야 하는 것은 **다가가던
  /// 기록**뿐이다. 리더 옆에서 재던 작은 거리가 남은 채 안전지대로 튕겨 나가면,
  /// 그보다 가까워지기 전까지 "다가가지 못하고 있다" 로 읽혀 제한 시간이 지나면
  /// 놓친 것이 된다.
  ///
  /// 상대가 쓰러졌을 때도 같은 초기화를 하지만([update] 의 ② 분기), 그것은
  /// **상대**가 옮겨 갈 때의 이야기라 내가 옮겨 가는 이 경우를 덮지 못한다.
  void noteSelfMoved() {
    _rejoinTime = 0;
    _bestDistance = double.infinity;
  }

  /// 한 프레임을 진행시키고 이번에 할 일을 돌려준다.
  ///
  /// [following] 은 따라가기로 한 상태인지, [leader] 는 따라갈 상대의 지금 모습
  /// (월드에서 찾지 못했으면 null), [selfGrid] 는 내 그리드 좌표다.
  PartyFollowDecision update(
    double dt, {
    required bool following,
    required FollowTarget? leader,
    required Vector2 selfGrid,
  }) {
    if (!following) {
      reset();
      return const PartyFollowDecision(PartyFollowAction.none);
    }

    // ① 상대가 목록에 없다. 정말 떠났을 수도, 구독이 잠깐 비었을 수도 있다.
    //
    // 곧바로 끊지 않고 [missingGrace] 만큼 기다린다 — 그 사이 다시 보이면 아무
    // 일도 없었던 것처럼 이어진다. 기다리는 동안에는 사냥 중심을 옮기지 않고
    // 하던 것을 잇는다(상대가 쓰러졌을 때와 같은 처리다).
    if (leader == null) {
      _missingTime += dt;
      if (_missingTime < missingGrace) {
        return const PartyFollowDecision(PartyFollowAction.hold);
      }
      reset();
      return const PartyFollowDecision(
        PartyFollowAction.lost,
        message: '따라가던 요원이 월드에서 사라졌다',
      );
    }
    _missingTime = 0;

    // 따라갈 사람이 바뀌었으면(파티장 위임) 처음부터 다시 잰다.
    if (leader.characterId != _targetId) {
      _targetId = leader.characterId;
      _rejoinTime = 0;
      _bestDistance = double.infinity;
      _rejoining = false;
    }

    final distance = (leader.grid - selfGrid).length;

    // ② 상대가 쓰러져 있다. 사냥 중심을 옮기지 않고 그대로 둔다.
    //
    // 여기서 추종을 끊지 않는 이유는, 상대가 곧 안전지대에서 되살아나기 때문이다.
    // 끊어 버리면 다 같이 물러나는 대신 각자 흩어진다. 되살아나면 그 자리가 새
    // 중심이 되어 자연히 안전지대로 모인다.
    //
    // 다가가던 기록도 함께 지운다. 되살아나는 자리는 쓰러진 자리가 아니라
    // 안전지대라, 그 사이의 거리 변화는 따라붙기의 진전과 아무 관계가 없다.
    if (!leader.alive) {
      _rejoinTime = 0;
      _bestDistance = double.infinity;
      return const PartyFollowDecision(PartyFollowAction.hold);
    }

    // ③ 손쓸 수 없이 멀다. 가로지르다 쓰러지느니 여기서 끊는다.
    if (distance > giveUpDistanceTiles) {
      reset();
      return const PartyFollowDecision(
        PartyFollowAction.lost,
        message: '따라가던 요원이 너무 멀다',
      );
    }

    // ④ 멀어졌으면 사냥보다 따라붙는 것이 먼저다.
    if (_shouldRejoin(distance)) {
      _rejoining = true;

      // 다가가고 있으면 시계를 되돌린다. 멀리 있는 상대에게 오래 걸어가는 것은
      // 막힌 것이 아니다.
      if (distance < _bestDistance - _progressEpsilonTiles) {
        _bestDistance = distance;
        _rejoinTime = 0;
      } else {
        _rejoinTime += dt;
      }

      if (_rejoinTime >= rejoinTimeout) {
        reset();
        return const PartyFollowDecision(
          PartyFollowAction.lost,
          message: '따라가던 요원에게 닿을 수 없다',
        );
      }

      return PartyFollowDecision(
        PartyFollowAction.rejoin,
        destination: leader.grid.clone(),
      );
    }

    // ⑤ 따라붙었다. 사냥 중심을 상대에게 둔다.
    _rejoining = false;
    _rejoinTime = 0;
    _bestDistance = double.infinity;
    return PartyFollowDecision(
      PartyFollowAction.anchor,
      destination: leader.grid.clone(),
    );
  }

  /// 따라붙기를 시작할지, 하던 것을 이어갈지.
  ///
  /// 시작하는 기준과 그만두는 기준이 다르다(히스테리시스). 한 기준만 쓰면 그
  /// 경계에서 사냥과 복귀가 매 프레임 뒤바뀐다.
  bool _shouldRejoin(double distance) {
    if (_rejoining) return distance > resumeDistanceTiles;
    return distance > rejoinDistanceTiles;
  }
}
