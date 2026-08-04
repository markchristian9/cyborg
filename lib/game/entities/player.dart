import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../audio/game_audio.dart';
import '../fx/damage_text.dart';
import '../fx/hit_spark.dart';
import '../iso.dart';
import '../level/level_map.dart';
import '../palette.dart';
import '../systems/buff.dart';
import '../systems/inventory.dart';
import '../systems/level_system.dart';
import 'iso_entity.dart';
import 'pickup.dart';
import 'projectile.dart';

/// 플레이어의 현재 행동 상태.
enum PlayerState { idle, run, melee, dash, hurt, dead }

/// 인간 저항군 사이보그. 플레이어가 조작하는 캐릭터.
class Player extends IsoEntity with Damageable {
  Player({required Vector2 grid})
      : super(grid: grid, bodyRadius: 0.28, depthBias: 0.02);

  // ── 스탯 ────────────────────────────────────────────────────────────
  double _hp = 120;
  double _maxHp = 120;
  double energy = 100;
  double maxEnergy = 100;
  int level = 1;
  int xp = 0;
  int xpToNextLevel = LevelSystem.xpToNext(1);
  double meleeDamage = 26;
  double rangedDamage = 18;
  double moveSpeed = 3.6; // 초당 타일 수

  /// 바닥의 전리품을 자동으로 끌어당기는 반경(타일 단위).
  double lootRadius = 2.8;

  /// 포션으로 얻은 강화 효과들.
  final BuffSet buffs = BuffSet();

  @override
  double get hp => _hp;

  @override
  double get maxHp => _maxHp;

  /// 버프가 반영된 근접 피해량.
  double get effectiveMeleeDamage => meleeDamage * buffs.damageMultiplier;

  /// 버프가 반영된 원거리 피해량.
  double get effectiveRangedDamage => rangedDamage * buffs.damageMultiplier;

  /// 버프가 반영된 이동 속도.
  double get effectiveMoveSpeed => moveSpeed * buffs.speedMultiplier;

  // ── 상태 ────────────────────────────────────────────────────────────
  PlayerState state = PlayerState.idle;

  /// 그리드 좌표계 기준의 입력 방향(정규화 전).
  final Vector2 moveInput = Vector2.zero();

  /// 마지막으로 바라본 방향(그리드 좌표계).
  final Vector2 facing = Vector2(1, 1)..normalize();

  final Vector2 _velocity = Vector2.zero();
  final Vector2 _knockback = Vector2.zero();

  double _animTime = 0;
  double _meleeTimer = 0;
  double _meleeCooldown = 0;
  double _shootCooldown = 0;
  double _dashTimer = 0;
  double _dashCooldown = 0;
  double _invulnerable = 0;
  double _hazardTick = 0;
  double _deathTimer = 0;
  double _stepTimer = 0;
  int _comboStep = 0;
  double _comboWindow = 0;
  bool _meleeHitApplied = false;
  final List<_DashGhost> _ghosts = [];

  static const double _meleeDuration = 0.32;
  static const double _meleeRange = 1.5;
  static const double _dashDuration = 0.18;
  static const double _dashSpeed = 13.0;

  bool get isDashing => _dashTimer > 0;
  bool get isInvulnerable => _invulnerable > 0;
  double get dashCooldownRatio =>
      (_dashCooldown / 0.9).clamp(0.0, 1.0).toDouble();

  // ── 입력 진입점 ─────────────────────────────────────────────────────

  /// 근접 공격(에너지 블레이드)을 시도한다.
  void tryMelee() {
    if (!isAlive || _meleeCooldown > 0 || isDashing) return;
    _comboStep = _comboWindow > 0 ? (_comboStep + 1) % 3 : 0;
    _comboWindow = 0.65;
    _meleeTimer = _meleeDuration;
    _meleeCooldown = _meleeDuration + 0.06;
    _meleeHitApplied = false;
    state = PlayerState.melee;
    // 콤보 마무리는 더 묵직한 스윙음으로 구분한다.
    GameAudio.play(
      _comboStep == 2 ? Sfx.bladeSwingHeavy : Sfx.bladeSwing,
    );
  }

  /// 플라즈마 볼트를 발사한다.
  void tryShoot() {
    if (!isAlive || _shootCooldown > 0) return;
    if (energy < 12) {
      GameAudio.play(Sfx.uiError);
      return;
    }
    _shootCooldown = 0.24;
    energy -= 12;
    final dir = facing.clone()..normalize();
    game.spawnProjectile(
      Projectile(
        grid: grid + dir * 0.4,
        direction: dir,
        speed: 9.5,
        damage: effectiveRangedDamage,
        owner: ProjectileOwner.player,
        z: 0.62,
      ),
    );
    game.shakeCamera(2.5, 0.08);
    GameAudio.play(Sfx.plasmaShot);
  }

  /// 회피 대시를 시도한다.
  void tryDash() {
    if (!isAlive || _dashCooldown > 0) return;
    if (energy < 20) {
      GameAudio.play(Sfx.uiError);
      return;
    }
    if (moveInput.length2 > 0.01) {
      facing.setFrom(moveInput.normalized());
    }
    energy -= 20;
    _dashTimer = _dashDuration;
    _dashCooldown = 0.9;
    _invulnerable = math.max(_invulnerable, _dashDuration + 0.08);
    state = PlayerState.dash;
    GameAudio.play(Sfx.dash);
  }

  // ── 갱신 ────────────────────────────────────────────────────────────

  @override
  void update(double dt) {
    _animTime += dt;
    _tickTimers(dt);

    // 거리에 따른 소리 감쇠는 플레이어를 기준으로 계산한다.
    GameAudio.listener = grid;

    if (!isAlive) {
      _deathTimer += dt;
      super.update(dt);
      return;
    }

    buffs.update(dt);
    energy = math.min(
      maxEnergy,
      energy + dt * 16 * buffs.energyRegenMultiplier,
    );

    _updateMovement(dt);
    _updateSteps(dt);
    _updateMelee();
    _updateHazard(dt);
    _updateGhosts(dt);

    super.update(dt);
  }

  /// 이동 속도에 맞춰 발소리 간격을 조절한다.
  void _updateSteps(double dt) {
    final speed = _velocity.length;
    if (isDashing || speed < 0.5) {
      // 멈췄다가 다시 걸으면 곧바로 첫 발소리가 나도록 짧게 남겨 둔다.
      _stepTimer = 0.1;
      return;
    }
    _stepTimer -= dt;
    if (_stepTimer <= 0) {
      // 다리 애니메이션(_animTime * 9)의 반주기에 맞춘 간격.
      _stepTimer = (1.26 / speed).clamp(0.18, 0.5);
      GameAudio.play(Sfx.step);
    }
  }

  void _tickTimers(double dt) {
    if (_meleeTimer > 0) _meleeTimer -= dt;
    if (_meleeCooldown > 0) _meleeCooldown -= dt;
    if (_shootCooldown > 0) _shootCooldown -= dt;
    if (_dashCooldown > 0) _dashCooldown -= dt;
    if (_invulnerable > 0) _invulnerable -= dt;
    if (_comboWindow > 0) _comboWindow -= dt;
    if (_dashTimer > 0) {
      _dashTimer -= dt;
      if (_dashTimer <= 0 && state == PlayerState.dash) {
        state = PlayerState.idle;
      }
    }
  }

  void _updateMovement(double dt) {
    if (isDashing) {
      _velocity
        ..setFrom(facing)
        ..normalize()
        ..scale(_dashSpeed);
      if (_ghosts.length < 12) {
        _ghosts.add(_DashGhost(grid.clone(), facing.clone()));
      }
    } else if (moveInput.length2 > 0.001) {
      final dir = moveInput.normalized();
      facing.setFrom(dir);
      final speedFactor = state == PlayerState.melee ? 0.35 : 1.0;
      _velocity
        ..setFrom(dir)
        ..scale(effectiveMoveSpeed * speedFactor);
      if (state != PlayerState.melee) state = PlayerState.run;
    } else {
      _velocity.setZero();
      if (state == PlayerState.run) state = PlayerState.idle;
    }

    // 넉백은 지수적으로 감쇠시킨다.
    if (_knockback.length2 > 0.0001) {
      _velocity.add(_knockback);
      _knockback.scale(math.max(0, 1 - dt * 9));
    }

    _moveWithCollision(_velocity * dt);
  }

  /// 축을 분리해 이동시켜 벽을 따라 미끄러지도록 한다.
  void _moveWithCollision(Vector2 delta) {
    final map = game.map;
    final r = bodyRadius;

    bool free(double gx, double gy) {
      return map.isWalkableAt(gx - r, gy - r) &&
          map.isWalkableAt(gx + r, gy - r) &&
          map.isWalkableAt(gx - r, gy + r) &&
          map.isWalkableAt(gx + r, gy + r);
    }

    if (delta.x != 0 && free(grid.x + delta.x, grid.y)) {
      grid.x += delta.x;
    }
    if (delta.y != 0 && free(grid.x, grid.y + delta.y)) {
      grid.y += delta.y;
    }
  }

  void _updateMelee() {
    if (state != PlayerState.melee) return;
    if (_meleeTimer <= 0) {
      state = moveInput.length2 > 0.001 ? PlayerState.run : PlayerState.idle;
      return;
    }
    // 스윙 중반에 한 번만 판정한다.
    final progress = 1 - (_meleeTimer / _meleeDuration);
    if (!_meleeHitApplied && progress >= 0.35) {
      _meleeHitApplied = true;
      _resolveMeleeHit();
    }
  }

  void _resolveMeleeHit() {
    final dir = facing.normalized();
    final comboBonus = _comboStep == 2 ? 1.6 : 1.0;
    final damage = effectiveMeleeDamage * comboBonus;
    var hitAny = false;

    for (final target in game.meleeTargets()) {
      final toTarget = target.grid - grid;
      final distance = toTarget.length;
      if (distance > _meleeRange + target.bodyRadius) continue;
      if (distance > 0.001) {
        final alignment = toTarget.normalized().dot(dir);
        // 전방 약 120도 부채꼴.
        if (alignment < 0.35) continue;
      }
      hitAny = true;
      final knock = distance > 0.001 ? toTarget.normalized() : dir;
      target.applyDamage(
        damage,
        knockback: knock * (_comboStep == 2 ? 3.4 : 1.9),
        critical: _comboStep == 2,
      );
      game.spawnEffect(
        HitSpark(
          grid: target.grid.clone(),
          z: 0.55,
          color: GamePalette.bladeGlow,
        ),
      );
    }

    if (hitAny) {
      game.shakeCamera(_comboStep == 2 ? 8 : 4, 0.12);
      energy = math.min(maxEnergy, energy + 4);
      GameAudio.play(_comboStep == 2 ? Sfx.meleeCrit : Sfx.meleeHit);
    }
  }

  void _updateHazard(double dt) {
    final tile = game.map.tileAt(grid.x.floor(), grid.y.floor());
    if (tile != TileType.hazard) {
      _hazardTick = 0;
      return;
    }
    GameAudio.play(Sfx.hazardBurn);
    _hazardTick += dt;
    if (_hazardTick >= 0.5) {
      _hazardTick = 0;
      applyDamage(5, ignoreInvulnerable: true);
    }
  }

  void _updateGhosts(double dt) {
    for (final ghost in _ghosts) {
      ghost.life -= dt * 3.2;
    }
    _ghosts.removeWhere((ghost) => ghost.life <= 0);
  }

  // ── 피해 / 성장 ─────────────────────────────────────────────────────

  @override
  void applyDamage(
    double amount, {
    Vector2? knockback,
    bool critical = false,
    bool ignoreInvulnerable = false,
  }) {
    if (!isAlive) return;
    if (!ignoreInvulnerable && (isInvulnerable || isDashing)) return;
    // 안전지대 안에서는 어떤 피해도 통하지 않는다. 재접속 직후의 무방비
    // 상태를 지켜 주는 것이 이 구역의 존재 이유다.
    if (game.map.isInSafeZone(grid.x, grid.y)) return;

    // 장갑 경화 같은 버프는 들어오는 피해 자체를 깎는다.
    final taken = amount * buffs.damageTakenMultiplier;

    _hp = math.max(0, _hp - taken);
    _invulnerable = math.max(_invulnerable, 0.55);
    if (knockback != null) _knockback.add(knockback);

    game.spawnEffect(
      DamageText(
        grid: grid.clone(),
        z: 1.0,
        amount: taken,
        color: GamePalette.hpFillLow,
      ),
    );
    game.shakeCamera(9, 0.2);
    game.onPlayerDamaged();

    if (_hp <= 0) {
      state = PlayerState.dead;
      GameAudio.play(Sfx.playerDeath);
      // 이 세계에 게임 오버는 없다. 게임 본체가 곧바로 안전지대에서
      // 재가동시킨다.
      game.onPlayerDied();
    } else {
      // 큰 피해일수록 크게 들리도록 한다.
      GameAudio.play(
        Sfx.playerHurt,
        volumeScale: (0.5 + taken / 40).clamp(0.5, 1.2),
      );
    }
  }

  /// 재가동 직후 유지되는 무적 시간(초).
  ///
  /// 안전지대 안은 어차피 무적이지만, 밖으로 걸어 나가는 순간 대기하던
  /// 로봇에게 즉사하지 않도록 짧은 유예를 준다.
  static const double respawnInvulnerability = 2.0;

  /// [point]에서 즉시 재가동한다.
  ///
  /// 사망 직후 게임 본체가 안전지대 좌표를 넘겨 호출한다. 죽은 것은 몸체일
  /// 뿐이고 의식은 백업되어 있으므로, 레벨·경험치·버프는 그대로 두고
  /// 전투 상태만 되돌린다.
  void respawnAt(Vector2 point) {
    grid.setFrom(point);
    _hp = _maxHp;
    energy = maxEnergy;
    state = PlayerState.idle;

    moveInput.setZero();
    _velocity.setZero();
    _knockback.setZero();
    _ghosts.clear();

    _deathTimer = 0;
    _meleeTimer = 0;
    _meleeCooldown = 0;
    _shootCooldown = 0;
    _dashTimer = 0;
    _dashCooldown = 0;
    _comboStep = 0;
    _comboWindow = 0;
    _meleeHitApplied = true;
    _hazardTick = 0;
    _invulnerable = respawnInvulnerability;

    // 순간이동이므로 화면 좌표도 이번 프레임에 바로 맞춘다.
    syncTransform();
  }

  /// 체력을 회복하고 실제로 채워진 양을 돌려준다.
  ///
  /// [showText]가 false면 회복 수치를 띄우지 않는다. 포션처럼 호출한 쪽이
  /// 따로 라벨을 표시할 때 쓴다.
  double heal(double amount, {bool showText = true}) {
    if (!isAlive) return 0;
    final before = _hp;
    _hp = math.min(_maxHp, _hp + amount);
    final healed = _hp - before;
    if (showText && healed > 0) {
      game.spawnEffect(
        DamageText(
          grid: grid.clone(),
          z: 1.0,
          amount: healed,
          color: GamePalette.healGlow,
          prefix: '+',
        ),
      );
    }
    return healed;
  }

  /// 에너지를 회복하고 실제로 채워진 양을 돌려준다.
  double restoreEnergy(double amount) {
    final before = energy;
    energy = math.min(maxEnergy, energy + amount);
    return energy - before;
  }

  /// 포션 한 개를 마신다. 회복과 강화 효과가 함께 적용된다.
  ///
  /// 인벤토리에서 개수를 줄인 뒤 호출되므로 여기서는 효과만 적용한다.
  PotionUseResult drinkPotion(PickupKind kind, PotionEffect effect) {
    final healed = effect.heal > 0 ? heal(effect.heal, showText: false) : 0.0;
    final energized =
        effect.energy > 0 ? restoreEnergy(effect.energy) : 0.0;

    final buff = effect.buff;
    if (buff != null) buffs.apply(buff);

    // 마시는 순간 몸이 달아오르는 느낌을 준다.
    game.spawnEffect(
      HitSpark(
        grid: grid.clone(),
        z: 0.7,
        color: PickupSpec.table[kind]!.color,
      ),
    );

    return PotionUseResult(
      kind: kind,
      healed: healed,
      energized: energized,
      buffed: buff != null,
    );
  }

  /// 경험치를 획득하고 필요 시 레벨업한다. 한 번에 여러 레벨이 오를 수 있다.
  void gainXp(int amount, {bool showText = true}) {
    if (!isAlive || amount <= 0) return;
    if (level >= LevelSystem.maxLevel) return;

    xp += amount;
    if (showText) {
      game.spawnEffect(
        DamageText(
          grid: grid.clone(),
          z: 1.25,
          amount: amount.toDouble(),
          color: GamePalette.xpGlow,
          prefix: '+',
        ),
      );
    }

    while (level < LevelSystem.maxLevel && xp >= xpToNextLevel) {
      xp -= xpToNextLevel;
      _levelUp();
    }
    // 만렙에 도달하면 남은 경험치는 버린다.
    if (level >= LevelSystem.maxLevel) xp = 0;
  }

  void _levelUp() {
    level++;
    final gains = LevelSystem.gainsFor(level);
    _maxHp += gains.maxHp;
    maxEnergy += gains.maxEnergy;
    meleeDamage += gains.meleeDamage;
    rangedDamage += gains.rangedDamage;
    moveSpeed += gains.moveSpeed;
    xpToNextLevel = LevelSystem.xpToNext(level);

    // 레벨업하면 완전히 회복하고 잠깐 무적이 된다.
    _hp = _maxHp;
    energy = maxEnergy;
    _invulnerable = math.max(_invulnerable, 0.6);

    game.spawnEffect(
      HitSpark(
        grid: grid.clone(),
        z: 0.6,
        color: GamePalette.xpGlow,
      ),
    );
    GameAudio.play(Sfx.levelUp);
    // 배너와 화면 흔들림 등 연출은 게임 본체가 담당한다.
    game.onLevelUp(level, milestone: gains.milestone);
  }

  // ── 렌더링 ──────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    renderShadow(canvas, 22, radiusY: 11);

    for (final ghost in _ghosts) {
      _renderGhost(canvas, ghost);
    }

    if (!isAlive) {
      _renderDeath(canvas);
      return;
    }

    if (!buffs.isEmpty) _renderBuffAura(canvas);

    // 피격 무적 중 깜빡임.
    final blink = isInvulnerable && !isDashing;
    if (blink && (_animTime * 18).floor().isEven) {
      return;
    }

    canvas.save();
    final right = facesRight(facing);
    if (!right) canvas.scale(-1, 1);
    _renderBody(canvas, back: !facesDown(facing));
    canvas.restore();

    if (state == PlayerState.melee) {
      _renderBladeSwing(canvas);
    }
  }

  /// 포션 강화 중임을 알리는 발밑 링과 떠오르는 입자.
  void _renderBuffAura(Canvas canvas) {
    for (final buff in buffs.active) {
      final color = buff.spec.color;
      // 효과가 끝나갈수록 옅어져 남은 시간을 짐작할 수 있게 한다.
      final fade = buff.ratio < 0.25 ? buff.ratio / 0.25 : 1.0;
      final pulse = 0.75 + math.sin(_animTime * 6) * 0.25;

      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: 58 + pulse * 8,
          height: 29 + pulse * 4,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = color.withValues(alpha: 0.45 * fade * pulse)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );

      // 몸을 따라 올라가는 작은 입자 세 개.
      for (var i = 0; i < 3; i++) {
        final phase = (_animTime * 0.8 + i / 3) % 1.0;
        final radius = 22 - phase * 6;
        final angle = phase * math.pi * 2 + i * 2.1;
        canvas.drawCircle(
          Offset(math.cos(angle) * radius, -phase * 72),
          2.2 * (1 - phase),
          Paint()..color = color.withValues(alpha: 0.7 * fade * (1 - phase)),
        );
      }
    }
  }

  void _renderGhost(Canvas canvas, _DashGhost ghost) {
    final offset = gridToScreen(ghost.grid.x, ghost.grid.y, z) -
        gridToScreen(grid.x, grid.y, z);
    canvas.save();
    canvas.translate(offset.x, offset.y);
    canvas.saveLayer(
      Rect.fromCenter(center: const Offset(0, -50), width: 140, height: 160),
      Paint()
        ..color = GamePalette.playerAccent
            .withValues(alpha: (ghost.life * 0.45).clamp(0.0, 0.45))
        ..colorFilter = ColorFilter.mode(
          GamePalette.playerAccent,
          BlendMode.srcATop,
        ),
    );
    if (!facesRight(ghost.facing)) canvas.scale(-1, 1);
    _renderBody(canvas, back: !facesDown(ghost.facing));
    canvas.restore();
    canvas.restore();
  }

  /// 사이보그 본체. 원점은 발밑, 화면 정렬(빌보드)로 그린다.
  void _renderBody(Canvas canvas, {required bool back}) {
    final running = state == PlayerState.run || isDashing;
    final cycle = _animTime * (isDashing ? 20 : 9);
    final swing = running ? math.sin(cycle) : 0.0;
    final bob = running ? math.sin(cycle * 2) * 2.0 : math.sin(_animTime * 2) * 1.2;

    final armor = Paint()..color = GamePalette.playerArmor;
    final armorLight = Paint()..color = GamePalette.playerArmorLight;
    final accent = Paint()..color = GamePalette.playerAccent;
    final dark = Paint()..color = const Color(0xFF161C25);

    final baseY = -bob;

    // 다리
    for (var i = 0; i < 2; i++) {
      final phase = i == 0 ? swing : -swing;
      final legX = i == 0 ? -7.0 : 7.0;
      final path = Path()
        ..moveTo(legX - 4, baseY - 42)
        ..lineTo(legX + 4, baseY - 42)
        ..lineTo(legX + 4 + phase * 5, baseY - 4)
        ..lineTo(legX - 4 + phase * 5, baseY - 4)
        ..close();
      canvas.drawPath(path, i == 0 ? armor : dark);
      // 부츠
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(legX - 6 + phase * 5, baseY - 8, 13, 7),
          const Radius.circular(2),
        ),
        dark,
      );
    }

    // 몸통(사다리꼴 아머)
    final torso = Path()
      ..moveTo(-11, baseY - 74)
      ..lineTo(11, baseY - 74)
      ..lineTo(9, baseY - 40)
      ..lineTo(-9, baseY - 40)
      ..close();
    canvas.drawPath(torso, armor);

    // 흉갑 하이라이트
    final chest = Path()
      ..moveTo(-8, baseY - 72)
      ..lineTo(2, baseY - 72)
      ..lineTo(0, baseY - 52)
      ..lineTo(-7, baseY - 52)
      ..close();
    canvas.drawPath(chest, armorLight);

    if (!back) {
      // 가슴 에너지 코어
      canvas.drawCircle(
        Offset(0, baseY - 60),
        4.5,
        Paint()
          ..color = GamePalette.playerAccent
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawCircle(Offset(0, baseY - 60), 2.6, accent);
    } else {
      // 등 뒤 동력팩
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-8, baseY - 70, 16, 20),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0xFF1E2733),
      );
      canvas.drawRect(
        Rect.fromLTWH(-5, baseY - 66, 10, 3),
        accent,
      );
    }

    // 어깨 패드
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-16, baseY - 76, 11, 12),
        const Radius.circular(4),
      ),
      armorLight,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(5, baseY - 76, 11, 12),
        const Radius.circular(4),
      ),
      armorLight,
    );

    // 팔(무기 쪽은 앞으로)
    final armSwing = running ? -swing * 6 : 0.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-17, baseY - 66 + armSwing, 7, 22),
        const Radius.circular(3),
      ),
      armor,
    );
    final weaponArm = Path()
      ..moveTo(11, baseY - 66)
      ..lineTo(18, baseY - 62)
      ..lineTo(18, baseY - 50)
      ..lineTo(11, baseY - 48)
      ..close();
    canvas.drawPath(weaponArm, armorLight);

    // 목
    canvas.drawRect(Rect.fromLTWH(-3, baseY - 80, 6, 7), dark);

    // 머리(헬멧)
    final headCenter = Offset(0.5, baseY - 88);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromCenter(center: headCenter, width: 21, height: 19),
        topLeft: const Radius.circular(8),
        topRight: const Radius.circular(8),
        bottomLeft: const Radius.circular(4),
        bottomRight: const Radius.circular(4),
      ),
      armorLight,
    );

    if (!back) {
      // 바이저
      final visor = RRect.fromRectAndRadius(
        Rect.fromLTWH(-2, baseY - 92, 12, 6),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        visor,
        Paint()
          ..color = GamePalette.playerVisor
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
      );
      canvas.drawRRect(visor, Paint()..color = GamePalette.playerVisor);
      // 턱 라인
      canvas.drawRect(
        Rect.fromLTWH(-3, baseY - 84, 9, 3),
        Paint()..color = GamePalette.playerSkin,
      );
    } else {
      // 뒤통수 케이블
      canvas.drawLine(
        Offset(0, baseY - 84),
        Offset(-2, baseY - 72),
        Paint()
          ..color = accent.color.withValues(alpha: 0.7)
          ..strokeWidth = 2,
      );
    }

    // 헬멧 안테나
    canvas.drawLine(
      Offset(-6, baseY - 96),
      Offset(-9, baseY - 106),
      Paint()
        ..color = GamePalette.playerAccent
        ..strokeWidth = 1.6,
    );
    canvas.drawCircle(Offset(-9, baseY - 107), 1.8, accent);

    // 대기 상태에서 블레이드를 손에 든 실루엣
    if (state != PlayerState.melee) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(17, baseY - 58, 3, 26),
          const Radius.circular(1.5),
        ),
        Paint()..color = GamePalette.bladeGlow.withValues(alpha: 0.55),
      );
    }
  }

  /// 에너지 블레이드 스윙 궤적.
  void _renderBladeSwing(Canvas canvas) {
    final progress =
        (1 - (_meleeTimer / _meleeDuration)).clamp(0.0, 1.0).toDouble();
    final screenDir = gridDirToScreenDir(facing.normalized())..normalize();
    final baseAngle = math.atan2(screenDir.y, screenDir.x);

    // 콤보 단계마다 스윙 방향을 바꿔 리듬감을 준다.
    final reverse = _comboStep == 1;
    final sweep = _comboStep == 2 ? math.pi * 1.6 : math.pi * 1.05;
    final start = reverse ? sweep / 2 : -sweep / 2;
    final angle = baseAngle + (reverse ? start - sweep * progress
        : start + sweep * progress);

    final pivot = Offset(0, -52);
    final length = _comboStep == 2 ? 74.0 : 62.0;
    final fade = math.sin(progress * math.pi);

    // 궤적(호)
    final trailPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16 * fade
      ..strokeCap = StrokeCap.round
      ..color = GamePalette.bladeGlow.withValues(alpha: 0.35 * fade)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    final trailSweep = (reverse ? -1 : 1) * sweep * progress;
    canvas.drawArc(
      Rect.fromCircle(center: pivot, radius: length * 0.78),
      baseAngle + start,
      trailSweep,
      false,
      trailPaint,
    );

    // 칼날
    final tip = pivot + Offset(math.cos(angle), math.sin(angle)) * length;
    final hilt = pivot + Offset(math.cos(angle), math.sin(angle)) * 18;
    canvas.drawLine(
      hilt,
      tip,
      Paint()
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..color = GamePalette.bladeGlow.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawLine(
      hilt,
      tip,
      Paint()
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round
        ..color = GamePalette.bladeCore,
    );
  }

  void _renderDeath(Canvas canvas) {
    final t = _deathTimer.clamp(0.0, 1.0).toDouble();
    canvas.save();
    canvas.translate(0, -6 * (1 - t));
    canvas.rotate(-math.pi / 2 * t);
    canvas.scale(1, 1 - t * 0.15);
    _renderBody(canvas, back: false);
    canvas.restore();

    // 파손된 코어에서 새어 나오는 스파크
    if (t < 1) {
      final flicker = math.Random(_deathTimer.floor()).nextDouble();
      canvas.drawCircle(
        Offset(10 * t, -20),
        6 * (1 - t) * (0.5 + flicker * 0.5),
        Paint()
          ..color = GamePalette.playerAccent.withValues(alpha: 0.6 * (1 - t))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }
  }
}

class _DashGhost {
  _DashGhost(this.grid, this.facing);

  final Vector2 grid;
  final Vector2 facing;
  double life = 1;
}
