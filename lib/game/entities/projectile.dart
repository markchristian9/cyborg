import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../audio/game_audio.dart';
import '../fx/hit_spark.dart';
import '../iso.dart';
import '../palette.dart';
import 'iso_entity.dart';

/// 발사체를 쏜 진영.
enum ProjectileOwner { player, enemy }

/// 직선으로 날아가는 에너지 발사체.
class Projectile extends IsoEntity {
  Projectile({
    required Vector2 grid,
    required Vector2 direction,
    required this.speed,
    required this.damage,
    required this.owner,
    double z = 0.6,
    this.maxLifetime = 2.2,
    this.radius = 0.18,
    this.homing = 0,
  })  : direction = direction.normalized(),
        super(grid: grid, z: z, bodyRadius: 0.18, depthBias: 0.5);

  final Vector2 direction;
  final double speed;
  final double damage;
  final ProjectileOwner owner;
  final double maxLifetime;
  final double radius;

  /// 0보다 크면 플레이어 방향으로 서서히 유도된다(초당 회전 강도).
  final double homing;

  double _life = 0;
  final List<Vector2> _trail = [];

  Color get _color => owner == ProjectileOwner.player
      ? GamePalette.playerAccent
      : GamePalette.robotEnergy;

  @override
  void update(double dt) {
    _life += dt;
    if (_life > maxLifetime) {
      removeFromParent();
      return;
    }

    if (homing > 0 && game.player.isAlive) {
      final toPlayer = (game.player.grid - grid);
      if (toPlayer.length2 > 0.01) {
        toPlayer.normalize();
        direction
          ..lerp(toPlayer, (homing * dt).clamp(0.0, 1.0))
          ..normalize();
      }
    }

    _trail.insert(0, grid.clone());
    if (_trail.length > 6) _trail.removeLast();

    grid.add(direction * speed * dt);

    // 안전지대의 보호막은 적의 탄을 통과시키지 않는다.
    if (owner == ProjectileOwner.enemy &&
        game.map.safeZone.containsPoint(grid)) {
      _burst();
      return;
    }

    // 벽 충돌
    if (!game.map.isWalkableAt(grid.x, grid.y)) {
      _burst();
      return;
    }

    // 대상 충돌
    final targets = owner == ProjectileOwner.player
        ? game.projectileTargetsForPlayer()
        : <Damageable>[game.player];
    for (final target in targets) {
      if (!target.isAlive) continue;
      final distance = (target.grid - grid).length;
      if (distance <= radius + target.bodyRadius) {
        // 서버가 판정하는 대상에게는 피해를 넣지 않는다. **이 발사체는 이미
        // 판정이 끝난 스킬의 연출**이다 — 쏘는 순간 서버가 마력·사거리·피해를
        // 정했고, 여기서 또 때렸다고 알리면 한 발에 두 번의 요청이 나간다.
        // 그 두 번째 요청은 근접 공격으로 취급되어(사거리 2.2 타일) 대부분
        // 거절되지만, 통과하면 쿨다운을 잡아먹어 다음 평타가 막힌다.
        if (!target.isServerJudged) {
          target.applyDamage(
            damage,
            knockback:
                direction * (owner == ProjectileOwner.player ? 1.4 : 2.2),
          );
        }
        _burst();
        return;
      }
    }

    super.update(dt);
  }

  void _burst() {
    game.spawnEffect(
      HitSpark(grid: grid.clone(), z: z, color: _color, count: 6, spread: 26),
    );
    GameAudio.play(Sfx.boltImpact, at: grid);
    removeFromParent();
  }

  @override
  void render(Canvas canvas) {
    final color = _color;

    // 잔상
    for (var i = 0; i < _trail.length; i++) {
      final offset = gridToScreen(_trail[i].x, _trail[i].y, z) -
          gridToScreen(grid.x, grid.y, z);
      final fade = (1 - i / _trail.length) * 0.5;
      canvas.drawCircle(
        offset.toOffset(),
        7.0 * (1 - i / _trail.length) + 1,
        Paint()
          ..color = color.withValues(alpha: fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
    }

    // 코어
    canvas.drawCircle(
      Offset.zero,
      11,
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );

    // 진행 방향으로 늘어난 탄체
    final screenDir = gridDirToScreenDir(direction)..normalize();
    canvas.save();
    canvas.rotate(math.atan2(screenDir.y, screenDir.x));
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 18, height: 6),
      Paint()..color = color,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset.zero, width: 9, height: 3),
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    canvas.restore();
  }
}
