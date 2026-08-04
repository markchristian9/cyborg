import 'dart:math' as math;

import 'package:flame/components.dart';

import '../entities/enemy.dart';
import '../iso.dart';
import '../level/level_map.dart';

/// 월드에 상주하는 로봇 한 개체의 논리 정보.
///
/// 실제 [Enemy] 컴포넌트는 플레이어가 가까이 왔을 때만 만들어지고,
/// 멀어지면 제거된다. 이 시드는 그동안에도 계속 살아 있는 "장부"다.
class MonsterSeed {
  MonsterSeed({
    required this.id,
    required this.kind,
    required this.home,
    required this.hpMultiplier,
    required this.damageMultiplier,
  }) : position = home.clone();

  /// 개체 고유 번호. 활성화된 [Enemy]와 시드를 연결하는 열쇠다.
  final int id;

  final EnemyKind kind;

  /// 배치된 원래 자리. 리스폰과 순찰 기준점이 된다.
  final Vector2 home;

  final double hpMultiplier;
  final double damageMultiplier;

  /// 마지막으로 관측된 위치. 비활성화될 때 갱신된다.
  Vector2 position;

  /// 지금 [Enemy] 컴포넌트로 살아 움직이는 중인지 여부.
  bool active = false;

  /// 0보다 크면 파괴된 상태이며, 이 시간이 지나야 다시 나타난다.
  double respawnIn = 0;

  bool get isDestroyed => respawnIn > 0;
}

/// 1 km × 1 km 월드 전역에 흩어진 로봇 개체군.
///
/// 수천 마리를 한꺼번에 컴포넌트로 만들 수는 없으므로 개체를 청크별로
/// 나눠 담고, 플레이어 주변 청크만 [seedsNear]로 꺼내 쓴다.
class MonsterPopulation {
  MonsterPopulation._({
    required this.map,
    required Map<int, List<MonsterSeed>> byChunk,
    required this.total,
  }) : _byChunk = byChunk;

  final LevelMap map;

  /// 청크 키(cy * chunksX + cx) → 그 청크에 속한 개체 목록.
  final Map<int, List<MonsterSeed>> _byChunk;

  /// 월드 전체 개체 수.
  final int total;

  /// 파괴된 개체가 다시 나타나기까지의 시간(초).
  static const double respawnDelay = 75;

  /// 살아 있는(파괴되지 않은) 개체 수.
  int get aliveCount {
    var count = 0;
    for (final list in _byChunk.values) {
      for (final seed in list) {
        if (!seed.isDestroyed) count++;
      }
    }
    return count;
  }

  /// 파괴된 개체의 리스폰 시계를 돌린다.
  void tick(double dt) {
    for (final list in _byChunk.values) {
      for (final seed in list) {
        if (seed.respawnIn > 0) {
          seed.respawnIn -= dt;
          if (seed.respawnIn <= 0) {
            seed.respawnIn = 0;
            seed.position.setFrom(seed.home);
          }
        }
      }
    }
  }

  /// [center]를 중심으로 [radiusTiles] 안에 있는 청크의 개체를 모아 준다.
  ///
  /// 파괴 상태인 개체는 제외한다.
  List<MonsterSeed> seedsNear(Vector2 center, double radiusTiles) {
    final minCx =
        ((center.x - radiusTiles) / kChunkTiles).floor().clamp(0, map.chunksX - 1);
    final maxCx =
        ((center.x + radiusTiles) / kChunkTiles).floor().clamp(0, map.chunksX - 1);
    final minCy =
        ((center.y - radiusTiles) / kChunkTiles).floor().clamp(0, map.chunksY - 1);
    final maxCy =
        ((center.y + radiusTiles) / kChunkTiles).floor().clamp(0, map.chunksY - 1);

    final result = <MonsterSeed>[];
    for (var cy = minCy; cy <= maxCy; cy++) {
      for (var cx = minCx; cx <= maxCx; cx++) {
        final list = _byChunk[cy * map.chunksX + cx];
        if (list == null) continue;
        for (final seed in list) {
          if (seed.isDestroyed) continue;
          result.add(seed);
        }
      }
    }
    return result;
  }

  /// 개체가 파괴되었을 때 장부에 기록한다.
  void markDestroyed(MonsterSeed seed) {
    seed.active = false;
    seed.respawnIn = respawnDelay;
  }

  /// 월드 전역에 로봇 순찰대와 둥지를 절차적으로 배치한다.
  ///
  /// 시작 지점 주변은 안전 지대로 비우고, 중심에서 멀어질수록
  /// 개체 밀도와 상위 기종의 비중이 함께 올라간다.
  factory MonsterPopulation.generate(
    LevelMap map, {
    int? seed,

    /// 시작 지점 주위로 개체를 두지 않을 반경(타일).
    double safeRadius = 26,
  }) {
    final random = math.Random(seed ?? 77021);
    final byChunk = <int, List<MonsterSeed>>{};
    var nextId = 0;
    var total = 0;

    final spawn = map.spawn;
    final halfSpan = math.max(map.width, map.height) / 2;

    /// 통행 가능한 칸을 찾을 때까지 주변을 조금 훑어본다.
    Vector2? findFootingNear(int cx, int cy) {
      for (var attempt = 0; attempt < 14; attempt++) {
        final x = cx + random.nextInt(7) - 3;
        final y = cy + random.nextInt(7) - 3;
        if (!map.isWalkable(x, y)) continue;
        // 안전지대 안이나 경계에 걸치는 자리에는 상주 개체를 두지 않는다.
        if (map.safeZone.overlapsBody(x + 0.5, y + 0.5, 1.0)) continue;
        return Vector2(x + 0.5, y + 0.5);
      }
      return null;
    }

    for (var cy = 0; cy < map.chunksY; cy++) {
      for (var cx = 0; cx < map.chunksX; cx++) {
        final baseX = cx * kChunkTiles;
        final baseY = cy * kChunkTiles;
        final centerX = baseX + kChunkTiles / 2;
        final centerY = baseY + kChunkTiles / 2;

        final dx = centerX - spawn.x;
        final dy = centerY - spawn.y;
        final distance = math.sqrt(dx * dx + dy * dy);
        if (distance < safeRadius) continue;

        // 0(중심) ~ 1(외곽). 바깥일수록 적진 깊숙한 곳이다.
        final depth = (distance / halfSpan).clamp(0.0, 1.0);

        // 청크당 개체 수. 외곽 청크는 소대 규모로 몰려 있다.
        final squad = 3 + random.nextInt(4) + (depth * 6).round();
        final list = <MonsterSeed>[];

        for (var i = 0; i < squad; i++) {
          final footing = findFootingNear(
            baseX + random.nextInt(kChunkTiles),
            baseY + random.nextInt(kChunkTiles),
          );
          if (footing == null) continue;

          final kind = _rollKind(random, depth);
          list.add(
            MonsterSeed(
              id: nextId++,
              kind: kind,
              home: footing,
              hpMultiplier: 1 + depth * 1.6 + random.nextDouble() * 0.2,
              damageMultiplier: 1 + depth * 0.9,
            ),
          );
        }

        // 외곽에는 구역 지휘 유닛이 드물게 주둔한다.
        if (depth > 0.45 && random.nextDouble() < 0.07) {
          final footing = findFootingNear(
            baseX + kChunkTiles ~/ 2,
            baseY + kChunkTiles ~/ 2,
          );
          if (footing != null) {
            list.add(
              MonsterSeed(
                id: nextId++,
                kind: EnemyKind.commander,
                home: footing,
                hpMultiplier: 1 + depth * 1.2,
                damageMultiplier: 1 + depth * 0.8,
              ),
            );
          }
        }

        if (list.isEmpty) continue;
        byChunk[cy * map.chunksX + cx] = list;
        total += list.length;
      }
    }

    return MonsterPopulation._(map: map, byChunk: byChunk, total: total);
  }

  /// 구역 깊이에 따라 기종을 뽑는다.
  static EnemyKind _rollKind(math.Random random, double depth) {
    final roll = random.nextDouble();
    if (roll < 0.10 + depth * 0.22) return EnemyKind.heavy;
    if (roll < 0.45 + depth * 0.20) return EnemyKind.sentry;
    return EnemyKind.scout;
  }
}
