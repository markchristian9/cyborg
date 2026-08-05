import 'package:actionrpg/game/iso.dart';
import 'package:actionrpg/game/systems/auto_hunt.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

/// 자동 사냥이 다루는 최소한의 대상. 좌표와 생사만 있으면 된다.
class _Mob {
  _Mob(double x, double y, {this.alive = true}) : grid = Vector2(x, y);

  final Vector2 grid;
  bool alive;
}

AutoHuntController<_Mob> _controller({double radiusMeters = 5}) =>
    AutoHuntController<_Mob>(
      gridOf: (mob) => mob.grid,
      aliveOf: (mob) => mob.alive,
      radiusMeters: radiusMeters,
    );

/// 사거리는 실제 게임과 같은 근접 사거리(1.5 타일)를 기본으로 쓴다.
AutoHuntDecision<_Mob> _step(
  AutoHuntController<_Mob> hunt, {
  required Vector2 player,
  List<_Mob> mobs = const [],
  double dt = 1 / 60,
  double attackRange = 1.5,
  bool suspended = false,
}) {
  return hunt.update(
    dt,
    playerGrid: player,
    candidates: mobs,
    attackRangeTiles: attackRange,
    suspended: suspended,
  );
}

void main() {
  group('자동 사냥 — 켜고 끄기', () {
    test('꺼져 있으면 아무 판단도 하지 않는다', () {
      final hunt = _controller();
      expect(hunt.enabled, isFalse);
      expect(hunt.anchor, isNull);

      final decision = _step(
        hunt,
        player: Vector2.zero(),
        mobs: [_Mob(1, 0)],
      );
      expect(decision.action, AutoHuntAction.none);
    });

    test('켠 자리가 탐색의 중심이 된다', () {
      final hunt = _controller()..enable(Vector2(12, 7));
      expect(hunt.enabled, isTrue);
      expect(hunt.anchor, Vector2(12, 7));
    });

    test('앵커는 켤 때 넘긴 좌표의 복사본이라 원본을 따라 움직이지 않는다', () {
      final origin = Vector2(3, 3);
      final hunt = _controller()..enable(origin);

      // 플레이어가 이동해도 사냥터의 중심은 그 자리에 남아야 한다.
      origin.setValues(50, 50);
      expect(hunt.anchor, Vector2(3, 3));
    });

    test('끄면 앵커와 타깃이 모두 비워진다', () {
      final hunt = _controller()..enable(Vector2.zero());
      _step(hunt, player: Vector2.zero(), mobs: [_Mob(2, 0)]);
      expect(hunt.target, isNotNull);

      hunt.disable();
      expect(hunt.enabled, isFalse);
      expect(hunt.anchor, isNull);
      expect(hunt.target, isNull);
    });

    test('토글은 껐다 켰다를 뒤집고 켠 뒤의 상태를 돌려준다', () {
      final hunt = _controller();
      expect(hunt.toggle(Vector2(1, 1)), isTrue);
      expect(hunt.enabled, isTrue);
      expect(hunt.toggle(Vector2(1, 1)), isFalse);
      expect(hunt.enabled, isFalse);
    });
  });

  group('자동 사냥 — 반경', () {
    test('반경은 1 m 아래로도 10 m 위로도 갈 수 없다', () {
      final hunt = _controller();

      hunt.radiusMeters = 0.2;
      expect(hunt.radiusMeters, AutoHuntController.minRadiusMeters);
      expect(hunt.radiusMeters, 1.0);

      hunt.radiusMeters = 99;
      expect(hunt.radiusMeters, AutoHuntController.maxRadiusMeters);
      expect(hunt.radiusMeters, 10.0);
    });

    test('생성자로 넘긴 반경도 같은 범위로 잘린다', () {
      expect(_controller(radiusMeters: 0).radiusMeters, 1.0);
      expect(_controller(radiusMeters: 1000).radiusMeters, 10.0);
    });

    test('거리 비교에 쓰는 값은 미터가 아니라 타일로 환산한 값이다', () {
      final hunt = _controller(radiusMeters: 8);
      expect(hunt.radiusTiles, metersToTiles(8));
    });
  });

  group('자동 사냥 — 대상 선택', () {
    test('반경 안의 대상을 고른다', () {
      final hunt = _controller(radiusMeters: 5)..enable(Vector2.zero());
      final mob = _Mob(3, 0);

      _step(hunt, player: Vector2.zero(), mobs: [mob]);
      expect(hunt.target, same(mob));
    });

    test('반경 밖의 대상은 고르지 않는다', () {
      final hunt = _controller(radiusMeters: 5)..enable(Vector2.zero());
      final far = _Mob(6, 0);

      final decision = _step(hunt, player: Vector2.zero(), mobs: [far]);
      expect(hunt.target, isNull);
      expect(decision.action, AutoHuntAction.idle);
    });

    test('반경 경계에 정확히 걸친 대상은 사냥 대상에 포함된다', () {
      final hunt = _controller(radiusMeters: 5)..enable(Vector2.zero());
      final edge = _Mob(5, 0);

      _step(hunt, player: Vector2.zero(), mobs: [edge]);
      expect(hunt.target, same(edge));
    });

    test('죽어 있는 대상은 처음부터 고르지 않는다', () {
      final hunt = _controller()..enable(Vector2.zero());
      final corpse = _Mob(1, 0, alive: false);

      _step(hunt, player: Vector2.zero(), mobs: [corpse]);
      expect(hunt.target, isNull);
    });

    test('플레이어가 아니라 앵커에 가까운 쪽을 고른다', () {
      // 이것이 "앵커 중심 사냥"의 핵심이다. 플레이어 기준으로 고르면 추격할
      // 때마다 반경 가장자리의 다음 사냥감이 더 가까워져 앵커에서 끝없이
      // 끌려 나간다.
      final hunt = _controller(radiusMeters: 5)..enable(Vector2.zero());

      final nearAnchor = _Mob(1, 0); // 앵커에서 1, 플레이어에서 3
      final nearPlayer = _Mob(4.5, 0); // 앵커에서 4.5, 플레이어에서 0.5

      _step(
        hunt,
        player: Vector2(4, 0),
        mobs: [nearPlayer, nearAnchor],
      );
      expect(hunt.target, same(nearAnchor));
    });

    test('앵커를 옮기면 쫓던 대상을 놓고 새 중심에서 다시 고른다', () {
      final hunt = _controller(radiusMeters: 3)..enable(Vector2.zero());
      final first = _Mob(2, 0);
      final second = _Mob(20, 0);

      _step(hunt, player: Vector2.zero(), mobs: [first, second]);
      expect(hunt.target, same(first));

      hunt.moveAnchor(Vector2(20, 0));
      expect(hunt.target, isNull);

      _step(hunt, player: Vector2.zero(), mobs: [first, second]);
      expect(hunt.target, same(second));
    });

    test('꺼져 있으면 앵커를 옮기라는 요청을 무시한다', () {
      final hunt = _controller();
      hunt.moveAnchor(Vector2(5, 5));
      expect(hunt.anchor, isNull);
    });
  });

  group('자동 사냥 — 대상 해제', () {
    test('대상이 죽으면 놓아준다', () {
      final hunt = _controller()..enable(Vector2.zero());
      final mob = _Mob(2, 0);

      _step(hunt, player: Vector2.zero(), mobs: [mob]);
      expect(hunt.target, same(mob));

      mob.alive = false;
      _step(hunt, player: Vector2.zero(), mobs: [mob]);
      expect(hunt.target, isNull);
    });

    test('반경을 살짝 넘은 대상은 히스테리시스 안에서 계속 쫓는다', () {
      final hunt = _controller(radiusMeters: 5)..enable(Vector2.zero());
      final mob = _Mob(4, 0);

      _step(hunt, player: Vector2.zero(), mobs: [mob]);
      expect(hunt.target, same(mob));

      // 5.0 을 넘었지만 아직 5.0 + 0.5 안이다. 경계에서 잡았다 놨다 하는
      // 것을 막기 위해 놓는 기준을 더 넓게 두었다.
      mob.grid.setValues(5.3, 0);
      _step(hunt, player: Vector2.zero(), mobs: [mob]);
      expect(hunt.target, same(mob));
    });

    test('히스테리시스까지 넘어가면 놓아준다', () {
      final hunt = _controller(radiusMeters: 5)..enable(Vector2.zero());
      final mob = _Mob(4, 0);

      _step(hunt, player: Vector2.zero(), mobs: [mob]);
      expect(hunt.target, same(mob));

      mob.grid.setValues(5.0 + AutoHuntController.releaseMargin + 0.1, 0);
      _step(hunt, player: Vector2.zero(), mobs: [mob]);
      expect(hunt.target, isNull);
    });

    test('forget 은 쫓던 대상을 즉시 놓게 한다', () {
      final hunt = _controller()..enable(Vector2.zero());
      final mob = _Mob(2, 0);

      _step(hunt, player: Vector2.zero(), mobs: [mob]);
      expect(hunt.target, same(mob));

      hunt.forget(mob);
      expect(hunt.target, isNull);
    });
  });

  group('자동 사냥 — 행동 결정', () {
    test('사거리 밖이면 대상 쪽으로 접근한다', () {
      final hunt = _controller()..enable(Vector2.zero());
      final mob = _Mob(3, 0);

      final decision = _step(hunt, player: Vector2.zero(), mobs: [mob]);
      expect(decision.action, AutoHuntAction.approach);
      expect(decision.target, same(mob));
      expect(decision.destination, Vector2(3, 0));
    });

    test('사거리 안이면 공격한다', () {
      final hunt = _controller()..enable(Vector2.zero());
      final mob = _Mob(1.2, 0);

      final decision = _step(
        hunt,
        player: Vector2.zero(),
        mobs: [mob],
        attackRange: 1.5,
      );
      expect(decision.action, AutoHuntAction.attack);
      expect(decision.target, same(mob));
    });

    test('사거리에 정확히 걸치면 접근이 아니라 공격이다', () {
      final hunt = _controller()..enable(Vector2.zero());
      final mob = _Mob(1.5, 0);

      final decision = _step(
        hunt,
        player: Vector2.zero(),
        mobs: [mob],
        attackRange: 1.5,
      );
      expect(decision.action, AutoHuntAction.attack);
    });

    test('사냥감이 없고 앵커에서 벗어나 있으면 앵커로 돌아간다', () {
      final hunt = _controller()..enable(Vector2.zero());

      final decision = _step(hunt, player: Vector2(3, 0));
      expect(decision.action, AutoHuntAction.returnToAnchor);
      expect(decision.destination, Vector2.zero());
    });

    test('사냥감이 없고 앵커 위에 있으면 기다린다', () {
      final hunt = _controller()..enable(Vector2.zero());

      final decision = _step(hunt, player: Vector2(0.3, 0));
      expect(decision.action, AutoHuntAction.idle);
      expect(decision.destination, isNull);
    });

    test('돌아갈 목적지는 앵커의 복사본이라 호출부가 바꿔도 안전하다', () {
      final hunt = _controller()..enable(Vector2.zero());

      final decision = _step(hunt, player: Vector2(3, 0));
      decision.destination!.setValues(99, 99);
      expect(hunt.anchor, Vector2.zero());
    });

    test('사람이 직접 조작하는 동안에는 개입하지 않되 상태는 지킨다', () {
      final hunt = _controller()..enable(Vector2.zero());
      final mob = _Mob(2, 0);

      _step(hunt, player: Vector2.zero(), mobs: [mob]);
      expect(hunt.target, same(mob));

      final decision = _step(
        hunt,
        player: Vector2.zero(),
        mobs: [mob],
        suspended: true,
      );
      expect(decision.action, AutoHuntAction.none);
      // 손을 떼면 하던 사냥을 그대로 이어야 한다.
      expect(hunt.target, same(mob));
    });
  });

  group('자동 사냥 — 닿지 않는 대상 포기', () {
    test('오래 쫓아도 사거리에 못 넣으면 포기하고 한동안 다시 고르지 않는다', () {
      final hunt = _controller(radiusMeters: 10)..enable(Vector2.zero());
      // 벽 뒤에 있어 영원히 닿지 못하는 상황을 흉내 낸다. 경로 탐색이 없으므로
      // 포기가 없으면 이 자리에서 사냥이 멈춘다.
      final unreachable = _Mob(5, 0);

      for (var i = 0; i < 4; i++) {
        _step(hunt, player: Vector2.zero(), mobs: [unreachable], dt: 1);
      }
      expect(hunt.target, isNull);

      // 곧바로 다시 고르면 같은 벽에 붙는 것을 반복한다.
      _step(hunt, player: Vector2.zero(), mobs: [unreachable], dt: 0.1);
      expect(hunt.target, isNull);
    });

    test('차단 시간이 지나면 다시 사냥 대상이 된다', () {
      final hunt = _controller(radiusMeters: 10)..enable(Vector2.zero());
      final mob = _Mob(5, 0);

      for (var i = 0; i < 4; i++) {
        _step(hunt, player: Vector2.zero(), mobs: [mob], dt: 1);
      }
      expect(hunt.target, isNull);

      // 첫 차단은 blockDurationBase(8초)다. 그만큼 흘리면 다시 후보가 된다.
      for (var i = 0; i < AutoHuntController.blockDurationBase.toInt(); i++) {
        _step(hunt, player: Vector2.zero(), mobs: [mob], dt: 1);
      }
      expect(hunt.target, same(mob));
    });

    test('차단 시간은 실패가 쌓일수록 배로 늘고 상한에서 멈춘다', () {
      const base = AutoHuntController.blockDurationBase;
      expect(AutoHuntController.blockDurationFor(1), base);
      expect(AutoHuntController.blockDurationFor(2), base * 2);
      expect(AutoHuntController.blockDurationFor(3), base * 4);
      // 상한을 넘기려 해도 거기서 멈춘다 — 잠깐 막혔던 몬스터가 사실상
      // 영구 제외되면 안 된다.
      expect(
        AutoHuntController.blockDurationFor(99),
        AutoHuntController.blockDurationMax,
      );
    });

    test('닿지 않는 몬스터가 둘이어도 더 먼 정상 몬스터에게 순서가 온다', () {
      // 회귀 방지: 차단 시간이 추격 시간보다 짧으면 A 와 B 의 차단 구간이
      // 서로 어긋나 항상 하나는 후보로 살아 있고, 그보다 먼 C 는 한 번도
      // 선택되지 못한다(영구 기아). 차단이 실패마다 길어져야 둘이 동시에
      // 막히는 순간이 생기고 그 틈에 C 가 선택된다.
      final hunt = _controller(radiusMeters: 10)..enable(Vector2.zero());
      final unreachableNear = _Mob(2, 0);
      final unreachableMid = _Mob(3, 0);
      final farther = _Mob(6, 0);
      final mobs = [unreachableNear, unreachableMid, farther];

      var reached = false;
      for (var i = 0; i < 60; i++) {
        _step(hunt, player: Vector2.zero(), mobs: mobs, dt: 1);
        if (identical(hunt.target, farther)) {
          reached = true;
          break;
        }
      }
      expect(reached, isTrue, reason: '더 먼 정상 몬스터가 한 번도 선택되지 않았다');
    });

    test('닿고 나면 그동안의 실패가 초기화되어 차단이 다시 짧아진다', () {
      final hunt = _controller(radiusMeters: 10)..enable(Vector2.zero());
      final mob = _Mob(5, 0);
      const base = AutoHuntController.blockDurationBase;

      // 1차 실패 → base 만큼 차단.
      for (var i = 0; i < 4; i++) {
        _step(hunt, player: Vector2.zero(), mobs: [mob], dt: 1);
      }
      for (var i = 0; i < base.toInt(); i++) {
        _step(hunt, player: Vector2.zero(), mobs: [mob], dt: 1);
      }
      expect(hunt.target, same(mob));

      // 사거리 안으로 붙어 한 번 때린다. 이때 실패 기록이 지워져야 한다.
      final decision = _step(hunt, player: Vector2(4.5, 0), mobs: [mob], dt: 0.1);
      expect(decision.action, AutoHuntAction.attack);

      // 다시 놓쳐 실패해도 2차(base*2)가 아니라 1차(base) 차단이어야 한다.
      for (var i = 0; i < 4; i++) {
        _step(hunt, player: Vector2.zero(), mobs: [mob], dt: 1);
      }
      expect(hunt.target, isNull);
      for (var i = 0; i < base.toInt(); i++) {
        _step(hunt, player: Vector2.zero(), mobs: [mob], dt: 1);
      }
      expect(hunt.target, same(mob));
    });

    test('때리는 동안 밀고 밀려도 포기 판정에 걸리지 않는다', () {
      final hunt = _controller()..enable(Vector2.zero());
      final mob = _Mob(1, 0);

      // 사거리 안에 머무는 한 아무리 오래 붙어 있어도 계속 때려야 한다.
      for (var i = 0; i < 20; i++) {
        final decision = _step(
          hunt,
          player: Vector2.zero(),
          mobs: [mob],
          dt: 1,
        );
        expect(decision.action, AutoHuntAction.attack);
      }
      expect(hunt.target, same(mob));
    });
  });
}
