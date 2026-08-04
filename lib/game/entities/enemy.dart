import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../audio/game_audio.dart';
import '../fx/damage_text.dart';
import '../fx/explosion.dart';
import '../iso.dart';
import '../palette.dart';
import '../systems/level_system.dart';
import '../systems/monster_population.dart';
import 'iso_entity.dart';
import 'projectile.dart';

/// AI 로봇 유닛의 종류.
enum EnemyKind {
  /// 정찰 드론. 빠르고 약하며 공중에 떠 있다.
  scout,

  /// 순찰 보행 로봇. 근접 강타를 사용한다.
  sentry,

  /// 중장갑 메크. 느리지만 원거리 플라즈마를 연사한다.
  heavy,

  /// 구역 지휘 유닛. 웨이브 보스.
  commander,
}

/// AI의 행동 단계.
enum EnemyPhase { idle, chase, telegraph, strike, recover, dead }

/// 몬스터 어그로 범위의 하한(미터).
const double kAggroMinMeters = 1.0;

/// 몬스터 어그로 범위의 상한(미터).
const double kAggroMaxMeters = 5.0;

/// 추격을 포기하기까지 어그로 범위에 더해 주는 여유(미터).
///
/// 어그로 경계에서 추격/배회 상태가 매 프레임 뒤집히는 것을 막는다.
const double kAggroReleaseMargin = 2.5;

/// 종류별 기본 스탯 표.
class EnemyStats {
  const EnemyStats({
    required this.maxHp,
    required this.speed,
    required this.damage,
    required this.attackRange,
    required this.aggroMinMeters,
    required this.aggroMaxMeters,
    required this.telegraphTime,
    required this.strikeTime,
    required this.recoverTime,
    required this.xp,
    required this.bodyRadius,
    required this.hoverHeight,
    required this.ranged,
    this.scale = 1.0,
  });

  final double maxHp;
  final double speed;
  final double damage;
  final double attackRange;

  /// 개체별 어그로 범위를 뽑을 구간의 하한(미터).
  ///
  /// 종류마다 감지 성능이 다르지만, 모든 값은
  /// [kAggroMinMeters]~[kAggroMaxMeters] 안에 들어간다.
  final double aggroMinMeters;

  /// 개체별 어그로 범위를 뽑을 구간의 상한(미터).
  final double aggroMaxMeters;

  final double telegraphTime;
  final double strikeTime;
  final double recoverTime;
  final int xp;
  final double bodyRadius;
  final double hoverHeight;
  final bool ranged;
  final double scale;

  static const Map<EnemyKind, EnemyStats> table = {
    EnemyKind.scout: EnemyStats(
      maxHp: 34,
      speed: 3.1,
      damage: 8,
      attackRange: 1.0,
      // 센서 특화 정찰기. 가장 멀리서 반응한다.
      aggroMinMeters: 4.0,
      aggroMaxMeters: 5.0,
      telegraphTime: 0.32,
      strikeTime: 0.12,
      recoverTime: 0.5,
      xp: 12,
      bodyRadius: 0.28,
      hoverHeight: 0.85,
      ranged: false,
    ),
    EnemyKind.sentry: EnemyStats(
      maxHp: 70,
      speed: 2.2,
      damage: 15,
      attackRange: 1.25,
      // 둔한 순찰기. 코앞까지 와야 알아챈다.
      aggroMinMeters: 1.0,
      aggroMaxMeters: 2.5,
      telegraphTime: 0.5,
      strikeTime: 0.16,
      recoverTime: 0.7,
      xp: 22,
      bodyRadius: 0.34,
      hoverHeight: 0,
      ranged: false,
    ),
    EnemyKind.heavy: EnemyStats(
      maxHp: 150,
      speed: 1.35,
      damage: 14,
      attackRange: 7.5,
      // 사거리는 길지만 탐지는 중간이다.
      aggroMinMeters: 2.5,
      aggroMaxMeters: 4.0,
      telegraphTime: 0.7,
      strikeTime: 0.45,
      recoverTime: 1.1,
      xp: 45,
      bodyRadius: 0.46,
      hoverHeight: 0,
      ranged: true,
      scale: 1.25,
    ),
    EnemyKind.commander: EnemyStats(
      maxHp: 620,
      speed: 1.6,
      damage: 22,
      attackRange: 9.0,
      // 지휘 유닛은 상한까지 예민하다.
      aggroMinMeters: 4.5,
      aggroMaxMeters: 5.0,
      telegraphTime: 0.75,
      strikeTime: 0.6,
      recoverTime: 1.0,
      xp: 260,
      bodyRadius: 0.72,
      hoverHeight: 0,
      ranged: true,
      scale: 1.9,
    ),
  };
}

/// AI 로봇 적 유닛.
class Enemy extends IsoEntity with Damageable {
  Enemy({
    required this.kind,
    required Vector2 grid,
    double hpMultiplier = 1.0,
    double damageMultiplier = 1.0,
  })  : stats = EnemyStats.table[kind]!,
        _hpScale = hpMultiplier,
        _damageScale = damageMultiplier,
        super(
          grid: grid,
          bodyRadius: EnemyStats.table[kind]!.bodyRadius,
          z: EnemyStats.table[kind]!.hoverHeight,
        ) {
    _maxHp = stats.maxHp * _hpScale;
    _hp = _maxHp;
  }

  final EnemyKind kind;
  final EnemyStats stats;
  final double _hpScale;
  final double _damageScale;

  /// 월드에 상주하는 개체라면 그 장부([MonsterSeed]).
  ///
  /// 웨이브로 투입된 추적대는 상주 개체가 아니므로 null이다.
  MonsterSeed? seed;

  late final double _maxHp;
  late double _hp;

  @override
  double get hp => _hp;

  @override
  double get maxHp => _maxHp;

  EnemyPhase phase = EnemyPhase.idle;

  final Vector2 facing = Vector2(1, 1)..normalize();
  final Vector2 _knockback = Vector2.zero();
  final Vector2 _wanderTarget = Vector2.zero();

  double _animTime = 0;
  double _phaseTimer = 0;
  double _hitFlash = 0;
  double _healthBarTimer = 0;
  double _wanderTimer = 0;
  int _burstShotsLeft = 0;
  double _burstTimer = 0;

  static final math.Random _rng = math.Random();
  late final double _phaseOffset = _rng.nextDouble() * math.pi * 2;

  /// 이 개체가 플레이어를 알아채는 거리(타일 = 미터).
  ///
  /// 같은 종류라도 개체마다 다르며, 값은 언제나
  /// [kAggroMinMeters]~[kAggroMaxMeters] 사이에 놓인다.
  late final double aggroRange = _rollAggroRange();

  double _rollAggroRange() {
    final span = stats.aggroMaxMeters - stats.aggroMinMeters;
    final meters = stats.aggroMinMeters + _rng.nextDouble() * span;
    return metersToTiles(meters.clamp(kAggroMinMeters, kAggroMaxMeters));
  }

  /// 추격을 포기하는 거리. 어그로 경계에서 상태가 떨리지 않도록 여유를 둔다.
  double get _releaseRange => aggroRange + metersToTiles(kAggroReleaseMargin);

  /// 지금 플레이어를 노릴 수 있는지 여부.
  ///
  /// 안전지대 안으로 들어간 플레이어에게는 손을 댈 수 없다.
  bool get _canTargetPlayer {
    final player = game.player;
    return player.isAlive && !game.map.safeZone.containsPoint(player.grid);
  }

  bool get isBoss => kind == EnemyKind.commander;

  @override
  void onMount() {
    super.onMount();
    // 스폰 지점이 안전지대와 겹치면 경계 바깥으로 밀어낸다.
    final zone = game.map.safeZone;
    if (zone.overlapsBody(grid.x, grid.y, bodyRadius)) {
      final outside = zone.pushOutside(grid, margin: bodyRadius + 0.2);
      grid.setFrom(game.map.nearestWalkable(outside));
      // 옮긴 좌표를 첫 프레임부터 반영한다.
      syncTransform();
    }
    _wanderTarget.setFrom(grid);
  }

  @override
  void update(double dt) {
    _animTime += dt;
    if (_hitFlash > 0) _hitFlash = math.max(0, _hitFlash - dt * 3.5);
    if (_healthBarTimer > 0) _healthBarTimer -= dt;

    if (!isAlive) {
      super.update(dt);
      return;
    }

    _updateAi(dt);
    _applyKnockback(dt);
    super.update(dt);
  }

  void _updateAi(double dt) {
    final player = game.player;
    final toPlayer = player.grid - grid;
    final distance = toPlayer.length;

    if (_phaseTimer > 0) _phaseTimer -= dt;

    switch (phase) {
      case EnemyPhase.idle:
        _wander(dt);
        if (_canTargetPlayer && distance <= aggroRange) {
          phase = EnemyPhase.chase;
          // 플레이어를 포착한 순간의 센서 경보음.
          GameAudio.play(Sfx.robotAlert, at: grid);
        }
      case EnemyPhase.chase:
        // 어그로가 풀리는 조건: 대상 사망, 안전지대 진입, 추격 한계 이탈.
        if (!_canTargetPlayer || distance > _releaseRange) {
          phase = EnemyPhase.idle;
          return;
        }
        if (distance > 0.01) facing.setFrom(toPlayer.normalized());
        if (distance <= stats.attackRange) {
          phase = EnemyPhase.telegraph;
          _phaseTimer = stats.telegraphTime;
          _burstShotsLeft = _burstCount;
          // 공격 예비 동작을 소리로도 알려 회피할 틈을 준다.
          GameAudio.play(Sfx.robotCharge, at: grid);
        } else {
          _moveToward(toPlayer.normalized(), stats.speed, dt);
        }
      case EnemyPhase.telegraph:
        // 예비 동작 중에 대상이 안전지대로 피하면 공격을 거둔다.
        if (!_canTargetPlayer) {
          phase = EnemyPhase.idle;
          return;
        }
        if (distance > 0.01) {
          facing.lerp(toPlayer.normalized(), (dt * 4).clamp(0.0, 1.0));
          facing.normalize();
        }
        if (_phaseTimer <= 0) {
          phase = EnemyPhase.strike;
          _phaseTimer = stats.strikeTime;
          _burstTimer = 0;
          if (!stats.ranged) _resolveMeleeStrike();
        }
      case EnemyPhase.strike:
        if (stats.ranged) {
          _burstTimer -= dt;
          if (_burstTimer <= 0 && _burstShotsLeft > 0) {
            _fire();
            _burstShotsLeft--;
            _burstTimer = 0.16;
          }
        }
        if (_phaseTimer <= 0) {
          phase = EnemyPhase.recover;
          _phaseTimer = stats.recoverTime;
        }
      case EnemyPhase.recover:
        if (_phaseTimer <= 0) {
          phase = EnemyPhase.chase;
        }
      case EnemyPhase.dead:
        break;
    }
  }

  int get _burstCount => switch (kind) {
        EnemyKind.heavy => 3,
        EnemyKind.commander => 5,
        _ => 1,
      };

  void _wander(double dt) {
    _wanderTimer -= dt;
    if (_wanderTimer <= 0) {
      _wanderTimer = 1.5 + _rng.nextDouble() * 2.5;
      final angle = _rng.nextDouble() * math.pi * 2;
      final radius = 1.5 + _rng.nextDouble() * 3;
      final target = Vector2(
        grid.x + math.cos(angle) * radius,
        grid.y + math.sin(angle) * radius,
      );
      // 배회 목표가 안전지대를 파고들지 않도록 경계 밖으로 되민다.
      _wanderTarget.setFrom(
        game.map.safeZone.pushOutside(target, margin: bodyRadius + 0.2),
      );
    }
    final toTarget = _wanderTarget - grid;
    if (toTarget.length2 < 0.05) return;
    final dir = toTarget.normalized();
    facing.setFrom(dir);
    _moveToward(dir, stats.speed * 0.4, dt);
  }

  /// 벽을 피하고 다른 적과 겹치지 않도록 이동한다.
  void _moveToward(Vector2 dir, double speed, double dt) {
    final steer = dir.clone();

    // 주변 유닛과의 분리(separation) 스티어링.
    final separation = Vector2.zero();
    for (final other in game.enemies) {
      if (identical(other, this) || !other.isAlive) continue;
      final away = grid - other.grid;
      final distance = away.length;
      final minDistance = bodyRadius + other.bodyRadius + 0.12;
      if (distance > 0.001 && distance < minDistance) {
        separation.add(away.normalized() * ((minDistance - distance) / minDistance));
      }
    }
    if (separation.length2 > 0.0001) {
      steer.add(separation * 1.6);
    }
    if (steer.length2 < 0.0001) return;
    steer.normalize();

    final delta = steer * speed * dt;
    _slideMove(delta);
  }

  void _slideMove(Vector2 delta) {
    final map = game.map;
    final zone = map.safeZone;
    final r = bodyRadius;

    bool free(double gx, double gy) {
      // 안전지대는 적에게 닫혀 있다. 몸통이 경계에 걸치는 것도 막는다.
      // 넉백도 이 경로를 지나므로 밀려서 들어가는 일 역시 없다.
      if (zone.overlapsBody(gx, gy, r)) return false;
      return map.isWalkableAt(gx - r, gy - r) &&
          map.isWalkableAt(gx + r, gy - r) &&
          map.isWalkableAt(gx - r, gy + r) &&
          map.isWalkableAt(gx + r, gy + r);
    }

    if (delta.x != 0 && free(grid.x + delta.x, grid.y)) grid.x += delta.x;
    if (delta.y != 0 && free(grid.x, grid.y + delta.y)) grid.y += delta.y;
  }

  void _applyKnockback(double dt) {
    if (_knockback.length2 < 0.0001) return;
    _slideMove(_knockback * dt);
    _knockback.scale(math.max(0, 1 - dt * 8));
  }

  void _resolveMeleeStrike() {
    final player = game.player;
    if (!_canTargetPlayer) return;
    final toPlayer = player.grid - grid;
    if (toPlayer.length > stats.attackRange + player.bodyRadius + 0.25) return;
    final knock = toPlayer.length2 > 0.001
        ? toPlayer.normalized() * 3.2
        : facing.clone() * 3.2;
    player.applyDamage(stats.damage * _damageScale, knockback: knock);
  }

  void _fire() {
    final player = game.player;
    if (!_canTargetPlayer) return;
    final aim = (player.grid - grid);
    if (aim.length2 < 0.0001) return;
    aim.normalize();

    // 지휘 유닛은 부채꼴로 흩뿌린다.
    final spread = isBoss ? 0.26 : 0.06;
    final offset = (_rng.nextDouble() - 0.5) * spread;
    final rotated = Vector2(
      aim.x * math.cos(offset) - aim.y * math.sin(offset),
      aim.x * math.sin(offset) + aim.y * math.cos(offset),
    );

    game.spawnProjectile(
      Projectile(
        grid: grid + rotated * (bodyRadius + 0.25),
        direction: rotated,
        speed: isBoss ? 7.0 : 6.2,
        damage: stats.damage * _damageScale,
        owner: ProjectileOwner.enemy,
        z: 0.7 * stats.scale,
        homing: isBoss ? 0.9 : 0,
      ),
    );
    GameAudio.play(isBoss ? Sfx.bossShot : Sfx.enemyShot, at: grid);
  }

  @override
  void applyDamage(double amount, {Vector2? knockback, bool critical = false}) {
    if (!isAlive) return;
    _hp = math.max(0, _hp - amount);
    _hitFlash = 1;
    _healthBarTimer = 2.5;
    GameAudio.play(Sfx.robotHit, at: grid);

    // 무거운 유닛일수록 넉백에 강하다.
    if (knockback != null) {
      final resistance = switch (kind) {
        EnemyKind.scout => 1.4,
        EnemyKind.sentry => 1.0,
        EnemyKind.heavy => 0.45,
        EnemyKind.commander => 0.12,
      };
      _knockback.add(knockback * resistance);
    }

    game.spawnEffect(
      DamageText(
        grid: grid.clone(),
        z: z + 1.1 * stats.scale,
        amount: amount,
        color: critical ? GamePalette.hitSpark : GamePalette.textPrimary,
        critical: critical,
      ),
    );

    // 피격 시 추격 상태로 전환한다.
    if (phase == EnemyPhase.idle) phase = EnemyPhase.chase;

    if (_hp <= 0) _die();
  }

  /// 이 적의 경험치 가치. 웨이브 강화 배율까지 반영한 값이다.
  ///
  /// 플레이어 레벨에 따른 감소는 지급 시점에 [LevelSystem.killXp]가 처리한다.
  late final int xpValue =
      LevelSystem.enemyXpValue(stats.xp, hpScale: _hpScale);

  void _die() {
    phase = EnemyPhase.dead;
    game.spawnEffect(
      Explosion(
        grid: grid.clone(),
        z: z + 0.3,
        blastScale: stats.scale * (isBoss ? 2.2 : 1.0),
      ),
    );
    game.shakeCamera(isBoss ? 26 : 6, isBoss ? 0.6 : 0.15);
    GameAudio.play(
      isBoss ? Sfx.explosionBoss : Sfx.explosion,
      at: grid,
      // 덩치가 클수록 폭발이 묵직하게 들린다.
      volumeScale: stats.scale.clamp(0.8, 1.4),
    );
    game.onEnemyKilled(this);
    removeFromParent();
  }

  // ── 렌더링 ──────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    final s = stats.scale;
    renderShadow(canvas, 20 * s, radiusY: 10 * s);

    canvas.save();
    canvas.scale(s);
    if (!facesRight(facing)) canvas.scale(-1, 1);

    switch (kind) {
      case EnemyKind.scout:
        _renderScout(canvas);
      case EnemyKind.sentry:
        _renderSentry(canvas);
      case EnemyKind.heavy:
        _renderHeavy(canvas);
      case EnemyKind.commander:
        _renderCommander(canvas);
    }
    canvas.restore();

    if (_hitFlash > 0) _renderHitFlash(canvas);
    if (_healthBarTimer > 0 || isBoss) _renderHealthBar(canvas);
    if (phase == EnemyPhase.telegraph) _renderTelegraph(canvas);
  }

  Paint get _shell => Paint()
    ..color = Color.lerp(
      GamePalette.robotShell,
      Colors.white,
      _hitFlash * 0.7,
    )!;

  Paint get _shellLight => Paint()
    ..color = Color.lerp(
      GamePalette.robotShellLight,
      Colors.white,
      _hitFlash * 0.7,
    )!;

  Paint get _shellDark => Paint()
    ..color = Color.lerp(
      GamePalette.robotShellDark,
      Colors.white,
      _hitFlash * 0.5,
    )!;

  /// 붉은 센서 아이(발광).
  void _drawEye(Canvas canvas, Offset center, double radius) {
    canvas.drawCircle(
      center,
      radius * 2.4,
      Paint()
        ..color = GamePalette.robotEye.withValues(alpha: 0.5)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 2),
    );
    canvas.drawCircle(center, radius, Paint()..color = GamePalette.robotEye);
    canvas.drawCircle(
      center,
      radius * 0.45,
      Paint()..color = GamePalette.robotEyeGlow,
    );
  }

  void _renderScout(Canvas canvas) {
    final hover = math.sin(_animTime * 3.4 + _phaseOffset) * 3;
    final tilt = phase == EnemyPhase.chase
        ? math.sin(_animTime * 6) * 0.06
        : 0.0;

    canvas.save();
    canvas.translate(0, -34 + hover);
    canvas.rotate(tilt);

    // 회전하는 반중력 링
    final ringT = _animTime * 4;
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(0, 8),
        width: 46 + math.sin(ringT) * 3,
        height: 14,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = GamePalette.robotEnergy.withValues(alpha: 0.75)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // 역삼각형 동체
    final body = Path()
      ..moveTo(-17, -8)
      ..lineTo(17, -8)
      ..lineTo(8, 10)
      ..lineTo(-8, 10)
      ..close();
    canvas.drawPath(body, _shell);

    // 상단 장갑
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-14, -16, 28, 10),
        const Radius.circular(4),
      ),
      _shellLight,
    );

    // 센서
    _drawEye(canvas, const Offset(5, -2), 3.4);

    // 측면 부스터
    canvas.drawRect(Rect.fromLTWH(-22, -6, 6, 9), _shellDark);
    canvas.drawRect(Rect.fromLTWH(16, -6, 6, 9), _shellDark);
    final thrust = 0.5 + math.sin(_animTime * 18) * 0.5;
    canvas.drawCircle(
      Offset(-19, 5),
      3 * thrust + 1,
      Paint()
        ..color = GamePalette.robotEnergy.withValues(alpha: 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      Offset(19, 5),
      3 * thrust + 1,
      Paint()
        ..color = GamePalette.robotEnergy.withValues(alpha: 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    canvas.restore();
  }

  void _renderSentry(Canvas canvas) {
    final walking = phase == EnemyPhase.chase || phase == EnemyPhase.idle;
    final cycle = _animTime * 7 + _phaseOffset;
    final swing = walking ? math.sin(cycle) : 0.0;
    final bob = walking ? math.sin(cycle * 2).abs() * 2 : 0.0;
    final baseY = -bob;

    // 다리
    for (var i = 0; i < 2; i++) {
      final phaseSign = i == 0 ? swing : -swing;
      final legX = i == 0 ? -9.0 : 9.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(legX - 4, baseY - 36, 8, 22),
          const Radius.circular(3),
        ),
        i == 0 ? _shellDark : _shell,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(legX - 4 + phaseSign * 4, baseY - 16, 8, 14),
          const Radius.circular(3),
        ),
        _shellDark,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(legX - 7 + phaseSign * 4, baseY - 4, 15, 5),
          const Radius.circular(2),
        ),
        _shellDark,
      );
    }

    // 몸통
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-15, baseY - 66, 30, 32),
        const Radius.circular(5),
      ),
      _shell,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-11, baseY - 62, 14, 18),
        const Radius.circular(3),
      ),
      _shellLight,
    );
    // 흉부 발광 코어
    canvas.drawRect(
      Rect.fromLTWH(-4, baseY - 54, 14, 4),
      Paint()..color = GamePalette.robotEnergy.withValues(alpha: 0.9),
    );

    // 팔(공격 모션에 따라 들어올림)
    final armLift = switch (phase) {
      EnemyPhase.telegraph => -14.0 * (1 - _phaseTimer / stats.telegraphTime),
      EnemyPhase.strike => -16.0,
      EnemyPhase.recover => -6.0,
      _ => math.sin(cycle) * 3,
    };
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-22, baseY - 62 - armLift * 0.3, 8, 26),
        const Radius.circular(3),
      ),
      _shellDark,
    );
    canvas.save();
    canvas.translate(16, baseY - 58);
    canvas.rotate(armLift * 0.055);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-4, 0, 9, 28),
        const Radius.circular(3),
      ),
      _shellLight,
    );
    // 집게형 타격구
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-7, 24, 15, 11),
        const Radius.circular(3),
      ),
      _shellDark,
    );
    canvas.restore();

    // 머리
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-10, baseY - 82, 20, 16),
        const Radius.circular(4),
      ),
      _shellLight,
    );
    _drawEye(canvas, Offset(3, baseY - 74), 3.6);
    // 안테나
    canvas.drawLine(
      Offset(-6, baseY - 82),
      Offset(-8, baseY - 92),
      Paint()
        ..color = GamePalette.robotShellDark
        ..strokeWidth = 2,
    );
  }

  void _renderHeavy(Canvas canvas) {
    final idleSway = math.sin(_animTime * 2 + _phaseOffset) * 1.5;
    final walking = phase == EnemyPhase.chase;
    final cycle = _animTime * 4.5;
    final step = walking ? math.sin(cycle) : 0.0;
    final baseY = walking ? -math.sin(cycle * 2).abs() * 2 : idleSway * 0.3;

    // 굵은 다리
    for (var i = 0; i < 2; i++) {
      final legX = i == 0 ? -14.0 : 14.0;
      final phaseSign = i == 0 ? step : -step;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(legX - 8, baseY - 40, 16, 26),
          const Radius.circular(4),
        ),
        i == 0 ? _shellDark : _shell,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(legX - 10 + phaseSign * 3, baseY - 16, 20, 14),
          const Radius.circular(3),
        ),
        _shellDark,
      );
    }

    // 넓은 몸통
    final torso = Path()
      ..moveTo(-24, baseY - 78)
      ..lineTo(24, baseY - 78)
      ..lineTo(20, baseY - 38)
      ..lineTo(-20, baseY - 38)
      ..close();
    canvas.drawPath(torso, _shell);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-18, baseY - 74, 22, 24),
        const Radius.circular(4),
      ),
      _shellLight,
    );

    // 어깨 캐논
    final charging = phase == EnemyPhase.telegraph || phase == EnemyPhase.strike;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(12, baseY - 84, 26, 16),
        const Radius.circular(4),
      ),
      _shellDark,
    );
    canvas.drawRect(
      Rect.fromLTWH(34, baseY - 80, 14, 8),
      _shellLight,
    );
    if (charging) {
      final charge = phase == EnemyPhase.telegraph
          ? 1 - (_phaseTimer / stats.telegraphTime)
          : 1.0;
      canvas.drawCircle(
        Offset(50, baseY - 76),
        4 + charge * 6,
        Paint()
          ..color = GamePalette.robotEnergy.withValues(alpha: 0.85)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + charge * 6),
      );
    }

    // 반대쪽 어깨 장갑
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-38, baseY - 82, 20, 22),
        const Radius.circular(6),
      ),
      _shellLight,
    );

    // 머리
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-12, baseY - 96, 24, 18),
        const Radius.circular(4),
      ),
      _shell,
    );
    _drawEye(canvas, Offset(0, baseY - 87), 5);
    // 배기구 발광
    canvas.drawRect(
      Rect.fromLTWH(-22, baseY - 56, 6, 12),
      Paint()..color = GamePalette.robotEnergy.withValues(alpha: 0.6),
    );
  }

  void _renderCommander(Canvas canvas) {
    // 중장갑 메크를 기반으로 하되 위압적인 장식을 얹는다.
    _renderHeavy(canvas);

    final float = math.sin(_animTime * 1.6) * 2;

    // 등 뒤 부양 코어
    canvas.drawCircle(
      Offset(-4, -110 + float),
      13,
      Paint()
        ..color = GamePalette.robotEye.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(
      Offset(-4, -110 + float),
      7,
      Paint()..color = GamePalette.robotEyeGlow,
    );

    // 위성처럼 도는 방어 드론
    for (var i = 0; i < 3; i++) {
      final angle = _animTime * 1.8 + i * math.pi * 2 / 3;
      final orbit = Offset(math.cos(angle) * 48, math.sin(angle) * 18 - 92);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: orbit, width: 12, height: 8),
          const Radius.circular(3),
        ),
        _shellLight,
      );
      canvas.drawCircle(
        orbit,
        2.2,
        Paint()..color = GamePalette.robotEye,
      );
    }

    // 지휘관 표식(뿔)
    final crown = Path()
      ..moveTo(-14, -96)
      ..lineTo(-8, -116)
      ..lineTo(-2, -98)
      ..close();
    canvas.drawPath(crown, _shellLight);
  }

  void _renderHitFlash(Canvas canvas) {
    canvas.drawCircle(
      Offset(0, -30 * stats.scale),
      36 * stats.scale,
      Paint()
        ..color = Colors.white.withValues(alpha: _hitFlash * 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
  }

  void _renderHealthBar(Canvas canvas) {
    final s = stats.scale;
    final width = isBoss ? 96.0 : 46.0 * s;
    final height = isBoss ? 8.0 : 5.0;
    final top = isBoss ? -150.0 : -108.0 * s;
    final ratio = (_hp / _maxHp).clamp(0.0, 1.0);

    final rect = Rect.fromLTWH(-width / 2, top, width, height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(1.5), const Radius.circular(3)),
      Paint()..color = Colors.black.withValues(alpha: 0.65),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left, rect.top, width * ratio, height),
        const Radius.circular(2),
      ),
      Paint()
        ..color = isBoss
            ? GamePalette.robotEye
            : Color.lerp(GamePalette.hpFillLow, GamePalette.robotEnergy, ratio)!,
    );
  }

  /// 공격 예비 동작을 알리는 지면 경고 표시.
  void _renderTelegraph(Canvas canvas) {
    final progress =
        (1 - (_phaseTimer / stats.telegraphTime)).clamp(0.0, 1.0).toDouble();
    final alpha = 0.25 + progress * 0.45;

    if (stats.ranged) {
      // 조준선
      final screenDir = gridDirToScreenDir(facing.normalized())..normalize();
      final length = stats.attackRange * kTileWidth * 0.5;
      canvas.drawLine(
        Offset(screenDir.x * 20, screenDir.y * 20 - 40 * stats.scale),
        Offset(screenDir.x * length, screenDir.y * length - 40 * stats.scale),
        Paint()
          ..strokeWidth = 1.6
          ..color = GamePalette.robotEye.withValues(alpha: alpha * 0.8),
      );
    } else {
      // 근접 범위 원(아이소 타원)
      final radius = stats.attackRange * kHalfTileWidth;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: radius * 2,
          height: radius,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = GamePalette.robotEye.withValues(alpha: alpha),
      );
    }
  }
}
