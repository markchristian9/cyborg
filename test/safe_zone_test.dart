import 'dart:math' as math;

import 'package:actionrpg/game/entities/player.dart';
import 'package:actionrpg/game/systems/monster_codex.dart';
import 'package:actionrpg/game/iso.dart';
import 'package:actionrpg/game/level/level_map.dart';
import 'package:actionrpg/game/level/safe_zone.dart';
import 'package:actionrpg/game/systems/monster_population.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SafeZone', () {
    final zone = SafeZone.centeredOn(Vector2(500, 500));

    test('월드 중앙에 50 m × 50 m로 놓인다', () {
      expect(zone.sizeInMeters, 50);
      expect(zone.center, Vector2(500, 500));
      expect(tilesToMeters(zone.maxX - zone.minX), 50);
      expect(tilesToMeters(zone.maxY - zone.minY), 50);
    });

    test('중심에서 25 m까지가 안, 그 밖은 바깥이다', () {
      expect(zone.contains(500, 500), isTrue);
      expect(zone.contains(524.9, 524.9), isTrue);
      expect(zone.contains(525.1, 500), isFalse);
      expect(zone.contains(500, 474.9), isFalse);
    });

    test('몸통이 경계에 걸치는 것도 침범으로 본다', () {
      // 경계 바로 바깥이지만 반경 0.5인 몸통은 경계를 파고든다.
      expect(zone.overlapsBody(525.3, 500, 0.5), isTrue);
      expect(zone.overlapsBody(525.8, 500, 0.5), isFalse);
    });

    test('침범한 좌표는 가장 가까운 바깥으로 밀려난다', () {
      // 오른쪽 경계에 가까운 안쪽 지점.
      final pushed = zone.pushOutside(Vector2(524, 500), margin: 0.4);
      expect(pushed.x, greaterThanOrEqualTo(zone.maxX + 0.4));
      expect(pushed.y, 500);
      expect(zone.overlapsBody(pushed.x, pushed.y, 0.4), isFalse);

      // 바깥 지점은 그대로 둔다.
      final untouched = zone.pushOutside(Vector2(600, 600));
      expect(untouched, Vector2(600, 600));
    });

    test('경계까지의 부호 있는 거리는 안에서 음수다', () {
      expect(zone.signedDistance(500, 500), lessThan(0));
      expect(zone.signedDistance(530, 500), closeTo(5, 1e-9));
    });
  });

  group('안전지대 지형', () {
    final map = LevelMap.generate();

    test('맵의 안전지대는 월드 한가운데다', () {
      expect(map.safeZone.center, map.worldCenter);
      expect(map.safeZone.sizeInMeters, kSafeZoneSizeMeters);
    });

    test('구역 안에는 구조물도 방화벽도 없고 전부 통행 가능하다', () {
      final zone = map.safeZone;
      for (var y = zone.minY.floor(); y < zone.maxY.ceil(); y++) {
        for (var x = zone.minX.floor(); x < zone.maxX.ceil(); x++) {
          expect(map.isWalkable(x, y), isTrue, reason: '($x, $y)가 막혀 있다');
          expect(map.blockHeightAt(x, y), 0, reason: '($x, $y)에 구조물이 있다');
          expect(
            map.tileAt(x, y),
            isNot(TileType.hazard),
            reason: '($x, $y)에 방화벽이 남아 있다',
          );
        }
      }
    });

    test('재접속 지점은 언제나 안전지대 안이다', () {
      for (var seed = 0; seed < 40; seed++) {
        final point = map.respawnPoint(math.Random(seed));
        expect(map.safeZone.containsPoint(point), isTrue);
        expect(map.isWalkableAt(point.x, point.y), isTrue);
      }
    });
  });

  group('몬스터 어그로', () {
    test('모든 종의 어그로 범위가 1~9 m 안에 있다', () {
      for (final stats in MonsterCodex.all.map((s) => s.stats)) {
        expect(stats.aggroMinMeters, greaterThanOrEqualTo(kAggroMinMeters));
        expect(stats.aggroMaxMeters, lessThanOrEqualTo(kAggroMaxMeters));
        expect(stats.aggroMinMeters, lessThanOrEqualTo(stats.aggroMaxMeters));
      }
    });

    test('계통마다 어그로 폭이 다르게 잡혀 있다', () {
      final drone = MonsterCodex.ofBuild(MonsterBuild.drone).first.stats;
      final walker = MonsterCodex.ofBuild(MonsterBuild.walker).first.stats;
      // 비행 정찰 계통이 보행 계통보다 예민하다.
      expect(drone.aggroMinMeters, greaterThan(walker.aggroMaxMeters));
    });
  });

  group('사망 후 안전지대 재가동', () {
    test('재가동 지점은 언제나 안전지대 안이고 통행 가능하다', () {
      final map = LevelMap.generate();
      for (var seed = 0; seed < 60; seed++) {
        final point = map.respawnPoint(math.Random(seed));
        expect(map.safeZone.containsPoint(point), isTrue);
        expect(map.isWalkableAt(point.x, point.y), isTrue);
        // 경계에 딱 붙어 되살아나면 한 발짝에 밖으로 나가 버린다.
        expect(map.safeZone.signedDistance(point.x, point.y), lessThan(-1.0));
      }
    });

    test('재가동하면 쓰러지기 전의 클릭 이동 목표를 버린다', () {
      // 목표가 남으면 아무도 조작하지 않았는데 혼자 안전지대 밖으로 걸어간다.
      final player = Player(grid: Vector2(880, 880));
      player.moveTo(Vector2(900, 910));
      expect(player.moveTarget, isNotNull);

      player.respawnAt(Vector2(500, 500));

      expect(player.moveTarget, isNull);
      expect(player.grid, Vector2(500, 500));
      expect(player.hp, player.maxHp);
    });

    test('텔레포트도 떠나온 곳의 클릭 목표를 버린다', () {
      final player = Player(grid: Vector2(880, 880));
      player.moveTo(Vector2(900, 910));

      player.teleportTo(Vector2(500, 500));

      expect(player.moveTarget, isNull);
      expect(player.grid, Vector2(500, 500));
    });
  });

  group('몬스터 배치', () {
    test('안전지대 안에는 한 마리도 놓이지 않는다', () {
      // 웨이브가 사라지면서 스폰 책임이 `MonsterPopulation` 으로 옮겨졌다.
      // 안전지대는 쉬는 곳이라는 약속은 그대로여야 한다 — 여기가 뚫리면
      // 접속하자마자 얻어맞고, 회복할 자리가 월드에서 사라진다.
      final map = LevelMap.generate();
      final population = MonsterPopulation.generate(map);

      // 안전지대와 그 둘레만 보면 된다. 먼 사냥터의 몹은 이 약속과 무관하다.
      final nearby = population.seedsNear(
        map.safeZone.center,
        kSafeZoneSizeMeters,
      );

      for (final seed in nearby) {
        expect(
          map.safeZone.containsPoint(seed.home),
          isFalse,
          reason: '${seed.home}이 안전지대 안이다',
        );
      }
    });
  });
}
