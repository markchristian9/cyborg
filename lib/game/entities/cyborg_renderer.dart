import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../palette.dart';
import 'cyborg_design.dart';

/// [CyborgDesign] 프로필 하나를 캔버스에 그리는 렌더러.
///
/// 원점은 캐릭터의 발밑이고 y축은 위로 갈수록 음수다. 아이소메트릭 월드
/// 위에 세우는 빌보드이므로 좌우 반전(`canvas.scale(-1, 1)`)은 호출하는
/// 쪽에서 처리한다.
///
/// 게임 내 플레이어와 캐릭터 선택 화면이 같은 코드를 공유하도록
/// 상태를 갖지 않는 정적 메서드로 구성했다.
abstract final class CyborgRenderer {
  // 신체 각 부위의 높이를 총 키에 대한 비율로 정의한다.
  // 프레임마다 키가 달라도 비율이 같아 같은 계열의 실루엣을 유지한다.
  static const double _ankleRatio = 0.075;
  static const double _kneeRatio = 0.215;
  static const double _hipRatio = 0.385;
  static const double _waistRatio = 0.500;
  static const double _chestRatio = 0.625;
  static const double _shoulderRatio = 0.700;
  static const double _neckRatio = 0.745;
  static const double _headBottomRatio = 0.790;

  /// 사이보그 본체를 그린다.
  ///
  /// [baseY]는 상하 반동으로 인한 y 오프셋, [swing]은 -1~1 범위의 보행
  /// 위상, [back]은 뒷모습 여부다. [showBlade]가 참이면 대기 상태에서
  /// 손에 든 에너지 블레이드를 함께 그린다.
  static void drawBody(
    Canvas canvas, {
    required CyborgDesign design,
    double baseY = 0,
    double swing = 0,
    bool back = false,
    bool showBlade = true,
    double armSwing = 0,
  }) {
    final h = design.totalHeight;
    final y = _Levels(design, baseY);

    final armor = Paint()..color = design.armorBase;
    final armorLight = Paint()..color = design.armorLight;
    final accent = Paint()..color = design.accent;
    // 밝은 데이터 공간이 배경이므로 그림자 면은 가장 진한 톤으로 고정한다.
    final dark = Paint()..color = _deepShade;

    _drawLegs(canvas, design, y, swing, armor, dark, accent);
    _drawPelvis(canvas, design, y, armor);
    _drawTorso(canvas, design, y, armor, armorLight);

    if (back) {
      _drawBackDetails(canvas, design, y, accent, dark);
    } else {
      _drawFrontDetails(canvas, design, y, accent, armorLight);
    }

    _drawShoulders(canvas, design, y, armorLight, accent);
    _drawArms(canvas, design, y, armSwing, armor, armorLight);
    _drawNeck(canvas, design, y, dark);
    _drawHead(canvas, design, y, back, armorLight, accent, dark);

    if (showBlade) {
      _drawHolsteredBlade(canvas, design, y, h);
    }
  }

  // ── 하체 ────────────────────────────────────────────────────────────

  static void _drawLegs(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    double swing,
    Paint armor,
    Paint dark,
    Paint accent,
  ) {
    final t = design.legThickness;
    final stance = design.hipWidth * 0.38;

    for (var i = 0; i < 2; i++) {
      // 두 다리가 서로 반대 위상으로 흔들린다.
      final phase = (i == 0 ? swing : -swing) * design.strideScale;
      final legX = i == 0 ? -stance : stance;
      final footX = legX + phase * 5;

      // 허벅지에서 발목으로 이어지는 사다리꼴.
      final path = Path()
        ..moveTo(legX - t / 2, y.hip)
        ..lineTo(legX + t / 2, y.hip)
        ..lineTo(footX + t * 0.45, y.ankle)
        ..lineTo(footX - t * 0.45, y.ankle)
        ..close();
      // 뒤쪽 다리를 어둡게 칠해 깊이를 만든다.
      canvas.drawPath(path, i == 0 ? armor : dark);

      // 인공 힘줄이 노출된 프레임은 종아리에 발광 라인을 그린다.
      if (design.has(CyborgImplant.legTendon)) {
        canvas.drawLine(
          Offset(legX, y.knee),
          Offset(footX, y.ankle + 4),
          Paint()
            ..color = design.accent.withValues(alpha: i == 0 ? 0.85 : 0.45)
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round,
        );
      }

      // 부츠
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            footX - t * 0.7,
            y.ankle - 1,
            t * 1.5,
            y.foot - y.ankle + 1,
          ),
          const Radius.circular(2),
        ),
        dark,
      );
    }
  }

  static void _drawPelvis(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    Paint armor,
  ) {
    final half = design.hipWidth / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(-half, y.waist, half, y.hip + 2),
        const Radius.circular(3),
      ),
      armor,
    );
  }

  // ── 몸통 ────────────────────────────────────────────────────────────

  /// 어깨에서 골반까지의 실루엣을 그린다.
  ///
  /// 허리 폭이 가슴보다 충분히 좁으면 베지에 곡선이 안쪽으로 휘어
  /// 오목한(여성형) 실루엣이 되고, 그렇지 않으면 거의 직선에 가까운
  /// 볼록한(남성형) 실루엣이 된다.
  static void _drawTorso(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    Paint armor,
    Paint armorLight,
  ) {
    final chest = design.chestWidth / 2;
    final waist = design.waistWidth / 2;
    final hip = design.hipWidth / 2;

    // taper가 음수일수록 허리가 안쪽으로 깊게 파인다.
    final pinch = design.torsoTaper * chest;

    final path = Path()
      ..moveTo(-chest, y.chestTop)
      ..lineTo(chest, y.chestTop)
      // 오른쪽 옆구리: 가슴 → 허리
      ..quadraticBezierTo(
        chest + pinch,
        (y.chestTop + y.waist) / 2,
        waist,
        y.waist,
      )
      // 오른쪽 골반
      ..lineTo(hip, y.hip)
      ..lineTo(-hip, y.hip)
      // 왼쪽 옆구리: 허리 → 가슴
      ..lineTo(-waist, y.waist)
      ..quadraticBezierTo(
        -chest - pinch,
        (y.chestTop + y.waist) / 2,
        -chest,
        y.chestTop,
      )
      ..close();
    canvas.drawPath(path, armor);

    // 흉갑 하이라이트: 빛을 받는 왼쪽 면.
    final plate = Path()
      ..moveTo(-chest * 0.72, y.chestTop + 2)
      ..lineTo(chest * 0.18, y.chestTop + 2)
      ..lineTo(chest * 0.02, y.chest)
      ..lineTo(-chest * 0.62, y.chest)
      ..close();
    canvas.drawPath(plate, armorLight);
  }

  // ── 정면 디테일 ─────────────────────────────────────────────────────

  static void _drawFrontDetails(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    Paint accent,
    Paint armorLight,
  ) {
    final chest = design.chestWidth / 2;

    // 흉골 프레임: 가슴 중앙을 세로로 가로지르는 노출 골격.
    if (design.has(CyborgImplant.sternalFrame)) {
      final rib = Paint()
        ..color = design.armorLight
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 3; i++) {
        final ry = y.chestTop - 3 - i * 5.0;
        canvas.drawLine(
          Offset(-chest * 0.55, ry),
          Offset(chest * 0.55, ry),
          rib,
        );
      }
    }

    // 가슴 에너지 코어: 모든 프레임의 공통 동력원.
    final coreY = y.chest + (y.chestTop - y.chest) * 0.35;
    canvas.drawCircle(
      Offset(0, coreY),
      design.frame == CyborgFrame.assault ? 4.5 : 3.4,
      Paint()
        ..color = design.accent
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(
      Offset(0, coreY),
      design.frame == CyborgFrame.assault ? 2.6 : 2.0,
      accent,
    );

    // 생명유지 흡입구: 복부에 뚫린 포트.
    if (design.has(CyborgImplant.vitalIntake)) {
      final portY = (y.waist + y.chest) / 2;
      for (var i = -1; i <= 1; i += 2) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(i * design.waistWidth * 0.28, portY),
            width: 3.4,
            height: 5.2,
          ),
          Paint()..color = design.accent.withValues(alpha: 0.55),
        );
      }
    }
  }

  // ── 배면 디테일 ─────────────────────────────────────────────────────

  static void _drawBackDetails(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    Paint accent,
    Paint dark,
  ) {
    // 척추 동력팩: 등에 업은 대형 배터리.
    if (design.has(CyborgImplant.spinalPowerPack)) {
      final w = design.chestWidth * 0.7;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(-w / 2, y.chestTop + 4, w / 2, y.chest + 4),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0xFF1E2733),
      );
      canvas.drawRect(
        Rect.fromLTRB(-w * 0.3, y.chestTop + 8, w * 0.3, y.chestTop + 11),
        accent,
      );
    }

    // 척추 발광 레일: 목덜미에서 허리까지 흐르는 얇은 라인.
    if (design.has(CyborgImplant.spinalLightRail)) {
      canvas.drawLine(
        Offset(0, y.chestTop + 2),
        Offset(0, y.waist),
        Paint()
          ..color = design.accent.withValues(alpha: 0.9)
          ..strokeWidth = 2.2
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
      // 척추 마디를 나타내는 점.
      for (var i = 0; i < 4; i++) {
        final t = i / 3;
        canvas.drawCircle(
          Offset(0, y.chestTop + 2 + (y.waist - y.chestTop - 2) * t),
          1.5,
          Paint()..color = design.accentSoft,
        );
      }
    }
  }

  // ── 어깨 · 팔 ───────────────────────────────────────────────────────

  static void _drawShoulders(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    Paint armorLight,
    Paint accent,
  ) {
    final pad = design.shoulderPadSize;
    if (pad <= 0) return;
    final outer = design.shoulderWidth / 2;

    for (var i = -1; i <= 1; i += 2) {
      final cx = i * (outer - pad / 2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(cx, y.shoulder),
            width: pad,
            height: pad * 1.05,
          ),
          Radius.circular(pad * 0.36),
        ),
        armorLight,
      );

      // 어깨 구동기: 관절에 드러난 유압 실린더.
      if (design.has(CyborgImplant.shoulderActuator)) {
        canvas.drawCircle(
          Offset(cx, y.shoulder + pad * 0.1),
          pad * 0.18,
          accent,
        );
      }
    }
  }

  static void _drawArms(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    double armSwing,
    Paint armor,
    Paint armorLight,
  ) {
    final t = design.armThickness;
    final outer = design.shoulderWidth / 2;
    final armTop = y.shoulder + design.shoulderPadSize * 0.3;
    final armLength = (armTop - y.waist).abs() + design.armThickness;

    // 왼팔(뒤쪽): 보행에 맞춰 흔들린다.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-outer + 1, armTop + armSwing, t, armLength),
        Radius.circular(t * 0.4),
      ),
      armor,
    );

    // 오른팔(무기 쪽): 앞으로 내밀어 무기를 잡은 자세로 고정한다.
    final weaponArm = Path()
      ..moveTo(outer - t, armTop)
      ..lineTo(outer + t * 0.6, armTop + t * 0.5)
      ..lineTo(outer + t * 0.6, armTop + armLength * 0.72)
      ..lineTo(outer - t, armTop + armLength * 0.78)
      ..close();
    canvas.drawPath(weaponArm, armorLight);
  }

  // ── 머리 ────────────────────────────────────────────────────────────

  static void _drawNeck(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    Paint dark,
  ) {
    final w = design.headWidth * 0.28;
    canvas.drawRect(
      Rect.fromLTRB(-w / 2, y.headBottom, w / 2, y.neck),
      dark,
    );
  }

  static void _drawHead(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    bool back,
    Paint armorLight,
    Paint accent,
    Paint dark,
  ) {
    final hw = design.headWidth;
    final hh = design.headHeight;
    final center = Offset(0.5, y.headBottom - hh / 2);

    // 뒷머리는 헬멧보다 먼저 그려 겹치지 않게 한다.
    if (design.hairStyle == CyborgHair.ponytail) {
      _drawPonytail(canvas, design, center, hw, hh, back);
    }

    // 헬멧: 위는 둥글고 아래는 각진 형태.
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromCenter(center: center, width: hw, height: hh),
        topLeft: Radius.circular(hw * 0.38),
        topRight: Radius.circular(hw * 0.38),
        bottomLeft: Radius.circular(hw * 0.19),
        bottomRight: Radius.circular(hw * 0.19),
      ),
      armorLight,
    );

    if (!back) {
      // 바이저
      final visor = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          -hw * 0.1,
          center.dy - hh * 0.22,
          hw * 0.56,
          hh * 0.3,
        ),
        Radius.circular(hh * 0.15),
      );
      canvas.drawRRect(
        visor,
        Paint()
          ..color = design.visorColor
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawRRect(visor, Paint()..color = design.visorColor);

      // 헬멧 아래로 드러난 턱.
      canvas.drawRect(
        Rect.fromLTWH(
          -hw * 0.14,
          center.dy + hh * 0.28,
          hw * 0.42,
          hh * 0.16,
        ),
        Paint()..color = GamePalette.playerSkin,
      );
    } else if (design.hairStyle == CyborgHair.napeCable) {
      // 뒤통수에서 목으로 이어지는 접속 케이블.
      canvas.drawLine(
        Offset(0, center.dy + hh * 0.3),
        Offset(-2, y.neck + 4),
        Paint()
          ..color = design.accent.withValues(alpha: 0.7)
          ..strokeWidth = 2,
      );
    }

    // 대뇌피질 모듈: 관자놀이에 박힌 연산 유닛.
    if (design.has(CyborgImplant.corticalModule)) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(-hw * 0.42, center.dy - hh * 0.05),
            width: hw * 0.16,
            height: hh * 0.34,
          ),
          const Radius.circular(1.5),
        ),
        dark,
      );
      canvas.drawCircle(
        Offset(-hw * 0.42, center.dy - hh * 0.05),
        1.4,
        accent,
      );
    }

    // 헬멧 안테나
    final antennaBase = Offset(-hw * 0.3, center.dy - hh * 0.5);
    final antennaTip = Offset(antennaBase.dx - 3, antennaBase.dy - 10);
    canvas.drawLine(
      antennaBase,
      antennaTip,
      Paint()
        ..color = design.accent
        ..strokeWidth = 1.6,
    );
    canvas.drawCircle(antennaTip, 1.8, accent);
  }

  static void _drawPonytail(
    Canvas canvas,
    CyborgDesign design,
    Offset center,
    double hw,
    double hh,
    bool back,
  ) {
    // 뒤로 흘러내린 머리채. 뒷모습에서는 더 크게 보인다.
    final length = hh * (back ? 1.5 : 1.15);
    final side = back ? 0.0 : -hw * 0.42;
    final path = Path()
      ..moveTo(side, center.dy - hh * 0.28)
      ..quadraticBezierTo(
        side - hw * 0.55,
        center.dy + length * 0.4,
        side - hw * 0.28,
        center.dy + length,
      )
      ..quadraticBezierTo(
        side - hw * 0.05,
        center.dy + length * 0.45,
        side + hw * 0.12,
        center.dy - hh * 0.2,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFF17222E));
    // 머리카락에 섞인 광섬유 가닥.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = design.accent.withValues(alpha: 0.5),
    );
  }

  // ── 무기 ────────────────────────────────────────────────────────────

  static void _drawHolsteredBlade(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    double h,
  ) {
    final x = design.shoulderWidth / 2 + design.armThickness * 0.5;
    final top = y.shoulder + design.shoulderPadSize * 0.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, top, 3, h * 0.24),
        const Radius.circular(1.5),
      ),
      Paint()..color = GamePalette.bladeGlow.withValues(alpha: 0.55),
    );
  }

  /// 캐릭터 선택 화면 등에서 쓰는 프리뷰. 정면 대기 자세로 그린다.
  ///
  /// [scale]로 크기를 조절하며, [time]을 넘기면 가볍게 호흡한다.
  static void drawPreview(
    Canvas canvas, {
    required CyborgDesign design,
    double scale = 1.0,
    double time = 0,
  }) {
    canvas.save();
    canvas.scale(scale);
    final breathe = math.sin(time * 2) * 1.2;
    drawBody(
      canvas,
      design: design,
      baseY: -breathe,
      back: false,
      showBlade: true,
    );
    canvas.restore();
  }
}

/// 프로필의 총 키로부터 각 부위의 y 좌표를 계산해 둔 값.
///
/// 발밑이 원점이고 위로 갈수록 음수이므로 모든 값이 0 이하다.
class _Levels {
  _Levels(CyborgDesign design, double baseY)
      : foot = baseY,
        ankle = baseY - design.totalHeight * CyborgRenderer._ankleRatio,
        knee = baseY - design.totalHeight * CyborgRenderer._kneeRatio,
        hip = baseY - design.totalHeight * CyborgRenderer._hipRatio,
        waist = baseY - design.totalHeight * CyborgRenderer._waistRatio,
        chest = baseY - design.totalHeight * CyborgRenderer._chestRatio,
        chestTop = baseY - design.totalHeight * CyborgRenderer._shoulderRatio,
        shoulder = baseY - design.totalHeight * CyborgRenderer._shoulderRatio,
        neck = baseY - design.totalHeight * CyborgRenderer._neckRatio,
        headBottom =
            baseY - design.totalHeight * CyborgRenderer._headBottomRatio;

  final double foot;
  final double ankle;
  final double knee;
  final double hip;
  final double waist;
  final double chest;

  /// 몸통 상단(어깨선).
  final double chestTop;
  final double shoulder;
  final double neck;
  final double headBottom;
}
