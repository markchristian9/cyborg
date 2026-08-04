import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../entities/iso_entity.dart';
import '../palette.dart';

/// 로봇이 파괴될 때의 폭발 이펙트.
///
/// 충격파 링, 화염 코어, 흩어지는 파편으로 구성된다.
class Explosion extends IsoEntity {
  Explosion({
    required Vector2 grid,
    double z = 0.5,
    this.blastScale = 1.0,
    this.tint = GamePalette.robotEnergy,
  }) : super(grid: grid, z: z, depthBias: 3) {
    final random = math.Random();
    final shardCount = (7 * blastScale).round().clamp(5, 18);
    for (var i = 0; i < shardCount; i++) {
      final angle = random.nextDouble() * math.pi * 2;
      final speed = (30 + random.nextDouble() * 60) * blastScale;
      _shards.add(
        _Shard(
          velocity: Offset(math.cos(angle), math.sin(angle) * 0.55) * speed,
          lift: 40 + random.nextDouble() * 70,
          size: (2 + random.nextDouble() * 4) * blastScale,
          spin: (random.nextDouble() - 0.5) * 14,
        ),
      );
    }
  }

  final double blastScale;
  final Color tint;
  final List<_Shard> _shards = [];

  double _life = 0;
  static const double _duration = 0.65;

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

    // 충격파 링(아이소메트릭이므로 세로로 눌린 타원)
    final ringRadius = 20 + 68 * t * blastScale;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: ringRadius * 2,
        height: ringRadius,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * fade
        ..color = tint.withValues(alpha: 0.5 * fade),
    );

    // 화염 코어
    if (t < 0.5) {
      final coreT = t / 0.5;
      canvas.drawCircle(
        Offset(0, -14 * blastScale),
        (26 * blastScale) * (0.4 + coreT * 0.9),
        Paint()
          ..color = Color.lerp(
            GamePalette.hitSpark,
            tint,
            coreT,
          )!.withValues(alpha: 0.85 * (1 - coreT))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 12 * blastScale),
      );
    }

    // 파편
    final shardPaint = Paint()..color = GamePalette.robotShellLight;
    for (final shard in _shards) {
      final pos = shard.velocity * t;
      // 위로 튀었다가 중력으로 떨어진다.
      final y = pos.dy - shard.lift * (t - t * t * 2.2);
      canvas.save();
      canvas.translate(pos.dx, y - 14);
      canvas.rotate(shard.spin * t);
      shardPaint.color =
          GamePalette.robotShellLight.withValues(alpha: fade.clamp(0.0, 1.0));
      canvas.drawRect(
        Rect.fromCenter(
          center: Offset.zero,
          width: shard.size,
          height: shard.size * 0.7,
        ),
        shardPaint,
      );
      canvas.restore();
    }
  }
}

class _Shard {
  _Shard({
    required this.velocity,
    required this.lift,
    required this.size,
    required this.spin,
  });

  final Offset velocity;
  final double lift;
  final double size;
  final double spin;
}
