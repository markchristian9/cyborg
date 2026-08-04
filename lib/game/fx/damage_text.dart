import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../entities/iso_entity.dart';

/// 피해량이 떠오르며 사라지는 텍스트 이펙트.
class DamageText extends IsoEntity {
  DamageText({
    required Vector2 grid,
    required this.amount,
    required this.color,
    this.prefix = '',
    this.critical = false,
    double z = 0.8,
  }) : super(grid: grid, z: z, depthBias: 4);

  final double amount;
  final Color color;
  final String prefix;
  final bool critical;

  double _life = 0;
  static const double _duration = 0.85;
  late final double _drift = (math.Random().nextDouble() - 0.5) * 26;

  late final TextPainter _painter = TextPainter(
    text: TextSpan(
      text: '$prefix${amount.round()}',
      style: TextStyle(
        color: color,
        fontSize: critical ? 26 : 19,
        fontWeight: FontWeight.w900,
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
    z += dt * 1.1;
    if (_life >= _duration) {
      removeFromParent();
      return;
    }
    super.update(dt);
  }

  @override
  void render(Canvas canvas) {
    final t = (_life / _duration).clamp(0.0, 1.0);
    final opacity = t < 0.7 ? 1.0 : 1 - (t - 0.7) / 0.3;
    final scale = critical ? 1.0 + math.sin(t * math.pi) * 0.25 : 1.0;

    canvas.save();
    canvas.translate(_drift * t, 0);
    canvas.scale(scale);
    canvas.saveLayer(
      Rect.fromLTWH(-60, -40, 120, 60),
      Paint()..color = Colors.white.withValues(alpha: opacity.clamp(0.0, 1.0)),
    );
    _painter.paint(canvas, Offset(-_painter.width / 2, -_painter.height));
    canvas.restore();
    canvas.restore();
  }
}
