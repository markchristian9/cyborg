import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import '../palette.dart';

/// 액션 버튼에 표시할 아이콘 종류.
enum ActionIcon { blade, plasma, dash, zoomIn, zoomOut }

/// 터치 조작용 원형 액션 버튼.
///
/// 누르는 즉시 [onPressed]가 호출되고, [cooldownRatio]가 0보다 크면
/// 남은 쿨다운이 부채꼴로 표시된다.
class ActionButton extends PositionComponent
    with TapCallbacks, DragCallbacks {
  ActionButton({
    required this.icon,
    required this.onPressed,
    required this.color,
    required this.radius,
    this.id = '',
    this.cooldownRatio,
    this.enabledCheck,
    Vector2? position,
    int priority = 0,
  }) : super(
          position: position,
          priority: priority,
          size: Vector2.all(radius * 2),
          anchor: Anchor.center,
        );

  final ActionIcon icon;
  final VoidCallback onPressed;
  final Color color;
  final double radius;

  /// 레이아웃 배치 시 버튼을 구분하기 위한 식별자.
  final String id;

  /// 0(준비 완료) ~ 1(방금 사용) 사이의 쿨다운 비율을 반환한다.
  final double Function()? cooldownRatio;

  /// 사용 가능한 상태인지 반환한다.
  final bool Function()? enabledCheck;

  double _pressAnim = 0;
  bool _held = false;

  bool get _enabled => enabledCheck?.call() ?? true;

  @override
  bool containsLocalPoint(Vector2 point) {
    final dx = point.x - radius;
    final dy = point.y - radius;
    return dx * dx + dy * dy <= radius * radius;
  }

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    _trigger();
  }

  @override
  void onTapUp(TapUpEvent event) {
    _held = false;
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    _held = false;
  }

  @override
  void onDragStart(DragStartEvent event) {
    event.handled = true;
    _trigger();
  }

  @override
  void onDragEnd(DragEndEvent event) {
    _held = false;
  }

  void _trigger() {
    _held = true;
    _pressAnim = 1;
    if (_enabled) onPressed();
  }

  double _repeatTimer = 0;

  @override
  void update(double dt) {
    if (_pressAnim > 0) _pressAnim = math.max(0, _pressAnim - dt * 5);
    // 길게 누르면 연속 발동한다.
    if (_held) {
      _repeatTimer -= dt;
      if (_repeatTimer <= 0) {
        _repeatTimer = 0.12;
        if (_enabled) onPressed();
      }
    } else {
      _repeatTimer = 0;
    }
  }

  @override
  void render(Canvas canvas) {
    final center = Offset(radius, radius);
    final enabled = _enabled;
    final press = 1 - _pressAnim * 0.08;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(press);
    canvas.translate(-center.dx, -center.dy);

    // 바깥 글로우
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: enabled ? 0.16 : 0.05)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    // 본체
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = GamePalette.hudBackground,
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: enabled ? 0.85 : 0.3),
    );

    // 쿨다운 부채꼴
    final ratio = cooldownRatio?.call() ?? 0;
    if (ratio > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius - 3),
        -math.pi / 2,
        math.pi * 2 * ratio.clamp(0.0, 1.0),
        true,
        Paint()..color = Colors.black.withValues(alpha: 0.55),
      );
    }

    _drawIcon(canvas, center, enabled ? color : color.withValues(alpha: 0.35));
    canvas.restore();
  }

  void _drawIcon(Canvas canvas, Offset center, Color tint) {
    final paint = Paint()
      ..color = tint
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    switch (icon) {
      case ActionIcon.blade:
        // 에너지 검
        canvas.drawLine(
          center + const Offset(-11, 11),
          center + const Offset(9, -9),
          paint..strokeWidth = 4,
        );
        canvas.drawLine(
          center + const Offset(-13, 5),
          center + const Offset(-5, 13),
          paint..strokeWidth = 3,
        );
        canvas.drawCircle(
          center + const Offset(10, -10),
          3,
          Paint()..color = tint,
        );
      case ActionIcon.plasma:
        // 조준 표적
        canvas.drawCircle(center, 9, paint..strokeWidth = 2.5);
        canvas.drawLine(
          center + const Offset(-14, 0),
          center + const Offset(-11, 0),
          paint,
        );
        canvas.drawLine(
          center + const Offset(11, 0),
          center + const Offset(14, 0),
          paint,
        );
        canvas.drawLine(
          center + const Offset(0, -14),
          center + const Offset(0, -11),
          paint,
        );
        canvas.drawLine(
          center + const Offset(0, 11),
          center + const Offset(0, 14),
          paint,
        );
        canvas.drawCircle(center, 2.5, Paint()..color = tint);
      case ActionIcon.dash:
        // 이중 갈매기표
        for (var i = 0; i < 2; i++) {
          final dx = i * 9.0 - 6;
          final path = Path()
            ..moveTo(center.dx + dx - 4, center.dy - 9)
            ..lineTo(center.dx + dx + 5, center.dy)
            ..lineTo(center.dx + dx - 4, center.dy + 9);
          canvas.drawPath(path, paint..strokeWidth = 3);
        }

      case ActionIcon.zoomIn:
      case ActionIcon.zoomOut:
        // 돋보기. 손잡이는 오른쪽 아래로 뻗고, 안쪽 부호가 방향을 알린다.
        final lens = center + const Offset(-2, -2);
        canvas.drawCircle(lens, 7, paint..strokeWidth = 2.4);
        canvas.drawLine(
          lens + const Offset(5, 5),
          lens + const Offset(10, 10),
          paint..strokeWidth = 2.8,
        );
        // 가로줄은 둘 다, 세로줄은 확대에만 — 그래서 +와 −가 된다.
        canvas.drawLine(
          lens + const Offset(-3.5, 0),
          lens + const Offset(3.5, 0),
          paint..strokeWidth = 2.2,
        );
        if (icon == ActionIcon.zoomIn) {
          canvas.drawLine(
            lens + const Offset(0, -3.5),
            lens + const Offset(0, 3.5),
            paint..strokeWidth = 2.2,
          );
        }
    }
  }
}

/// 반투명한 원형 조이스틱 배경을 그리는 컴포넌트.
class JoystickBase extends PositionComponent {
  JoystickBase({required this.radius})
      : super(size: Vector2.all(radius * 2), anchor: Anchor.center);

  final double radius;

  @override
  void render(Canvas canvas) {
    final center = Offset(radius, radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = GamePalette.hudBackground.withValues(alpha: 0.55),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = GamePalette.hudBorder.withValues(alpha: 0.4),
    );
    // 아이소메트릭 방향 힌트(마름모)
    final hint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = GamePalette.hudBorder.withValues(alpha: 0.18);
    final path = Path()
      ..moveTo(center.dx, center.dy - radius * 0.55)
      ..lineTo(center.dx + radius * 0.55, center.dy)
      ..lineTo(center.dx, center.dy + radius * 0.55)
      ..lineTo(center.dx - radius * 0.55, center.dy)
      ..close();
    canvas.drawPath(path, hint);
  }
}

/// 조이스틱 손잡이.
class JoystickKnob extends PositionComponent {
  JoystickKnob({required this.radius})
      : super(size: Vector2.all(radius * 2), anchor: Anchor.center);

  final double radius;

  @override
  void render(Canvas canvas) {
    final center = Offset(radius, radius);
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = GamePalette.playerAccent.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = const Color(0xFF16202B),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = GamePalette.playerAccent.withValues(alpha: 0.9),
    );
    canvas.drawCircle(
      center,
      radius * 0.28,
      Paint()..color = GamePalette.playerAccent.withValues(alpha: 0.8),
    );
  }
}
