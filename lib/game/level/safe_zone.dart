import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../iso.dart';
import '../palette.dart';

/// 안전지대 한 변의 길이(미터). 가로 50 m × 세로 50 m.
const double kSafeZoneSizeMeters = 50.0;

/// 월드 한가운데에 놓이는 정사각형 안전지대.
///
/// 적 유닛은 이 구역 안으로 들어올 수 없고, 안에 있는 플레이어를 공격할 수도
/// 없다. 판정은 그리드(타일) 좌표계의 축 정렬 사각형으로 이루어지며,
/// [kMetersPerTile]이 1이므로 반변 25는 곧 25 m를 뜻한다.
class SafeZone {
  SafeZone({required Vector2 center, required this.halfExtent})
      : center = center.clone();

  /// [worldCenter]를 중심으로 한 변이 [sizeInMeters]인 안전지대를 만든다.
  factory SafeZone.centeredOn(
    Vector2 worldCenter, {
    double sizeInMeters = kSafeZoneSizeMeters,
  }) {
    return SafeZone(
      center: worldCenter,
      halfExtent: metersToTiles(sizeInMeters) / 2,
    );
  }

  /// 안전지대의 중심(그리드 좌표).
  final Vector2 center;

  /// 한 변의 절반 길이(타일 단위).
  final double halfExtent;

  /// 한 변의 길이(미터).
  double get sizeInMeters => tilesToMeters(halfExtent * 2);

  double get minX => center.x - halfExtent;
  double get maxX => center.x + halfExtent;
  double get minY => center.y - halfExtent;
  double get maxY => center.y + halfExtent;

  /// 해당 지점이 안전지대 안인지 여부.
  bool contains(double gx, double gy) =>
      gx >= minX && gx <= maxX && gy >= minY && gy <= maxY;

  /// [grid] 지점이 안전지대 안인지 여부.
  bool containsPoint(Vector2 grid) => contains(grid.x, grid.y);

  /// 반경 [radius]인 몸체가 경계를 조금이라도 침범하는지 여부.
  ///
  /// 적의 이동 판정에 쓰이며, 몸통이 경계선에 걸치는 것도 침범으로 본다.
  bool overlapsBody(double gx, double gy, double radius) =>
      gx + radius > minX &&
      gx - radius < maxX &&
      gy + radius > minY &&
      gy - radius < maxY;

  /// 경계선까지의 거리. 안쪽이면 음수, 바깥이면 양수다.
  double signedDistance(double gx, double gy) {
    final dx = math.max(minX - gx, gx - maxX);
    final dy = math.max(minY - gy, gy - maxY);
    if (dx <= 0 && dy <= 0) return math.max(dx, dy);
    final ox = math.max(dx, 0.0);
    final oy = math.max(dy, 0.0);
    return math.sqrt(ox * ox + oy * oy);
  }

  /// 안전지대를 침범한 좌표를 가장 가까운 바깥쪽으로 밀어낸 좌표를 돌려준다.
  ///
  /// [margin]은 몸체 반경처럼 경계에서 추가로 띄울 여유다.
  /// 침범하지 않았다면 원래 좌표의 복사본을 그대로 돌려준다.
  Vector2 pushOutside(Vector2 grid, {double margin = 0}) {
    if (!overlapsBody(grid.x, grid.y, margin)) return grid.clone();

    final toLeft = grid.x - (minX - margin);
    final toRight = (maxX + margin) - grid.x;
    final toTop = grid.y - (minY - margin);
    final toBottom = (maxY + margin) - grid.y;

    final nearest = math.min(
      math.min(toLeft, toRight),
      math.min(toTop, toBottom),
    );
    if (nearest == toLeft) return Vector2(minX - margin, grid.y);
    if (nearest == toRight) return Vector2(maxX + margin, grid.y);
    if (nearest == toTop) return Vector2(grid.x, minY - margin);
    return Vector2(grid.x, maxY + margin);
  }
}

/// 안전지대를 월드에 그려 주는 레이어.
///
/// 지면 위·캐릭터 아래에 깔리며, 정적인 바닥과 역장 벽은 [ui.Picture]로
/// 한 번만 래스터화하고 맥동하는 발광만 매 프레임 덧그린다.
class SafeZoneField extends PositionComponent {
  SafeZoneField(this.zone) : super(priority: -90000);

  final SafeZone zone;

  /// 경계에 세워지는 역장 벽의 높이(타일 z 단위).
  static const double _wallHeight = 1.8;

  ui.Picture? _cached;
  double _time = 0;

  @override
  Future<void> onLoad() async {
    _cached = _record();
  }

  @override
  void onRemove() {
    _cached?.dispose();
    _cached = null;
    super.onRemove();
  }

  @override
  void update(double dt) {
    _time += dt;
  }

  /// 안전지대 바닥의 아이소메트릭 외곽선.
  Path _floorOutline() {
    final north = gridToScreen(zone.minX, zone.minY);
    final east = gridToScreen(zone.maxX, zone.minY);
    final south = gridToScreen(zone.maxX, zone.maxY);
    final west = gridToScreen(zone.minX, zone.maxY);
    return Path()
      ..moveTo(north.x, north.y)
      ..lineTo(east.x, east.y)
      ..lineTo(south.x, south.y)
      ..lineTo(west.x, west.y)
      ..close();
  }

  /// 경계 한 변을 따라 세워지는 역장 벽의 사각형 경로.
  Path _wallQuad(Vector2 from, Vector2 to) {
    final bottomA = gridVecToScreen(from);
    final bottomB = gridVecToScreen(to);
    final lift = _wallHeight * kHeightUnit;
    return Path()
      ..moveTo(bottomA.x, bottomA.y)
      ..lineTo(bottomB.x, bottomB.y)
      ..lineTo(bottomB.x, bottomB.y - lift)
      ..lineTo(bottomA.x, bottomA.y - lift)
      ..close();
  }

  /// 안전지대의 네 꼭짓점(그리드 좌표).
  List<Vector2> get _corners => [
        Vector2(zone.minX, zone.minY),
        Vector2(zone.maxX, zone.minY),
        Vector2(zone.maxX, zone.maxY),
        Vector2(zone.minX, zone.maxY),
      ];

  ui.Picture _record() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 바닥 보호막.
    final floor = _floorOutline();
    canvas.drawPath(
      floor,
      Paint()..color = GamePalette.safeZoneFill.withValues(alpha: 0.22),
    );

    // 5 m 간격의 내부 격자.
    final lattice = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = GamePalette.safeZoneEdge.withValues(alpha: 0.22);
    const step = 5.0;
    for (var offset = step; offset < zone.halfExtent * 2; offset += step) {
      final x = zone.minX + offset;
      final y = zone.minY + offset;
      final vTop = gridToScreen(x, zone.minY);
      final vBottom = gridToScreen(x, zone.maxY);
      final hLeft = gridToScreen(zone.minX, y);
      final hRight = gridToScreen(zone.maxX, y);
      canvas.drawLine(vTop.toOffset(), vBottom.toOffset(), lattice);
      canvas.drawLine(hLeft.toOffset(), hRight.toOffset(), lattice);
    }

    // 경계 역장 벽. 아래는 진하고 위로 갈수록 사라진다.
    final corners = _corners;
    for (var i = 0; i < corners.length; i++) {
      final from = corners[i];
      final to = corners[(i + 1) % corners.length];
      final quad = _wallQuad(from, to);
      final bounds = quad.getBounds();
      canvas.drawPath(
        quad,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(bounds.center.dx, bounds.bottom),
            Offset(bounds.center.dx, bounds.top),
            [
              GamePalette.safeZoneGlow.withValues(alpha: 0.30),
              GamePalette.safeZoneGlow.withValues(alpha: 0.02),
            ],
          ),
      );
    }

    // 지면 경계선.
    canvas.drawPath(
      floor,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = GamePalette.safeZoneEdge.withValues(alpha: 0.85),
    );

    // 모서리 기둥.
    for (final corner in corners) {
      final base = gridVecToScreen(corner);
      final top = base - Vector2(0, _wallHeight * kHeightUnit);
      canvas.drawLine(
        base.toOffset(),
        top.toOffset(),
        Paint()
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..color = GamePalette.safeZoneEdge.withValues(alpha: 0.9),
      );
    }

    return recorder.endRecording();
  }

  @override
  void render(Canvas canvas) {
    final picture = _cached;
    if (picture != null) canvas.drawPicture(picture);

    // 경계 발광의 맥동.
    final pulse = 0.45 + 0.3 * math.sin(_time * 1.8);
    canvas.drawPath(
      _floorOutline(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..color = GamePalette.safeZoneGlow.withValues(alpha: pulse * 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // 모서리 기둥 끝의 신호등.
    final blink = 0.55 + 0.45 * math.sin(_time * 3.2);
    for (final corner in _corners) {
      final top = gridVecToScreen(corner) -
          Vector2(0, _wallHeight * kHeightUnit);
      canvas.drawCircle(
        top.toOffset(),
        5 + blink * 3,
        Paint()
          ..color = GamePalette.safeZoneGlow.withValues(alpha: blink * 0.8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(
        top.toOffset(),
        3,
        Paint()..color = Colors.white.withValues(alpha: 0.9),
      );
    }
  }
}
