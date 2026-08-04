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
