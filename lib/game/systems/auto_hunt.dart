import 'package:flame/components.dart';

import '../iso.dart';

/// 자동 사냥이 이번 프레임에 내린 판단.
enum AutoHuntAction {
  /// 자동 사냥이 꺼져 있거나 지금은 개입하지 않는다.
  none,

  /// 사냥할 것이 없고 앵커 위에 있다. 제자리에서 기다린다.
  idle,

  /// 타깃이 사거리 밖이다. 타깃 쪽으로 걸어간다.
  approach,

  /// 타깃이 사거리 안이다. 때린다.
  attack,

  /// 사냥할 것이 없는데 앵커에서 벗어나 있다. 앵커로 돌아간다.
  returnToAnchor,
}

/// [AutoHuntController.update] 가 돌려주는 한 프레임분 지시.
///
/// 컨트롤러는 게임 객체를 직접 건드리지 않고 이 값만 돌려준다. 실제로
/// 걷게 하거나 때리게 하는 것은 호출부의 몫이다 — 판단과 실행을 갈라
/// 두었기 때문에 Flame 을 띄우지 않고도 판단만 따로 검사할 수 있다.
class AutoHuntDecision<T> {
  const AutoHuntDecision(this.action, {this.target, this.destination});

  final AutoHuntAction action;

  /// [AutoHuntAction.approach]·[AutoHuntAction.attack] 일 때의 대상.
  final T? target;

  /// 걸어갈 그리드 좌표. [AutoHuntAction.approach] 와
  /// [AutoHuntAction.returnToAnchor] 에서만 채워진다.
  final Vector2? destination;
}

/// 앵커를 중심으로 한 반경 안에서만 몬스터를 찾아 사냥하는 상태 기계.
///
/// 게임 객체를 모르게 만들었다. 대상의 타입은 [T] 로 열어 두고 좌표와 생사만
/// 콜백으로 받는다 — 덕분에 이 파일은 Flame·SpacetimeDB 어느 쪽에도 기대지
/// 않고, 테스트에서는 좌표만 가진 가짜 대상으로 검사할 수 있다.
///
/// **거리는 전부 그리드(타일) 단위로 계산한다.** 사람이 정하는 반경만 미터로
/// 받아 [metersToTiles] 로 바꾼다. 화면 좌표(아이소메트릭 투영 후)는 x·y 축의
/// 축척이 달라 거리 비교에 쓸 수 없다 — 같은 1m 라도 세로 방향이 절반으로
/// 눌리기 때문에, 화면 좌표로 재면 반경이 원이 아니라 찌그러진 마름모가 된다.
class AutoHuntController<T extends Object> {
  AutoHuntController({
    required this.gridOf,
    required this.aliveOf,
    double radiusMeters = defaultRadiusMeters,
  }) : _radiusMeters = radiusMeters.clamp(minRadiusMeters, maxRadiusMeters);

  /// 대상의 그리드 좌표를 읽는다.
  final Vector2 Function(T) gridOf;

  /// 대상이 아직 살아 있는지 읽는다.
  final bool Function(T) aliveOf;

  /// 사람이 고를 수 있는 탐색 반경의 하한(미터).
  static const double minRadiusMeters = 1.0;

  /// 사람이 고를 수 있는 탐색 반경의 상한(미터).
  static const double maxRadiusMeters = 10.0;

  /// 켰을 때의 기본 탐색 반경(미터).
  static const double defaultRadiusMeters = 5.0;

  /// 타깃을 놓아주는 거리에 더하는 여유(타일).
  ///
  /// 잡을 때와 놓을 때의 기준이 같으면 반경 경계에 걸친 몬스터를 잡았다
  /// 놨다 반복한다. 놓는 쪽을 조금 더 멀리 잡아 그 진동을 없앤다.
  static const double releaseMargin = 0.5;

  /// 이 거리(타일)보다 앵커에서 멀어지면 사냥감이 없을 때 되돌아온다.
  ///
  /// 0 으로 두면 앵커 위에서 미세하게 떨리므로 약간의 무시 구간을 둔다.
  static const double anchorReturnThreshold = 0.6;

  /// 한 타깃을 이 시간(초) 안에 사거리에 넣지 못하면 포기한다.
  ///
  /// 경로 탐색이 없으므로 벽 뒤의 몬스터에는 영원히 닿지 못한다. 포기가
  /// 없으면 그 자리에서 벽에 붙어 사냥이 멈춘다.
  static const double pursuitTimeout = 4.0;

  /// 처음 포기한 타깃을 다시 노리지 않는 시간(초).
  ///
  /// 곧바로 풀면 같은 몬스터를 다시 골라 벽에 붙는 것을 반복한다.
  /// [pursuitTimeout] 보다 길어야 한다 — 짧으면 닿지 않는 몬스터 둘이
  /// 번갈아 풀리면서 더 먼 정상 몬스터에게 순서가 영영 오지 않는다.
  static const double blockDurationBase = 8.0;

  /// 반복 실패로 늘어난 차단 시간의 상한(초).
  ///
  /// 상한이 없으면 잠깐 막혔던 몬스터가 사실상 영구 제외된다.
  static const double blockDurationMax = 60.0;

  /// 자동 사냥이 켜져 있는지.
  bool get enabled => _enabled;
  bool _enabled = false;

  /// 탐색의 중심(그리드 좌표). 꺼져 있으면 null.
  Vector2? get anchor => _anchor;
  Vector2? _anchor;

  /// 지금 교전 중인 대상.
  T? get target => _target;
  T? _target;

  double _radiusMeters;

  /// 탐색 반경(미터). 1~10 으로 제한된다.
  double get radiusMeters => _radiusMeters;

  set radiusMeters(double value) {
    _radiusMeters = value.clamp(minRadiusMeters, maxRadiusMeters);
  }

  /// 탐색 반경(타일). 실제 거리 비교에 쓰는 값이다.
  double get radiusTiles => metersToTiles(_radiusMeters);

  /// 지금 타깃을 쫓은 시간.
  double _pursuitTime = 0;

  /// 포기한 타깃과 남은 차단 시간.
  final Map<T, double> _blocked = {};

  /// 타깃별로 연달아 닿지 못한 횟수.
  ///
  /// 차단이 풀린 뒤에도 남겨 두어야 차단 시간이 실패마다 배로 늘어난다.
  /// 매번 같은 시간만 차단하면, 닿지 않는 몬스터가 여럿일 때 그들의 차단
  /// 구간이 서로 어긋나 항상 누군가 하나는 후보로 살아 있고, 그보다 먼
  /// 정상 몬스터는 한 번도 선택되지 못한다.
  final Map<T, int> _failures = {};

  /// [failures] 번째 실패에 적용할 차단 시간(초).
  static double blockDurationFor(int failures) {
    var duration = blockDurationBase;
    for (var i = 1; i < failures; i++) {
      duration *= 2;
      if (duration >= blockDurationMax) return blockDurationMax;
    }
    return duration;
  }

  /// [origin] 을 중심으로 자동 사냥을 켠다.
  void enable(Vector2 origin) {
    _enabled = true;
    _anchor = origin.clone();
    _target = null;
    _pursuitTime = 0;
    _blocked.clear();
    _failures.clear();
  }

  /// 자동 사냥을 끄고 상태를 비운다.
  void disable() {
    _enabled = false;
    _anchor = null;
    _target = null;
    _pursuitTime = 0;
    _blocked.clear();
    _failures.clear();
  }

  /// 켜져 있으면 끄고, 꺼져 있으면 [origin] 에서 켠다. 켠 뒤의 상태를 돌려준다.
  bool toggle(Vector2 origin) {
    if (_enabled) {
      disable();
    } else {
      enable(origin);
    }
    return _enabled;
  }

  /// 탐색의 중심을 [point] 로 옮긴다.
  ///
  /// 자동 사냥 중 땅을 클릭했을 때 불린다. 중심이 바뀌면 지금 쫓던 대상은
  /// 새 반경 밖일 수 있으므로 놓아주고 다시 고르게 한다.
  void moveAnchor(Vector2 point) {
    if (!_enabled) return;
    _anchor = point.clone();
    _target = null;
    _pursuitTime = 0;
  }

  /// 한 프레임을 진행시키고 이번에 할 일을 돌려준다.
  ///
  /// [playerGrid] 는 플레이어의 현재 그리드 좌표, [candidates] 는 지금 월드에
  /// 있는 사냥 후보, [attackRangeTiles] 는 이 거리 안에 들어오면 때릴 수 있는
  /// 거리(타일)다.
  ///
  /// [suspended] 가 true 면 판단만 쉬고 상태는 그대로 둔다. 사람이 조이스틱을
  /// 잡고 있는 동안 자동 사냥이 이동을 덮어쓰지 않게 하는 데 쓴다.
  AutoHuntDecision<T> update(
    double dt, {
    required Vector2 playerGrid,
    required Iterable<T> candidates,
    required double attackRangeTiles,
    bool suspended = false,
  }) {
    if (!_enabled) return AutoHuntDecision<T>(AutoHuntAction.none);

    _tickBlocklist(dt);

    final anchor = _anchor;
    if (anchor == null) return AutoHuntDecision<T>(AutoHuntAction.none);

    // 사람이 직접 조작하는 동안에는 판단을 내리지 않는다. 타깃과 앵커는
    // 유지하므로 손을 떼면 하던 사냥을 그대로 잇는다.
    if (suspended) return AutoHuntDecision<T>(AutoHuntAction.none);

    _releaseTargetIfInvalid(anchor);

    // 쫓던 대상이 없으면 반경 안에서 새로 고른다.
    if (_target == null) {
      _target = _pickTarget(anchor, candidates);
      _pursuitTime = 0;
    }

    final target = _target;
    if (target == null) {
      // 사냥감이 없다. 앵커에서 벗어나 있으면 돌아가고, 아니면 기다린다.
      final drift = (playerGrid - anchor).length;
      if (drift > anchorReturnThreshold) {
        return AutoHuntDecision<T>(
          AutoHuntAction.returnToAnchor,
          destination: anchor.clone(),
        );
      }
      return AutoHuntDecision<T>(AutoHuntAction.idle);
    }

    final targetGrid = gridOf(target);
    final distance = (targetGrid - playerGrid).length;

    if (distance <= attackRangeTiles) {
      // 닿았으니 추격 시계를 되돌린다. 때리는 동안 밀고 밀리며 사거리를
      // 들락거려도 포기 판정에 걸리지 않게 한다.
      _pursuitTime = 0;
      // 닿은 이상 지금까지의 실패는 무의미하다. 남겨 두면 한 번 막혔던
      // 몬스터가 이후에 정상적으로 잡히는데도 차단 시간만 계속 길어진다.
      _failures.remove(target);
      return AutoHuntDecision<T>(AutoHuntAction.attack, target: target);
    }

    // 사거리에 넣지 못한 시간만 쌓는다. 오래 끌면 닿을 수 없는 자리(벽 뒤)로
    // 보고 놓아준 뒤 잠시 제외한다.
    _pursuitTime += dt;
    if (_pursuitTime >= pursuitTimeout) {
      // 실패가 쌓일수록 더 오래 제외한다. 그래야 닿지 않는 몬스터들이
      // 결국 동시에 차단되는 순간이 오고, 그 틈에 더 먼 정상 몬스터가
      // 선택된다.
      final failures = (_failures[target] ?? 0) + 1;
      _failures[target] = failures;
      _blocked[target] = blockDurationFor(failures);
      _target = null;
      _pursuitTime = 0;
      return AutoHuntDecision<T>(AutoHuntAction.idle);
    }

    return AutoHuntDecision<T>(
      AutoHuntAction.approach,
      target: target,
      destination: targetGrid.clone(),
    );
  }

  /// 죽었거나 반경 밖으로 밀려난 타깃을 놓아준다.
  void _releaseTargetIfInvalid(Vector2 anchor) {
    final target = _target;
    if (target == null) return;

    if (!aliveOf(target)) {
      _target = null;
      _pursuitTime = 0;
      return;
    }

    // 놓는 기준은 잡는 기준보다 [releaseMargin] 만큼 넓다(히스테리시스).
    final distance = (gridOf(target) - anchor).length;
    if (distance > radiusTiles + releaseMargin) {
      _target = null;
      _pursuitTime = 0;
    }
  }

  /// 반경 안에서 앵커에 가장 가까운 후보를 고른다.
  ///
  /// **플레이어가 아니라 앵커와의 거리로 고른다.** 플레이어 기준으로 고르면
  /// 추격하다 반경 가장자리의 다음 몬스터가 더 가까워지는 일이 이어지면서
  /// 앵커에서 끝없이 끌려 나간다. 앵커 기준이면 사냥터가 제자리에 머문다.
  T? _pickTarget(Vector2 anchor, Iterable<T> candidates) {
    final limit = radiusTiles;
    T? best;
    var bestDistance2 = double.infinity;

    for (final candidate in candidates) {
      if (!aliveOf(candidate)) continue;
      if (_blocked.containsKey(candidate)) continue;

      final distance2 = (gridOf(candidate) - anchor).length2;
      if (distance2 > limit * limit) continue;
      if (distance2 < bestDistance2) {
        bestDistance2 = distance2;
        best = candidate;
      }
    }

    return best;
  }

  void _tickBlocklist(double dt) {
    if (_blocked.isEmpty) return;
    _blocked.updateAll((_, remaining) => remaining - dt);
    _blocked.removeWhere((_, remaining) => remaining <= 0);
  }

  /// 사라진 대상을 상태에서 지운다.
  ///
  /// 월드에서 제거된 몬스터를 계속 참조하면 차단 목록이 자라기만 하고,
  /// 쫓던 대상이 사라졌는데도 다음 프레임까지 그 자리를 향해 걷는다.
  void forget(T candidate) {
    _blocked.remove(candidate);
    // 실패 기록도 함께 지운다. 남겨 두면 월드에서 사라진 개체의 항목이
    // 계속 쌓이고, 같은 자리에 다시 배치된 개체가 옛 이력을 물려받는다.
    _failures.remove(candidate);
    if (identical(_target, candidate)) {
      _target = null;
      _pursuitTime = 0;
    }
  }
}
