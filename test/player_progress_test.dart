import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:actionrpg/game/entities/player.dart';
import 'package:actionrpg/game/systems/level_system.dart';

/// 리더보드 순위의 **입력값**이 되는 성장 상태를 잠근다.
///
/// 순위 규칙은 서버가 갖고 있지만, 서버에 올라가는 누적 경험치를 만드는 것은
/// 여기다. 이 파일이 지키는 것이 깨지면 순위표는 규칙이 맞아도 틀린 값을 줄
/// 세우게 된다.
void main() {
  Player freshPlayer() => Player(grid: Vector2.zero());

  group('서버 성장 상태 복원', () {
    test('저장된 누적에서 레벨과 진행도를 되살린다', () {
      // 10 레벨은 누적 2,232 에서 시작한다. 거기에 200 을 더 쌓은 상태.
      final at10 = LevelSystem.totalXpForLevel(10);
      final player = freshPlayer()..restoreProgress(totalXp: at10 + 200);

      expect(player.totalXp, at10 + 200);
      expect(player.level, 10);
      expect(player.xp, 200);
      expect(player.xpToNextLevel, LevelSystem.xpToNext(10));
    });

    test('복원하면 그 레벨까지의 스탯 상승이 모두 반영된다', () {
      final base = freshPlayer();
      final baseHp = base.maxHp;
      final baseMelee = base.meleeDamage;

      final grown = freshPlayer()
        ..restoreProgress(totalXp: LevelSystem.totalXpForLevel(10));

      // 2~10 레벨의 상승분이 누적돼야 한다. 숫자만 바꿔치기하면 1 레벨 몸으로
      // 10 레벨 몬스터를 상대하게 된다.
      var expectedHp = baseHp;
      var expectedMelee = baseMelee;
      for (var level = 2; level <= 10; level++) {
        final gains = LevelSystem.gainsFor(level);
        expectedHp += gains.maxHp;
        expectedMelee += gains.meleeDamage;
      }

      expect(grown.maxHp, expectedHp);
      expect(grown.meleeDamage, expectedMelee);
      expect(grown.hp, grown.maxHp, reason: '복원 직후에는 온전한 몸이어야 한다');
    });

    test('복원은 레벨업 연출을 일으키지 않는다', () {
      // `_levelUp` 은 `game.spawnEffect`·`game.onLevelUp` 을 부른다. 복원이 그
      // 경로를 탄다면 게임에 붙지 않은 이 Player 에서 예외가 났을 것이다.
      // 예외 없이 끝나는 것 자체가 연출·서버 보고를 타지 않았다는 증거다.
      expect(
        () => freshPlayer()
            .restoreProgress(totalXp: LevelSystem.totalXpForLevel(25)),
        returnsNormally,
      );
    });

    test('서버가 이상한 값을 줘도 범위 안으로 들어온다', () {
      final negative = freshPlayer()..restoreProgress(totalXp: -5);
      expect(negative.totalXp, 0);
      expect(negative.level, 1);

      final huge = freshPlayer()
        ..restoreProgress(totalXp: LevelSystem.maxTotalXp + 1000);
      expect(huge.totalXp, LevelSystem.maxTotalXp);
      expect(huge.level, LevelSystem.maxLevel);
    });

    test('레벨·진행도가 누적과 항상 맞물린다', () {
      for (final level in [1, 2, 7, 30, 137, 400]) {
        final player = freshPlayer()
          ..restoreProgress(totalXp: LevelSystem.totalXpForLevel(level));
        expect(player.level, level);
        expect(player.xp, 0, reason: '레벨 시작점이면 진행도는 0 이다');
        expect(
          LevelSystem.totalXpForLevel(player.level) + player.xp,
          player.totalXp,
        );
      }
    });
  });

  group('성장', () {
    test('70을 넘는 레벨도 복원된다', () {
      final beyond = freshPlayer()
        ..restoreProgress(totalXp: LevelSystem.totalXpForLevel(87));

      expect(beyond.level, 87);
      expect(beyond.xpToNextLevel, LevelSystem.xpToNext(87));
    });

    test('만렙에서 레벨이 멈추고 누적만 쌓인다', () {
      final atMax = LevelSystem.totalXpForLevel(LevelSystem.maxLevel);
      final maxed = freshPlayer()..restoreProgress(totalXp: atMax + 5000000);

      expect(maxed.level, LevelSystem.maxLevel);
      expect(maxed.totalXp, atMax + 5000000);
      expect(
        maxed.xp,
        5000000,
        reason: '만렙 진행도는 만렙 도달 후 더 쌓은 양이며 순위를 가른다',
      );
    });

    test('누적이 늘면 레벨도 따라 오른다', () {
      final a = freshPlayer()
        ..restoreProgress(totalXp: LevelSystem.totalXpForLevel(50));
      final b = freshPlayer()
        ..restoreProgress(totalXp: LevelSystem.totalXpForLevel(51));

      expect(b.level, greaterThan(a.level));
      expect(b.totalXp, greaterThan(a.totalXp));
    });
  });

  // 경험치 획득(`gainXp`)은 레벨업 연출과 서버 보고를 함께 일으켜 게임에 붙어
  // 있어야만 돌아간다. 그래서 여기서 다루지 않는다 — 누적이 서버에 제대로
  // 닿는지는 `test/spacetime_integration_test.dart` 의 리더보드 그룹이 실제
  // 서버를 상대로 확인한다.
}
