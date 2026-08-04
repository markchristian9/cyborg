import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:actionrpg/game/action_rpg_game.dart';
import 'package:actionrpg/game/entities/enemy.dart';
import 'package:actionrpg/game/entities/iso_entity.dart';
import 'package:actionrpg/game/systems/hit_stop.dart';
import 'package:actionrpg/game/systems/monster_codex.dart';

/// 전투 중 게임이 멈추던(hang) 두 원인에 대한 회귀 테스트.
///
/// 두 증상은 원인이 완전히 다르다.
///  1. **진짜 정지** — 적이 죽는 순간 `ConcurrentModificationError` 가 Flame 의
///     `update()` 안에서 터져 게임 루프가 죽었다.
///  2. **체감 정지** — 히트스톱이 연속 피격마다 새로 걸려 슬로우모션이 영영
///     끝나지 않았다.
void main() {
  group('대상 목록은 스냅샷이다 — 순회 중 적이 죽어도 멈추지 않는다', () {
    /// 살아 있는 로봇 [count]기를 목록에 세운다.
    ActionRpgGame gameWithEnemies(int count) {
      final game = ActionRpgGame();
      for (var i = 0; i < count; i++) {
        game.enemies.add(
          Enemy(
            species: MonsterCodex.byLevel(1),
            grid: Vector2(i.toDouble(), 0),
          ),
        );
      }
      return game;
    }

    test('meleeTargets()는 지연 순회가 아니라 복사본을 돌려준다', () {
      final game = gameWithEnemies(3);

      // 반환값이 `Iterable`(sync* 지연 순회)로 되돌아가면 여기서 걸린다.
      expect(game.meleeTargets(), isA<List<Damageable>>());
      expect(game.projectileTargetsForPlayer(), isA<List<Damageable>>());
    });

    test('순회 도중 원본 목록에서 대상을 지워도 예외가 나지 않는다', () {
      final game = gameWithEnemies(3);
      final targets = game.meleeTargets();

      // 실제 전투에서 `onEnemyKilled` 가 하는 일 그대로다 — 근접 공격이 대상
      // 목록을 도는 동안 맞아 죽은 적이 `enemies` 에서 빠진다. 목록이 `enemies`
      // 를 지연 순회하고 있으면 다음 걸음에서 ConcurrentModificationError 가
      // 터지고, 그 예외는 게임 루프의 update 안이라 화면이 통째로 멈춘다.
      expect(() {
        for (final target in targets) {
          game.enemies.remove(target);
        }
      }, returnsNormally);

      // 스냅샷이므로 셋 다 끝까지 돌았다.
      expect(game.enemies, isEmpty);
      expect(targets, hasLength(3));
    });

    test('발사체가 쓰는 목록도 같은 계약을 지킨다', () {
      final game = gameWithEnemies(2);
      final targets = game.projectileTargetsForPlayer();

      expect(() {
        for (final target in targets) {
          game.enemies.remove(target);
        }
      }, returnsNormally);
      expect(targets, hasLength(2));
    });

    test('스냅샷은 뜬 시점에 고정된다 — 이후 원본 변경에 흔들리지 않는다', () {
      final game = gameWithEnemies(2);
      final targets = game.meleeTargets();

      // 스트리밍이 새 로봇을 깨우거나(enemies.add) 처치가 목록을 줄여도
      // (enemies.remove) 이번 판정은 뜬 시점의 대상만 본다.
      game.enemies.add(
        Enemy(species: MonsterCodex.byLevel(1), grid: Vector2(9, 9)),
      );
      game.enemies.removeAt(0);

      expect(targets, hasLength(2));
      expect(game.enemies, hasLength(2));
    });
  });

  group('히트스톱은 스스로를 연장하지 못한다', () {
    test('한 번 걸면 슬로우가 걸리고 시간이 1/4로 흐른다', () {
      final hitStop = HitStop()..trigger(0.06);

      expect(hitStop.isActive, isTrue);
      expect(hitStop.advance(0.016), closeTo(0.016 * HitStop.timeScale, 1e-9));
    });

    test('슬로우 중 연속으로 맞아도 재발동하지 않는다', () {
      final hitStop = HitStop()..trigger(0.06);

      // 난전에서 매 프레임 얻어맞는 상황. 잠금이 없다면 _remaining 이 매번
      // 0.06 으로 되채워져 슬로우가 영원히 풀리지 않는다 — 그것이 "PC 가
      // 공격받으면 게임이 멈춘다"의 정체였다.
      var elapsed = 0.0;
      for (var i = 0; i < 60; i++) {
        hitStop.trigger(0.06);
        hitStop.advance(0.016);
        elapsed += 0.016;
      }

      expect(elapsed, greaterThan(0.9));
      expect(
        hitStop.isActive,
        isFalse,
        reason: '1초 가까이 두들겨 맞아도 슬로우는 진작 풀려 있어야 한다',
      );
    });

    test('잠금이 풀린 뒤에는 다시 걸린다 — 연출을 잃지는 않는다', () {
      final hitStop = HitStop()..trigger(0.06);

      // 슬로우(0.06) + 회복(0.18) 을 모두 흘려보낸다.
      for (var i = 0; i < 20; i++) {
        hitStop.advance(0.016);
      }
      expect(hitStop.isLocked, isFalse);

      hitStop.trigger(0.05);
      expect(hitStop.isActive, isTrue);
    });

    test('내부 타이머는 감쇠 전 dt로 줄어든다', () {
      final hitStop = HitStop()..trigger(0.1);

      // 느려진 dt 로 자기 타이머를 줄이면 슬로우가 네 배 오래 간다.
      hitStop.advance(0.04);

      expect(hitStop.remaining, closeTo(0.06, 1e-9));
    });

    test('reset()은 슬로우와 잠금을 함께 지운다', () {
      final hitStop = HitStop()..trigger(0.16);

      hitStop.reset();

      expect(hitStop.isActive, isFalse);
      expect(hitStop.isLocked, isFalse);
    });
  });
}
