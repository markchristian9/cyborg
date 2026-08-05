import 'package:actionrpg/game/entities/enemy.dart';
import 'package:actionrpg/game/net/world_presence.dart';
import 'package:actionrpg/game/systems/monster_codex.dart';
import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// 서버가 판정하는 대상에게 **클라이언트가 같은 타격을 두 번 보내지 않는지** 지킨다.
///
/// 이 회귀는 실제로 났었다. 플라즈마를 서버 스킬(`cast_skill`)로 옮긴 뒤에도
/// 날아간 발사체가 몹에 닿으면 `Enemy.applyDamage` → `presence.attack` 이 돌아,
/// 한 발에 `cast_skill` 과 `attack_monster` 두 요청이 나갔다. 두 번째는 근접
/// 공격으로 취급되어(사거리 2.2 타일) 대개 거절되지만, 통과하면 공유 쿨다운을
/// 잡아먹어 다음 평타가 막힌다.
///
/// 발사체가 서버 몹을 그냥 지나가게 하는 것이 답이며, 그 판단의 근거가
/// [Damageable.isServerJudged] 다.
void main() {
  group('서버가 판정하는 대상', () {
    test('서버 몹은 클라이언트 피해를 받지 않는다고 표시한다', () {
      final enemy = Enemy(
        species: MonsterCodex.byLevel(5),
        grid: Vector2(10, 10),
      )..serverId = 42;

      expect(enemy.isServerDriven, isTrue);
      expect(
        enemy.isServerJudged,
        isTrue,
        reason: '서버가 모는 몹은 화면에서 무엇이 닿아도 로컬로 깎이면 안 된다',
      );
    });

    test('서버에 없는 몹은 로컬 판정을 받는다', () {
      // 오프라인·프리뷰 모드의 몹이다. 여기서는 클라이언트가 유일한 판정자다.
      final enemy = Enemy(
        species: MonsterCodex.byLevel(5),
        grid: Vector2(10, 10),
      );

      expect(enemy.isServerDriven, isFalse);
      expect(enemy.isServerJudged, isFalse);
    });

    test('서버 몹의 체력은 서버가 준 비율로만 움직인다', () {
      final enemy = Enemy(
        species: MonsterCodex.byLevel(5),
        grid: Vector2(10, 10),
      )..serverId = 7;

      final full = enemy.hp;
      expect(full, enemy.maxHp);

      // 서버가 절반으로 깎였다고 알려 주면 그때 비로소 줄어든다.
      enemy.applyServerState(
        grid: Vector2(10, 10),
        hpRatio: 0.5,
        alive: true,
        tagged: false,
      );
      expect(enemy.hp, closeTo(enemy.maxHp * 0.5, 0.001));

      // 서버가 죽었다고 하면 체력이 남아 있어도 죽은 것이다 — 되살아나는 순간
      // (체력이 가득 찬 채 alive 만 바뀌는 경우)을 놓치지 않으려는 구분이다.
      enemy.applyServerState(
        grid: Vector2(10, 10),
        hpRatio: 0.5,
        alive: false,
        tagged: false,
      );
      expect(enemy.isAlive, isFalse);
    });
  });

  group('WorldPresence 계약', () {
    test('오프라인 구현은 서버 상태를 내주지 않는다', () {
      const presence = OfflineWorldPresence();
      expect(presence.me, isNull);
      expect(presence.isAvailable, isFalse);
      expect(presence.monsters, isEmpty);
      expect(presence.others, isEmpty);
    });

    test('오프라인 구현의 공격·스킬 호출은 조용히 아무 일도 하지 않는다', () {
      // 서버가 없을 때도 게임은 그대로 돌아야 한다. 예외를 던지면 오프라인
      // 모드에서 공격할 때마다 게임 루프가 끊긴다.
      const presence = OfflineWorldPresence();
      expect(() => presence.attack(1), returnsNormally);
      expect(() => presence.castSkill('plasma', 1), returnsNormally);
      expect(() => presence.attackPlayer(1), returnsNormally);
    });
  });

  group('원격 요원의 체력', () {
    test('PK 판단에 쓸 수 있도록 비율을 내준다', () {
      final remote = RemotePlayer(
        characterId: 1,
        name: '요원',
        kind: 'male_cyborg',
        level: 3,
        grid: Vector2(5, 5),
        alive: true,
        hp: 3000,
        maxHp: 12000,
      );
      expect(remote.hpRatio, closeTo(0.25, 0.0001));
    });

    test('최대 체력이 0이면 0을 준다 — 나눗셈이 깨지지 않아야 한다', () {
      // 서버 행이 아직 초기화되기 전에 올 수 있다.
      final remote = RemotePlayer(
        characterId: 1,
        name: '요원',
        kind: 'male_cyborg',
        level: 1,
        grid: Vector2(5, 5),
        alive: true,
        hp: 0,
        maxHp: 0,
      );
      expect(remote.hpRatio, 0);
    });
  });
}
