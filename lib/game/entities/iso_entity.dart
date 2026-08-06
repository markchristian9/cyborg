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
  ///
  /// 🛑 **가장자리를 `MaskFilter.blur` 로 부드럽게 하지 않는다.** 이 메서드는
  /// 월드에 있는 **모든 몸**이 프레임마다 한 번씩 부른다 — 사람, 몹, 보급품,
  /// 나무까지다. 블러는 그릴 때마다 오프스크린 패스를 하나씩 여는 GPU 작업이라,
  /// 그 수만큼 래스터 스레드에 쌓인다.
  ///
  /// 실측(프로파일 빌드, 요원 한 명):
  ///
  /// ```text
  ///   블러를 걷어내기 전   raster 평균 9.4~11.1ms · p95 13.7~15.5ms
  ///   걷어낸 뒤            raster 평균  6.4~7.3ms · p95  7.3~10.2ms
  ///   (build 시간은 그대로 3.4~3.7ms — 값은 전부 GPU 쪽에 있었다)
  /// ```
  ///
  /// 60fps 예산이 16.6ms 인데 p95 가 15.5ms 였다. 사람이 몰릴수록 몸 수만큼
  /// 늘어나는 비용이라, 이 게임이 노리는 자리에서 가장 먼저 무너지는 축이다.
  ///
  /// 대신 **방사형 그라디언트**로 가장자리를 흘린다. 그라디언트는 셰이더 fill
  /// 이라 오프스크린 패스가 없다 — [CyborgRenderer] 의 명암이 같은 이유로 같은
  /// 선택을 하고 있다.
  void renderShadow(Canvas canvas, double radiusX, {double? radiusY}) {
    final lift = (z * kHeightUnit).clamp(0.0, 160.0);
    final shrink = (1 - lift / 260).clamp(0.35, 1.0);
    final alpha = (0.42 * shrink).clamp(0.08, 0.42);

    final rx = radiusX * shrink * _shadowSpread;
    final ry = (radiusY ?? radiusX * 0.5) * shrink * _shadowSpread;
    if (rx <= 0 || ry <= 0) return;

    // 단위 원을 그려 놓고 캔버스를 늘려 타원으로 만든다. 셰이더를 타원마다
    // 새로 굽지 않아도 되는 것이 요점이다 — `createShader` 는 사각형을 받아
    // 구우므로, 크기가 조금씩 다른 몸마다 따로 구우면 아낀 것을 도로 뱉는다.
    canvas.save();
    canvas.translate(0, lift);
    canvas.scale(rx, ry);
    canvas.drawCircle(Offset.zero, 1, _shadowPaint(alpha));
    canvas.restore();
  }

  /// 그라디언트로 흘리면 가장자리가 안쪽부터 옅어지므로, 블러가 바깥으로
  /// 번지던 만큼 원을 조금 키워야 예전과 같은 크기로 보인다.
  static const double _shadowSpread = 1.18;

  /// 알파별 그림자 붓. 단위 원(-1..1)에 맞춰 구운 셰이더를 담는다.
  ///
  /// 알파는 고도에서 나오는 연속값이지만 눈에 보이는 단계는 훨씬 성기다. 1/64
  /// 로 끊어 담으면 붓은 많아야 서른 몇 개가 만들어지고 그 뒤로는 계속 재사용
  /// 된다 — 프레임마다 셰이더를 굽는 것이 이 최적화가 없애려는 바로 그 비용이다.
  static final Map<int, Paint> _shadowPaints = {};

  static Paint _shadowPaint(double alpha) {
    final bucket = (alpha * 64).round();
    return _shadowPaints.putIfAbsent(bucket, () {
      final color = GamePalette.shadow.withValues(alpha: bucket / 64);
      return Paint()
        ..shader = RadialGradient(
          colors: [color, color, color.withValues(alpha: 0)],
          // 안쪽 6 할은 꽉 찬 그늘, 바깥 4 할에서 흘린다. 블러 4px 이 만들던
          // 번짐과 눈으로 구별되지 않는 폭이다.
          stops: const [0.0, 0.6, 1.0],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1));
    });
  }
}

/// 피해를 받을 수 있는 대상.
mixin Damageable on IsoEntity {
  double get hp;
  double get maxHp;
  bool get isAlive => hp > 0;

  /// 이 대상의 피해를 **서버가 판정하는지**.
  ///
  /// 참이면 화면에서 무엇이 닿았든 그것만으로는 아무것도 깎이지 않는다. 판정은
  /// 서버가 자기 좌표로 이미 했거나 곧 하며, 결과는 표가 바뀌는 것으로 돌아온다.
  ///
  /// 이 구분이 필요한 이유는 **같은 타격이 두 번 서버로 나가는 것을 막기 위해서**다.
  /// 예컨대 플라즈마는 쏘는 순간 서버 스킬로 판정이 끝나는데, 날아간 발사체가
  /// 몹에 닿았다고 또 공격을 보내면 한 발에 두 번의 요청이 나간다.
  bool get isServerJudged => false;

  /// [amount]만큼 피해를 입힌다. [knockback]은 그리드 단위 밀려나는 방향/세기다.
  void applyDamage(double amount, {Vector2? knockback, bool critical = false});
}
