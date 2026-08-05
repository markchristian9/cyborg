import 'dart:math' as math;

import 'package:flame/components.dart';

import 'level_map.dart';

/// 텔레포트로 갈 수 있는 곳.
///
/// 방위는 **그리드 축** 기준이다. 미니맵이 그리드 좌표를 그대로 가로·세로에
/// 옮기므로(`hud.dart`의 `toRadar`), 미니맵에서 위로 보이는 쪽이 북(y가 작은
/// 쪽)이어야 라벨과 화면이 어긋나지 않는다.
enum TeleportDestination {
  safeZone,
  north,
  east,
  south,
  west;

  /// 목록에 표시할 이름.
  String get label => switch (this) {
        TeleportDestination.safeZone => '안전지대',
        TeleportDestination.north => '북부 구역',
        TeleportDestination.east => '동부 구역',
        TeleportDestination.south => '남부 구역',
        TeleportDestination.west => '서부 구역',
      };

  /// 이름 아래에 덧붙이는 한 줄 설명.
  String get description => switch (this) {
        TeleportDestination.safeZone => '월드 중앙의 재가동 광장',
        TeleportDestination.north => '월드 북쪽 끝',
        TeleportDestination.east => '월드 동쪽 끝',
        TeleportDestination.south => '월드 남쪽 끝',
        TeleportDestination.west => '월드 서쪽 끝',
      };

  /// 안전지대인지 여부. 목록에서 다른 색으로 강조한다.
  bool get isSafe => this == TeleportDestination.safeZone;

  /// [grid] 가 지금 속해 있는 구역.
  ///
  /// 텔레포트 목적지와 같은 이름을 쓴다. "북부 구역으로 이동" 해서 도착한 곳이
  /// "북부 구역" 이라고 표시되어야 두 화면이 같은 세계를 가리킨다.
  ///
  /// 경계는 월드 중앙에서 본 대각선이다. 방위는 [anchorOn] 과 마찬가지로
  /// **그리드 축** 기준이라 미니맵에서 위로 보이는 쪽이 북쪽이다.
  static TeleportDestination at(Vector2 grid, LevelMap map) {
    if (map.safeZone.containsPoint(grid)) return TeleportDestination.safeZone;

    final offset = grid - map.worldCenter;
    // 두 축 중 더 멀리 벗어난 쪽이 구역을 정한다. 그 갈림이 곧 대각선이다.
    if (offset.x.abs() > offset.y.abs()) {
      return offset.x > 0 ? TeleportDestination.east : TeleportDestination.west;
    }
    return offset.y > 0
        ? TeleportDestination.south
        : TeleportDestination.north;
  }

  /// 월드 가장자리에서 안쪽으로 얼마나 들어온 곳을 "끝"으로 볼지(타일).
  ///
  /// 맵 외곽 세 칸은 [TileType.none]이라 아예 통행할 수 없고([LevelMap] 생성
  /// 참고), 그 언저리는 노이즈로 허공이 뚫려 있어 착지에 적당하지 않다.
  /// 대로 간격(40)보다 좁게 잡아 가장자리라는 느낌은 남긴다.
  static const double edgeInset = 30;

  /// 가장자리가 막혀 있을 때 안쪽으로 물러나며 다시 찾는 횟수.
  static const int _retryCount = 12;

  /// 한 번 물러날 때의 거리(타일).
  static const double _retryStride = 12;

  /// 보정 전의 목표 지점.
  Vector2 anchorOn(LevelMap map) {
    final w = map.width.toDouble();
    final h = map.height.toDouble();
    return switch (this) {
      TeleportDestination.safeZone => map.safeZoneCenter.clone(),
      TeleportDestination.north => Vector2(w / 2, edgeInset),
      TeleportDestination.east => Vector2(w - edgeInset, h / 2),
      TeleportDestination.south => Vector2(w / 2, h - edgeInset),
      TeleportDestination.west => Vector2(edgeInset, h / 2),
    };
  }

  /// 가장자리에서 월드 중앙을 향하는 단위 방향.
  Vector2 get _inward => switch (this) {
        TeleportDestination.safeZone => Vector2.zero(),
        TeleportDestination.north => Vector2(0, 1),
        TeleportDestination.east => Vector2(-1, 0),
        TeleportDestination.south => Vector2(0, -1),
        TeleportDestination.west => Vector2(1, 0),
      };

  /// 실제로 착지시킬 통행 가능한 좌표를 고른다.
  ///
  /// [LevelMap.nearestWalkable]은 반경 24 안에서 찾지 못하면 예외 대신 월드
  /// 중앙([LevelMap.spawn])을 돌려준다. 가장자리가 넓게 막힌 지형에서 그대로
  /// 쓰면 "동쪽으로 갔는데 한복판에 도착"하는 조용한 오동작이 되므로, 중앙으로
  /// 조금씩 물러나며 진짜 착지점을 찾는다.
  Vector2 resolve(LevelMap map, [math.Random? random]) {
    if (isSafe) return map.respawnPoint(random);

    final anchor = anchorOn(map);
    final inward = _inward;
    for (var step = 0; step < _retryCount; step++) {
      final candidate = anchor + inward * (step * _retryStride);
      final point = map.nearestWalkable(candidate);
      if (!_fellBackToCenter(point, map)) return point;
    }
    // 그 축이 통째로 막혀 있다. 광장으로 보내는 편이 허공에 떨어뜨리는 것보다 낫다.
    return map.respawnPoint(random);
  }

  /// [point]가 [LevelMap.nearestWalkable]의 실패 반환값인지 여부.
  bool _fellBackToCenter(Vector2 point, LevelMap map) =>
      point.distanceToSquared(map.spawn) < 0.001;
}
