import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../entities/cyborg_design.dart';
import '../entities/cyborg_renderer.dart';
import '../palette.dart';

/// 사이보그 프레임을 한 명 그리는 캔버스.
///
/// 게임 월드가 아니라 위젯 트리 위에서 [CyborgRenderer]를 그대로 재사용하므로,
/// 여기서 보이는 실루엣이 실제 인게임 캐릭터와 정확히 일치한다.
class CyborgPreviewPainter extends CustomPainter {
  const CyborgPreviewPainter({
    required this.design,
    required this.time,
    required this.walking,
    required this.showBack,
    required this.scale,
  });

  final CyborgDesign design;

  /// 애니메이션 경과 시간(초).
  final double time;

  /// 보행 애니메이션 재생 여부.
  final bool walking;

  /// 뒷모습을 보여줄지 여부.
  final bool showBack;

  /// 확대 배율.
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    // 캐릭터의 발밑을 캔버스 아래쪽 기준선에 맞춘다.
    final groundY = size.height * 0.86;
    canvas.save();
    canvas.translate(size.width / 2, groundY);
    canvas.scale(scale);

    _drawGroundShadow(canvas);

    final cycle = time * 9;
    final swing = walking ? _sin(cycle) : 0.0;
    final bob = walking
        ? _sin(cycle * 2) * 2.0 * design.bobScale
        : _sin(time * 2) * 1.2;

    CyborgRenderer.drawBody(
      canvas,
      design: design,
      baseY: -bob,
      swing: swing,
      back: showBack,
      armSwing: walking ? -swing * 6 : 0.0,
    );

    canvas.restore();
  }

  /// 인게임과 동일한 타원 그림자.
  void _drawGroundShadow(Canvas canvas) {
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: design.hipWidth * 2.4,
        height: design.hipWidth * 1.1,
      ),
      Paint()
        ..color = GamePalette.shadow.withValues(alpha: 0.42)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
  }

  static double _sin(double v) => math.sin(v);

  @override
  bool shouldRepaint(CyborgPreviewPainter old) =>
      old.time != time ||
      old.design != design ||
      old.walking != walking ||
      old.showBack != showBack ||
      old.scale != scale;
}

/// 한 프레임의 프리뷰 + 사양표를 담은 카드.
class CyborgPreviewCard extends StatelessWidget {
  const CyborgPreviewCard({
    super.key,
    required this.design,
    required this.time,
    required this.walking,
    required this.showBack,
    required this.scale,
  });

  final CyborgDesign design;
  final double time;
  final bool walking;
  final bool showBack;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GamePalette.hudBackground,
        border: Border.all(color: design.accent.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(),
          const SizedBox(height: 4),
          Text(
            design.tagline,
            style: TextStyle(
              color: GamePalette.textDim,
              fontSize: 12,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: CustomPaint(
              size: Size.infinite,
              painter: CyborgPreviewPainter(
                design: design,
                time: time,
                walking: walking,
                showBack: showBack,
                scale: scale,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _silhouetteSpec(),
          const SizedBox(height: 10),
          _implantList(),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: design.accent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(color: design.accent, blurRadius: 8),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          design.codename,
          style: TextStyle(
            color: design.accent,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          design.frame == CyborgFrame.assault ? '남성형' : '여성형',
          style: const TextStyle(
            color: GamePalette.textDim,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  /// 실루엣을 결정하는 핵심 수치.
  Widget _silhouetteSpec() {
    final rows = <(String, String)>[
      ('키', '${design.totalHeight.toStringAsFixed(0)} px'),
      ('어깨', design.shoulderWidth.toStringAsFixed(1)),
      ('가슴', design.chestWidth.toStringAsFixed(1)),
      ('허리', design.waistWidth.toStringAsFixed(1)),
      ('골반', design.hipWidth.toStringAsFixed(1)),
      (
        '실루엣',
        design.hasConcaveWaist ? '오목형 (concave)' : '볼록형 (convex)',
      ),
    ];

    return Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 1.5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: GamePalette.textDim,
                    fontSize: 11,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(
                    color: GamePalette.textPrimary,
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _implantList() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final implant in design.implants)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              border: Border.all(
                color: design.accent.withValues(alpha: 0.35),
              ),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              _implantLabel(implant),
              style: TextStyle(
                color: design.accentSoft,
                fontSize: 10,
              ),
            ),
          ),
      ],
    );
  }

  static String _implantLabel(CyborgImplant implant) => switch (implant) {
        CyborgImplant.sternalFrame => '흉골 프레임',
        CyborgImplant.shoulderActuator => '어깨 구동기',
        CyborgImplant.spinalPowerPack => '척추 동력팩',
        CyborgImplant.spinalLightRail => '척추 발광 레일',
        CyborgImplant.vitalIntake => '생명유지 흡입구',
        CyborgImplant.corticalModule => '대뇌피질 모듈',
        CyborgImplant.legTendon => '인공 힘줄',
      };
}

/// 남성형·여성형 프레임을 나란히 비교하는 화면.
///
/// `player.dart`를 비롯한 게임 본체 코드를 전혀 건드리지 않고,
/// [CyborgDesign] 프로필과 [CyborgRenderer]만으로 동작한다.
class CyborgPreviewPage extends StatefulWidget {
  const CyborgPreviewPage({super.key});

  @override
  State<CyborgPreviewPage> createState() => _CyborgPreviewPageState();
}

class _CyborgPreviewPageState extends State<CyborgPreviewPage>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = Ticker(_onTick);
  double _time = 0;
  bool _walking = true;
  bool _showBack = false;
  double _scale = 2.0;

  @override
  void initState() {
    super.initState();
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    setState(() {
      _time = elapsed.inMicroseconds / 1e6;
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GamePalette.voidColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title(),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  children: [
                    for (var i = 0; i < CyborgDesign.all.length; i++) ...[
                      if (i > 0) const SizedBox(width: 20),
                      Expanded(
                        child: CyborgPreviewCard(
                          design: CyborgDesign.all[i],
                          time: _time,
                          walking: _walking,
                          showBack: _showBack,
                          scale: _scale,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _controls(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _title() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Text(
          'CYBORG FRAME',
          style: TextStyle(
            color: GamePalette.textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: 4,
          ),
        ),
        const SizedBox(width: 12),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            '인간 저항군 신체 프레임 규격',
            style: TextStyle(
              color: GamePalette.hudBorder.withValues(alpha: 0.8),
              fontSize: 12,
              letterSpacing: 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _controls() {
    return Row(
      children: [
        _toggle(
          label: _walking ? '보행 중' : '대기 중',
          active: _walking,
          onTap: () => setState(() => _walking = !_walking),
        ),
        const SizedBox(width: 10),
        _toggle(
          label: _showBack ? '뒷모습' : '정면',
          active: _showBack,
          onTap: () => setState(() => _showBack = !_showBack),
        ),
        const SizedBox(width: 20),
        const Text(
          '배율',
          style: TextStyle(color: GamePalette.textDim, fontSize: 12),
        ),
        Expanded(
          child: Slider(
            value: _scale,
            min: 1.0,
            max: 3.5,
            activeColor: GamePalette.hudBorder,
            onChanged: (v) => setState(() => _scale = v),
          ),
        ),
        Text(
          '${_scale.toStringAsFixed(1)}x',
          style: const TextStyle(
            color: GamePalette.textPrimary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _toggle({
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? GamePalette.hudBorder.withValues(alpha: 0.18)
              : Colors.transparent,
          border: Border.all(
            color: active
                ? GamePalette.hudBorder
                : GamePalette.textDim.withValues(alpha: 0.4),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? GamePalette.hudBorder : GamePalette.textDim,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
