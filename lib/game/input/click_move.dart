import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import '../action_rpg_game.dart';
import '../entities/iso_entity.dart';
import '../iso.dart';
import '../palette.dart';

/// 월드 바닥 전체를 덮어 "빈 땅 클릭"을 받아 내는 투명 레이어.
///
/// Flame 의 탭 이벤트는 위에 그려진 컴포넌트부터 전달되고 **첫 처리자에서
/// 멈춘다**(`continuePropagation` 기본값 false). 이 레이어를 월드의 가장
/// 아래에 깔아 두면 뷰포트에 있는 조이스틱·액션 버튼이 항상 먼저 탭을
/// 가져가고, 아무 UI 도 잡지 않은 탭만 여기로 내려온다. 덕분에 기존 조작을
/// 하나도 건드리지 않고 클릭 이동을 얹을 수 있다.
class ClickMoveLayer extends PositionComponent
    with TapCallbacks, DragCallbacks, HasGameReference<ActionRpgGame> {
  ClickMoveLayer() : super(priority: -1000000);

  // 월드 어디를 찍든 받아야 하므로 히트 영역을 제한하지 않는다.
  @override
  bool containsLocalPoint(Vector2 point) => true;

  @override
  void onTapDown(TapDownEvent event) {
    // 빈 땅을 눌렀다는 것은 아무도 고르지 않았다는 뜻이다. 골라 둔 요원을 놓지
    // 않으면 하단 행동 막대가 엉뚱한 사람을 향한 채 화면에 남는다.
    game.clearRemotePlayerSelection();
    // 이 컴포넌트는 월드 원점에 놓이므로 로컬 좌표가 곧 월드 좌표다.
    game.movePlayerToWorldPoint(event.localPosition);
  }

  // 누른 채 끌면 목표가 손가락을 따라온다. 탭을 반복하지 않고도 추격 방향을
  // 계속 고쳐 잡을 수 있다.
  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    game.movePlayerToWorldPoint(event.localPosition);
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    game.movePlayerToWorldPoint(event.localEndPosition);
  }
}

/// 탭을 삼켜 월드로 새지 않게 막는 투명 차폐막.
///
/// Flame 의 탭은 **`TapCallbacks` 를 구현한 컴포넌트**에서만 멈춘다
/// (`continuePropagation` 기본값 false). 그런데 Flame 의 `JoystickComponent` 는
/// `DragCallbacks` 만 갖고 있고, 이 프로젝트의 `Hud` 도 표시 전용이라 탭 처리자가
/// 아니다. 그래서 조이스틱을 잡으려다 짧게 놓치거나 체력바를 건드리면 그 탭이
/// [ClickMoveLayer] 까지 내려가 캐릭터가 엉뚱한 곳으로 걸어간다.
///
/// 이 컴포넌트를 그 위에 덮어 두면 탭이 여기서 소비된다. 히트 영역을 실제
/// 위젯 사각형에 맞춰야 한다 — 넓게 잡으면 그만큼 월드를 클릭할 수 없다.
class TapShield extends PositionComponent with TapCallbacks {
  TapShield({
    required super.position,
    required super.size,
    super.anchor,
    super.priority = 80,
  });

  @override
  void onTapDown(TapDownEvent event) {
    // 아무것도 하지 않는다. 받는 것 자체가 목적이다.
  }
}

/// 클릭한 지점에 잠깐 남는 표식.
///
/// 어디를 눌렀는지 눈으로 확인되지 않으면 캐릭터가 왜 그쪽으로 가는지
/// 알 수 없다. 퍼지는 링과 지면에 박힌 십자로 목적지를 알린다.
class MoveMarker extends IsoEntity {
  MoveMarker({required Vector2 grid})
      : super(grid: grid, depthBias: -0.4);

  double _life = 0;
  static const double _duration = 0.55;

  @override
  void update(double dt) {
    _life += dt;
    if (_life >= _duration) {
      removeFromParent();
      return;
    }
    super.update(dt);
  }

  @override
  void render(Canvas canvas) {
    final t = (_life / _duration).clamp(0.0, 1.0);
    final fade = 1 - t;

    // 아이소메트릭 지면에 눕도록 세로로 눌린 링.
    final r = 10 + 26 * t;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: r * 2,
        height: r,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4 * fade
        ..color = GamePalette.playerAccent.withValues(alpha: 0.85 * fade),
    );

    // 가운데 십자. 링이 퍼져 사라진 뒤에도 잠깐 남아 지점을 특정한다.
    final cross = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = GamePalette.playerAccent.withValues(alpha: fade);
    const arm = 6.0;
    canvas.drawLine(const Offset(-arm, 0), const Offset(arm, 0), cross);
    canvas.drawLine(
      const Offset(0, -arm / 2),
      const Offset(0, arm / 2),
      cross,
    );
  }
}

/// 캐릭터 발밑에서 목적지까지 이어지는 안내선.
///
/// 클릭 이동 중에만 나타난다. 목적지가 화면 밖이거나 벽 뒤에 있을 때
/// 어디로 가는 중인지 알려 준다.
class MovePathHint extends Component with HasGameReference<ActionRpgGame> {
  // 지면(-100000)보다 위, 모든 월드 엔티티(깊이 우선순위 ≥ 0)보다 아래에 둔다.
  // 이보다 낮으면 불투명한 지면 청크가 안내선을 통째로 덮어 아무것도 보이지 않는다.
  MovePathHint() : super(priority: -1);

  double _time = 0;

  @override
  void update(double dt) => _time += dt;

  @override
  void render(Canvas canvas) {
    final target = game.player.moveTarget;
    if (target == null || !game.player.isAlive) return;

    final from = gridVecToScreen(game.player.grid);
    final to = gridVecToScreen(target);
    final delta = to - from;
    final distance = delta.length;
    if (distance < 12) return;

    // 흐르는 점선으로 진행 방향을 표시한다.
    final dir = delta / distance;
    const gap = 14.0;
    final offset = (_time * 42) % gap;
    final paint = Paint()
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = GamePalette.playerAccent.withValues(alpha: 0.32);

    for (var d = offset; d < distance - 6; d += gap) {
      final a = from + dir * d;
      final b = from + dir * math.min(d + 5, distance - 6);
      canvas.drawLine(Offset(a.x, a.y), Offset(b.x, b.y), paint);
    }
  }
}
