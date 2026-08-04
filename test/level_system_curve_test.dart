import 'package:flutter_test/flutter_test.dart';

import 'package:actionrpg/game/systems/level_system.dart';

/// 경험치 곡선을 **고정된 값**으로 못 박는다.
///
/// 서버(`spacetimedb/src/leaderboard.rs`)가 같은 세 상수로 같은 식을 계산하고,
/// 보고된 누적 경험치에서 레벨을 유도한다. 두 곳이 조금이라도 어긋나면 화면의
/// 레벨과 리더보드의 레벨이 달라지는데, 그 증상은 아주 늦게 드러난다.
///
/// 그래서 양쪽이 **같은 기대값**을 검증한다. 서버 `leaderboard::tests` 에 같은
/// 숫자가 적혀 있으므로, 한쪽 곡선만 고치면 둘 중 하나가 즉시 깨진다.
void main() {
  group('다음 레벨까지의 경험치', () {
    test('서버와 같은 고정값을 낸다', () {
      const expected = <int, int>{
        1: 60,
        2: 93,
        3: 132,
        10: 573,
        30: 3453,
        50: 8733,
        70: 16413,
        100: 54633,
        500: 2456233,
        999: 10386840,
      };
      expected.forEach((level, want) {
        expect(
          LevelSystem.xpToNext(level),
          want,
          reason: '레벨 $level 의 요구 경험치가 서버와 다르다',
        );
      });
    });

    test('레벨이 오를수록 무거워진다', () {
      for (var level = 1; level < LevelSystem.maxLevel; level++) {
        expect(LevelSystem.xpToNext(level + 1),
            greaterThan(LevelSystem.xpToNext(level)));
      }
    });

    test('70을 넘으면 곡선이 확 꺾인다', () {
      final before = LevelSystem.xpToNext(70) - LevelSystem.xpToNext(69);
      final after = LevelSystem.xpToNext(71) - LevelSystem.xpToNext(70);
      expect(
        after,
        greaterThan(before * 2),
        reason: '70을 넘어선 증가폭이 그 전의 두 배도 안 된다',
      );

      // 그 격차는 레벨이 오를수록 더 벌어진다.
      final far = LevelSystem.xpToNext(200) - LevelSystem.xpToNext(199);
      expect(far, greaterThan(after));
    });
  });

  group('누적 경험치', () {
    test('닫힌 식이 실제 합과 같다', () {
      var running = 0;
      for (var level = 1; level <= LevelSystem.maxLevel; level++) {
        expect(
          LevelSystem.totalXpForLevel(level),
          running,
          reason: '레벨 $level 의 누적이 실제 합과 다르다',
        );
        running += LevelSystem.xpToNext(level);
      }
    });

    test('누적에서 레벨을 되돌릴 수 있다', () {
      for (var level = 1; level < LevelSystem.maxLevel; level++) {
        final at = LevelSystem.totalXpForLevel(level);
        expect(LevelSystem.levelForTotalXp(at), level);
        expect(
          LevelSystem.levelForTotalXp(at + LevelSystem.xpToNext(level) - 1),
          level,
        );
        expect(
          LevelSystem.levelForTotalXp(at + LevelSystem.xpToNext(level)),
          level + 1,
        );
      }
    });

    test('레벨 안의 진행도가 맞아떨어진다', () {
      // 3 레벨은 누적 153 에서 시작하고 다음까지 132 → 4 레벨은 285.
      expect(LevelSystem.levelForTotalXp(153), 3);
      expect(LevelSystem.progressWithin(153), 0);
      expect(LevelSystem.progressWithin(200), 47);
      expect(LevelSystem.levelForTotalXp(284), 3);
      expect(LevelSystem.levelForTotalXp(285), 4);
      expect(LevelSystem.progressWithin(284), 131);
      expect(LevelSystem.progressWithin(285), 0);
      expect(LevelSystem.levelForTotalXp(0), 1);
    });
  });

  group('만렙 999', () {
    test('만렙에서 레벨이 멈춘다', () {
      final atMax = LevelSystem.totalXpForLevel(LevelSystem.maxLevel);
      expect(LevelSystem.levelForTotalXp(atMax), LevelSystem.maxLevel);
      // 넘치게 쌓아도 더 오르지 않는다.
      expect(
        LevelSystem.levelForTotalXp(LevelSystem.maxTotalXp),
        LevelSystem.maxLevel,
      );
    });

    test('만렙까지의 누적이 u32 안에 들어간다', () {
      // 이 성질이 깨지면 서버가 total_xp 를 u32 로 둘 수 없다.
      final atMax = LevelSystem.totalXpForLevel(LevelSystem.maxLevel);
      expect(atMax, 3357620767);
      expect(atMax, lessThan(LevelSystem.maxTotalXp));

      // 만렙 이후에도 9억 넘게 더 쌓을 수 있어야 순위 경쟁이 이어진다.
      expect(LevelSystem.maxTotalXp - atMax, greaterThan(900000000));
    });
  });
}
