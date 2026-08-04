import 'dart:math' as math;

import 'package:flame/components.dart';

/// 아이소메트릭 타일 한 칸의 화면상 가로 폭.
const double kTileWidth = 128.0;

/// 아이소메트릭 타일 한 칸의 화면상 세로 폭 (2:1 다이메트릭 투영).
const double kTileHeight = 64.0;

const double kHalfTileWidth = kTileWidth / 2;
const double kHalfTileHeight = kTileHeight / 2;

/// 그리드 z(고도) 1 단위가 화면에서 차지하는 픽셀 높이.
const double kHeightUnit = 56.0;

/// 타일 한 칸이 나타내는 실제 거리(미터).
///
/// 이동 속도(타일/초), 사거리, 시야 같은 게임 수치는 모두 타일 단위이므로
/// 이 값이 1.0이라는 것은 "타일 = 미터"임을 뜻한다.
const double kMetersPerTile = 1.0;

/// 게임 월드 한 변의 길이(미터). 가로 1 km × 세로 1 km.
const double kWorldSizeMeters = 1000.0;

/// 월드 한 변의 타일 수. [kWorldSizeMeters] / [kMetersPerTile].
const int kWorldTiles = 1000;

/// 지면 렌더링과 구조물 스트리밍의 단위가 되는 청크 한 변의 타일 수.
///
/// 100만 타일을 한 번에 다룰 수 없으므로 월드를 이 크기의 격자로 나누고
/// 카메라 근처의 청크만 그리거나 마운트한다.
const int kChunkTiles = 32;

/// 월드 한 변의 청크 수.
const int kWorldChunks = (kWorldTiles + kChunkTiles - 1) ~/ kChunkTiles;

/// 미터 단위 거리를 타일 단위로 변환한다.
double metersToTiles(double meters) => meters / kMetersPerTile;

/// 타일 단위 거리를 미터 단위로 변환한다.
double tilesToMeters(double tiles) => tiles * kMetersPerTile;

/// 그리드(논리) 좌표를 화면(월드) 좌표로 변환한다.
///
/// 그리드 좌표는 타일 단위의 실수 좌표이며, [z]는 지면으로부터의 고도다.
/// 반환되는 좌표는 해당 지점의 "발밑"에 해당한다.
Vector2 gridToScreen(double gx, double gy, [double z = 0]) {
  return Vector2(
    (gx - gy) * kHalfTileWidth,
    (gx + gy) * kHalfTileHeight - z * kHeightUnit,
  );
}

/// [gridToScreen]과 동일하되 [Vector2]를 받는다.
Vector2 gridVecToScreen(Vector2 grid, [double z = 0]) =>
    gridToScreen(grid.x, grid.y, z);

/// 화면(월드) 좌표를 지면(z = 0) 기준 그리드 좌표로 역변환한다.
Vector2 screenToGrid(Vector2 screen) {
  final a = screen.x / kHalfTileWidth;
  final b = screen.y / kHalfTileHeight;
  return Vector2((b + a) / 2, (b - a) / 2);
}

/// 그리드 좌표로부터 렌더링 깊이 우선순위를 계산한다.
///
/// 아이소메트릭 뷰에서는 `x + y`가 클수록 화면 앞쪽(아래쪽)이므로 나중에
/// 그려야 한다. Flame의 `priority`는 정수라 소수점을 보존하기 위해 100배한다.
int depthPriority(Vector2 grid, {double bias = 0}) {
  return ((grid.x + grid.y + bias) * 100).round();
}

/// 그리드 방향 벡터를 화면상의 방향 벡터로 변환한다(평행이동 없음).
Vector2 gridDirToScreenDir(Vector2 dir) {
  return Vector2(
    (dir.x - dir.y) * kHalfTileWidth,
    (dir.x + dir.y) * kHalfTileHeight,
  );
}

/// 화면상의 방향 벡터를 그리드 방향 벡터로 변환한다(평행이동 없음).
///
/// 조이스틱이나 키보드 입력처럼 화면 기준으로 들어온 방향을
/// 그리드 좌표계의 이동 방향으로 바꿀 때 쓴다.
Vector2 screenDirToGridDir(Vector2 dir) {
  final a = dir.x / kHalfTileWidth;
  final b = dir.y / kHalfTileHeight;
  final result = Vector2((b + a) / 2, (b - a) / 2);
  if (result.length2 > 1e-9) result.normalize();
  return result;
}

/// 그리드 방향 벡터가 화면상 오른쪽을 향하는지 여부.
bool facesRight(Vector2 dir) => (dir.x - dir.y) >= 0;

/// 그리드 방향 벡터가 화면상 아래쪽(카메라 쪽)을 향하는지 여부.
bool facesDown(Vector2 dir) => (dir.x + dir.y) >= 0;

/// 8방향 인덱스(0 = 화면 오른쪽, 시계 방향)를 구한다.
int facingOctant(Vector2 dir) {
  final screen = gridDirToScreenDir(dir);
  if (screen.length2 < 1e-6) return 0;
  final angle = math.atan2(screen.y, screen.x);
  final normalized = (angle + math.pi * 2) % (math.pi * 2);
  return ((normalized / (math.pi / 4)).round()) % 8;
}
