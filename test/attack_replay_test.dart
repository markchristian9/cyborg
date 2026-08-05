import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:actionrpg/game/entities/enemy.dart';
import 'package:actionrpg/game/entities/remote_player.dart';
import 'package:actionrpg/game/net/world_presence.dart';
import 'package:actionrpg/game/systems/monster_codex.dart';

/// 남의 공격을 **언제 재생하고 언제 재생하지 않는지** 고정한다.
///
/// 이 분기는 두 요구가 맞서는 자리다.
///  - 시야에 들어온 사람이 등장하자마자 허공을 치면 안 된다(과거 공격 비재생).
///  - 한 번도 공격한 적 없는 사람의 **첫 공격**은 보여야 한다.
///
/// 한때 둘을 "기준값이 0 이면 재생하지 않는다" 하나로 처리했고, 그래서 첫 공격이
/// 함께 버려졌다. 두 사람이 마주 서서 동기화를 시험할 때 가장 먼저 보는 바로 그
/// 한 번이 빠지는 결함이었다. 서버 표까지만 보는 통합 테스트로는 잡히지 않는다.
void main() {
  RemotePlayer snapshot({required int attackAt, int skill = AttackSkill.none}) =>
      RemotePlayer(
        characterId: 7,
        name: '동료',
        kind: 'male_cyborg',
        level: 3,
        grid: Vector2(100, 100),
        alive: true,
        hp: 100,
        maxHp: 100,
        lastAttackAtMicros: attackAt,
        attackDir: Vector2(1, 0),
        attackSkill: skill,
      );

  group('다른 요원의 공격', () {
    test('한 번도 공격한 적 없는 사람의 첫 공격은 재생된다', () {
      // 서버 기본값은 epoch — 클라이언트에는 0 으로 온다.
      final entity = RemotePlayerEntity(snapshot: snapshot(attackAt: 0));
      expect(entity.isSwinging, isFalse, reason: '등장하자마자 휘두르면 안 된다');

      entity.applySnapshot(snapshot(attackAt: 1000));
      expect(
        entity.isSwinging,
        isTrue,
        reason: '첫 공격이 삼켜졌다 — 마주 서서 시험할 때 가장 먼저 보는 한 번이다',
      );
    });

    test('이미 공격한 적 있는 사람이 시야에 들어와도 과거 공격은 재생하지 않는다', () {
      // 시야 밖에서 이미 휘두른 뒤 들어온 사람.
      final entity = RemotePlayerEntity(snapshot: snapshot(attackAt: 5000));
      expect(entity.isSwinging, isFalse);

      // 같은 값이 다시 와도 마찬가지다.
      entity.applySnapshot(snapshot(attackAt: 5000));
      expect(
        entity.isSwinging,
        isFalse,
        reason: '등장 직후 과거 공격을 되살리면 허공에 헛스윙이 보인다',
      );
    });

    test('연이은 공격도 매번 재생된다', () {
      final entity = RemotePlayerEntity(snapshot: snapshot(attackAt: 1000));

      entity.applySnapshot(snapshot(attackAt: 2000));
      expect(entity.isSwinging, isTrue);

      // 동작이 끝날 때까지 돌린 뒤 다음 공격.
      for (var i = 0; i < 30; i++) {
        entity.update(1 / 60);
      }
      expect(entity.isSwinging, isFalse, reason: '동작이 끝나야 다음 것이 보인다');

      entity.applySnapshot(snapshot(attackAt: 3000));
      expect(entity.isSwinging, isTrue);
    });

    test('같은 시각이 매 프레임 다시 와도 한 번만 재생한다', () {
      final entity = RemotePlayerEntity(snapshot: snapshot(attackAt: 1000));
      entity.applySnapshot(snapshot(attackAt: 2000));

      // 게임 루프는 서버 갱신과 무관하게 매 프레임 스냅샷을 밀어 넣는다.
      for (var i = 0; i < 30; i++) {
        entity.applySnapshot(snapshot(attackAt: 2000));
        entity.update(1 / 60);
      }
      expect(
        entity.isSwinging,
        isFalse,
        reason: '같은 공격이 매 프레임 다시 재생되어 동작이 끝나지 않는다',
      );
    });
  });

  group('몬스터의 타격', () {
    Enemy serverMonster({required int attackAt}) {
      final enemy = Enemy(
        species: MonsterCodex.byLevel(1),
        grid: Vector2(100, 100),
      )..serverId = 1;
      enemy.applyServerState(
        grid: Vector2(100, 100),
        hpRatio: 1,
        alive: true,
        tagged: false,
        lastAttackAtMicros: attackAt,
      );
      return enemy;
    }

    test('한 번도 때린 적 없는 몹의 첫 타격은 재생된다', () {
      final enemy = serverMonster(attackAt: 0);
      for (var i = 0; i < 5; i++) {
        enemy.update(1 / 60);
      }
      expect(enemy.phase, isNot(EnemyPhase.strike));

      enemy.applyServerState(
        grid: Vector2(100, 100),
        hpRatio: 1,
        alive: true,
        tagged: false,
        lastAttackAtMicros: 1000,
      );
      enemy.update(1 / 60);
      expect(
        enemy.phase,
        EnemyPhase.strike,
        reason: '첫 타격이 삼켜졌다 — 몹이 조용히 서서 체력만 깎는 것처럼 보인다',
      );
    });

    test('이미 때린 적 있는 몹이 시야에 들어와도 과거 타격은 재생하지 않는다', () {
      final enemy = serverMonster(attackAt: 5000);
      enemy.update(1 / 60);
      expect(enemy.phase, isNot(EnemyPhase.strike));
    });
  });
}
