import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../iso.dart';
import '../net/world_presence.dart';
import '../palette.dart';
import 'cyborg_design.dart';
import 'cyborg_renderer.dart';
import 'iso_entity.dart';

/// 같은 월드에 있는 **다른 요원**의 몸.
///
/// 조종하지 않는 몸이므로 입력도 전투 판정도 없다. 서버가 알려 준 좌표를 향해
/// 미끄러지듯 따라가며 그려질 뿐이다.
///
/// 좌표를 그대로 순간이동시키지 않는 이유가 있다. 위치 보고는 0.2 초마다 오는데
/// 받은 값을 즉시 반영하면 다른 사람이 초당 다섯 번 깜빡이며 튄다. 목표를 향해
/// 보간하면 같은 데이터로도 걸어오는 것처럼 보인다.
class RemotePlayerEntity extends IsoEntity {
  RemotePlayerEntity({required RemotePlayer snapshot})
      : characterId = snapshot.characterId,
        name = snapshot.name,
        level = snapshot.level,
        design = _designFor(snapshot.kind),
        _target = snapshot.grid.clone(),
        alive = snapshot.alive,
        super(grid: snapshot.grid.clone(), bodyRadius: 0.28, depthBias: 0.02);

  /// 서버가 부여한 캐릭터 식별자. 같은 사람을 다시 찾는 열쇠다.
  final int characterId;

  String name;
  int level;
  bool alive;

  /// 이 몸이 쓰는 신체 프레임. 내 캐릭터와 같은 렌더러로 그린다.
  final CyborgDesign design;

  /// 서버가 마지막으로 알려 준 위치. 여기를 향해 미끄러진다.
  Vector2 _target;

  double _animTime = 0;

  /// 마지막으로 나아간 방향. 멈춰 있으면 직전 방향을 유지한다.
  double _renderYaw = 0;

  /// 실제로 움직이고 있는지. 다리 애니메이션을 켤지 정한다.
  bool _moving = false;

  /// 서버 외형 문자열을 신체 프레임으로 옮긴다.
  ///
  /// 모르는 값이 와도 칸이 비지 않도록 기본 프레임으로 떨어뜨린다 — 서버에
  /// 새 외형이 생겼는데 이 클라이언트가 낡았을 때를 위한 것이다.
  static CyborgDesign _designFor(String kind) {
    return kind == 'female_cyborg'
        ? CyborgDesign.infiltrator
        : CyborgDesign.assault;
  }

  /// 서버가 알려 준 체력 비율(0~1).
  ///
  /// **PK 가 허용되므로 이것이 보여야 한다.** 상대가 얼마나 버티는지 모르면
  /// 덤빌지 물러설지 판단할 수 없고, 몹에게 쫓기는 동료를 알아볼 수도 없다.
  double hpRatio = 1;

  /// 체력 바를 더 보여 줄 시간(초).
  ///
  /// 멀쩡한 사람 머리 위에까지 바를 띄우면 사냥터가 막대로 뒤덮인다. 다치거나
  /// 회복하는 동안만 잠깐 띄우고, 조용해지면 이름표만 남긴다.
  double _healthBarTimer = 0;

  /// 지금 체력 바를 그려야 하는지.
  ///
  /// 만신창이인 사람은 계속 보여 준다 — 곧 쓰러질 상대를 놓치면 PK 든 구조든
  /// 판단할 기회가 사라진다.
  bool get _showHealthBar => _healthBarTimer > 0 || hpRatio < 0.999;

  /// 서버가 보낸 새 상태를 반영한다.
  void applySnapshot(RemotePlayer snapshot) {
    _target = snapshot.grid.clone();
    name = snapshot.name;
    level = snapshot.level;
    alive = snapshot.alive;

    final ratio = snapshot.hpRatio;
    // 값이 움직인 동안만 바를 띄운다. 다치는 쪽뿐 아니라 차오르는 쪽도 보여
    // 준다 — 회복하는 상대를 지금 칠지 기다릴지가 PK 의 판단거리다.
    if ((ratio - hpRatio).abs() > 0.001) _healthBarTimer = 3.0;
    hpRatio = ratio;
  }

  @override
  void update(double dt) {
    _animTime += dt;
    if (_healthBarTimer > 0) _healthBarTimer -= dt;

    final delta = _target - grid;
    final distance = delta.length;

    // 멀리 벌어졌으면(접속 직후, 텔레포트, 오래 끊겼다 돌아옴) 걸어가는 시늉을
    // 하지 않고 곧바로 옮긴다. 월드를 가로질러 미끄러지는 모습이 더 이상하다.
    if (distance > 12) {
      grid.setFrom(_target);
      _moving = false;
    } else if (distance > 0.02) {
      // 남은 거리에 비례해 따라간다. 보고 간격(0.2초)보다 조금 빠르게 잡아야
      // 다음 보고가 오기 전에 목표에 닿아 멈칫거리지 않는다.
      final step = math.min(1.0, dt * 9);
      grid.addScaled(delta, step);
      _moving = true;
      _renderYaw = _yawFor(delta);
    } else {
      _moving = false;
    }

    super.update(dt);
  }

  /// 그리드 방향을 화면 기준 각도로 바꾼다.
  double _yawFor(Vector2 gridDir) {
    final screen = gridDirToScreenDir(gridDir.normalized());
    return math.atan2(screen.y, screen.x);
  }

  @override
  void render(Canvas canvas) {
    if (!alive) {
      _renderDowned(canvas);
      return;
    }

    final cycle = _animTime * 9;
    final swing = _moving ? math.sin(cycle) : 0.0;
    final bob = _moving
        ? math.sin(cycle * 2) * 2.0 * design.bobScale
        : math.sin(_animTime * 2) * 1.2;

    CyborgRenderer.drawBody(
      canvas,
      design: design,
      yaw: _renderYaw,
      baseY: -bob,
      swing: swing,
      // 남의 몸에 칼날을 켜 두면 나를 향해 겨눈 것처럼 읽힌다. 아군인지
      // 적인지는 이름표가 말해 주고, 무기는 실제로 휘두를 때만 보여야 한다.
      showBlade: false,
      armSwing: _moving ? -swing * 6 : 0,
      time: _animTime,
    );

    _renderNameplate(canvas);
  }

  /// 쓰러진 몸. 아직 월드에 있지만 조종되지 않는 상태다.
  void _renderDowned(Canvas canvas) {
    canvas.save();
    canvas.translate(0, -6);
    canvas.scale(1.0, 0.35);
    canvas.drawCircle(
      Offset.zero,
      14,
      Paint()..color = GamePalette.shadow.withValues(alpha: 0.5),
    );
    canvas.restore();
    _renderNameplate(canvas);
  }

  /// 머리 위 이름표.
  ///
  /// 다른 요원을 **알아보는** 것이 이 몸을 그리는 이유의 절반이다. 누가 어느
  /// 수준인지 모르면 함께 사냥할지 피할지 판단할 수 없다.
  void _renderNameplate(Canvas canvas) {
    final label = 'Lv.$level $name';
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: alive ? GamePalette.textPrimary : GamePalette.textDim,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          shadows: const [
            Shadow(color: Colors.white, blurRadius: 3),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const top = -78.0;
    final rect = Rect.fromCenter(
      center: Offset(0, top),
      width: painter.width + 12,
      height: painter.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(5)),
      Paint()..color = GamePalette.hudBackground.withValues(alpha: 0.85),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        // 내 몸(청록)과 구별되는 색으로 테두리를 둘러 한눈에 남임을 알린다.
        ..color = GamePalette.remotePlayer.withValues(alpha: 0.8),
    );
    painter.paint(canvas, Offset(-painter.width / 2, top - painter.height / 2));

    if (alive && _showHealthBar) _renderHealthBar(canvas, top);
  }

  /// 이름표 아래에 붙는 체력 바.
  ///
  /// 몹의 체력 바와 같은 자리·같은 크기로 그린다. 사냥터에서 눈이 한 곳만
  /// 훑으면 되도록 하려는 것이고, 색만 달리해 **사람과 로봇을 가른다.**
  void _renderHealthBar(Canvas canvas, double nameplateTop) {
    const width = 34.0;
    const height = 4.0;
    final y = nameplateTop + 11;
    final rect = Rect.fromLTWH(-width / 2, y, width, height);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = GamePalette.hudBackground.withValues(alpha: 0.85),
    );

    final filled = Rect.fromLTWH(
      rect.left,
      rect.top,
      width * hpRatio.clamp(0.0, 1.0),
      height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(filled, const Radius.circular(2)),
      Paint()
        // 얼마 안 남았으면 붉게 바꾼다. 쓰러지기 직전인 사람은 한눈에 보여야
        // 구하러 갈지 덤빌지 정할 수 있다.
        ..color = hpRatio < 0.3
            ? GamePalette.hpFillLow
            : GamePalette.remotePlayer,
    );
  }
}
