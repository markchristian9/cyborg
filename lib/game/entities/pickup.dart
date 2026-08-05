import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../audio/game_audio.dart';
import '../fx/loot_text.dart';
import '../palette.dart';
import '../systems/buff.dart';
import 'iso_entity.dart';
import 'player.dart';

/// 전리품의 등급. 발광 세기와 착지 연출의 화려함을 결정한다.
enum LootRarity { common, uncommon, rare }

/// 바닥에 떨어지는 전리품 종류.
///
/// AI 로봇을 파괴하면 잔해에서 사이보그가 쓸 수 있는 나노 수리액·에너지
/// 셀 따위가 튀어나온다. 포션류는 인벤토리에 쌓이고, 데이터 칩과 스크랩
/// 코어는 회수하는 즉시 경험치·점수로 환산된다.
enum PickupKind {
  /// 1등급 나노 수리액(100). 가장 흔한 응급 처치용.
  nanoVial,

  /// 2등급 나노 캐니스터(200). 장갑 경화가 함께 걸린다.
  nanoCanister,

  /// 3등급 재생 셀(300).
  repairCell,

  /// 4등급 재생 앰플(500).
  regenAmpoule,

  /// 5등급 정비 키트(1000). 좀처럼 나오지 않는다.
  overhaulKit,

  /// 에너지 셀. 에너지를 회복한다.
  energyCell,

  /// 과충전 셀. 에너지를 크게 채우고 과충전 상태가 된다.
  overchargeCell,

  /// 전투 강화제. 마시면 한동안 훨씬 강해진다.
  combatStim,

  /// 데이터 칩. 회수 즉시 경험치가 된다.
  dataChip,

  /// 스크랩 코어. 회수 즉시 점수가 된다.
  scrapCore,
}

/// 포션을 마셨을 때 실제로 일어나는 일.
class PotionEffect {
  const PotionEffect({this.heal = 0, this.energy = 0, this.buff});

  /// 회복되는 체력.
  final double heal;

  /// 회복되는 에너지.
  final double energy;

  /// 함께 걸리는 강화 효과.
  final BuffKind? buff;
}

/// 전리품 종류별 고정 정보.
class PickupSpec {
  const PickupSpec({
    required this.name,
    required this.amount,
    required this.color,
    required this.unit,
    required this.rarity,
    required this.radius,
    this.potion,
  });

  /// 인벤토리와 획득 라벨에 표시할 이름.
  final String name;

  /// 즉시 환산형의 기본 효과량(경험치·점수). 포션은 [potion]을 따른다.
  final double amount;

  /// 아이콘과 발광에 쓰는 색.
  final Color color;

  /// 즉시 환산형의 단위 표기.
  final String unit;

  final LootRarity rarity;

  /// 아이콘의 대략적인 화면 반지름(픽셀). 그림자·발광 크기 계산에 쓴다.
  final double radius;

  /// 포션이면 사용 효과, 즉시 환산형이면 null이다.
  final PotionEffect? potion;

  /// 인벤토리에 쌓이는 포션인지 여부.
  bool get isPotion => potion != null;

  static const Map<PickupKind, PickupSpec> table = {
    // ── 회복 물약 5등급 ─────────────────────────────────────────────────
    // 회복량은 100·200·300·500·1000 다섯 뿐이고, 몸체 내구도가 10,000이라
    // 어느 등급도 판세를 뒤집지 못한다. 의도한 설계다 — 큰 체력 풀로 오래
    // 버티는 것이 주(主)이고 물약은 곁다리다.
    // 2등급 이상은 드롭 확률을 크게 낮췄다(`drop_table.dart`).
    PickupKind.nanoVial: PickupSpec(
      name: 'REPAIR VIAL',
      amount: 100,
      color: GamePalette.healGlow,
      unit: 'HP',
      rarity: LootRarity.common,
      radius: 11,
      potion: PotionEffect(heal: 100),
    ),
    PickupKind.nanoCanister: PickupSpec(
      name: 'NANO CANISTER',
      amount: 200,
      color: GamePalette.healGlow,
      unit: 'HP',
      rarity: LootRarity.uncommon,
      radius: 12,
      // 2등급에만 장갑 경화가 딸려 있다. 회복량이 아니라 이 버프가
      // 이 등급을 고르는 이유다.
      potion: PotionEffect(heal: 200, buff: BuffKind.fortify),
    ),
    PickupKind.repairCell: PickupSpec(
      name: 'REPAIR CELL',
      amount: 300,
      color: GamePalette.healGlow,
      unit: 'HP',
      rarity: LootRarity.uncommon,
      radius: 13,
      potion: PotionEffect(heal: 300),
    ),
    PickupKind.regenAmpoule: PickupSpec(
      name: 'REGEN AMPOULE',
      amount: 500,
      color: GamePalette.healGlow,
      unit: 'HP',
      rarity: LootRarity.rare,
      radius: 15,
      potion: PotionEffect(heal: 500),
    ),
    PickupKind.overhaulKit: PickupSpec(
      name: 'OVERHAUL KIT',
      amount: 1000,
      color: GamePalette.healGlow,
      unit: 'HP',
      rarity: LootRarity.rare,
      radius: 17,
      potion: PotionEffect(heal: 1000),
    ),
    PickupKind.energyCell: PickupSpec(
      name: 'ENERGY CELL',
      amount: 32,
      color: GamePalette.energyFill,
      unit: 'EN',
      rarity: LootRarity.common,
      radius: 12,
      potion: PotionEffect(energy: 55),
    ),
    PickupKind.overchargeCell: PickupSpec(
      name: 'OVERCHARGE CELL',
      amount: 75,
      color: GamePalette.playerVisor,
      unit: 'EN',
      rarity: LootRarity.rare,
      radius: 14,
      potion: PotionEffect(energy: 120, buff: BuffKind.overdrive),
    ),
    PickupKind.combatStim: PickupSpec(
      name: 'COMBAT STIM',
      amount: 0,
      color: GamePalette.robotEnergy,
      unit: '',
      rarity: LootRarity.rare,
      radius: 12,
      potion: PotionEffect(heal: 25, energy: 25, buff: BuffKind.strength),
    ),
    PickupKind.dataChip: PickupSpec(
      name: 'DATA CHIP',
      amount: 18,
      color: GamePalette.xpGlow,
      unit: 'XP',
      rarity: LootRarity.uncommon,
      radius: 10,
    ),
    PickupKind.scrapCore: PickupSpec(
      name: 'SCRAP CORE',
      amount: 40,
      color: GamePalette.robotShellLight,
      unit: 'PTS',
      rarity: LootRarity.uncommon,
      radius: 11,
    ),
  };
}

/// 파괴된 로봇이 떨어뜨리는 전리품.
///
/// 생성되면 잔해에서 튀어나오듯 포물선을 그리며 착지하고, 잠시 뒤부터
/// 플레이어 쪽으로 끌려가 자동 회수된다([Player.lootRadius] 참고).
/// 포션은 인벤토리에 쌓이고, 그 밖의 것은 즉시 환산된다.
class Pickup extends IsoEntity {
  Pickup({
    required super.grid,
    required this.kind,
    double? amount,
    Vector2? launchVelocity,
    double launchLift = 2.6,
    this.serverId,
  })  : spec = PickupSpec.table[kind]!,
        amount = amount ?? PickupSpec.table[kind]!.amount,
        _velocity = launchVelocity?.clone() ?? Vector2.zero(),
        _verticalSpeed = launchLift,
        super(z: _restZ, bodyRadius: 0.3, depthBias: 0.1);

  final PickupKind kind;
  final PickupSpec spec;

  /// 서버가 부여한 번호. 서버가 떨군 전리품이면 값이 있다.
  ///
  /// **서버가 떨군 것은 서버가 거둔다.** 무엇이 떨어졌는지가 모두에게 같아야
  /// 하는 이유는 분배 때문이다 — 각자 굴리면 같은 몹을 잡고도 서로 다른 것을
  /// 보게 되어, 누가 무엇을 가져갔는지를 두고 이야기할 수조차 없다.
  final int? serverId;

  /// 서버가 쥐고 있는 전리품인지.
  bool get isServerOwned => serverId != null;

  /// 서버에 줍기를 요청해 두었는지. 한 번만 보내기 위한 빗장이다.
  bool _pickRequested = false;

  /// 서버가 거절했다. 남의 우선권이 살아 있거나 이미 누가 가져갔다.
  ///
  /// 거절당한 뒤에도 계속 요청하면 초당 수십 번 헛되이 왕복한다. 잠시 쉬었다
  /// 다시 시도한다 — 우선권은 12 초 뒤 풀리므로 기다릴 값어치가 있다.
  double _pickBackoff = 0;

  /// 즉시 환산형에 실제로 적용될 효과량.
  final double amount;

  Color get color => spec.color;

  // ── 낙하 물리 ──────────────────────────────────────────────────────
  final Vector2 _velocity;
  double _verticalSpeed;
  int _bounces = 0;
  bool _grounded = false;

  /// 착지 후 자석이 작동하기까지의 여유. 즉시 빨려 들어가면 무엇이
  /// 떨어졌는지 보이지 않으므로 아주 짧게만 둔다.
  double _settleDelay = 0.18;

  static const double _restZ = 0.24;
  static const double _gravity = 11.0;
  static const double _bounceDamping = 0.42;
  static const int _maxBounces = 2;

  // ── 회수 ───────────────────────────────────────────────────────────
  double _magnetSpeed = 0;
  bool _collected = false;

  /// 이 거리 안으로 들어오면 회수된다(타일 단위).
  static const double _grabDistance = 0.45;

  // ── 수명 ───────────────────────────────────────────────────────────
  double _life = 0;
  static const double _lifetime = 26;
  static const double _blinkFrom = 4;

  /// 자석에 끌려가는 중인지 여부.
  bool get isBeingPulled => _magnetSpeed > 0;

  @override
  void update(double dt) {
    _life += dt;
    if (_pickBackoff > 0) _pickBackoff -= dt;
    // 서버가 쥔 것은 수명도 서버가 정한다. 여기서 지우면 아직 표에 남아 있는
    // 전리품이 내 화면에서만 사라져, 남들이 줍는 것을 보고도 나는 빈 바닥을
    // 본다.
    if (!isServerOwned && _life > _lifetime) {
      removeFromParent();
      return;
    }

    if (_grounded) {
      if (_settleDelay > 0) _settleDelay -= dt;
      // 지면에서 살짝 떠 흔들린다.
      z = _restZ + math.sin(_life * 3) * 0.055;
      _updateMagnet(dt);
      if (_collected) return;
    } else {
      _updateFall(dt);
    }

    super.update(dt);
  }

  /// 잔해에서 튀어나와 포물선을 그리며 착지한다.
  void _updateFall(double dt) {
    _verticalSpeed -= _gravity * dt;
    z += _verticalSpeed * dt;

    // 벽을 뚫고 나가지 않도록 갈 수 있는 칸으로만 민다.
    if (_velocity.length2 > 0.0001) {
      final next = grid + _velocity * dt;
      if (game.map.isWalkableAt(next.x, next.y)) {
        grid.setFrom(next);
      } else {
        _velocity.setZero();
      }
      // 공기 저항.
      _velocity.scale(math.max(0, 1 - dt * 3.2));
    }

    if (z > _restZ) return;

    // 착지: 몇 번 튕긴 뒤 멈춘다.
    z = _restZ;
    _bounces++;
    if (_bounces > _maxBounces || _verticalSpeed.abs() < 0.9) {
      _grounded = true;
      _verticalSpeed = 0;
      _velocity.setZero();
    } else {
      _verticalSpeed = -_verticalSpeed * _bounceDamping;
      _velocity.scale(0.5);
    }
  }

  /// 플레이어가 회수 반경에 들어오면 끌려가고, 닿으면 회수된다.
  void _updateMagnet(double dt) {
    final player = game.player;
    if (!player.isAlive) {
      _magnetSpeed = 0;
      return;
    }

    // 인벤토리가 가득 차면 끌려가지도, 회수되지도 않고 바닥에 남는다.
    if (spec.isPotion && !game.inventory.canAccept(kind)) {
      _magnetSpeed = 0;
      return;
    }

    final toPlayer = player.grid - grid;
    final distance = toPlayer.length;

    if (distance < _grabDistance) {
      if (isServerOwned) {
        _requestServerPick(player);
      } else {
        _collect(player);
      }
      return;
    }

    if (_settleDelay > 0) return;
    if (distance > player.lootRadius) {
      _magnetSpeed = 0;
      return;
    }

    // 끌려가기 시작하면 점점 빨라져 확실히 따라붙는다.
    _magnetSpeed = math.min(11, _magnetSpeed + dt * 26);
    grid.add(toPlayer.normalized() * _magnetSpeed * dt);
  }

  /// 서버에 줍기를 청한다. **가져갔는지는 서버가 답한다.**
  ///
  /// 낙관적으로 먼저 먹은 척하지 않는다. 하나뿐인 물건에 두 사람이 동시에 손을
  /// 뻗으면 한 명은 반드시 빈손인데, 미리 연출하면 그중 하나는 거짓이 된다 —
  /// 회복량까지 화면에 뜬 뒤 되돌리는 것이 아무 일도 없던 것보다 나쁘다.
  void _requestServerPick(Player player) {
    if (_pickRequested || _collected || _pickBackoff > 0) return;
    _pickRequested = true;

    game.presence.pickLoot(serverId!).then((taken) {
      _pickRequested = false;
      if (taken) {
        // 서버가 내 것이라 했다. 이제 효과를 낸다.
        _collect(player);
      } else {
        // 남의 우선권이거나 이미 누가 가져갔다. 표에서 사라지면 게임 본체가
        // 이 몸을 걷어 간다.
        _pickBackoff = 1.5;
        _magnetSpeed = 0;
      }
    });
  }

  void _collect(Player player) {
    if (_collected) return;

    final String label;
    if (spec.isPotion) {
      // 포션은 쓰지 않고 인벤토리에 보관한다.
      if (!game.inventory.add(kind)) return;
      label = '+ ${spec.name}';
    } else {
      switch (kind) {
        case PickupKind.dataChip:
          player.gainXp(amount.round(), showText: false);
        case PickupKind.scrapCore:
          break; // 점수 가산은 게임 본체가 처리한다.
        default:
          break;
      }
      label = '+${amount.round()} ${spec.unit}';
    }

    _collected = true;
    GameAudio.play(
      switch (kind) {
        PickupKind.nanoVial ||
        PickupKind.nanoCanister ||
        PickupKind.repairCell ||
        PickupKind.regenAmpoule ||
        PickupKind.overhaulKit ||
        PickupKind.combatStim =>
          Sfx.pickupHealth,
        PickupKind.energyCell || PickupKind.overchargeCell => Sfx.pickupEnergy,
        PickupKind.dataChip || PickupKind.scrapCore => Sfx.pickupChip,
      },
      // 희귀한 전리품일수록 또렷하게 들리도록 한다.
      volumeScale: spec.rarity == LootRarity.rare ? 1.3 : 1.0,
    );
    game.spawnEffect(
      LootText(
        grid: player.grid.clone(),
        text: label,
        color: color,
        emphasized: spec.rarity == LootRarity.rare,
      ),
    );
    game.onPickupCollected(this);
    removeFromParent();
  }

  @override
  void onRemove() {
    // 회수든 수명 만료든 목록에서 확실히 빠지도록 한다.
    game.pickups.remove(this);
    super.onRemove();
  }

  // ── 렌더링 ─────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    // 사라지기 직전 깜빡임.
    if (_lifetime - _life < _blinkFrom && (_life * 8).floor().isEven) return;

    renderShadow(canvas, spec.radius, radiusY: spec.radius * 0.5);

    final pulse = 0.7 + math.sin(_life * 5) * 0.3;
    final glowScale = switch (spec.rarity) {
      LootRarity.common => 1.0,
      LootRarity.uncommon => 1.25,
      LootRarity.rare => 1.6,
    };

    canvas.drawCircle(
      Offset.zero,
      spec.radius * 1.35 * pulse * glowScale,
      Paint()
        ..color = color.withValues(alpha: 0.35 * pulse)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 8 * glowScale),
    );

    // 희귀 등급은 발밑에 링을 하나 더 두른다.
    if (spec.rarity == LootRarity.rare) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: 46 + math.sin(_life * 4) * 6,
          height: 23 + math.sin(_life * 4) * 3,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: 0.5 * pulse),
      );
    }

    canvas.save();
    canvas.rotate(math.sin(_life * 2) * 0.25);
    drawIcon(canvas, kind, color);
    canvas.restore();
  }

  /// 전리품 아이콘을 원점 기준으로 그린다.
  ///
  /// 월드의 [Pickup]과 인벤토리 UI가 같은 그림을 쓰도록 정적 메서드로 둔다.
  static void drawIcon(Canvas canvas, PickupKind kind, Color color) {
    switch (kind) {
      // 회복 물약은 등급이 오를수록 병이 커진다. 바닥에 떨어진 것만 보고도
      // 주우러 갈 가치가 있는지 판단할 수 있어야 한다.
      case PickupKind.nanoVial:
        _drawVial(canvas, color, scale: 1.0);
      case PickupKind.nanoCanister:
        _drawVial(canvas, color, scale: 1.15);
      case PickupKind.repairCell:
        _drawVial(canvas, color, scale: 1.3);
      case PickupKind.regenAmpoule:
        _drawVial(canvas, color, scale: 1.5);
      case PickupKind.overhaulKit:
        _drawVial(canvas, color, scale: 1.75);
      case PickupKind.energyCell:
        _drawCell(canvas, color, small: true);
      case PickupKind.overchargeCell:
        _drawCell(canvas, color, small: false);
      case PickupKind.combatStim:
        _drawStim(canvas, color);
      case PickupKind.dataChip:
        _drawChip(canvas, color);
      case PickupKind.scrapCore:
        _drawCore(canvas, color);
    }
  }

  /// 나노 수리액 병. 십자 마크가 붙은 유리병 형태다.
  static void _drawVial(Canvas canvas, Color color, {double scale = 1.0}) {
    final s = scale;
    final glass = Paint()..color = const Color(0xFF13301F);

    // 병 몸통
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-7 * s, -8 * s, 14 * s, 17 * s),
        Radius.circular(4 * s),
      ),
      glass,
    );
    // 내용물
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-4.5 * s, -2 * s, 9 * s, 10 * s),
        Radius.circular(2.5 * s),
      ),
      Paint()..color = color,
    );
    // 병목과 마개
    canvas.drawRect(Rect.fromLTWH(-3 * s, -12 * s, 6 * s, 5 * s), glass);
    canvas.drawRect(
      Rect.fromLTWH(-4 * s, -14 * s, 8 * s, 2.5 * s),
      Paint()..color = color.withValues(alpha: 0.85),
    );
    // 십자 마크
    final cross = Paint()..color = color;
    canvas.drawRect(Rect.fromLTWH(-4 * s, -0.9 * s, 8 * s, 1.8 * s), cross);
    canvas.drawRect(Rect.fromLTWH(-0.9 * s, -4 * s, 1.8 * s, 8 * s), cross);

    // 2등급 이상은 눈금을 그어 한눈에 구분되게 한다.
    if (s > 1.0) {
      final tick = Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 1.2;
      canvas.drawLine(Offset(-6 * s, 2 * s), Offset(-3 * s, 2 * s), tick);
      canvas.drawLine(Offset(-6 * s, 5 * s), Offset(-3 * s, 5 * s), tick);
    }
  }

  /// 에너지 셀. 배터리 형태다.
  static void _drawCell(Canvas canvas, Color color, {required bool small}) {
    final s = small ? 1.0 : 1.3;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-7 * s, -11 * s, 14 * s, 22 * s),
        Radius.circular(3 * s),
      ),
      Paint()..color = const Color(0xFF15263A),
    );
    canvas.drawRect(
      Rect.fromLTWH(-4 * s, -8 * s, 8 * s, 16 * s),
      Paint()..color = color,
    );
    canvas.drawRect(
      Rect.fromLTWH(-3 * s, -14 * s, 6 * s, 3 * s),
      Paint()..color = color,
    );

    // 과충전 셀은 번개 표식을 얹는다.
    if (!small) {
      final bolt = Path()
        ..moveTo(1.5 * s, -7 * s)
        ..lineTo(-3 * s, 0.5 * s)
        ..lineTo(0, 0.5 * s)
        ..lineTo(-1.5 * s, 7 * s)
        ..lineTo(3 * s, -0.5 * s)
        ..lineTo(0, -0.5 * s)
        ..close();
      canvas.drawPath(bolt, Paint()..color = const Color(0xFF0B1622));
    }
  }

  /// 전투 강화제. 주사기 형태다.
  static void _drawStim(Canvas canvas, Color color) {
    final body = Paint()..color = const Color(0xFF2A1A18);

    // 약통
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-5, -10, 10, 18),
        const Radius.circular(2),
      ),
      body,
    );
    canvas.drawRect(
      const Rect.fromLTWH(-3, -6, 6, 12),
      Paint()..color = color,
    );
    // 손잡이
    canvas.drawRect(const Rect.fromLTWH(-8, -12, 16, 3), body);
    // 피스톤
    canvas.drawRect(
      const Rect.fromLTWH(-1.5, -17, 3, 6),
      Paint()..color = color.withValues(alpha: 0.9),
    );
    // 바늘
    canvas.drawRect(
      const Rect.fromLTWH(-1, 8, 2, 7),
      Paint()..color = GamePalette.robotShellLight,
    );
  }

  /// 데이터 칩. 경험치로 환산되는 회로 조각이다.
  static void _drawChip(Canvas canvas, Color color) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-9, -9, 18, 18),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFF241C3A),
    );
    canvas.drawRect(
      const Rect.fromLTWH(-4, -4, 8, 8),
      Paint()..color = color,
    );
    final pin = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1.6;
    for (var i = -1; i <= 1; i++) {
      final offset = i * 5.0;
      canvas.drawLine(Offset(offset, -13), Offset(offset, -9), pin);
      canvas.drawLine(Offset(offset, 9), Offset(offset, 13), pin);
      canvas.drawLine(Offset(-13, offset), Offset(-9, offset), pin);
      canvas.drawLine(Offset(9, offset), Offset(13, offset), pin);
    }
  }

  /// 스크랩 코어. 로봇 동력원의 잔해로 점수가 된다.
  static void _drawCore(Canvas canvas, Color color) {
    // 육각형 껍데기
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = math.pi / 3 * i - math.pi / 2;
      final point = Offset(math.cos(angle), math.sin(angle)) * 10;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, Paint()..color = GamePalette.robotShellDark);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = GamePalette.robotShellLight,
    );
    // 중심 코어
    canvas.drawCircle(Offset.zero, 4.2, Paint()..color = color);
    canvas.drawCircle(
      Offset.zero,
      6.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withValues(alpha: 0.6),
    );
  }
}
