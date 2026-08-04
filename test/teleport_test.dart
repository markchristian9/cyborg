import 'dart:math' as math;

import 'package:actionrpg/game/level/level_map.dart';
import 'package:actionrpg/game/level/teleport_destinations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TeleportDestination', () {
    final map = LevelMap.generate();

    test('목적지는 안전지대와 네 방위 다섯 곳이다', () {
      expect(TeleportDestination.values.length, 5);
      expect(
        TeleportDestination.values.where((d) => d.isSafe).length,
        1,
        reason: '안전지대는 하나뿐이어야 한다',
      );
    });

    test('안전지대는 월드 한가운데를 가리킨다', () {
      final anchor = TeleportDestination.safeZone.anchorOn(map);
      expect(anchor, map.safeZoneCenter);
      expect(map.safeZone.containsPoint(anchor), isTrue);
    });

    test('방위는 미니맵과 같은 그리드 축을 따른다', () {
      final north = TeleportDestination.north.anchorOn(map);
      final south = TeleportDestination.south.anchorOn(map);
      final east = TeleportDestination.east.anchorOn(map);
      final west = TeleportDestination.west.anchorOn(map);

      // 북이 남보다 y가 작고, 동이 서보다 x가 크다.
      expect(north.y, lessThan(south.y));
      expect(east.x, greaterThan(west.x));

      // 남북은 가로 한가운데, 동서는 세로 한가운데에 놓인다.
      expect(north.x, map.width / 2);
      expect(south.x, map.width / 2);
      expect(east.y, map.height / 2);
      expect(west.y, map.height / 2);
    });

    test('목표 지점은 통행 불가한 외곽 여백을 벗어나 있다', () {
      // 맵 가장자리 세 칸은 TileType.none 이라 착지할 수 없다.
      for (final dest in TeleportDestination.values) {
        final anchor = dest.anchorOn(map);
        expect(anchor.x, greaterThan(3));
        expect(anchor.y, greaterThan(3));
        expect(anchor.x, lessThan(map.width - 3));
        expect(anchor.y, lessThan(map.height - 3));
      }
    });

    test('다섯 목적지 모두 통행 가능한 곳으로 착지한다', () {
      for (final dest in TeleportDestination.values) {
        final point = dest.resolve(map, math.Random(7));
        expect(
          map.isWalkableAt(point.x, point.y),
          isTrue,
          reason: '${dest.label}의 착지점 $point 이 막혀 있다',
        );
      }
    });

    test('안전지대로 가면 언제나 광장 안에 내린다', () {
      for (var seed = 0; seed < 20; seed++) {
        final point =
            TeleportDestination.safeZone.resolve(map, math.Random(seed));
        expect(map.safeZone.containsPoint(point), isTrue);
        expect(map.isWalkableAt(point.x, point.y), isTrue);
      }
    });

    test('방위 목적지는 월드 중앙으로 떨어지지 않는다', () {
      // nearestWalkable 은 찾지 못하면 조용히 월드 중앙을 돌려준다. 방위
      // 목적지가 그 폴백에 걸리면 "동쪽으로 갔는데 한복판" 이 된다.
      final compass = TeleportDestination.values.where((d) => !d.isSafe);
      for (final dest in compass) {
        final point = dest.resolve(map, math.Random(3));
        expect(
          point.distanceTo(map.worldCenter),
          greaterThan(100),
          reason: '${dest.label}가 월드 중앙으로 폴백했다',
        );
      }
    });

    test('착지점은 목표 방위 쪽에 머문다', () {
      final center = map.worldCenter;
      final north = TeleportDestination.north.resolve(map, math.Random(1));
      final south = TeleportDestination.south.resolve(map, math.Random(1));
      final east = TeleportDestination.east.resolve(map, math.Random(1));
      final west = TeleportDestination.west.resolve(map, math.Random(1));

      expect(north.y, lessThan(center.y));
      expect(south.y, greaterThan(center.y));
      expect(east.x, greaterThan(center.x));
      expect(west.x, lessThan(center.x));
    });

    test('모든 목적지에 이름과 설명이 있다', () {
      for (final dest in TeleportDestination.values) {
        expect(dest.label, isNotEmpty);
        expect(dest.description, isNotEmpty);
      }
    });
  });
}
