import 'dart:math' as math;

import 'package:actionrpg/game/entities/enemy.dart';
import 'package:actionrpg/game/entities/pickup.dart';
import 'package:actionrpg/game/systems/buff.dart';
import 'package:actionrpg/game/systems/drop_table.dart';
import 'package:actionrpg/game/systems/inventory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DropTable', () {
    test('확률 0인 항목은 절대 나오지 않는다', () {
      const table = DropTable([DropEntry(PickupKind.nanoVial, chance: 0)]);
      for (var seed = 0; seed < 50; seed++) {
        expect(table.roll(math.Random(seed)), isEmpty);
      }
    });

    test('확률 1인 항목은 항상 나온다', () {
      const table = DropTable([DropEntry(PickupKind.nanoVial, chance: 1)]);
      for (var seed = 0; seed < 50; seed++) {
        final results = table.roll(math.Random(seed));
        expect(results, hasLength(1));
        expect(results.single.kind, PickupKind.nanoVial);
      }
    });

    test('maxDrops를 넘겨 떨어지지 않는다', () {
      const table = DropTable(
        [
          DropEntry(PickupKind.nanoVial, chance: 1, minCount: 5, maxCount: 5),
          DropEntry(PickupKind.energyCell, chance: 1, minCount: 5, maxCount: 5),
        ],
        maxDrops: 3,
      );
      expect(table.roll(math.Random(7)), hasLength(3));
    });

    test('개수는 min~max 범위 안에 들어간다', () {
      const table = DropTable(
        [DropEntry(PickupKind.dataChip, chance: 1, minCount: 2, maxCount: 4)],
        maxDrops: 10,
      );
      for (var seed = 0; seed < 100; seed++) {
        final count = table.roll(math.Random(seed)).length;
        expect(count, inInclusiveRange(2, 4));
      }
    });

    test('luck은 확률을 올리고 1을 넘지 않는다', () {
      const table = DropTable([DropEntry(PickupKind.nanoVial, chance: 0.9)]);
      // luck을 크게 주면 어떤 시드에서도 반드시 나온다.
      for (var seed = 0; seed < 50; seed++) {
        expect(table.roll(math.Random(seed), luck: 1.0), hasLength(1));
      }
    });

    test('amountMultiplier가 회수량에 반영된다', () {
      const table = DropTable([DropEntry(PickupKind.dataChip, chance: 1)]);
      final base = PickupSpec.table[PickupKind.dataChip]!.amount;
      final result = table.roll(math.Random(3), amountMultiplier: 2).single;
      // 지터(0.85~1.15)가 곱해지므로 범위로 확인한다.
      expect(result.amount, inInclusiveRange(base * 2 * 0.85, base * 2 * 1.15));
    });

    test('모든 적 종류에 드롭 표가 있다', () {
      for (final kind in EnemyKind.values) {
        expect(DropTables.forEnemy(kind).entries, isNotEmpty);
      }
    });

    test('보스는 확정 드롭이라 항상 무언가 떨군다', () {
      for (var seed = 0; seed < 30; seed++) {
        final results = DropTables.commander.roll(math.Random(seed));
        expect(results, isNotEmpty);
      }
    });
  });

  group('Inventory', () {
    test('포션은 담기고 즉시 환산형은 담기지 않는다', () {
      final inventory = Inventory();
      expect(inventory.add(PickupKind.nanoVial), isTrue);
      expect(inventory.add(PickupKind.dataChip), isFalse);
      expect(inventory.countOf(PickupKind.nanoVial), 1);
      expect(inventory.countOf(PickupKind.dataChip), 0);
    });

    test('같은 종류는 한 칸에 쌓인다', () {
      final inventory = Inventory();
      inventory
        ..add(PickupKind.energyCell)
        ..add(PickupKind.energyCell)
        ..add(PickupKind.energyCell);
      expect(inventory.slots, hasLength(1));
      expect(inventory.countOf(PickupKind.energyCell), 3);
      expect(inventory.totalCount, 3);
    });

    test('스택 한도를 넘으면 더 받지 않는다', () {
      final inventory = Inventory(maxStack: 2);
      expect(inventory.add(PickupKind.nanoVial), isTrue);
      expect(inventory.add(PickupKind.nanoVial), isTrue);
      expect(inventory.canAccept(PickupKind.nanoVial), isFalse);
      expect(inventory.add(PickupKind.nanoVial), isFalse);
      expect(inventory.countOf(PickupKind.nanoVial), 2);
    });

    test('칸이 다 차면 새 종류를 받지 않는다', () {
      final inventory = Inventory(slotCount: 2);
      inventory
        ..add(PickupKind.nanoVial)
        ..add(PickupKind.energyCell);
      expect(inventory.canAccept(PickupKind.combatStim), isFalse);
      expect(inventory.add(PickupKind.combatStim), isFalse);
      // 이미 가진 종류는 계속 받을 수 있다.
      expect(inventory.canAccept(PickupKind.nanoVial), isTrue);
    });

    test('bestHealingPotion은 소형 회복 포션을 먼저 고른다', () {
      final inventory = Inventory();
      expect(inventory.bestHealingPotion(), isNull);
      inventory.add(PickupKind.nanoCanister);
      expect(inventory.bestHealingPotion(), PickupKind.nanoCanister);
      inventory.add(PickupKind.nanoVial);
      expect(inventory.bestHealingPotion(), PickupKind.nanoVial);
    });

    test('clear로 전부 비운다', () {
      final inventory = Inventory()..add(PickupKind.nanoVial);
      inventory.clear();
      expect(inventory.isEmpty, isTrue);
      expect(inventory.totalCount, 0);
    });
  });

  group('BuffSet', () {
    test('버프를 걸면 배율이 곱해진다', () {
      final buffs = BuffSet()..apply(BuffKind.strength);
      final spec = BuffSpec.table[BuffKind.strength]!;
      expect(buffs.damageMultiplier, spec.damageMultiplier);
      expect(buffs.speedMultiplier, spec.speedMultiplier);
    });

    test('여러 버프의 배율은 서로 곱해진다', () {
      final buffs = BuffSet()
        ..apply(BuffKind.strength)
        ..apply(BuffKind.overdrive);
      final expected = BuffSpec.table[BuffKind.strength]!.damageMultiplier *
          BuffSpec.table[BuffKind.overdrive]!.damageMultiplier;
      expect(buffs.damageMultiplier, closeTo(expected, 1e-9));
    });

    test('시간이 지나면 만료되고 배율이 1로 돌아온다', () {
      final buffs = BuffSet()..apply(BuffKind.fortify);
      expect(buffs.has(BuffKind.fortify), isTrue);

      buffs.update(BuffSpec.table[BuffKind.fortify]!.duration + 0.1);
      expect(buffs.isEmpty, isTrue);
      expect(buffs.damageTakenMultiplier, 1.0);
    });

    test('같은 버프를 다시 걸면 지속 시간이 갱신된다', () {
      final buffs = BuffSet()..apply(BuffKind.strength);
      final duration = BuffSpec.table[BuffKind.strength]!.duration;

      buffs.update(duration - 1);
      buffs.apply(BuffKind.strength);
      expect(buffs.active.single.remaining, closeTo(duration, 1e-9));

      // 갱신했으므로 원래 만료 시점을 지나도 살아 있다.
      buffs.update(2);
      expect(buffs.has(BuffKind.strength), isTrue);
    });

    test('버프가 없으면 모든 배율이 1이다', () {
      final buffs = BuffSet();
      expect(buffs.damageMultiplier, 1.0);
      expect(buffs.speedMultiplier, 1.0);
      expect(buffs.damageTakenMultiplier, 1.0);
      expect(buffs.energyRegenMultiplier, 1.0);
    });
  });

  group('PickupSpec', () {
    test('모든 종류에 스펙이 정의되어 있다', () {
      for (final kind in PickupKind.values) {
        expect(PickupSpec.table[kind], isNotNull, reason: '$kind');
      }
    });

    test('포션은 효과가 있고 즉시 환산형은 없다', () {
      const potions = [
        PickupKind.nanoVial,
        PickupKind.nanoCanister,
        PickupKind.energyCell,
        PickupKind.overchargeCell,
        PickupKind.combatStim,
      ];
      for (final kind in potions) {
        expect(PickupSpec.table[kind]!.isPotion, isTrue, reason: '$kind');
      }
      expect(PickupSpec.table[PickupKind.dataChip]!.isPotion, isFalse);
      expect(PickupSpec.table[PickupKind.scrapCore]!.isPotion, isFalse);
    });

    test('포션은 회복이든 강화든 실제 효과를 준다', () {
      for (final kind in PickupKind.values) {
        final potion = PickupSpec.table[kind]!.potion;
        if (potion == null) continue;
        expect(
          potion.heal > 0 || potion.energy > 0 || potion.buff != null,
          isTrue,
          reason: '$kind는 아무 효과도 없다',
        );
      }
    });
  });
}
