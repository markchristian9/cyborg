import 'dart:typed_data';

import 'package:actionrpg/game/iso.dart';
import 'package:actionrpg/game/level/level_map.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

/// 월드 규격은 "플레이어가 실제로 걸을 수 있는 거리"로 정의된다.
///
/// 격자 한 변이 1000이어도 가장자리가 통행 불가 테두리면 걸을 수 있는 거리는
/// 그만큼 줄어든다. 이 파일은 그 구분이 무너지지 않도록 못 박는다.
void main() {
  group('월드 규격 상수', () {
    test('걸을 수 있는 거리가 가로 1 km · 세로 1 km 다', () {
      expect(kWorldSizeMeters, 1000.0);
      expect(kWorldPlayableTiles, 1000);
      // 타일이 곧 미터라는 전제. 이게 깨지면 아래 계산이 전부 어긋난다.
      expect(kMetersPerTile, 1.0);
      expect(tilesToMeters(kWorldPlayableTiles.toDouble()), kWorldSizeMeters);
    });

    test('격자는 걸을 수 있는 영역에 양쪽 테두리를 더한 크기다', () {
      expect(kWorldTiles, kWorldPlayableTiles + kWorldEdgeMarginTiles * 2);
      // 테두리는 걸을 수 있는 거리를 깎지 않는다.
      expect(kWorldTiles, greaterThan(kWorldPlayableTiles));
    });

    test('청크 격자가 월드를 빈틈없이 덮는다', () {
      expect(kWorldChunks * kChunkTiles, greaterThanOrEqualTo(kWorldTiles));
      expect((kWorldChunks - 1) * kChunkTiles, lessThan(kWorldTiles));
    });
  });

  group('생성된 월드', () {
    final map = LevelMap.generate();

    test('격자 크기가 상수와 일치한다', () {
      expect(map.width, kWorldTiles);
      expect(map.height, kWorldTiles);
      expect(map.chunksX, kWorldChunks);
      expect(map.chunksY, kWorldChunks);
    });

    test('걸을 수 있는 폭이 정확히 1 km 다', () {
      expect(map.playableWidthInMeters, kWorldSizeMeters);
      expect(map.playableHeightInMeters, kWorldSizeMeters);
      // 격자 자체는 테두리만큼 더 크다.
      expect(map.widthInMeters, greaterThan(map.playableWidthInMeters));
    });

    test('테두리는 네 변 모두 통행 불가다', () {
      final midX = map.width ~/ 2;
      final midY = map.height ~/ 2;
      for (var i = 0; i < kWorldEdgeMarginTiles; i++) {
        expect(map.isWalkable(i, midY), isFalse, reason: '서쪽 $i번째');
        expect(map.isWalkable(map.width - 1 - i, midY), isFalse,
            reason: '동쪽 $i번째');
        expect(map.isWalkable(midX, i), isFalse, reason: '북쪽 $i번째');
        expect(map.isWalkable(midX, map.height - 1 - i), isFalse,
            reason: '남쪽 $i번째');
      }
    });

    test('안전지대는 월드 한가운데다', () {
      expect(map.safeZone.center, map.worldCenter);
    });

    test('한 덩어리로 이어진 통행 영역이 가로·세로 1 km를 덮는다', () {
      // 규격의 핵심. 폭이 1000이어도 중간이 끊겨 있으면 1 km를 걸을 수 없다.
      // 안전지대에서 물을 부어, 닿는 칸이 어디까지 퍼지는지 잰다.
      final reach = _floodFrom(map, map.safeZoneCenter);

      expect(
        reach.maxX - reach.minX + 1,
        kWorldPlayableTiles,
        reason: '동서로 이어진 폭이 1 km가 아니다',
      );
      expect(
        reach.maxY - reach.minY + 1,
        kWorldPlayableTiles,
        reason: '남북으로 이어진 폭이 1 km가 아니다',
      );
      // 통행 가능 구간의 양 끝에 정확히 닿아야 한다.
      expect(reach.minX, map.playableMin);
      expect(reach.maxX, map.playableMaxX - 1);
      expect(reach.minY, map.playableMin);
      expect(reach.maxY, map.playableMaxY - 1);
    });
  });
}

/// 폭 우선 탐색으로 [from]에서 걸어서 닿을 수 있는 칸의 범위를 잰다.
_Reach _floodFrom(LevelMap map, Vector2 from) {
  final startX = from.x.floor();
  final startY = from.y.floor();
  final visited = Uint8List(map.width * map.height);
  final queue = <int>[startY * map.width + startX];
  visited[queue.first] = 1;

  var minX = startX, maxX = startX, minY = startY, maxY = startY;

  for (var head = 0; head < queue.length; head++) {
    final index = queue[head];
    final x = index % map.width;
    final y = index ~/ map.width;

    if (x < minX) minX = x;
    if (x > maxX) maxX = x;
    if (y < minY) minY = y;
    if (y > maxY) maxY = y;

    void visit(int nx, int ny) {
      if (nx < 0 || ny < 0 || nx >= map.width || ny >= map.height) return;
      final next = ny * map.width + nx;
      if (visited[next] != 0) return;
      if (!map.isWalkable(nx, ny)) return;
      visited[next] = 1;
      queue.add(next);
    }

    visit(x - 1, y);
    visit(x + 1, y);
    visit(x, y - 1);
    visit(x, y + 1);
  }

  return _Reach(minX: minX, maxX: maxX, minY: minY, maxY: maxY);
}

class _Reach {
  _Reach({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final int minX;
  final int maxX;
  final int minY;
  final int maxY;
}
