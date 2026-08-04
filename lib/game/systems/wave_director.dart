import 'dart:math' as math;

import 'package:flame/components.dart';

import '../entities/enemy.dart';
import '../level/level_map.dart';

/// 한 웨이브의 구성 정보.
class WavePlan {
  WavePlan({
    required this.index,
    required this.units,
    required this.hpMultiplier,
    required this.damageMultiplier,
    required this.isBossWave,
  });

  final int index;

  /// 이번 웨이브에서 등장할 유닛 목록.
  final List<EnemyKind> units;
  final double hpMultiplier;
  final double damageMultiplier;
  final bool isBossWave;

  int get totalCount => units.length;
}

/// 웨이브 진행을 계획하고 스폰 지점을 결정하는 시스템.
///
/// 실제 스폰은 게임 본체가 수행하고, 이 클래스는 "무엇을 어디에"만 정한다.
class WaveDirector {
  WaveDirector({required this.map, math.Random? random})
      : _random = random ?? math.Random();

  final LevelMap map;
  final math.Random _random;

  int currentWave = 0;

  /// [wave]번째(1부터) 웨이브 구성을 만든다.
  WavePlan planFor(int wave) {
    final isBossWave = wave % 5 == 0;
    final units = <EnemyKind>[];

    // 웨이브가 진행될수록 총량과 상위 유닛 비중이 늘어난다.
    final budget = 3 + wave * 2;
    var spent = 0;

    if (isBossWave) {
      units.add(EnemyKind.commander);
      spent += 8;
    }

    while (spent < budget) {
      final roll = _random.nextDouble();
      final heavyChance = (wave - 2) * 0.05;
      final sentryChance = 0.25 + wave * 0.04;

      if (wave >= 3 && roll < heavyChance.clamp(0.0, 0.32)) {
        units.add(EnemyKind.heavy);
        spent += 4;
      } else if (roll < sentryChance.clamp(0.0, 0.6) + 0.2) {
        units.add(EnemyKind.sentry);
        spent += 2;
      } else {
        units.add(EnemyKind.scout);
        spent += 1;
      }
    }

    units.shuffle(_random);

    return WavePlan(
      index: wave,
      units: units,
      hpMultiplier: 1 + (wave - 1) * 0.16,
      damageMultiplier: 1 + (wave - 1) * 0.1,
      isBossWave: isBossWave,
    );
  }

  /// 스폰 지점을 안전지대 경계에서 최소한 이만큼 띄운다(타일).
  static const double _safeZoneClearance = 1.5;

  /// 플레이어로부터 [minDistance] 이상 떨어진 통행 가능한 스폰 지점을 고른다.
  ///
  /// 안전지대 안에는 절대 스폰하지 않는다. 플레이어가 안전지대 안에 있으면
  /// 그 주변이 통째로 금지 구역이므로, 경계 바깥의 한 지점을 기준으로 삼는다.
  Vector2 pickSpawnPoint(
    Vector2 playerGrid, {
    double minDistance = 9,
    double maxDistance = 20,
  }) {
    final zone = map.safeZone;
    final origin = zone.containsPoint(playerGrid)
        ? _pointOutsideSafeZone()
        : playerGrid;

    for (var attempt = 0; attempt < 220; attempt++) {
      final angle = _random.nextDouble() * math.pi * 2;
      final distance =
          minDistance + _random.nextDouble() * (maxDistance - minDistance);
      final x = origin.x + math.cos(angle) * distance;
      final y = origin.y + math.sin(angle) * distance;
      if (zone.overlapsBody(x, y, _safeZoneClearance)) continue;
      if (!map.isWalkableAt(x, y)) continue;
      // 유닛 몸집을 고려해 주변 칸도 비어 있어야 한다.
      if (!map.isWalkableAt(x - 0.5, y - 0.5)) continue;
      if (!map.isWalkableAt(x + 0.5, y + 0.5)) continue;
      return Vector2(x, y);
    }
    // 최후 수단: 맵 전체에서 아무 통행 가능 지점.
    for (var attempt = 0; attempt < 400; attempt++) {
      final x = _random.nextDouble() * map.width;
      final y = _random.nextDouble() * map.height;
      if (zone.overlapsBody(x, y, _safeZoneClearance)) continue;
      if (map.isWalkableAt(x, y)) return Vector2(x, y);
    }
    return map.nearestWalkable(_pointOutsideSafeZone());
  }

  /// 안전지대 경계 바로 바깥의 한 지점을 무작위 방향으로 고른다.
  ///
  /// 정사각형 경계까지의 거리를 방향별로 계산하므로 네 변 어디로든
  /// 고르게 흩어진다.
  Vector2 _pointOutsideSafeZone() {
    final zone = map.safeZone;
    final angle = _random.nextDouble() * math.pi * 2;
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    final reach = (zone.halfExtent + _safeZoneClearance + 1) /
        math.max(cos.abs(), sin.abs());
    return Vector2(
      zone.center.x + cos * reach,
      zone.center.y + sin * reach,
    );
  }
}
