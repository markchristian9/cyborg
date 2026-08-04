import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../entities/iso_entity.dart';

/// 타격 순간 튀는 불꽃 이펙트.
class HitSpark extends IsoEntity {
  HitSpark({
    required Vector2 grid,
    required this.color,
    double z = 0.5,
    this.count = 8,
    this.spread = 34,
  }) : super(grid: grid, z: z, depthBias: 3) {
    final random = math.Random();
    for (var i = 0; i < count; i++) {
      final angle = random.nextDouble() * math.pi * 2;
      final speed = spread * (0.5 + random.nextDouble());
      _particles.add(
        _Spark(
          Offset(math.cos(angle), math.sin(angle) * 0.6) * speed,
          1.5 + random.nextDouble() * 2.5,
        ),
      );
    }
  }

  final Color color;
  final int count;
  final double spread;
  final List<_Spark> _particles = [];

  double _life = 0;
  static const double _duration = 0.3;

  @override
  void update(double dt) {
    _life += dt;
    if (_life >= _duration) {
      removeFromParent();
      return;
    }
    super.update(dt);
  }

  @override
  void render(Canvas canvas) {
    final t = (_life / _duration).clamp(0.0, 1.0);
    final fade = 1 - t;

    // 중심 섬광
    canvas.drawCircle(
      Offset.zero,
      16 * (1 - t) + 4,
      Paint()
        ..color = color.withValues(alpha: 0.55 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..color = color.withValues(alpha: fade);

    for (final spark in _particles) {
      final from = spark.velocity * (t * 0.6);
      final to = spark.velocity * t;
      paint.strokeWidth = spark.width * fade;
      canvas.drawLine(from, to, paint);
    }
  }
}

class _Spark {
  _Spark(this.velocity, this.width);

  final Offset velocity;
  final double width;
}
