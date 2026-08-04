import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../game/entities/cyborg_design.dart';
import '../game/entities/cyborg_renderer.dart';
import '../game/palette.dart';
import 'cyborg_kind.dart';

/// 캐릭터 선택 화면에 세워 두는 사이보그 전신 초상.
///
/// 게임 안 플레이어와 **같은 렌더러**([CyborgRenderer])로 그린다. 선택 화면에서
/// 고른 몸이 곧 게임에서 조종하는 몸이므로, 그림이 두 벌이면 언젠가 어긋난다.
/// 여기서 하는 일은 캔버스를 위젯 크기에 맞추고 정지 포즈로 세우는 것뿐이다.
class CyborgPortrait extends StatefulWidget {
  const CyborgPortrait({
    super.key,
    required this.kind,
    this.selected = true,
    this.animate = true,
  });

  final CyborgKind kind;

  /// 선택 상태. 꺼지면 발밑 발광이 죽고 전체가 옅어진다.
  final bool selected;

  /// 숨쉬기를 재생할지. 목록에 여럿 세울 때는 꺼서 부담을 줄인다.
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
      builder: (context, _) => CustomPaint(
        painter: _PortraitPainter(
          design: widget.kind.design,
          selected: widget.selected,
          time: _controller.value * 3,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _PortraitPainter extends CustomPainter {
  _PortraitPainter({
    required this.design,
    required this.selected,
    required this.time,
  });

  final CyborgDesign design;
  final bool selected;

  /// 초 단위 경과 시간. 숨쉬기 위상에만 쓴다.
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    // 렌더러의 원점은 발밑이고 위로 갈수록 y 가 음수다. 키에 여백을 조금 붙여
    // 안테나와 발밑 발광이 잘리지 않게 한다.
    final height = design.totalHeight * 1.12;
    final width = design.shoulderWidth * 2.0;

    final scale = math.min(size.width / width, size.height / height);

    canvas.save();
    // 가로 가운데, 세로는 발밑이 아래쪽에 오도록 놓는다.
    canvas.translate(size.width / 2, size.height / 2 + height * scale * 0.46);
    canvas.scale(scale);

    _paintGroundGlow(canvas);

    // 선택되지 않은 초상은 숨을 멈춘다. 여러 개가 동시에 들썩이면 시선이 흩어진다.
    final breath = selected ? math.sin(time * 1.9) * 1.1 * design.bobScale : 0.0;

    // 선택 해제 시 전체를 옅게 만든다. 색을 빼면 어느 쪽이 어느 프레임인지
    // 알 수 없으므로, 형태는 남기고 투명도만 낮춘다.
    if (!selected) {
      canvas.saveLayer(
        null,
        Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.45),
      );
    }

    // `time` 을 넘겨야 코어가 맥동한다. 넘기지 않으면 게임 안에서는 뛰는
    // 심장이 선택 화면에서만 멎어 있다. `baseY` 부호도 게임과 같게 —
    // 위로 뜨는 것이 들숨이다(y 는 위로 갈수록 음수).
    CyborgRenderer.drawBody(
      canvas,
      design: design,
      baseY: -breath,
      time: time,
    );

    if (!selected) canvas.restore();
    canvas.restore();
  }

  /// 발밑 원형 발광. 캐릭터가 허공에 뜬 것처럼 보이지 않게 바닥을 만든다.
  void _paintGroundGlow(Canvas canvas) {
    final accent = selected ? design.accent : GamePalette.textDim;
    final width = design.shoulderWidth * 1.45;

    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: width, height: width * 0.3),
      Paint()
        ..color = accent.withValues(alpha: selected ? 0.35 : 0.12)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: width * 0.62,
        height: width * 0.18,
      ),
      Paint()..color = accent.withValues(alpha: selected ? 0.6 : 0.2),
    );
  }

  @override
  bool shouldRepaint(_PortraitPainter old) =>
      old.design != design || old.selected != selected || old.time != time;
}
