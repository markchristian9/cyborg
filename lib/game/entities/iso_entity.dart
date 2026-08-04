import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../action_rpg_game.dart';
import '../iso.dart';
import '../palette.dart';

/// 아이소메트릭 월드에 배치되는 모든 오브젝트의 공통 베이스.
///
/// 게임 로직은 타일 단위의 그리드 좌표([grid])와 고도([z])로만 다루고,
/// 화면 좌표와 렌더링 순서는 [syncTransform]이 매 프레임 갱신한다.
abstract class IsoEntity extends PositionComponent
    with HasGameReference<ActionRpgGame> {
  IsoEntity({
    required Vector2 grid,
    this.z = 0,
    this.bodyRadius = 0.32,
    this.depthBias = 0,
  }) : grid = grid.clone();

  /// 타일 단위의 논리 위치.
  Vector2 grid;

  /// 지면으로부터의 고도(타일 높이 단위).
  double z;

  /// 그리드 단위의 원형 충돌 반경.
  double bodyRadius;

  /// 같은 칸에 겹칠 때 렌더링 우선순위를 미세 조정하는 값.
  double depthBias;

  @override
  void onMount() {
    super.onMount();
    syncTransform();
  }

  /// 그리드 좌표를 화면 좌표와 깊이 우선순위로 반영한다.
  void syncTransform() {
    final screen = gridToScreen(grid.x, grid.y, z);
    position.setValues(screen.x, screen.y);
    priority = depthPriority(grid, bias: depthBias);
  }

  @override
  void update(double dt) {
    super.update(dt);
    syncTransform();
  }

  /// 지면에 드리우는 타원 그림자를 그린다.
  ///
  /// 고도가 높을수록 작고 옅어진다.
  void renderShadow(Canvas canvas, double radiusX, {double? radiusY}) {
    final lift = (z * kHeightUnit).clamp(0.0, 160.0);
    final shrink = (1 - lift / 260).clamp(0.35, 1.0);
    final alpha = (0.42 * shrink).clamp(0.08, 0.42);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(0, lift),
        width: radiusX * 2 * shrink,
        height: (radiusY ?? radiusX * 0.5) * 2 * shrink,
      ),
      Paint()
        ..color = GamePalette.shadow.withValues(alpha: alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }
}

/// 피해를 받을 수 있는 대상.
mixin Damageable on IsoEntity {
  double get hp;
  double get maxHp;
  bool get isAlive => hp > 0;

  /// [amount]만큼 피해를 입힌다. [knockback]은 그리드 단위 밀려나는 방향/세기다.
  void applyDamage(double amount, {Vector2? knockback, bool critical = false});
}
