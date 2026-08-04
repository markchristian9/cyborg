import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../entities/iso_entity.dart';

/// 전리품을 회수했을 때 떠오르는 라벨(`+22 HP` 등).
///
/// 숫자만 다루는 `DamageText`와 달리 단위가 붙은 임의의 문자열을 띄운다.
class LootText extends IsoEntity {
  LootText({
    required super.grid,
    required this.text,
    required this.color,
    this.emphasized = false,
    super.z = 1.1,
  }) : super(depthBias: 4);

  final String text;
  final Color color;

  /// 희귀 전리품이면 크게 튀어오르며 강조된다.
  final bool emphasized;

  double _life = 0;
  static const double _duration = 1.0;

  /// 같은 순간에 여러 개가 겹치지 않도록 가로로 조금씩 흩뜨린다.
  late final double _drift = (math.Random().nextDouble() - 0.5) * 30;

  late final TextPainter _painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: emphasized ? 20 : 16,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
        height: 1,
        shadows: const [
          Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 1)),
        ],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  void update(double dt) {
    _life += dt;
    if (_life >= _duration) {
      removeFromParent();
      return;
    }
    // 처음엔 빠르게, 끝으로 갈수록 천천히 떠오른다.
    z += dt * (1.4 - _life * 0.8).clamp(0.3, 1.4);
    super.update(dt);
  }

  @override
  void render(Canvas canvas) {
    final t = (_life / _duration).clamp(0.0, 1.0);
    final opacity = t < 0.65 ? 1.0 : 1 - (t - 0.65) / 0.35;
    final scale = emphasized ? 1 + math.sin(t * math.pi) * 0.2 : 1.0;

    canvas.save();
    canvas.translate(_drift * t, 0);
    canvas.scale(scale);
    canvas.saveLayer(
      Rect.fromLTWH(-80, -44, 160, 64),
      Paint()..color = Colors.white.withValues(alpha: opacity.clamp(0.0, 1.0)),
    );
    _painter.paint(canvas, Offset(-_painter.width / 2, -_painter.height));
    canvas.restore();
    canvas.restore();
  }
}
