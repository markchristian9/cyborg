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
    _tapPointer = event.pointerId;
    _begin();
  }

  @override
  void onTapUp(TapUpEvent event) {
    if (_tapPointer != event.pointerId) return;
    _tapPointer = null;
    _endIfNobodyHolds();
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    if (_tapPointer != event.pointerId) return;
    _tapPointer = null;
    // 탭이 물러나는 자리는 두 가지를 함께 뜻한다 — "버튼 밖에서 손을 뗐다" 와
    // "손가락이 밀려 드래그가 아레나를 이겼다" 다. 뒤엣것이면 **바로 다음 줄에**
    // [onDragStart] 가 이어진다. 그 인계를 새 누름으로 세지 않도록 표시만 남긴다.
    _tapHandingOver = true;
    _endIfNobodyHolds();
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    event.handled = true;
    _dragPointer = event.pointerId;

    // 방금 물러난 탭에서 넘겨받은 것이라면 이미 센 누름이다. 쥔 상태만
    // 되살리고 발동하지 않는다.
    if (_tapHandingOver) {
      _held = true;
      return;
    }
    // 조이스틱을 쥔 손이 버튼 위로 미끄러져 들어온 경우다. 이건 새 누름이다.
    _begin();
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (_dragPointer != event.pointerId) return;
    _dragPointer = null;
    _endIfNobodyHolds();
  }

  /// 지금 이 버튼을 쥐고 있는 탭·드래그의 번호. 아무도 쥐지 않았으면 null.
  ///
  /// 🛑 **둘을 따로 들고 있어야 한다.** [ActionButton] 은 `TapCallbacks` 와
  /// `DragCallbacks` 를 함께 쓰는데, 두 갈래는 **서로 다른 번호 체계**를 쓴다 —
  /// 탭 번호는 Flutter 의 포인터 번호이고, 드래그 번호는 Flame 안의 전역
  /// 카운터(`FlameDragAdapter._globalIdCounter`)다. 그래서 번호가 같다고 같은
  /// 손가락이 아니고, 다르다고 다른 손가락도 아니다. 한 칸에 섞어 담으면
  /// 우연히 겹친 두 번호가 서로를 지운다.
  int? _tapPointer;
  int? _dragPointer;

  /// 탭이 방금 물러났고 드래그가 이어받을 수 있는 상태인가.
  ///
  /// 인계는 **한 묶음의 이벤트 안에서** 일어난다(취소 바로 다음이 시작이다).
  /// 그래서 [update] 가 한 번 돌면 지운다 — 그 뒤에 오는 드래그는 인계가 아니라
  /// 정말로 새로 시작한 것이다.
  bool _tapHandingOver = false;

  void _begin() {
    _held = true;
    // 첫 연타는 **한 박자 뒤**다. 0 으로 두면 누른 바로 다음 프레임에
    // `_repeatTimer <= 0` 이 성립해 버려, 가만히 톡 눌러도 두 번 나갔다.
    _repeatTimer = _repeatDelay;
    _pressAnim = 1;
    if (_enabled) onPressed();
  }

  void _endIfNobodyHolds() {
    if (_tapPointer == null && _dragPointer == null) _held = false;
  }

  /// 누르고 있을 때 연타가 시작되기까지의 시간(초).
  ///
  /// 한 번 톡 누른 것과 눌러 두는 것을 가르는 값이다. 짧으면 탭 하나가 연타로
  /// 새고, 길면 눌러도 이어지지 않는 것처럼 느껴진다.
  static const double _repeatDelay = 0.3;

  /// 연타 간격(초).
  static const double _repeatInterval = 0.12;

  double _repeatTimer = 0;

  @override
  void update(double dt) {
    // 인계 창은 한 프레임짜리다. 이 뒤에 오는 드래그는 새 누름이다.
    _tapHandingOver = false;
    if (_pressAnim > 0) _pressAnim = math.max(0, _pressAnim - dt * 5);
    // 길게 누르면 연속 발동한다.
    if (_held) {
      _repeatTimer -= dt;
      if (_repeatTimer <= 0) {
        _repeatTimer = _repeatInterval;
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
///
/// 🛑 **손잡이와 달리 `anchor` 를 건드리지 않는다.** [JoystickComponent] 는
/// 손잡이의 기준점을 자기가 정하지만(`knob.anchor = Anchor.center`), 배경은
/// `add` 하기만 하고 손대지 않는다. 그래서 배경은 기본값인 좌상단 기준으로
/// 남아 있어야 조이스틱 상자를 (0,0) 부터 가득 채운다.
///
/// 여기에 `Anchor.center` 를 주면 배경이 상자의 **모서리**를 중심으로 그려져
/// 반경만큼(62픽셀) 왼쪽 위로 밀린다 — 손잡이는 제자리인데 테두리만 어긋난
/// 모습이다. 생성자의 `assert` 는 `position` 이 0 인지만 보므로 이것을
/// 잡아 주지 않고, 예외도 나지 않는다.
class JoystickBase extends PositionComponent {
  JoystickBase({required this.radius}) : super(size: Vector2.all(radius * 2));

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
