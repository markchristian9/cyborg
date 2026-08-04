import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import '../action_rpg_game.dart';
import '../iso.dart';
import '../palette.dart';
import '../systems/auto_hunt.dart';

/// 자동 사냥을 켜고 끄는 버튼.
///
/// [ActionButton] 을 재사용하지 않는다. 그쪽은 누르고 있으면 0.12초마다
/// 연속 발동하도록 되어 있어서, 토글에 쓰면 손가락을 얹고 있는 동안 켜짐과
/// 꺼짐이 초당 여덟 번 뒤집힌다.
class AutoHuntButton extends PositionComponent
    with TapCallbacks, HasGameReference<ActionRpgGame> {
  AutoHuntButton({required this.radius, super.position, super.priority = 90})
      : super(size: Vector2.all(radius * 2), anchor: Anchor.center);

  final double radius;

  double _pressAnim = 0;
  double _time = 0;

  static const Color _accent = GamePalette.hitSpark;

  final TextPaint _title = TextPaint(
    style: const TextStyle(
      color: _accent,
      fontSize: 10,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.0,
    ),
  );
  final TextPaint _titleOff = TextPaint(
    style: TextStyle(
      color: _accent.withValues(alpha: 0.45),
      fontSize: 10,
      fontWeight: FontWeight.w900,
      letterSpacing: 1.0,
    ),
  );
  final TextPaint _range = TextPaint(
    style: const TextStyle(
      color: GamePalette.textPrimary,
      fontSize: 12,
      fontWeight: FontWeight.w800,
    ),
  );

  @override
  bool containsLocalPoint(Vector2 point) {
    final dx = point.x - radius;
    final dy = point.y - radius;
    return dx * dx + dy * dy <= radius * radius;
  }

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    _pressAnim = 1;
    game.toggleAutoHunt();
  }

  @override
  void update(double dt) {
    _time += dt;
    if (_pressAnim > 0) _pressAnim = math.max(0, _pressAnim - dt * 5);
  }

  @override
  void render(Canvas canvas) {
    final on = game.autoHunt.enabled;
    final center = Offset(radius, radius);
    final press = 1 - _pressAnim * 0.08;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(press);
    canvas.translate(-center.dx, -center.dy);

    // 켜져 있는 동안 천천히 맥동시켜 "지금 돌고 있다"를 알린다.
    final pulse = on ? 0.75 + math.sin(_time * 3.2) * 0.25 : 0.0;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = _accent.withValues(alpha: on ? 0.14 + pulse * 0.12 : 0.05)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(center, radius, Paint()..color = GamePalette.hudBackground);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = on ? 2.6 : 2
        ..color = _accent.withValues(alpha: on ? 0.9 : 0.3),
    );

    // 위: AUTO / 아래: 현재 반경. 켜져 있을 때만 반경이 의미를 가지므로
    // 꺼져 있으면 흐리게 둔다.
    (on ? _title : _titleOff).render(
      canvas,
      'AUTO',
      Vector2(radius, radius - 12),
      anchor: Anchor.center,
    );
    _range.render(
      canvas,
      '${game.autoHunt.radiusMeters.toStringAsFixed(0)}m',
      Vector2(radius, radius + 6),
      anchor: Anchor.center,
    );

    canvas.restore();
  }
}

/// 자동 사냥 반경을 1 m 씩 늘리고 줄이는 작은 버튼.
///
/// 자동 사냥이 꺼져 있으면 그리지도 않고 탭도 받지 않는다 — 반경만 바꿔 놓고
/// 왜 아무 일도 없는지 헤매지 않도록, 조절할 수 있을 때만 나타난다.
class AutoHuntRadiusButton extends PositionComponent
    with TapCallbacks, HasGameReference<ActionRpgGame> {
  AutoHuntRadiusButton({
    required this.deltaMeters,
    this.radius = 15,
    super.position,
    super.priority = 90,
  }) : super(size: Vector2.all(radius * 2), anchor: Anchor.center);

  /// 한 번 누를 때 바뀌는 양(미터). 음수면 줄이는 버튼이다.
  final double deltaMeters;

  final double radius;

  double _pressAnim = 0;

  bool get _active => game.autoHunt.enabled;

  /// 더 이상 이 방향으로 못 가는 상태인지(1 m 하한·10 m 상한).
  bool get _exhausted {
    final value = game.autoHunt.radiusMeters;
    return deltaMeters < 0
        ? value <= AutoHuntController.minRadiusMeters
        : value >= AutoHuntController.maxRadiusMeters;
  }

  @override
  bool containsLocalPoint(Vector2 point) {
    if (!_active) return false;
    final dx = point.x - radius;
    final dy = point.y - radius;
    return dx * dx + dy * dy <= radius * radius;
  }

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    _pressAnim = 1;
    game.adjustAutoHuntRadius(deltaMeters);
  }

  @override
  void update(double dt) {
    if (_pressAnim > 0) _pressAnim = math.max(0, _pressAnim - dt * 5);
  }

  @override
  void render(Canvas canvas) {
    if (!_active) return;

    final center = Offset(radius, radius);
    final dim = _exhausted;
    final press = 1 - _pressAnim * 0.12;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(press);
    canvas.translate(-center.dx, -center.dy);

    canvas.drawCircle(
      center,
      radius,
      Paint()..color = GamePalette.hudBackground.withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = GamePalette.hudBorder.withValues(alpha: dim ? 0.25 : 0.7),
    );

    final mark = Paint()
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = GamePalette.textPrimary.withValues(alpha: dim ? 0.25 : 0.95);
    const arm = 6.0;
    canvas.drawLine(
      center + const Offset(-arm, 0),
      center + const Offset(arm, 0),
      mark,
    );
    if (deltaMeters > 0) {
      canvas.drawLine(
        center + const Offset(0, -arm),
        center + const Offset(0, arm),
        mark,
      );
    }

    canvas.restore();
  }
}

/// 자동 사냥의 중심과 반경을 바닥에 그려 주는 월드 오버레이.
///
/// 어디를 중심으로 얼마나 도는지 눈에 보이지 않으면, 캐릭터가 왜 특정 지점을
/// 벗어나지 않는지 알 수 없다.
class AutoHuntRangeField extends Component
    with HasGameReference<ActionRpgGame> {
  // 지면(-100000)보다 위, 월드 엔티티(깊이 우선순위 ≥ 0)보다 아래.
  AutoHuntRangeField() : super(priority: -2);

  double _time = 0;

  /// 그리드 상의 정원(正圓)이 화면에서 갖는 가로 반지름의 배율.
  ///
  /// 그리드 원 `(r·cos t, r·sin t)` 를 [gridToScreen] 에 넣으면
  /// `x = r√2·kHalfTileWidth·cos(t+45°)`, `y = r√2·kHalfTileHeight·sin(t+45°)`
  /// 가 되어 **회전 없는 축 정렬 타원**이 된다. 그래서 반지름에 이 배율만
  /// 곱하면 되고 캔버스를 돌릴 필요가 없다.
  static final double _ellipseScale = math.sqrt2;

  @override
  void update(double dt) => _time += dt;

  @override
  void render(Canvas canvas) {
    final hunt = game.autoHunt;
    final anchor = hunt.anchor;
    if (!hunt.enabled || anchor == null) return;

    final center = gridVecToScreen(anchor);
    final origin = Offset(center.x, center.y);
    final rx = hunt.radiusTiles * kHalfTileWidth * _ellipseScale;
    final ry = hunt.radiusTiles * kHalfTileHeight * _ellipseScale;
    final pulse = 0.75 + math.sin(_time * 2.4) * 0.25;

    // 반경 경계
    canvas.drawOval(
      Rect.fromCenter(center: origin, width: rx * 2, height: ry * 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = GamePalette.hitSpark.withValues(alpha: 0.3 + pulse * 0.2),
    );
    // 옅은 채움. 경계선만 있으면 넓은 반경에서 안쪽인지 바깥인지 헷갈린다.
    canvas.drawOval(
      Rect.fromCenter(center: origin, width: rx * 2, height: ry * 2),
      Paint()..color = GamePalette.hitSpark.withValues(alpha: 0.05),
    );

    // 중심 표식
    canvas.drawOval(
      Rect.fromCenter(center: origin, width: 18, height: 9),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = GamePalette.hitSpark.withValues(alpha: 0.8),
    );
    final cross = Paint()
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = GamePalette.hitSpark.withValues(alpha: 0.55);
    canvas.drawLine(origin + const Offset(-14, 0), origin + const Offset(-22, 0), cross);
    canvas.drawLine(origin + const Offset(14, 0), origin + const Offset(22, 0), cross);
  }
}
