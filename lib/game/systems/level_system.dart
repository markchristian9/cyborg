import 'dart:math' as math;

/// 레벨업 한 번에 오르는 스탯 상승치.
class LevelGains {
  const LevelGains({
    required this.maxHp,
    required this.maxEnergy,
    required this.maxMp,
    required this.meleeDamage,
    required this.rangedDamage,
    required this.moveSpeed,
    required this.milestone,
  });

  final double maxHp;
  final double maxEnergy;
  final double maxMp;
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

  // ── 성장 곡선 ─────────────────────────────────────────────────────────
  //
  // 곡선은 **정수 산술만** 쓴다. 예전에는 `60 × 1.22^(level-1)` 이라는 지수식
  // 이었는데, 서버와 클라이언트가 각자 계산하면 부동소수 마지막 자리가 갈릴 수
  // 있어 고정 표로 못 박아야 했다. 정수 다항식이면 두 언어가 같은 정수 연산을
  // 하므로 어긋날 여지가 없고, 표 없이 만렙까지 뻗을 수 있다.
  //
  // 서버 `spacetimedb/src/leaderboard.rs` 가 같은 상수로 같은 식을 계산한다.
  // 곡선을 바꾸려면 양쪽을 함께 고친다 — 양쪽 테스트가 같은 기대값을 검증하므로
  // 한쪽만 고치면 즉시 깨진다.

  /// 도달할 수 있는 최고 레벨. 서버 `MAX_LEVEL` 과 같아야 한다.
  static const int maxLevel = 999;

  /// 1 → 2 레벨에 드는 경험치.
  static const int baseXp = 60;

  /// 레벨마다 선형으로 붙는 몫.
  static const int linearXp = 30;

  /// 레벨의 제곱에 비례해 붙는 몫.
  static const int quadraticXp = 3;

  /// 이 레벨을 넘어서면 곡선이 한 번 더 꺾인다.
  static const int steepFrom = 70;

  /// [steepFrom]을 넘은 뒤 레벨마다 선형으로 더 붙는 몫.
  ///
  /// 이 항이 있어야 71레벨에서 **즉시** 무거워진 것이 느껴진다. 제곱항만
  /// 더하면 경계 직후에는 몇 십밖에 차이 나지 않아 체감되지 않는다.
  static const int steepLinearXp = 500;

  /// [steepFrom]을 넘은 뒤 제곱에 비례해 더 붙는 몫. 후반을 무겁게 만든다.
  static const int steepQuadraticXp = 8;

  /// 누적 경험치의 상한. 서버 `MAX_TOTAL_XP`(= u32 최댓값)와 같아야 한다.
  ///
  /// 만렙까지 필요한 누적이 33억 5762만이고 여기에 9억 3734만이 남는다.
  /// 그 여유가 만렙 도달자끼리의 경쟁 공간이다.
  static const int maxTotalXp = 4294967295;

  /// 레벨 차이에 따른 경험치 감소의 하한.
  ///
  /// 이 하한이 없으면 후반 웨이브의 보상 증가분보다 감소분이 커져서
  /// 20레벨 부근에서 성장이 사실상 멈춘다.
  static const double _minFalloff = 0.55;

  /// [level]에서 다음 레벨까지 필요한 경험치.
  ///
  /// 레벨 1은 60, 10은 573, 70은 16,413. 71부터 가속이 붙어 100은 54,633,
  /// 500은 2,456,233, 만렙 999는 10,386,840이다.
  static int xpToNext(int level) {
    final lv = level.clamp(1, maxLevel);
    final n = lv - 1;
    var need = baseXp + linearXp * n + quadraticXp * n * n;

    if (lv > steepFrom) {
      final j = lv - steepFrom;
      need += steepLinearXp * j + steepQuadraticXp * j * j;
    }
    return need;
  }

  /// 레벨 [level]에 도달하는 데 필요한 누적 경험치.
  ///
  /// [xpToNext]를 1부터 `level-1`까지 더한 값이며 닫힌 식으로 계산한다.
  /// 등차수열 합과 사각뿔수 공식이라 나눗셈이 항상 정확히 떨어진다.
  static int totalXpForLevel(int level) {
    if (level <= 1) return 0;
    final lv = math.min(level, maxLevel);
    final n = lv - 1; // 더할 항의 개수

    var total = baseXp * n +
        linearXp * (n * (n - 1) ~/ 2) +
        quadraticXp * ((n - 1) * n * (2 * n - 1) ~/ 6);

    // 가속 구간은 71레벨분부터 더해진다.
    if (lv > steepFrom + 1) {
      final m = lv - steepFrom - 1;
      total += steepLinearXp * (m * (m + 1) ~/ 2) +
          steepQuadraticXp * (m * (m + 1) * (2 * m + 1) ~/ 6);
    }
    return total;
  }

  /// 누적 경험치가 [total]일 때의 레벨.
  ///
  /// [totalXpForLevel]의 역함수다. 닫힌 식 대신 이진 탐색을 쓰는 이유는
  /// 정확성 때문이다 — 세제곱근을 부동소수로 구하면 경계 레벨에서 1씩 어긋날
  /// 수 있고, 그 어긋남이 서버와 클라이언트에서 다르면 "레벨이 화면마다 다른"
  /// 증상이 된다. 정수 비교만 쓰면 두 곳이 반드시 같은 답을 낸다.
  static int levelForTotalXp(int total) {
    var low = 1;
    var high = maxLevel;
    while (low < high) {
      final mid = low + (high - low + 1) ~/ 2;
      if (totalXpForLevel(mid) <= total) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }

  /// 누적 경험치에서 현재 레벨 안의 진행도를 구한다.
  ///
  /// 만렙에서는 "만렙에 도달한 뒤 더 쌓은 양"이 된다. 더 오를 레벨이 없으니
  /// 게이지로는 의미가 없지만, 만렙끼리의 순위를 가르는 값이다.
  static int progressWithin(int total) =>
      total - totalXpForLevel(levelForTotalXp(total));

  /// [level]로 올라설 때 얻는 성장치. 5레벨마다 상승폭이 커진다.
  static LevelGains gainsFor(int level) {
    final milestone = level % 5 == 0;
    return LevelGains(
      // 1레벨 내구도 10,000에서 레벨마다 정확히 1,000씩 늘어난다.
      // 강화 구간이라고 더 주지 않는다 — "레벨업 한 번에 +1,000" 이라는
      // 규칙이 플레이어에게 그대로 읽히는 편이 낫다.
      // 레벨 N의 최대 체력 = 10,000 + (N-1) × 1,000.
      maxHp: 1000,
      maxEnergy: milestone ? 14 : 8,
      // 마력도 체력과 같은 자릿수로 굴러간다. 만렙 30에서 최대 마력은
      // 5,000 + 29 × 600 = 22,400이 된다.
      maxMp: 600,
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
