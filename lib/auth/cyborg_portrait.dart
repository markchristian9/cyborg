import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/palette.dart';
import 'cyborg_kind.dart';

/// 캐릭터 선택 화면에 세워 두는 사이보그 전신 초상.
///
/// 게임 안 [Player] 와 **같은 조형 언어**로 그린다 — 같은 비율, 같은 팔레트,
/// 같은 부위 구성(사다리꼴 흉갑·어깨 패드·바이저·안테나·에너지 블레이드).
/// 스프라이트를 따로 만들지 않았으므로 여기서 도형을 직접 그린다.
///
/// 게임의 `Player` 컴포넌트를 그대로 쓰지 않는 이유는 그쪽이 Flame 의
/// 컴포넌트 수명과 전투 상태(`state`·`_animTime`·대시 잔상)에 묶여 있기
/// 때문이다. 선택 화면에 필요한 것은 정지 포즈 하나뿐이라, 그 의존성을 끌고
/// 오는 대신 같은 형태를 위젯 쪽에 옮겨 그린다.
class CyborgPortrait extends StatefulWidget {
  const CyborgPortrait({
    super.key,
    required this.kind,
    this.selected = true,
    this.animate = true,
  });

  final CyborgKind kind;

  /// 선택 상태. 꺼지면 발광이 죽고 전체가 어두워진다.
  final bool selected;

  /// 숨쉬기와 코어 맥동을 재생할지. 목록에 여럿 세울 때는 꺼서 부담을 줄인다.
  final bool animate;

  @override
  State<CyborgPortrait> createState() => _CyborgPortraitState();
}

class _CyborgPortraitState extends State<CyborgPortrait>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(CyborgPortrait oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _CyborgPainter(
            kind: widget.kind,
            selected: widget.selected,
            time: _controller.value * 3,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class _CyborgPainter extends CustomPainter {
  _CyborgPainter({
    required this.kind,
    required this.selected,
    required this.time,
  });

  final CyborgKind kind;
  final bool selected;

  /// 초 단위 경과 시간. 숨쉬기와 맥동의 위상에만 쓴다.
  final double time;

  /// 그림이 차지하는 논리 영역. 게임 안 플레이어와 같은 축척이다
  /// (발밑이 y = 0, 머리 끝이 y = -112).
  static const Rect _bounds = Rect.fromLTRB(-26, -118, 26, 6);

  @override
  void paint(Canvas canvas, Size size) {
    // 논리 좌표를 위젯 크기에 맞춘다. 가로세로 중 빡빡한 쪽을 기준으로 잡아
    // 어떤 칸 모양에서도 잘리지 않게 한다.
    final scale = math.min(
      size.width / _bounds.width,
      size.height / _bounds.height,
    );

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(0, -_bounds.center.dy);

    _paintGroundGlow(canvas);
    _paintBody(canvas);

    canvas.restore();
  }

  /// 발밑 원형 발광. 캐릭터가 공중에 뜬 것처럼 보이지 않게 바닥을 만들어 준다.
  void _paintGroundGlow(Canvas canvas) {
    final accent = selected ? kind.accent : GamePalette.textDim;

    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 2), width: 46, height: 13),
      Paint()
        ..color = accent.withValues(alpha: selected ? 0.30 : 0.10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(0, 2), width: 30, height: 8),
      Paint()..color = accent.withValues(alpha: selected ? 0.55 : 0.18),
    );
  }

  void _paintBody(Canvas canvas) {
    final heavy = kind.isHeavy;

    // 숨쉬기. 선택되지 않은 초상은 정지시켜 시선을 뺏지 않는다.
    final breath = selected ? math.sin(time * 1.9) * 1.1 : 0.0;
    final baseY = -breath;

    // 선택 해제된 초상은 채도를 낮춘다. 색을 완전히 지우면 어느 쪽이 어느
    // 캐릭터인지 알 수 없으므로 어둡게만 만든다.
    Color dim(Color color) => selected
        ? color
        : Color.lerp(color, GamePalette.voidColor, 0.55)!;

    final accentColor = dim(kind.accent);
    final armor = Paint()..color = dim(GamePalette.playerArmor);
    final armorLight = Paint()..color = dim(GamePalette.playerArmorLight);
    final accent = Paint()..color = accentColor;
    final dark = Paint()..color = dim(const Color(0xFF161C25));

    // 체형 파라미터. 이 세 값이 남녀 실루엣 차이를 만든다.
    final shoulderWidth = heavy ? 16.0 : 12.5;
    final waistWidth = heavy ? 9.0 : 6.5;
    final legOffset = heavy ? 7.0 : 5.5;
    final legWidth = heavy ? 4.0 : 3.2;

    // ── 다리 ──
    for (var i = 0; i < 2; i++) {
      final legX = i == 0 ? -legOffset : legOffset;
      final path = Path()
        ..moveTo(legX - legWidth, baseY - 42)
        ..lineTo(legX + legWidth, baseY - 42)
        ..lineTo(legX + legWidth, baseY - 4)
        ..lineTo(legX - legWidth, baseY - 4)
        ..close();
      canvas.drawPath(path, i == 0 ? armor : dark);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(legX - legWidth - 2, baseY - 8, legWidth * 2 + 4, 7),
          const Radius.circular(2),
        ),
        dark,
      );
    }

    // ── 몸통 ──
    // 남성은 어깨에서 허리로 곧게 좁아지고, 여성은 허리를 한 번 더 조인다.
    final torso = Path()..moveTo(-shoulderWidth + 5, baseY - 74);
    if (heavy) {
      torso
        ..lineTo(shoulderWidth - 5, baseY - 74)
        ..lineTo(waistWidth, baseY - 40)
        ..lineTo(-waistWidth, baseY - 40);
    } else {
      torso
        ..lineTo(shoulderWidth - 5, baseY - 74)
        ..quadraticBezierTo(
          waistWidth - 1.5,
          baseY - 58,
          waistWidth,
          baseY - 40,
        )
        ..lineTo(-waistWidth, baseY - 40)
        ..quadraticBezierTo(
          -waistWidth + 1.5,
          baseY - 58,
          -shoulderWidth + 5,
          baseY - 74,
        );
    }
    torso.close();
    canvas.drawPath(torso, armor);

    // 흉갑 하이라이트
    final chest = Path()
      ..moveTo(-8, baseY - 72)
      ..lineTo(2, baseY - 72)
      ..lineTo(0, baseY - 52)
      ..lineTo(-7, baseY - 52)
      ..close();
    canvas.drawPath(chest, armorLight);

    // 가슴 에너지 코어. 맥동은 캐릭터가 "켜져 있다"는 유일한 신호다.
    final pulse = selected ? 0.75 + math.sin(time * 3.4) * 0.25 : 0.35;
    canvas.drawCircle(
      Offset(0, baseY - 60),
      4.5 + pulse,
      Paint()
        ..color = accentColor.withValues(alpha: 0.75 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawCircle(Offset(0, baseY - 60), 2.6, accent);

    // ── 어깨 패드 ──
    final padWidth = heavy ? 11.0 : 8.5;
    final padHeight = heavy ? 12.0 : 9.5;
    for (final side in [-1, 1]) {
      final left = side < 0 ? -shoulderWidth : shoulderWidth - padWidth;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, baseY - 76, padWidth, padHeight),
          const Radius.circular(4),
        ),
        armorLight,
      );
    }

    // ── 팔 ──
    final armWidth = heavy ? 7.0 : 5.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-shoulderWidth - 1, baseY - 66, armWidth, 22),
        const Radius.circular(3),
      ),
      armor,
    );
    final weaponArm = Path()
      ..moveTo(shoulderWidth - 5, baseY - 66)
      ..lineTo(shoulderWidth + 2, baseY - 62)
      ..lineTo(shoulderWidth + 2, baseY - 50)
      ..lineTo(shoulderWidth - 5, baseY - 48)
      ..close();
    canvas.drawPath(weaponArm, armorLight);

    // ── 목 ──
    canvas.drawRect(Rect.fromLTWH(-3, baseY - 80, 6, 7), dark);

    // ── 머리(헬멧) ──
    final headWidth = heavy ? 21.0 : 19.0;
    final headCenter = Offset(0.5, baseY - 88);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromCenter(center: headCenter, width: headWidth, height: 19),
        topLeft: const Radius.circular(8),
        topRight: const Radius.circular(8),
        bottomLeft: const Radius.circular(4),
        bottomRight: const Radius.circular(4),
      ),
      armorLight,
    );

    // 여성 쪽에만 뒤로 흐르는 냉각 케이블 다발을 얹는다. 실루엣만으로 두 캐릭터를
    // 구분할 수 있게 하는 장치다.
    if (!heavy) {
      for (var i = 0; i < 3; i++) {
        final drop = 14.0 + i * 5;
        final sway = math.sin(time * 1.4 + i) * (selected ? 1.6 : 0);
        canvas.drawPath(
          Path()
            ..moveTo(-8, baseY - 92 + i * 2)
            ..quadraticBezierTo(
              -15 - i * 1.5 + sway,
              baseY - 92 + drop * 0.5,
              -11 - i + sway,
              baseY - 92 + drop,
            ),
          Paint()
            ..color = accentColor.withValues(alpha: 0.55 - i * 0.12)
            ..strokeWidth = 2.2
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke,
        );
      }
    }

    // 바이저
    final visorRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(-2, baseY - 92, heavy ? 12 : 11, heavy ? 6 : 5),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      visorRect,
      Paint()
        ..color = dim(kind.visor)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawRRect(visorRect, Paint()..color = dim(kind.visor));

    // 턱 라인
    canvas.drawRect(
      Rect.fromLTWH(-3, baseY - 84, 9, 3),
      Paint()..color = dim(GamePalette.playerSkin),
    );

    // 헬멧 안테나
    canvas.drawLine(
      Offset(-6, baseY - 96),
      Offset(-9, baseY - 106),
      Paint()
        ..color = accentColor
        ..strokeWidth = 1.6,
    );
    canvas.drawCircle(Offset(-9, baseY - 107), 1.8, accent);

    // 손에 든 에너지 블레이드
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(shoulderWidth + 1, baseY - 58, 3, 26),
        const Radius.circular(1.5),
      ),
      Paint()
        ..color = dim(GamePalette.bladeGlow)
            .withValues(alpha: selected ? 0.75 : 0.35),
    );
  }

  @override
  bool shouldRepaint(_CyborgPainter old) =>
      old.kind != kind || old.selected != selected || old.time != time;
}
