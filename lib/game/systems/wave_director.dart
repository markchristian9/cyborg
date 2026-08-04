import 'dart:math' as math;

import 'package:flame/components.dart';

import '../level/level_map.dart';
import 'monster_codex.dart';

/// 한 웨이브의 구성 정보.
class WavePlan {
  WavePlan({
    required this.index,
    required this.units,
    required this.hpMultiplier,
    required this.isBossWave,
  });

  final int index;

  /// 이번 웨이브에서 등장할 유닛 목록.
  final List<MonsterSpecies> units;
  final double hpMultiplier;
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

  /// [wave]번째 웨이브가 투입하는 추적대의 레벨대.
  ///
  /// 플레이어가 웨이브당 한두 레벨씩 오르는 것에 맞춰 완만하게 따라붙는다.
  /// 더 가파르게 잡으면 초반 몇 웨이브 만에 손댈 수 없는 기종이 내려온다.
  static int levelForWave(int wave) =>
      (1 + (wave - 1) * 1.5).round().clamp(1, MonsterCodex.maxLevel);

  /// 편성 예산에서 유닛 하나가 차지하는 몫.
  static int _cost(MonsterSpecies species) => switch (species.build) {
        MonsterBuild.drone => 1,
        MonsterBuild.walker => 2,
        MonsterBuild.siege => 4,
        MonsterBuild.sovereign => 8,
      };

  /// [wave]번째(1부터) 웨이브 구성을 만든다.
  WavePlan planFor(int wave) {
    final isBossWave = wave % 5 == 0;
    final level = levelForWave(wave);
    final units = <MonsterSpecies>[];

    // 웨이브가 진행될수록 총량과 상위 유닛 비중이 늘어난다.
    final budget = 3 + wave * 2;
    var spent = 0;

    if (isBossWave) {
      final sovereign = MonsterCodex.sovereignNear(level);
      units.add(sovereign);
      spent += _cost(sovereign);
    }

    while (spent < budget) {
      // 종 자체가 레벨을 품고 있으므로 난이도는 레벨대가 결정한다.
      final species = MonsterCodex.roll(_random, level, spread: 5);
      units.add(species);
      spent += _cost(species);
    }

    units.shuffle(_random);

    return WavePlan(
      index: wave,
      units: units,
      // 개체 편차용 미세 배율. 웨이브 난이도는 레벨대가 담당한다.
      hpMultiplier: 1 + (wave - 1) * 0.01,
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
    // 최후 수단: 기준점 둘레로 반경을 넓혀 가며 찾는다.
    //
    // 월드 전역을 무작위로 뽑으면 안 된다. 1 km 월드에서는 적이 최대 1.4 km
    // 떨어진 곳에 생기고, 그 거리는 몹 활성 반경 밖이라 영영 잠든 채로 남는다.
    // 웨이브 종료는 살아 있는 적이 없어야 성립하므로 웨이브가 끝나지 않는다.
    for (var ring = 2; ring <= 10; ring++) {
      final reach = maxDistance * ring;
      for (var attempt = 0; attempt < 40; attempt++) {
        final angle = _random.nextDouble() * math.pi * 2;
        final distance = _random.nextDouble() * reach;
        final x = origin.x + math.cos(angle) * distance;
        final y = origin.y + math.sin(angle) * distance;
        if (zone.overlapsBody(x, y, _safeZoneClearance)) continue;
        if (map.isWalkableAt(x, y)) return Vector2(x, y);
      }
    }

    // 그래도 못 찾으면 기준점에서 가장 가까운 통행 가능한 칸으로 떨어뜨린다.
    final fallback = map.nearestWalkable(origin);
    if (!zone.overlapsBody(fallback.x, fallback.y, _safeZoneClearance)) {
      return fallback;
    }
    return map.nearestWalkable(
      zone.pushOutside(fallback, margin: _safeZoneClearance + 0.5),
    );
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
