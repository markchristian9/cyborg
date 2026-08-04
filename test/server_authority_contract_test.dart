import 'package:actionrpg/game/entities/player.dart';
import 'package:actionrpg/game/systems/level_system.dart';
import 'package:actionrpg/game/systems/monster_codex.dart';
import 'package:actionrpg/game/systems/rest_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

/// 서버가 전투의 판정자가 된 뒤, **클라이언트의 수치는 서버 값의 사본**이다.
///
/// 이 파일은 그 사본이 정본과 어긋나지 않는지 클라이언트 쪽에서 못 박는다.
/// 서버 쪽 대응 테스트는 `spacetimedb/src/world.rs` 의 `mod tests` 에 있고,
/// **두 곳이 같은 숫자를 적고 있다는 것이 계약의 전부다.**
///
/// 어느 한쪽만 고치면 "분명히 맞았는데 안 죽는다" 는 형태로 터진다 — 화면은
/// 클라이언트 값으로 그리는데 죽고 사는 것은 서버 값이 정하기 때문이다.
/// 여기 숫자를 바꿀 일이 생기면 `world.rs` 의 같은 상수를 반드시 함께 고친다.
void main() {
  group('플레이어 체력 — 서버 max_hp_for_level 과 같아야 한다', () {
    test('1레벨은 10,000이다', () {
      // 서버: BASE_MAX_HP = 10_000
      expect(Player.baseMaxHp, 10000);
    });

    test('레벨업 한 번에 정확히 1,000씩 늘어난다', () {
      // 서버: HP_PER_LEVEL = 1_000
      for (final level in [2, 5, 10, 30]) {
        expect(
          LevelSystem.gainsFor(level).maxHp,
          1000,
          reason: '레벨 $level 의 체력 성장치가 서버 규격과 다르다',
        );
      }
    });

    test('레벨 N 의 최대 체력 = 10,000 + (N-1) × 1,000', () {
      // 서버 `max_hp_for_level` 과 같은 식인지 누적으로 확인한다.
      var maxHp = Player.baseMaxHp;
      for (var level = 2; level <= 30; level++) {
        maxHp += LevelSystem.gainsFor(level).maxHp;
      }
      expect(maxHp, 10000 + 29 * 1000);
    });
  });

  group('플레이어 마력 — 서버 max_mp_for_level 과 같아야 한다', () {
    test('레벨업 한 번에 600씩 늘어난다', () {
      // 서버: MP_PER_LEVEL = 600
      for (final level in [2, 5, 10, 30]) {
        expect(LevelSystem.gainsFor(level).maxMp, 600);
      }
    });
  });

  group('몬스터 피해 — 방어력 0이면 몬스터의 레벨과 같다', () {
    test('레벨이 곧 피해다', () {
      // 서버 `monster_ai` 는 `monster.level` 을 그대로 피해로 쓴다.
      for (final level in [1, 3, 10, 200]) {
        final species = MonsterCodex.byLevel(level);
        expect(
          species.stats.damage,
          level.toDouble(),
          reason: '레벨 $level 몬스터의 피해가 레벨과 다르다',
        );
      }
    });

    test('방어력 0에서는 받는 피해가 깎이지 않는다', () {
      // 서버 `damage_after_defense(amount, 0) == amount`.
      for (final amount in [1.0, 3.0, 10.0, 200.0]) {
        expect(Player.damageAfterDefense(amount, 0), amount);
      }
    });

    test('방어력이 상수와 같으면 절반이 된다', () {
      // 서버 DEFENSE_CONSTANT = 100 과 같은 승수형 공식.
      expect(Player.defenseConstant, 100);
      expect(
        Player.damageAfterDefense(100, Player.defenseConstant),
        closeTo(50, 0.001),
      );
    });
  });

  group('회복 — 서버 regen_tick 과 같은 비율이어야 한다', () {
    test('안전지대 회복 비율', () {
      // 서버: REST_HP_PER_MILLE = 120, REST_MP_PER_MILLE = 150 (1000분율).
      expect(RestRecovery.hpPerSecond, closeTo(0.12, 0.0001));
      expect(RestRecovery.mpPerSecond, closeTo(0.15, 0.0001));
    });

    test('야전 마력 회복 비율', () {
      // 서버: FIELD_MP_PER_MILLE = 5.
      expect(RestRecovery.fieldMpPerSecond, closeTo(0.005, 0.0001));
    });

    test('피격 후 회복 대기', () {
      // 서버: REST_WARMUP_MICROS = 1_500_000.
      expect(RestRecovery.warmupAfterDamage, closeTo(1.5, 0.0001));
    });
  });

  group('스킬 — 서버 skill_spec 과 같아야 한다', () {
    test('플라즈마 마력 비용', () {
      // 서버 SKILL_PLASMA.mp_cost = 60.
      expect(Player.plasmaMpCost, 60);
    });

    test('플라즈마 조준 거리는 서버 사거리와 같다', () {
      // 서버 SKILL_PLASMA.range_tiles = 10.0.
      // 클라이언트가 더 멀리 조준하면 서버가 거절해 "쐈는데 아무 일도 없다" 가 된다.
      expect(Player.plasmaAimRange, 10);
    });

    test('서버가 아는 스킬 이름을 쓴다', () {
      // 서버 `skill_spec` 은 "plasma" 만 안다.
      expect(Player.plasmaSkillId, 'plasma');
    });
  });

  group('무적 — 서버 재가동과 같아야 한다', () {
    test('재가동 직후 무적 시간', () {
      // 서버: RESPAWN_INVULNERABLE_MICROS = 2_000_000.
      expect(Player.respawnInvulnerability, closeTo(2.0, 0.0001));
    });
  });
}
