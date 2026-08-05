import 'dart:math' as math;

import 'monster_codex.dart';
import '../entities/pickup.dart';

/// 드롭 테이블의 한 줄. 각 항목은 서로 독립적으로 굴린다.
class DropEntry {
  const DropEntry(
    this.kind, {
    required this.chance,
    this.minCount = 1,
    this.maxCount = 1,
    this.amountScale = 1.0,
  });

  /// 떨어질 전리품 종류.
  final PickupKind kind;

  /// 이 항목이 나올 확률(0~1). 1이면 확정 드롭이다.
  final double chance;

  /// 당첨되었을 때 떨어지는 최소/최대 개수.
  final int minCount;
  final int maxCount;

  /// [PickupSpec.amount]에 곱해지는 효과량 배율.
  final double amountScale;
}

/// 실제로 굴려서 결정된 드롭 하나.
class DropResult {
  const DropResult(this.kind, this.amount);

  final PickupKind kind;
  final double amount;
}

/// 대상 하나가 파괴되었을 때 굴리는 드롭 표.
class DropTable {
  const DropTable(this.entries, {this.maxDrops = 4});

  final List<DropEntry> entries;

  /// 한 번에 떨어질 수 있는 최대 개수. 화면이 전리품으로 덮이지 않게 막는다.
  final int maxDrops;

  /// 표를 굴려 떨어질 전리품 목록을 만든다.
  ///
  /// [luck]은 확률에 더해지는 보너스로, 후반 웨이브일수록 조금 후해진다.
  /// [amountMultiplier]는 효과량 전체에 곱해진다.
  List<DropResult> roll(
    math.Random rng, {
    double luck = 0,
    double amountMultiplier = 1.0,
  }) {
    final results = <DropResult>[];

    for (final entry in entries) {
      if (results.length >= maxDrops) break;
      if (rng.nextDouble() >= (entry.chance + luck).clamp(0.0, 1.0)) continue;

      final span = entry.maxCount - entry.minCount;
      final count = entry.minCount + (span > 0 ? rng.nextInt(span + 1) : 0);
      final base = PickupSpec.table[entry.kind]!.amount;

      for (var i = 0; i < count && results.length < maxDrops; i++) {
        // 같은 종류라도 회수량이 조금씩 달라 단조롭지 않게 한다.
        final jitter = 0.85 + rng.nextDouble() * 0.3;
        results.add(
          DropResult(
            entry.kind,
            base * entry.amountScale * amountMultiplier * jitter,
          ),
        );
      }
    }

    return results;
  }
}

/// 이 게임에서 쓰는 모든 드롭 표.
///
/// 밸런스 조정은 이 파일만 고치면 된다.
abstract final class DropTables {
  // ── 회복 물약 드롭 정책 ───────────────────────────────────────────────
  //
  // 1등급(100 HP)만 흔하게 나온다. 2등급(200) 이상은 **의도적으로 매우 드물다** —
  // 회복은 물약에 기대는 것이 아니라 큰 체력 풀로 버티는 것이 이 게임의
  // 설계이기 때문이다. 상위 등급은 "운 좋으면 나오는 보너스"이지
  // 사냥 지속 시간을 좌우하는 자원이 아니다.
  //
  // 잡몹 기준 기대 확률: 200 → 2%, 300 → 0.8%, 500 → 0.2%, 1000 → 0.05%

  /// 정찰 드론. 값싼 잡몹이라 회복류 위주로 조금만 떨군다.
  static const scout = DropTable(
    [
      DropEntry(PickupKind.nanoVial, chance: 0.16),
      DropEntry(PickupKind.nanoCanister, chance: 0.012),
      DropEntry(PickupKind.energyCell, chance: 0.20),
      DropEntry(PickupKind.dataChip, chance: 0.12),
    ],
    maxDrops: 2,
  );

  /// 순찰 보행 로봇. 표준적인 드롭.
  static const sentry = DropTable(
    [
      DropEntry(PickupKind.nanoVial, chance: 0.22),
      DropEntry(PickupKind.nanoCanister, chance: 0.02),
      DropEntry(PickupKind.repairCell, chance: 0.008),
      DropEntry(PickupKind.energyCell, chance: 0.24),
      DropEntry(PickupKind.dataChip, chance: 0.18),
      DropEntry(PickupKind.scrapCore, chance: 0.10),
    ],
    maxDrops: 3,
  );

  /// 중장갑 메크. 단단한 만큼 보상이 두둑하다.
  static const heavy = DropTable(
    [
      DropEntry(PickupKind.nanoVial, chance: 0.30, maxCount: 2),
      DropEntry(PickupKind.nanoCanister, chance: 0.035),
      DropEntry(PickupKind.repairCell, chance: 0.015),
      DropEntry(PickupKind.regenAmpoule, chance: 0.004),
      DropEntry(PickupKind.overhaulKit, chance: 0.001),
      DropEntry(PickupKind.energyCell, chance: 0.32),
      DropEntry(PickupKind.dataChip, chance: 0.26),
      DropEntry(PickupKind.scrapCore, chance: 0.20),
    ],
    maxDrops: 4,
  );

  /// 지휘 유닛(보스). 전부 확정 드롭이다.
  static const commander = DropTable(
    [
      DropEntry(PickupKind.nanoCanister, chance: 1, minCount: 2, maxCount: 2),
      // 구역 보스만이 상위 등급을 기대할 수 있는 자리다. 그래도 확정은 아니다.
      DropEntry(PickupKind.repairCell, chance: 0.35),
      DropEntry(PickupKind.regenAmpoule, chance: 0.08),
      DropEntry(PickupKind.overhaulKit, chance: 0.02),
      DropEntry(PickupKind.overchargeCell, chance: 1),
      DropEntry(PickupKind.energyCell, chance: 1, maxCount: 2),
      DropEntry(PickupKind.dataChip, chance: 1, minCount: 2, maxCount: 3),
      DropEntry(PickupKind.scrapCore, chance: 1, minCount: 2, maxCount: 3),
    ],
    maxDrops: 10,
  );

  /// 파괴 가능한 보급 상자.
  static const crate = DropTable(
    [
      DropEntry(PickupKind.nanoVial, chance: 0.42),
      DropEntry(PickupKind.energyCell, chance: 0.46),
      DropEntry(PickupKind.dataChip, chance: 0.10),
    ],
    maxDrops: 2,
  );

  /// [kind]에 해당하는 적의 드롭 표.
  static DropTable forEnemy(MonsterBuild build) => switch (build) {
        MonsterBuild.drone => scout,
        MonsterBuild.walker => sentry,
        MonsterBuild.siege => heavy,
        MonsterBuild.sovereign => commander,
      };
}
