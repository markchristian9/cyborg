import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../palette.dart';
import 'cyborg_design.dart';

/// [CyborgDesign] 프로필 하나를 캔버스에 그리는 렌더러.
///
/// 원점은 캐릭터의 발밑이고 y축은 위로 갈수록 음수다.
///
/// ## 방향 처리 — 양자화 없는 연속 회전
///
/// 스프라이트 시트를 쓰지 않으므로 방향을 N장으로 쪼갤 이유가 없다. 몸통을
/// **타원기둥**으로 근사하고, 각 신체 부위에 "몸통 둘레상의 각도"([_Anchor])를
/// 부여한 뒤 시선각 `yaw` 만큼 돌려서 화면에 투영한다. 그래서 `yaw` 는 256 방향은
/// 물론 **실수 각도 전부**를 받는다.
///
/// 투영으로 각 부위의 화면 x 와 **깊이**가 함께 나오므로,
/// 깊이 부호로 앞/뒤 가림과 그리는 순서가 자동으로 결정된다. 예전처럼
/// `canvas.scale(-1, 1)` 로 좌우를 뒤집거나 `back` 불리언을 넘길 필요가 없다.
///
/// 게임 내 플레이어와 캐릭터 선택 화면이 같은 그림을 쓰도록 상태 없는 정적
/// 메서드로 구성했다.
abstract final class CyborgRenderer {
  /// 그림자 면·부츠·케이블처럼 가장 어두워야 하는 부위의 색.
  ///
  /// 배경이 밝은 데이터 공간이라 실루엣이 뭉개지지 않도록 팔레트에서
  /// 가장 진한 톤을 가져다 쓴다.
  static const Color _deepShade = GamePalette.textPrimary;

  /// 몸통의 앞뒤 두께 ÷ 좌우 폭. 옆에서 봤을 때 얼마나 얇아지는지를 정한다.
  static const double _bodyDepthRatio = 0.62;

  /// 머리의 앞뒤 두께 비율. 구에 가까워 몸통보다 덜 납작해진다.
  static const double _headDepthRatio = 0.88;

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
  /// [yaw]는 캐릭터가 바라보는 방향(라디안)이다. `0`이면 카메라를 정면으로
  /// 마주 보고, `π`면 등을 보인다. **연속값**이라 원하는 만큼 방향을 촘촘히
  /// 줄 수 있다. 그리드 방향 벡터에서 구하려면 `iso.dart` 의 `facingYaw()`를 쓴다.
  ///
  /// [baseY]는 상하 반동 오프셋, [swing]은 -1~1 범위의 보행 위상,
  /// [armSwing]은 팔 흔들림이다. [showBlade]가 참이면 등에 멘 블레이드를 그린다.
  static void drawBody(
    Canvas canvas, {
    required CyborgDesign design,
    double yaw = 0,
    double baseY = 0,
    double swing = 0,
    bool showBlade = true,
    double armSwing = 0,
    double time = 0,
  }) {
    final y = _Levels(design, baseY);
    final view = _View(design, yaw);
    // 코어와 발광 부위가 함께 맥동한다. 정지해 있어도 살아 있어 보인다.
    final pulse = 0.72 + 0.28 * math.sin(time * 3.2);

    final armor = Paint()..color = design.armorBase;
    final armorLight = Paint()..color = design.armorLight;
    final accent = Paint()..color = design.accent;
    // 밝은 데이터 공간이 배경이므로 그림자 면은 가장 진한 톤으로 고정한다.
    final dark = Paint()..color = _deepShade;

    // 몸통 뒤에 있는 것부터 그린다. 등에 업는 장비는 정면일 때 가려지고
    // 뒤를 보일 때만 드러난다.
    _drawBackRig(canvas, design, y, view, accent);
    if (showBlade) _drawHolsteredBlade(canvas, design, y, view);

    // 뒤쪽 팔 → 몸통 → 앞쪽 팔 순서로 그려야 팔이 몸을 올바르게 가린다.
    final arms = _armsByDepth(design, y, view, armSwing);
    for (final arm in arms.where((a) => a.depth <= 0)) {
      _drawArm(canvas, design, y, view, arm, armor, armorLight);
    }

    _drawLegs(canvas, design, y, view, swing, armor, dark, armorLight, pulse);
    _drawPelvis(canvas, design, y, view, armor);
    _drawTorso(canvas, design, y, view, armor, armorLight);
    _drawTorsoDetails(canvas, design, y, view, accent, armorLight, pulse);
    _drawShoulders(canvas, design, y, view, armorLight, accent);

    for (final arm in arms.where((a) => a.depth > 0)) {
      _drawArm(canvas, design, y, view, arm, armor, armorLight);
    }

    _drawNeck(canvas, design, y, view, dark);
    _drawHead(canvas, design, y, view, armorLight, accent, dark);
  }

  // ── 하체 ────────────────────────────────────────────────────────────

  static void _drawLegs(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    _View view,
    double swing,
    Paint armor,
    Paint dark,
    Paint armorLight,
    double pulse,
  ) {
    final t = design.legThickness;
    // 두 다리 사이가 벌어져 보이지 않도록 골반 폭보다 좁게 딛는다.
    final stanceRadius = design.hipWidth * 0.29;

    // 두 다리를 몸통 둘레의 좌우(±π/2)에 놓고 투영한다. 옆을 보면 한 다리가
    // 다른 다리 뒤로 들어가며 자연스럽게 겹친다.
    final legs = <_Limb>[];
    for (var i = 0; i < 2; i++) {
      final anchor = i == 0 ? -math.pi / 2 : math.pi / 2;
      final p = view.project(anchor, stanceRadius, stanceRadius * 0.7);
      // 보행 위상: 앞으로 뻗는 다리가 화면에서도 앞으로 나온다.
      final phase = (i == 0 ? swing : -swing) * design.strideScale;
      legs.add(_Limb(x: p.x, depth: p.depth, phase: phase));
    }
    // 뒤쪽 다리부터 그린다.
    legs.sort((a, b) => a.depth.compareTo(b.depth));

    for (final leg in legs) {
      final isBack = leg.depth <= 0;
      // 앞뒤로 내딛는 발은 시선각에 따라 화면 가로로도, 세로로도 보인다.
      // 가로 성분만 쓰면 정면·후면에서 보폭이 0이 된다.
      final strideX = leg.phase * 5 * view.strideProjection;
      final strideY = leg.phase * 2.6 * view.strideDepth;
      // 측면에서 두 다리가 한 짝으로 뭉치지 않게 살짝 벌린다.
      final split = view.sideSplit(t * 0.42) * (leg.x >= 0 ? 1 : -1);
      final hipX = leg.x + split;
      final footX = hipX + strideX;
      final footY = y.ankle + strideY;

      final path = Path()
        ..moveTo(hipX - t / 2, y.hip)
        ..lineTo(hipX + t / 2, y.hip)
        ..lineTo(footX + t * 0.45, footY)
        ..lineTo(footX - t * 0.45, footY)
        ..close();
      canvas.drawPath(path, isBack ? dark : armor);

      // 인공 힘줄이 노출된 프레임은 종아리에 발광 라인을 그린다.
      if (design.has(CyborgImplant.legTendon)) {
        canvas.drawLine(
          Offset(hipX, y.knee),
          Offset(footX, footY + 4),
          Paint()
            ..color = design.accent.withValues(alpha: isBack ? 0.45 : 0.85)
            ..strokeWidth = 1.6
            ..strokeCap = StrokeCap.round,
        );
      }

      // 무릎 마디. 허벅지와 종아리를 끊어 축소해도 관절이 1px 이라도 남게
      // 한다. 이 마디가 없으면 다리가 하나의 막대로 뭉친다.
      final kneeX = hipX + (footX - hipX) * 0.45;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(kneeX, y.knee),
            width: t * 1.12,
            height: t * 0.62,
          ),
          Radius.circular(t * 0.28),
        ),
        isBack ? dark : armorLight,
      );

      // 부츠
      final boot = Rect.fromLTWH(
        footX - t * 0.7,
        footY - 1,
        t * 1.5,
        y.foot - y.ankle + 1,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(boot, const Radius.circular(2)),
        dark,
      );
      // 부츠 밑창의 추진 발광. 지면과 닿는 선을 밝혀 캐릭터가 떠 보이지 않게 한다.
      canvas.drawLine(
        Offset(boot.left + 1, boot.bottom - 1),
        Offset(boot.right - 1, boot.bottom - 1),
        Paint()
          ..color = design.accent
              .withValues(alpha: (isBack ? 0.35 : 0.8) * pulse)
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
      );
    }
  }

  static void _drawPelvis(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    _View view,
    Paint armor,
  ) {
    final half = view.halfWidth(design.hipWidth);
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
  /// 허리 폭이 가슴보다 충분히 좁으면 베지에 곡선이 안쪽으로 휘어 오목한
  /// (여성형) 실루엣이 되고, 그렇지 않으면 볼록한(남성형) 실루엣이 된다.
  /// 각 폭은 시선각에 따라 줄어들어 옆을 볼수록 얇아진다.
  static void _drawTorso(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    _View view,
    Paint armor,
    Paint armorLight,
  ) {
    final chest = view.halfWidth(design.chestWidth);
    final waist = view.halfWidth(design.waistWidth);
    final hip = view.halfWidth(design.hipWidth);

    // taper가 음수일수록 허리가 안쪽으로 깊게 파인다.
    final pinch = design.torsoTaper * chest;

    final path = Path()
      ..moveTo(-chest, y.chestTop)
      ..lineTo(chest, y.chestTop)
      ..quadraticBezierTo(
        chest + pinch,
        (y.chestTop + y.waist) / 2,
        waist,
        y.waist,
      )
      ..lineTo(hip, y.hip)
      ..lineTo(-hip, y.hip)
      ..lineTo(-waist, y.waist)
      ..quadraticBezierTo(
        -chest - pinch,
        (y.chestTop + y.waist) / 2,
        -chest,
        y.chestTop,
      )
      ..close();
    canvas.drawPath(path, armor);

    // 흉갑 하이라이트. 빛을 받는 면이 시선각을 따라 이동한다.
    final lit = view.project(-0.6, design.chestWidth / 2, view.bodyDepth(design));
    if (lit.depth > 0) {
      final w = chest * 0.5;
      final plate = Path()
        ..moveTo(lit.x - w * 0.7, y.chestTop + 2)
        ..lineTo(lit.x + w * 0.5, y.chestTop + 2)
        ..lineTo(lit.x + w * 0.3, y.chest)
        ..lineTo(lit.x - w * 0.6, y.chest)
        ..close();
      canvas.save();
      canvas.clipPath(path);
      canvas.drawPath(plate, armorLight);
      canvas.restore();
    }

    // 림 라이트: 실루엣 가장자리를 따라 흐르는 얇은 발광 윤곽.
    // 밝은 데이터 공간 위에서 짙은 몸이 배경에 묻히지 않게 잡아 준다.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = design.accent.withValues(alpha: 0.55),
    );
  }

  /// 가슴·복부의 임플란트. 몸통 둘레 위 위치를 투영해 배치한다.
  static void _drawTorsoDetails(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    _View view,
    Paint accent,
    Paint armorLight,
    double pulse,
  ) {
    final halfW = design.chestWidth / 2;
    final halfD = view.bodyDepth(design);

    // 흉골 프레임: 가슴 정면(둘레각 0)을 가로지르는 노출 골격.
    if (design.has(CyborgImplant.sternalFrame)) {
      final c = view.project(0, halfW, halfD);
      if (c.depth > 0) {
        // 정면을 향할수록 갈비가 넓게 보이고, 옆을 보면 좁아진다.
        final spread = halfW * 0.55 * view.facingAmount;
        final rib = Paint()
          ..color = design.armorLight
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round;
        // 갈비는 어깨선(`chestTop`) **아래**, 가슴 안쪽에 놓여야 한다.
        // y 는 위로 갈수록 음수이므로 빼면 몸통 밖(목·머리)으로 올라간다.
        final rib0 = y.chestTop + 2.5;
        final ribGap = (y.chest - y.chestTop) / 3.6;
        for (var i = 0; i < 3; i++) {
          final ry = rib0 + i * ribGap;
          canvas.drawLine(
            Offset(c.x - spread, ry),
            Offset(c.x + spread, ry),
            rib,
          );
        }
      }
    }

    // 가슴 에너지 코어: 모든 프레임의 공통 동력원.
    final core = view.project(0, halfW * 0.35, halfD);
    if (core.depth > 0) {
      final coreY = y.chest + (y.chestTop - y.chest) * 0.35;
      final r = design.frame == CyborgFrame.assault ? 4.5 : 3.4;
      final c = Offset(core.x, coreY);
      // 바깥 후광 → 본체 → 흰 심지. 세 겹으로 쌓아야 발광처럼 읽힌다.
      canvas.drawCircle(
        c,
        r * (1.6 + 0.5 * pulse),
        Paint()
          ..color = design.accent.withValues(alpha: 0.30 * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = design.accent
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(c, r * 0.58, accent);
      canvas.drawCircle(
        c,
        r * 0.26,
        Paint()..color = GamePalette.bladeCore.withValues(alpha: pulse),
      );
      // 코어를 감싸는 방열 링.
      canvas.drawCircle(
        c,
        r * 1.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = design.accentSoft.withValues(alpha: 0.5 * pulse),
      );
    }

    // 생명유지 흡입구: 복부 좌우에 뚫린 포트.
    if (design.has(CyborgImplant.vitalIntake)) {
      final portY = (y.waist + y.chest) / 2;
      for (var i = -1; i <= 1; i += 2) {
        final p = view.project(i * 0.7, design.waistWidth / 2, halfD * 0.8);
        if (p.depth <= 0) continue;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(p.x, portY),
            width: 3.4,
            height: 5.2,
          ),
          Paint()..color = design.accent.withValues(alpha: 0.55),
        );
      }
    }
  }

  // ── 등에 업은 장비 ──────────────────────────────────────────────────

  /// 척추 동력팩과 발광 레일. 둘레각 π(등)에 붙어 있다.
  static void _drawBackRig(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    _View view,
    Paint accent,
  ) {
    final halfD = view.bodyDepth(design);

    if (design.has(CyborgImplant.spinalPowerPack)) {
      final p = view.project(math.pi, design.chestWidth * 0.2, halfD);
      if (p.depth > 0) {
        final w = design.chestWidth * 0.7 * view.facingAmount + 4;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(p.x, (y.chestTop + y.chest) / 2 + 4),
              width: w,
              height: (y.chest - y.chestTop).abs(),
            ),
            const Radius.circular(3),
          ),
          Paint()..color = _deepShade,
        );
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset(p.x, y.chestTop + 9),
            width: w * 0.6,
            height: 3,
          ),
          accent,
        );
      }
    }

    if (design.has(CyborgImplant.spinalLightRail)) {
      final p = view.project(math.pi, design.chestWidth * 0.1, halfD);
      if (p.depth > 0) {
        canvas.drawLine(
          Offset(p.x, y.chestTop + 2),
          Offset(p.x, y.waist),
          Paint()
            ..color = design.accent.withValues(alpha: 0.9)
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2),
        );
        for (var i = 0; i < 4; i++) {
          final t = i / 3;
          canvas.drawCircle(
            Offset(p.x, y.chestTop + 2 + (y.waist - y.chestTop - 2) * t),
            1.5,
            Paint()..color = design.accentSoft,
          );
        }
      }
    }
  }

  // ── 어깨 · 팔 ───────────────────────────────────────────────────────

  static void _drawShoulders(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    _View view,
    Paint armorLight,
    Paint accent,
  ) {
    final pad = design.shoulderPadSize;
    if (pad <= 0) return;

    final radius = design.shoulderWidth / 2 - pad / 2;
    // 앞뒤 두께는 **몸통** 기준이어야 어깨가 몸에 붙어 보인다. 어깨 폭으로
    // 두께까지 잡으면 옆을 볼 때 어깨가 몸 밖으로 붕 뜬다.
    final depth = view.bodyDepth(design);
    final pads = <_Limb>[];
    for (var i = 0; i < 2; i++) {
      final anchor = i == 0 ? -math.pi / 2 : math.pi / 2;
      final p = view.project(anchor, radius, depth);
      final split = view.sideSplit(pad * 0.3) * (i == 0 ? -1 : 1);
      // phase 로 좌우를 표시해 둔다(어깨는 보행에 흔들리지 않는다).
      pads.add(_Limb(x: p.x + split, depth: p.depth, phase: i == 0 ? -1 : 1));
    }
    pads.sort((a, b) => a.depth.compareTo(b.depth));

    for (final s in pads) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(s.x, y.shoulder),
            width: pad,
            height: pad * 1.05,
          ),
          Radius.circular(pad * 0.36),
        ),
        armorLight,
      );

      // 강습 프레임은 **한쪽 어깨에만** 증설 장갑을 단다. 좌우 대칭 실루엣은
      // 축소하면 정보량이 절반이라, 비대칭 덩어리 하나가 남녀 구분을 만든다.
      if (design.frame == CyborgFrame.assault && s.phase < 0) {
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            Rect.fromCenter(
              center: Offset(s.x - pad * 0.16, y.shoulder - pad * 0.16),
              width: pad * 1.22,
              height: pad * 0.86,
            ),
            topLeft: Radius.circular(pad * 0.42),
            topRight: Radius.circular(pad * 0.2),
            bottomLeft: Radius.circular(pad * 0.14),
            bottomRight: Radius.circular(pad * 0.14),
          ),
          armorLight,
        );
      }

      // 어깨 구동기: 관절에 드러난 유압 실린더.
      if (design.has(CyborgImplant.shoulderActuator) && s.depth > -radius * 0.5) {
        canvas.drawCircle(
          Offset(s.x, y.shoulder + pad * 0.1),
          pad * 0.18,
          accent,
        );
      }
    }
  }

  /// 두 팔을 깊이 순으로 정렬해 돌려준다.
  static List<_Limb> _armsByDepth(
    CyborgDesign design,
    _Levels y,
    _View view,
    double armSwing,
  ) {
    final radius = design.shoulderWidth / 2 - design.armThickness * 0.4;
    // 어깨와 같은 이유로 앞뒤 두께는 몸통 기준을 쓴다.
    final depth = view.bodyDepth(design);
    final arms = <_Limb>[];
    for (var i = 0; i < 2; i++) {
      final anchor = i == 0 ? -math.pi / 2 : math.pi / 2;
      final p = view.project(anchor, radius, depth);
      // 측면에서 두 팔이 한 짝으로 겹치지 않도록 벌린다.
      final split = view.sideSplit(design.armThickness * 0.55) * (i == 0 ? -1 : 1);
      arms.add(
        _Limb(
          x: p.x + split,
          depth: p.depth,
          // 왼팔만 보행에 맞춰 흔들리고, 오른팔은 무기를 든 자세로 고정한다.
          phase: i == 0 ? armSwing : 0,
          isWeaponArm: i == 1,
        ),
      );
    }
    arms.sort((a, b) => a.depth.compareTo(b.depth));
    return arms;
  }

  static void _drawArm(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    _View view,
    _Limb arm,
    Paint armor,
    Paint armorLight,
  ) {
    final t = design.armThickness;
    final armTop = y.shoulder + design.shoulderPadSize * 0.3;
    final armLength = (armTop - y.waist).abs() + t;

    if (!arm.isWeaponArm) {
      // 팔은 앞뒤로 흔들린다. 예전처럼 y 에만 더하면 어느 각도에서 보든
      // 위아래로 펌프질하는 것처럼 보인다 — 다리와 같이 시선각으로 분해한다.
      final swingX = arm.phase * 0.85 * view.strideProjection;
      final swingY = arm.phase * 0.45 * view.strideDepth;
      final path = Path()
        ..moveTo(arm.x - t / 2, armTop)
        ..lineTo(arm.x + t / 2, armTop)
        ..lineTo(arm.x + t / 2 + swingX, armTop + armLength + swingY)
        ..lineTo(arm.x - t / 2 + swingX, armTop + armLength + swingY)
        ..close();
      canvas.drawPath(path, armor);
      // 손목 마디. 팔 끝을 끊어 축소해도 관절이 남게 한다.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(
              arm.x + swingX,
              armTop + armLength + swingY - t * 0.35,
            ),
            width: t * 1.05,
            height: t * 0.8,
          ),
          Radius.circular(t * 0.3),
        ),
        armorLight,
      );
      return;
    }

    // 무기 팔: 팔꿈치를 살짝 앞으로 내민다. 몸통과 같은 톤이라야 실루엣이
    // 판때기처럼 뭉치지 않는다.
    final lean = t * 0.45 * view.strideProjection;
    final path = Path()
      ..moveTo(arm.x - t * 0.5, armTop)
      ..lineTo(arm.x + t * 0.5, armTop + t * 0.4)
      ..lineTo(arm.x + t * 0.5 + lean, armTop + armLength * 0.7)
      ..lineTo(arm.x - t * 0.5 + lean, armTop + armLength * 0.76)
      ..close();
    canvas.drawPath(path, armor);

    // 무기를 쥔 손: 팔 끝을 밝게 끊어 실루엣의 마디를 만든다.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(arm.x + lean * 0.8, armTop + armLength * 0.74),
          width: t * 1.15,
          height: t * 0.85,
        ),
        Radius.circular(t * 0.3),
      ),
      armorLight,
    );
  }

  // ── 머리 ────────────────────────────────────────────────────────────

  static void _drawNeck(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    _View view,
    Paint dark,
  ) {
    // 머리 아래부터 어깨선까지 이어 붙여야 머리가 떠 보이지 않는다.
    final w = view.halfWidth(design.headWidth * 0.3);
    canvas.drawRect(
      Rect.fromLTRB(-w, y.headBottom, w, y.chestTop + 2),
      dark,
    );
  }

  static void _drawHead(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    _View view,
    Paint armorLight,
    Paint accent,
    Paint dark,
  ) {
    final hh = design.headHeight;
    // 머리는 구에 가까워 옆을 봐도 몸통만큼 얇아지지 않는다.
    final hw = design.headWidth * view.headWidthScale;
    final cy = y.headBottom - hh / 2;
    final headR = design.headWidth / 2;
    final headD = headR * _headDepthRatio;

    // 뒷머리는 헬멧보다 먼저 그려 겹치지 않게 한다.
    if (design.hairStyle == CyborgHair.ponytail) {
      _drawPonytail(canvas, design, view, cy, headR, headD, hh);
    }

    // 헬멧
    final helmet = RRect.fromRectAndCorners(
      Rect.fromCenter(center: Offset(0, cy), width: hw, height: hh),
      topLeft: Radius.circular(hw * 0.38),
      topRight: Radius.circular(hw * 0.38),
      bottomLeft: Radius.circular(hw * 0.19),
      bottomRight: Radius.circular(hw * 0.19),
    );
    canvas.drawRRect(helmet, armorLight);
    // 헬멧 윤곽의 림 라이트.
    canvas.drawRRect(
      helmet,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = design.accent.withValues(alpha: 0.6),
    );
    // 정수리를 가로지르는 냉각 리지.
    canvas.drawLine(
      Offset(-hw * 0.06, cy - hh * 0.46),
      Offset(-hw * 0.06, cy - hh * 0.12),
      Paint()
        ..color = design.accentSoft.withValues(alpha: 0.45)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );

    // 바이저: 얼굴 정면(둘레각 0). 뒤를 보면 사라진다.
    final face = view.project(0, headR * 0.5, headD);
    if (face.depth > 0) {
      final vw = hw * 0.56 * (0.55 + 0.45 * view.facingAmount);
      final visor = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(face.x, cy - hh * 0.07),
          width: vw,
          height: hh * 0.3,
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
      // 바이저를 가로지르는 주사선. 렌즈처럼 보이게 하는 마디다.
      canvas.save();
      canvas.clipRRect(visor);
      canvas.drawLine(
        Offset(visor.left, cy - hh * 0.07),
        Offset(visor.right, cy - hh * 0.07),
        Paint()
          ..color = design.accent.withValues(alpha: 0.75)
          ..strokeWidth = 1.2,
      );
      canvas.restore();

      // 헬멧 아래로 드러난 턱.
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset(face.x, cy + hh * 0.36),
          width: vw * 0.72,
          height: hh * 0.16,
        ),
        Paint()..color = GamePalette.playerSkin,
      );
    }

    // 뒤통수 접속 케이블: 둘레각 π.
    if (design.hairStyle == CyborgHair.napeCable) {
      final nape = view.project(math.pi, headR * 0.4, headD);
      if (nape.depth > 0) {
        canvas.drawLine(
          Offset(nape.x, cy + hh * 0.3),
          Offset(nape.x - 2, y.neck + 4),
          Paint()
            ..color = design.accent.withValues(alpha: 0.7)
            ..strokeWidth = 2,
        );
      }
    }

    // 대뇌피질 모듈: 관자놀이(둘레각 -π/2)에 박힌 연산 유닛.
    if (design.has(CyborgImplant.corticalModule)) {
      final temple = view.project(-math.pi / 2, headR * 0.85, headD);
      if (temple.depth > -headR * 0.3) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset(temple.x, cy - hh * 0.05),
              width: design.headWidth * 0.16,
              height: hh * 0.34,
            ),
            const Radius.circular(1.5),
          ),
          dark,
        );
        canvas.drawCircle(Offset(temple.x, cy - hh * 0.05), 1.4, accent);
      }
    }

    // 헬멧 안테나: 왼쪽 관자놀이 위. 대뇌피질 모듈과 같은 기준으로 가려야
    // 뒤통수를 향할 때 헬멧을 관통하지 않는다.
    final ant = view.project(-math.pi / 2, headR * 0.6, headD);
    if (ant.depth > -headR * 0.3) {
      final antennaBase = Offset(ant.x, cy - hh * 0.5);
      // 꺾이는 방향도 앵커를 따라가야 한다. 고정 오프셋이면 어느 각도에서는
      // 안테나가 몸 안쪽으로 접힌다.
      final lean = ant.x >= 0 ? 3.0 : -3.0;
      final antennaTip = Offset(antennaBase.dx + lean, antennaBase.dy - 10);
      canvas.drawLine(
        antennaBase,
        antennaTip,
        Paint()
          ..color = design.accent
          ..strokeWidth = 1.6,
      );
      canvas.drawCircle(antennaTip, 1.8, accent);
    }
  }

  static void _drawPonytail(
    Canvas canvas,
    CyborgDesign design,
    _View view,
    double cy,
    double headR,
    double headD,
    double hh,
  ) {
    // 머리채는 뒤통수(둘레각 π)에 달려 있다. 정면을 보면 머리 뒤로 숨고,
    // 옆·뒤를 보면 길게 드러난다.
    final p = view.project(math.pi, headR * 0.7, headD);
    // 뒤를 향할수록(depth 가 클수록) 길어 보인다.
    final visible = (p.depth / (headR * 0.7)).clamp(-1.0, 1.0);
    final length = hh * (0.85 + 0.6 * ((visible + 1) / 2));
    final spread = design.headWidth * (0.16 + 0.18 * ((visible + 1) / 2));

    // 흘러내리는 방향은 **뒤통수가 있는 쪽**을 따라야 한다. 좌우 어느 쪽으로
    // 휠지를 고정해 두면, 반대편을 보는 각도에서 머리채가 헬멧을 가로질러
    // 얼굴 위로 넘어온다. 뒤통수 x 는 `-halfD·sin(yaw)`이므로 그 부호를 쓴다.
    final lean = -math.sin(view.yaw);
    final tipX = p.x + lean * spread * 1.2;
    final root = spread * 0.35;

    final path = Path()
      ..moveTo(p.x - root, cy - hh * 0.3)
      ..quadraticBezierTo(
        tipX - spread * 0.5,
        cy + length * 0.5,
        tipX,
        cy + length,
      )
      ..quadraticBezierTo(
        tipX + spread * 0.5,
        cy + length * 0.5,
        p.x + root,
        cy - hh * 0.3,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = _deepShade);
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

  /// 등에 멘 에너지 블레이드. 둘레각 π 부근에 비스듬히 걸려 있다.
  static void _drawHolsteredBlade(
    Canvas canvas,
    CyborgDesign design,
    _Levels y,
    _View view,
  ) {
    final p = view.project(
      math.pi * 0.75,
      design.shoulderWidth / 2,
      view.bodyDepth(design),
    );
    // 깊이 부호로 통째로 켜고 끄면 회전 중 한 프레임에 사라져 깜빡인다.
    // 경계에서 서서히 옅어지게 한다.
    final reveal = (p.depth / (design.shoulderWidth * 0.25)).clamp(0.0, 1.0);
    if (reveal <= 0.01) return;
    final top = y.shoulder + design.shoulderPadSize * 0.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(p.x, top, 3, design.totalHeight * 0.24),
        const Radius.circular(1.5),
      ),
      Paint()
        ..color = GamePalette.bladeGlow.withValues(alpha: 0.55 * reveal),
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
    double yaw = 0,
  }) {
    canvas.save();
    canvas.scale(scale);
    final breathe = math.sin(time * 2) * 1.2;
    drawBody(canvas, design: design, yaw: yaw, baseY: -breathe);
    canvas.restore();
  }
}

/// 시선각 하나에 대한 투영 계산을 모아 둔 값.
///
/// 몸통을 타원기둥으로 근사한다. 둘레 위의 점을 매개각 `t`(0 = 정면,
/// π = 등, ±π/2 = 좌우)로 지정하면 [project]가 회전 후의 화면 x 와 깊이를 준다.
class _View {
  _View(CyborgDesign design, double yaw)
      : yaw = yaw,
        _sin = math.sin(yaw),
        _cos = math.cos(yaw);

  /// 캐릭터가 바라보는 방향(라디안). 0이면 카메라를 정면으로 마주 본다.
  final double yaw;
  final double _sin;
  final double _cos;

  /// 정면을 얼마나 마주하고 있는지(0 = 완전 측면, 1 = 정면 또는 후면).
  double get facingAmount => _cos.abs();

  /// 보행 시 앞뒤 움직임이 화면 **가로**로 보이는 정도(-1~1).
  ///
  /// 측면(yaw = ±π/2)에서 최대이고 정면·후면에서 0이다.
  double get strideProjection => _sin;

  /// 보행 시 앞뒤 움직임이 화면 **세로**로 보이는 정도(-1~1).
  ///
  /// 정면에서 앞으로 뻗은 발은 카메라 쪽 = 화면 아래로 내려온다. 이 성분이
  /// 없으면 `strideProjection` 이 0이 되는 정면·후면에서 보폭이 통째로
  /// 사라져 다리가 붙은 채 위아래로만 흔들린다.
  double get strideDepth => _cos;

  /// 측면을 볼수록 커지는 좌우 분리량.
  ///
  /// 좌우 한 쌍인 부위(팔·다리·어깨)는 둘레각이 ±π/2 라 완전 측면에서
  /// 화면 x 가 정확히 같아진다. 그대로 두면 한 짝으로 뭉쳐 보이므로,
  /// 정면에서 0이고 측면에서 최대가 되는 오프셋으로 살짝 벌린다.
  double sideSplit(double amount) => (1 - facingAmount) * amount;

  /// 몸통의 앞뒤 반두께.
  double bodyDepth(CyborgDesign design) =>
      design.chestWidth / 2 * CyborgRenderer._bodyDepthRatio;

  /// 좌우 폭 [width]가 이 시선각에서 화면에 보이는 **반폭**.
  ///
  /// 타원을 돌려 x축에 투영한 폭이라 옆을 볼수록 두께 쪽으로 수렴한다.
  double halfWidth(double width) {
    final a = width / 2;
    final b = a * CyborgRenderer._bodyDepthRatio;
    return math.sqrt(a * a * _cos * _cos + b * b * _sin * _sin);
  }

  /// 머리 폭 배율. 구에 가까워 몸통만큼 납작해지지 않는다.
  double get headWidthScale {
    const d = CyborgRenderer._headDepthRatio;
    return math.sqrt(_cos * _cos + d * d * _sin * _sin);
  }

  /// 몸통 둘레 매개각 [t]의 점을 회전 후 화면 x·깊이로 투영한다.
  ///
  /// [halfW]는 좌우 반폭, [halfD]는 앞뒤 반두께다. 반환된 `depth`가 양수면
  /// 카메라 쪽(보임), 음수면 몸 뒤(가려짐)다.
  ({double x, double depth}) project(double t, double halfW, double halfD) {
    final st = math.sin(t);
    final ct = math.cos(t);
    return (
      x: halfW * st * _cos + halfD * ct * _sin,
      depth: -halfW * st * _sin + halfD * ct * _cos,
    );
  }
}

/// 좌우 한 쌍으로 존재하는 부위(팔·다리·어깨)의 투영 결과.
class _Limb {
  const _Limb({
    required this.x,
    required this.depth,
    required this.phase,
    this.isWeaponArm = false,
  });

  /// 화면 x 좌표.
  final double x;

  /// 카메라 쪽 깊이. 양수면 몸 앞, 음수면 몸 뒤.
  final double depth;

  /// 보행 위상에 따른 흔들림.
  final double phase;

  /// 무기를 든 팔인지.
  final bool isWeaponArm;
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
