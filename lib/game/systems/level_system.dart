import 'dart:math' as math;

/// 레벨업 한 번에 오르는 스탯 상승치.
class LevelGains {
  const LevelGains({
    required this.maxHp,
    required this.maxEnergy,
    required this.meleeDamage,
    required this.rangedDamage,
    required this.moveSpeed,
    required this.milestone,
  });

  final double maxHp;
  final double maxEnergy;
  final double meleeDamage;
  final double rangedDamage;
  final double moveSpeed;

  /// 5레벨 단위의 강화 구간인지 여부.
  final bool milestone;
}

/// 경험치 곡선과 성장 규칙을 모아 둔 정적 테이블.
///
/// 플레이어의 성장은 전부 이 클래스를 거치므로 밸런스 조정은 여기만 고치면 된다.
class LevelSystem {
  LevelSystem._();

  static const int maxLevel = 30;
  static const int _baseXp = 60;
  static const double _curve = 1.22;

  /// 레벨 차이에 따른 경험치 감소의 하한.
  ///
  /// 이 하한이 없으면 후반 웨이브의 보상 증가분보다 감소분이 커져서
  /// 20레벨 부근에서 성장이 사실상 멈춘다.
  static const double _minFalloff = 0.55;

  /// [level]에서 다음 레벨까지 필요한 경험치. 만렙이면 더 이상 오르지 않는다.
  static int xpToNext(int level) {
    if (level >= maxLevel) return 1 << 30;
    return (_baseXp * math.pow(_curve, level - 1)).round();
  }

  /// [level]로 올라설 때 얻는 성장치. 5레벨마다 상승폭이 커진다.
  static LevelGains gainsFor(int level) {
    final milestone = level % 5 == 0;
    return LevelGains(
      maxHp: milestone ? 34 : 18,
      maxEnergy: milestone ? 14 : 8,
      meleeDamage: milestone ? 8.0 : 4.5,
      rangedDamage: milestone ? 5.5 : 3.0,
      // 이동 속도는 강화 구간에서만 아주 조금 오른다.
      moveSpeed: milestone ? 0.08 : 0.0,
      milestone: milestone,
    );
  }

  /// 적 한 기의 기본 경험치 가치.
  ///
  /// [hpScale]은 웨이브 강화 배율이라 후반 웨이브의 적일수록 가치가 높다.
  static int enemyXpValue(int baseXp, {double hpScale = 1.0}) =>
      math.max(1, (baseXp * (0.7 + hpScale * 0.3)).round());

  /// [playerLevel]인 플레이어가 [value] 가치의 적을 처치했을 때 실제로 얻는 경험치.
  ///
  /// 레벨이 오를수록 같은 적의 가치는 떨어지지만 [_minFalloff] 아래로는 내려가지 않는다.
  static int killXp(int value, {required int playerLevel}) {
    final falloff = math.max(
      _minFalloff,
      math.pow(0.97, math.max(0, playerLevel - 1)).toDouble(),
    );
    return math.max(1, (value * falloff).round());
  }
}
