import 'package:actionrpg/game/systems/level_system.dart';
import 'package:actionrpg/game/systems/rest_recovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RestRecovery', () {
    test('거점 밖에서는 체력이 전혀 차지 않는다', () {
      final rest = RestRecovery()..update(1, sheltered: false);
      expect(rest.isRecovering, isFalse);
      expect(rest.hpGain(1, 10000), 0);
    });

    test('거점 안에 들어가면 곧바로 회복이 돈다', () {
      final rest = RestRecovery()..update(0.1, sheltered: true);
      expect(rest.isSheltered, isTrue);
      expect(rest.isRecovering, isTrue);
      expect(rest.hpGain(1, 10000), 10000 * RestRecovery.hpPerSecond);
    });

    test('얻어맞은 직후에는 대기 시간이 지나야 회복이 시작된다', () {
      final rest = RestRecovery()..notifyDamaged();

      rest.update(0.1, sheltered: true);
      expect(rest.isRecovering, isFalse);
      expect(rest.hpGain(1, 10000), 0);
      expect(rest.warmupRemaining, greaterThan(0));

      rest.update(RestRecovery.warmupAfterDamage, sheltered: true);
      expect(rest.isRecovering, isTrue);
      expect(rest.warmupRemaining, 0);
    });

    test('회복 중 다시 맞으면 대기가 다시 채워진다', () {
      final rest = RestRecovery()..update(0.1, sheltered: true);
      expect(rest.isRecovering, isTrue);

      rest.notifyDamaged();
      rest.update(0.1, sheltered: true);
      expect(rest.isRecovering, isFalse);
    });

    test('거점을 벗어나면 회복이 멈춘다', () {
      final rest = RestRecovery()..update(0.1, sheltered: true);
      expect(rest.isRecovering, isTrue);

      rest.update(0.1, sheltered: false);
      expect(rest.isRecovering, isFalse);
      expect(rest.hpGain(1, 10000), 0);
    });

    test('마력은 거점 밖에서도 아주 조금씩 찬다', () {
      final rest = RestRecovery()..update(1, sheltered: false);
      final field = rest.mpGain(1, 5000);

      expect(field, greaterThan(0));
      expect(field, 5000 * RestRecovery.fieldMpPerSecond);
    });

    test('거점 안 마력 회복이 밖보다 훨씬 빠르다', () {
      final outside = RestRecovery()..update(1, sheltered: false);
      final inside = RestRecovery()..update(1, sheltered: true);

      expect(
        inside.mpGain(1, 5000),
        greaterThan(outside.mpGain(1, 5000) * 10),
      );
    });

    test('쉬면 10초 안에 완전히 회복된다', () {
      final rest = RestRecovery()..update(0.1, sheltered: true);
      const maxHp = 10000.0;

      var hp = 0.0;
      var elapsed = 0.0;
      const step = 0.1;
      while (hp < maxHp && elapsed < 30) {
        rest.update(step, sheltered: true);
        hp = (hp + rest.hpGain(step, maxHp)).clamp(0, maxHp);
        elapsed += step;
      }

      expect(hp, maxHp);
      expect(elapsed, lessThanOrEqualTo(10));
    });

    test('reset하면 처음 상태로 돌아간다', () {
      final rest = RestRecovery()
        ..notifyDamaged()
        ..update(0.1, sheltered: true);
      rest.reset();

      expect(rest.isSheltered, isFalse);
      expect(rest.isRecovering, isFalse);
      expect(rest.warmupRemaining, 0);
    });
  });

  group('마력 성장', () {
    test('레벨업마다 최대 마력이 늘어난다', () {
      expect(LevelSystem.gainsFor(2).maxMp, greaterThan(0));
    });

    test('레벨을 올릴수록 마력이 크게 불어난다', () {
      // 만렙이 없어졌으므로 "끝까지" 라는 기준점도 없다. 예전 상한이던 30 을
      // 기준 삼아 그만큼 올렸을 때의 증가폭을 본다.
      const startMp = 5000.0;
      var maxMp = startMp;
      for (var level = 2; level <= 30; level++) {
        maxMp += LevelSystem.gainsFor(level).maxMp;
      }
      expect(maxMp, greaterThan(startMp * 3));
    });
  });
}
