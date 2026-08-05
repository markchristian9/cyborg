import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import '../action_rpg_game.dart';
import '../palette.dart';

/// 소리 전체를 켜고 끄는 버튼.
///
/// [ActionButton] 을 재사용하지 않는다. 그쪽은 누르고 있으면 0.12초마다
/// 연속 발동하도록 되어 있어서, 토글에 쓰면 손가락을 얹고 있는 동안 음소거가
/// 초당 여덟 번 뒤집힌다.
///
/// 켜짐·꺼짐을 스스로 기억하지 않고 매 프레임 [ActionRpgGame.isAudioMuted] 를
/// 다시 읽어 그린다. 소리를 끄는 길이 이 버튼 말고도 생기더라도(저장된 설정을
/// 안고 켜지는 첫 프레임 같은) 아이콘이 실제와 어긋나지 않는다.
class MuteButton extends PositionComponent
    with TapCallbacks, HasGameReference<ActionRpgGame> {
  MuteButton({super.position, super.priority = 130})
      : super(size: Vector2.all(buttonSize), anchor: Anchor.topRight);

  /// 버튼 한 변의 길이. 옆에 서는 월드 메뉴 버튼과 같은 크기로 맞춘다.
  static const double buttonSize = 44;

  double _pressAnim = 0;

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    _pressAnim = 1;
    game.toggleMute();
  }

  @override
  void update(double dt) {
    if (_pressAnim > 0) _pressAnim = math.max(0, _pressAnim - dt * 5);
  }

  @override
  void render(Canvas canvas) {
    paint(
      canvas,
      side: size.x,
      muted: game.isAudioMuted,
      press: _pressAnim,
    );
  }

  /// 버튼 한 칸을 [canvas] 의 (0,0) 자리에 그린다.
  ///
  /// 상태를 인자로 받는다 — 게임을 띄우지 않고도 켜짐·꺼짐 두 모양을 나란히
  /// 뽑아 눈으로 검수할 수 있어야 한다.
  static void paint(
    Canvas canvas, {
    required double side,
    required bool muted,
    double press = 0,
  }) {
    // 꺼져 있다는 것은 한눈에 읽혀야 한다. 색까지 죽여 다른 HUD 버튼과
    // 확실히 구별한다.
    final accent = muted ? GamePalette.textDim : GamePalette.hudBorder;
    final center = Offset(side / 2, side / 2);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(1 - press * 0.08);
    canvas.translate(-center.dx, -center.dy);

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, side, side),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      rect,
      Paint()
        ..color = accent.withValues(alpha: muted ? 0.06 : 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(rect, Paint()..color = GamePalette.hudBackground);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = accent.withValues(alpha: muted ? 0.3 : 0.55),
    );

    _drawSpeaker(canvas, center, accent, muted);
    canvas.restore();
  }

  /// 스피커 본체와, 소리가 살아 있으면 음파를·꺼져 있으면 ×를 그린다.
  static void _drawSpeaker(
    Canvas canvas,
    Offset center,
    Color color,
    bool muted,
  ) {
    // 음파와 × 가 오른쪽 절반을 쓰므로 본체를 왼쪽으로 조금 밀어 균형을 맞춘다.
    final cx = center.dx - 3;
    final cy = center.dy;

    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 스피커: 왼쪽의 네모난 몸통과 오른쪽으로 벌어지는 콘.
    canvas.drawPath(
      Path()
        ..moveTo(cx - 8, cy - 3.5)
        ..lineTo(cx - 4, cy - 3.5)
        ..lineTo(cx + 1, cy - 8.5)
        ..lineTo(cx + 1, cy + 8.5)
        ..lineTo(cx - 4, cy + 3.5)
        ..lineTo(cx - 8, cy + 3.5)
        ..close(),
      stroke,
    );

    if (muted) {
      // 소리가 나가는 자리를 ×로 지운다.
      for (final dir in const [1.0, -1.0]) {
        canvas.drawLine(
          Offset(cx + 5, cy - 4 * dir),
          Offset(cx + 11, cy + 4 * dir),
          stroke,
        );
      }
      return;
    }

    // 퍼져 나가는 음파 두 겹. 바깥쪽을 흐리게 해 멀어지는 느낌을 준다.
    for (final (radius, alpha) in const [(5.0, 1.0), (9.0, 0.55)]) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx + 1, cy), radius: radius),
        -math.pi / 3.4,
        math.pi / 1.7,
        false,
        Paint()
          ..color = color.withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.9
          ..strokeCap = StrokeCap.round,
      );
    }
  }
}
