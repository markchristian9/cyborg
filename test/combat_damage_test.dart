import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:actionrpg/game/entities/enemy.dart';
import 'package:actionrpg/game/entities/pickup.dart';
import 'package:actionrpg/game/entities/player.dart';
import 'package:actionrpg/game/systems/drop_table.dart';
import 'package:actionrpg/game/systems/level_system.dart';
import 'package:actionrpg/game/systems/monster_codex.dart';

/// 전투 수치의 불변식.
///
/// 규격: **방어력 0인 플레이어가 레벨 N 몬스터에게 맞으면 정확히 N 이 깎인다.**
/// 이 파일은 그 항등식이 어느 경로에서도 배율에 오염되지 않았음을 못 박는다.
/// 피해 수식에 배율이 다시 끼어들면 화면 표시는 반올림되어 그대로 보이므로
/// 눈으로는 발견되지 않는다 — 그래서 테스트가 유일한 감시 장치다.
void main() {
  group('몬스터 피해는 레벨과 항등이다', () {
    test('도감의 모든 레벨에서 공격력이 레벨과 같다', () {
      for (var level = 1; level <= MonsterCodex.maxLevel; level++) {
        final species = MonsterCodex.byLevel(level);
        expect(
          species.stats.damage,
          level.toDouble(),
          reason: '레벨 $level (${species.name}) 의 공격력이 레벨과 다르다',
        );
      }
    });

    test('요구 사례 — 3레벨은 3, 10레벨은 10', () {
      expect(MonsterCodex.byLevel(3).stats.damage, 3.0);
      expect(MonsterCodex.byLevel(10).stats.damage, 10.0);
    });

    test('계통이 달라도 같은 레벨이면 공격력이 같다', () {
      // 계통(drone·walker·siege·sovereign)별 배율이 남아 있으면 여기서 깨진다.
      final byBuild = <MonsterBuild, Set<double>>{};
      for (final species in MonsterCodex.all) {
        byBuild
            .putIfAbsent(species.build, () => <double>{})
            .add(species.stats.damage - species.level);
      }
      for (final entry in byBuild.entries) {
        expect(
          entry.value,
          {0.0},
          reason: '${entry.key} 계통에 피해 배율이 남아 있다',
        );
      }
    });

    test('개체가 되어도 공격력에 편차가 붙지 않는다', () {
      // 체력에는 개체 편차가 있지만 피해에는 없어야 한다.
      final species = MonsterCodex.byLevel(7);
      final enemy = Enemy(
        species: species,
        grid: Vector2.zero(),
        hpMultiplier: 1.4,
      );
      expect(enemy.stats.damage, 7.0);
      expect(enemy.level, 7);
      // 체력 배율은 살아 있어야 한다.
      expect(enemy.maxHp, closeTo(species.stats.maxHp * 1.4, 0.001));
    });
  });

  group('방어력', () {
    test('방어력 0이면 들어온 피해가 그대로 통과한다', () {
      for (final amount in [1.0, 3.0, 10.0, 200.0]) {
        expect(Player.damageAfterDefense(amount, 0), amount);
      }
    });

    test('방어력이 상수와 같으면 피해가 절반이 된다', () {
      expect(
        Player.damageAfterDefense(100, Player.defenseConstant),
        closeTo(50, 0.001),
      );
    });

    test('방어력이 아무리 높아도 피해가 0이 되지는 않는다', () {
      // 감산형이었다면 여기서 0 또는 음수가 된다. 저레벨 구역이 통째로
      // 무해해지는 절벽을 만들지 않기 위한 성질이다.
      final taken = Player.damageAfterDefense(3, 100000);
      expect(taken, greaterThan(0));
    });

    test('방어력이 오를수록 받는 피해가 단조 감소한다', () {
      var previous = double.infinity;
      for (var defense = 0.0; defense <= 500; defense += 25) {
        final taken = Player.damageAfterDefense(50, defense);
        expect(taken, lessThan(previous));
        previous = taken;
      }
    });
  });

  group('회복 물약 5등급', () {
    /// 등급 오름차순. 인벤토리가 소형부터 쓰는 순서이기도 하다.
    const grades = <PickupKind, double>{
      PickupKind.nanoVial: 100,
      PickupKind.nanoCanister: 200,
      PickupKind.repairCell: 300,
      PickupKind.regenAmpoule: 500,
      PickupKind.overhaulKit: 1000,
    };

    test('회복량은 100·200·300·500·1000 다섯 뿐이다', () {
      for (final entry in grades.entries) {
        final spec = PickupSpec.table[entry.key]!;
        expect(
          spec.potion?.heal,
          entry.value,
          reason: '${spec.name} 의 회복량이 규격과 다르다',
        );
      }
    });

    test('그 밖에 체력을 회복시키는 전리품은 강화제뿐이다', () {
      // 5등급 밖에서 회복이 새어 나오면 "물약은 곁다리" 라는 설계가 무너진다.
      final healers = PickupSpec.table.entries
          .where((e) => (e.value.potion?.heal ?? 0) > 0)
          .map((e) => e.key)
          .toSet();
      expect(healers, {...grades.keys, PickupKind.combatStim});
    });

    test('어느 등급도 1레벨 최대 체력의 10%를 넘지 못한다', () {
      // 물약 한 병으로 판세가 뒤집히지 않아야 한다.
      for (final heal in grades.values) {
        expect(heal / Player.baseMaxHp, lessThanOrEqualTo(0.1));
      }
    });

    test('2등급 이상은 잡몹에게서 거의 나오지 않는다', () {
      // "200 이상은 드롭 확률을 매우 낮게" 라는 요구를 못 박는다.
      for (final table in [DropTables.scout, DropTables.sentry]) {
        for (final entry in table.entries) {
          final heal = PickupSpec.table[entry.kind]!.potion?.heal ?? 0;
          if (heal >= 200) {
            expect(
              entry.chance,
              lessThan(0.03),
              reason: '${entry.kind} 의 잡몹 드롭 확률이 너무 높다',
            );
          }
        }
      }
    });

    test('등급이 오를수록 드롭이 귀해진다', () {
      double chanceIn(DropTable table, PickupKind kind) => table.entries
          .where((e) => e.kind == kind)
          .map((e) => e.chance)
          .fold(0.0, (a, b) => a + b);

      var previous = double.infinity;
      for (final kind in grades.keys) {
        final chance = chanceIn(DropTables.heavy, kind);
        expect(chance, lessThan(previous), reason: '$kind 가 앞 등급보다 흔하다');
        previous = chance;
      }
    });
  });

  group('체력 성장', () {
    test('레벨업 한 번에 최대 체력이 1,000 늘어난다', () {
      // 강화 구간(5의 배수)이라고 더 주지 않는다.
      for (var level = 2; level <= 200; level++) {
        expect(
          LevelSystem.gainsFor(level).maxHp,
          1000,
          reason: '레벨 $level 의 체력 성장폭이 1,000이 아니다',
        );
      }
    });

    test('레벨 N의 최대 체력은 10,000 + (N-1) × 1,000 이다', () {
      var maxHp = Player.baseMaxHp;
      for (var level = 2; level <= 50; level++) {
        maxHp += LevelSystem.gainsFor(level).maxHp;
        expect(
          maxHp,
          Player.baseMaxHp + (level - 1) * 1000,
          reason: '레벨 $level 의 누적 최대 체력이 어긋난다',
        );
      }
    });
  });
}
