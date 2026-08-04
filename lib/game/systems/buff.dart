import 'dart:ui';

import '../palette.dart';

/// 포션을 마셨을 때 일정 시간 유지되는 강화 효과.
enum BuffKind {
  /// 전투 강화제. 공격력이 크게 오른다.
  strength,

  /// 과충전. 공격력이 오르고 에너지가 빠르게 찬다.
  overdrive,

  /// 장갑 경화. 받는 피해가 줄어든다.
  fortify,
}

/// 버프 종류별 고정 정보.
class BuffSpec {
  const BuffSpec({
    required this.label,
    required this.color,
    required this.duration,
    this.damageMultiplier = 1.0,
    this.speedMultiplier = 1.0,
    this.damageTakenMultiplier = 1.0,
    this.energyRegenMultiplier = 1.0,
  });

  /// HUD에 표시할 짧은 이름.
  final String label;

  final Color color;

  /// 지속 시간(초).
  final double duration;

  /// 근접·원거리 피해량 배율.
  final double damageMultiplier;

  /// 이동 속도 배율.
  final double speedMultiplier;

  /// 받는 피해 배율. 1보다 작으면 그만큼 덜 아프다.
  final double damageTakenMultiplier;

  /// 에너지 자연 회복 배율.
  final double energyRegenMultiplier;

  static const Map<BuffKind, BuffSpec> table = {
    BuffKind.strength: BuffSpec(
      label: 'STR',
      color: GamePalette.robotEnergy,
      duration: 12,
      damageMultiplier: 1.6,
      speedMultiplier: 1.15,
    ),
    BuffKind.overdrive: BuffSpec(
      label: 'OVR',
      color: GamePalette.playerVisor,
      duration: 10,
      damageMultiplier: 1.3,
      energyRegenMultiplier: 2.5,
    ),
    BuffKind.fortify: BuffSpec(
      label: 'FRT',
      color: GamePalette.healGlow,
      duration: 8,
      damageTakenMultiplier: 0.65,
    ),
  };
}

/// 현재 걸려 있는 버프 하나.
class ActiveBuff {
  ActiveBuff(this.kind) : remaining = BuffSpec.table[kind]!.duration;

  final BuffKind kind;

  /// 남은 시간(초).
  double remaining;

  BuffSpec get spec => BuffSpec.table[kind]!;

  /// 0(막 끝남) ~ 1(방금 걸림) 사이의 잔여 비율.
  double get ratio => (remaining / spec.duration).clamp(0.0, 1.0);
}

/// 플레이어에게 걸린 버프들을 모아 관리한다.
///
/// 같은 종류를 다시 마시면 지속 시간이 갱신되고, 배율은 서로 곱해진다.
class BuffSet {
  final Map<BuffKind, ActiveBuff> _active = {};

  /// 지금 걸려 있는 버프 목록(남은 시간이 긴 순).
  List<ActiveBuff> get active {
    final list = _active.values.toList()
      ..sort((a, b) => b.remaining.compareTo(a.remaining));
    return list;
  }

  bool get isEmpty => _active.isEmpty;

  bool has(BuffKind kind) => _active.containsKey(kind);

  /// [kind] 버프를 건다. 이미 있으면 지속 시간을 다시 채운다.
  void apply(BuffKind kind) {
    final existing = _active[kind];
    if (existing != null) {
      existing.remaining = BuffSpec.table[kind]!.duration;
      return;
    }
    _active[kind] = ActiveBuff(kind);
  }

  /// 시간을 흘려보내고 끝난 버프를 걷어낸다.
  void update(double dt) {
    if (_active.isEmpty) return;
    _active.removeWhere((_, buff) {
      buff.remaining -= dt;
      return buff.remaining <= 0;
    });
  }

  void clear() => _active.clear();

  double get damageMultiplier => _product((spec) => spec.damageMultiplier);
  double get speedMultiplier => _product((spec) => spec.speedMultiplier);
  double get damageTakenMultiplier =>
      _product((spec) => spec.damageTakenMultiplier);
  double get energyRegenMultiplier =>
      _product((spec) => spec.energyRegenMultiplier);

  double _product(double Function(BuffSpec spec) pick) {
    var value = 1.0;
    for (final buff in _active.values) {
      value *= pick(buff.spec);
    }
    return value;
  }
}
