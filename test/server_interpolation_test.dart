import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:actionrpg/game/entities/enemy.dart';
import 'package:actionrpg/game/entities/remote_player.dart';
import 'package:actionrpg/game/net/world_presence.dart';
import 'package:actionrpg/game/systems/monster_codex.dart';

/// 서버가 띄엄띄엄 보내는 좌표를 **끊김 없이** 그리는지 확인한다.
///
/// 증상은 "몹이 뚝뚝 끊기며 순간이동하듯 움직인다" 였고, 원인은 남은 거리에
/// 비례해 다가가는 방식(지수 감쇠)이었다. 그 방식은 목표에 **일찍 닿아 멈추고**
/// 다음 갱신이 오면 다시 튀어 나간다 — 나아가다 서고를 반복하는 것이 눈에는
/// 순간이동으로 보인다.
///
/// 그래서 여기서 재는 것은 "목표에 가까운가" 가 아니라 **속도가 고른가** 다.
void main() {
  /// [steps] 프레임 동안 매 프레임 이동 거리를 모은다.
  List<double> stepLengths(void Function(double dt) advance, Vector2 watch,
      {int steps = 60, double dt = 1 / 60}) {
    final lengths = <double>[];
    var previous = watch.clone();
    for (var i = 0; i < steps; i++) {
      advance(dt);
      lengths.add((watch - previous).length);
      previous = watch.clone();
    }
    return lengths;
  }

  /// 멈춘 프레임의 비율. 등속으로 걷는다면 0 에 가까워야 한다.
  double stalledRatio(List<double> lengths) {
    final moving = lengths.where((l) => l > 1e-4).length;
    return 1 - moving / lengths.length;
  }

  /// 프레임별 이동거리의 변동계수(표준편차 / 평균).
  ///
  /// **끊김을 재는 진짜 지표다.** 멈춰 있는 프레임 수만 세면 지수 감쇠를 놓친다 —
  /// 그 방식은 아예 서는 것이 아니라 목표에 가까울수록 느려졌다가 새 값이 오면
  /// 다시 빨라지므로, 매 프레임 조금씩은 움직인다. 눈에 "뚝뚝" 으로 보이는 것은
  /// 정지가 아니라 **갱신 주기마다 되풀이되는 가속과 감속**이다.
  double speedVariation(List<double> lengths) {
    final mean = lengths.reduce((a, b) => a + b) / lengths.length;
    if (mean <= 0) return double.infinity;
    final variance = lengths
            .map((l) => (l - mean) * (l - mean))
            .reduce((a, b) => a + b) /
        lengths.length;
    return math.sqrt(variance) / mean;
  }

  group('몬스터', () {
    /// 월드 한가운데 선, 서버가 모는 몹 하나.
    Enemy serverMonster() {
      final enemy = Enemy(
        species: MonsterCodex.byLevel(1),
        grid: Vector2(100, 100),
      )..serverId = 1;
      enemy.applyServerState(
        grid: Vector2(100, 100),
        hpRatio: 1,
        alive: true,
        tagged: false,
      );
      return enemy;
    }

    test('서버 갱신 사이가 고른 속도로 메워진다', () {
      const tick = 1 / 24;
      const speed = 2.4;
      final enemy = serverMonster();

      var serverX = 100.0;
      var sinceTick = 0.0;
      // 첫 구간은 갱신 간격을 아직 모르므로 건너뛴다. 실측이 붙은 뒤를 잰다.
      for (var i = 0; i < 40; i++) {
        enemy.update(1 / 60);
        sinceTick += 1 / 60;
        if (sinceTick >= tick) {
          sinceTick -= tick;
          serverX += speed * tick;
          enemy.applyServerState(
            grid: Vector2(serverX, 100),
            hpRatio: 1,
            alive: true,
            tagged: false,
          );
        }
      }

      final lengths = stepLengths(
        (dt) {
          enemy.update(dt);
          sinceTick += dt;
          if (sinceTick >= tick) {
            sinceTick -= tick;
            serverX += speed * tick;
            enemy.applyServerState(
              grid: Vector2(serverX, 100),
              hpRatio: 1,
              alive: true,
              tagged: false,
            );
          }
        },
        enemy.grid,
      );

      // 멈춘 프레임이 거의 없어야 한다. 지수 감쇠 방식은 여기서 30% 넘게
      // 걸렸다 — 갱신 간격의 뒷부분을 통째로 서 있었기 때문이다.
      expect(
        stalledRatio(lengths),
        lessThan(0.1),
        reason: '갱신 사이에 멈춰 서는 프레임이 많다 — 끊겨 보인다',
      );

      // 프레임별 이동 거리가 고르게 나와야 한다. 튀는 프레임이 있으면 그것이
      // 곧 "순간이동" 이다.
      final mean = lengths.reduce((a, b) => a + b) / lengths.length;
      expect(mean, greaterThan(0), reason: '아예 움직이지 않았다');
      expect(
        lengths.reduce((a, b) => a > b ? a : b),
        lessThan(mean * 3),
        reason: '한 프레임에 몰아서 움직인다 — 순간이동으로 보인다',
      );
    });

    test('서버가 준 방향이 이동 방향을 이긴다 — 멈춰서 때릴 때', () {
      final enemy = Enemy(
        species: MonsterCodex.byLevel(1),
        grid: Vector2(100, 100),
      )..serverId = 1;

      // 왼쪽으로 걸어온 뒤 제자리에 서서, 오른쪽을 본다고 서버가 알려 준다.
      enemy.applyServerState(
        grid: Vector2(99, 100),
        hpRatio: 1,
        alive: true,
        tagged: false,
      );
      for (var i = 0; i < 20; i++) {
        enemy.update(1 / 60);
      }
      enemy.applyServerState(
        grid: Vector2(99, 100),
        hpRatio: 1,
        alive: true,
        tagged: false,
        facing: Vector2(1, 0),
      );
      for (var i = 0; i < 10; i++) {
        enemy.update(1 / 60);
      }

      // 좌표는 그대로인데 방향만 바뀌었다. 이 값이 반영되지 않으면 때리는 몹이
      // 자기 등 뒤를 향해 휘두른다.
      expect(enemy.facing.x, greaterThan(0.9));
    });
  });

  group('실제 호출 패턴 — 매 프레임 스냅샷', () {
    // 게임 루프는 서버 갱신과 무관하게 **매 프레임** 스냅샷을 밀어 넣는다
    // (`_syncRemotePlayers`·`_refreshMonsterStreaming`). 위 테스트들은 서버가
    // 갱신한 순간에만 넣어서 이 경로를 재현하지 않았고, 그래서 "구간이 매
    // 프레임 리셋되어 등속 보간이 지수 감쇠로 퇴화하는" 결함을 놓쳤다.

    test('몬스터 — 같은 스냅샷을 매 프레임 넣어도 등속으로 걷는다', () {
      const tick = 1 / 24;
      const speed = 2.4;
      final enemy = Enemy(
        species: MonsterCodex.byLevel(1),
        grid: Vector2(100, 100),
      )..serverId = 1;

      var serverX = 100.0;
      var sinceTick = 0.0;
      var current = Vector2(serverX, 100);

      void advance(double dt) {
        sinceTick += dt;
        if (sinceTick >= tick) {
          sinceTick -= tick;
          serverX += speed * tick;
          current = Vector2(serverX, 100);
        }
        // 갱신 여부와 무관하게 매 프레임 밀어 넣는다 — 실제 게임과 같다.
        enemy.applyServerState(
          grid: current,
          hpRatio: 1,
          alive: true,
          tagged: false,
        );
        enemy.update(dt);
      }

      for (var i = 0; i < 40; i++) {
        advance(1 / 60);
      }
      final lengths = stepLengths(advance, enemy.grid);

      expect(stalledRatio(lengths), lessThan(0.1));
      // 등속이면 프레임마다 같은 거리를 간다. 구간이 매 프레임 리셋되면 남은
      // 거리에 비례해 다가가는 꼴이 되어, 갱신 주기마다 빨라졌다 느려지는
      // 톱니가 생긴다 — 그것이 화면에서 "뚝뚝" 으로 보인다.
      expect(
        speedVariation(lengths),
        lessThan(0.2),
        reason: '갱신 주기마다 빨라졌다 느려진다 — 보간 구간이 리셋되고 있다',
      );
    });

    test('다른 요원 — 같은 스냅샷을 매 프레임 넣어도 등속으로 걷는다', () {
      const tick = 1 / 24;
      const speed = 3.0;
      RemotePlayer snap(double x) => RemotePlayer(
            characterId: 7,
            name: '동료',
            kind: 'male_cyborg',
            level: 3,
            grid: Vector2(x, 100),
            alive: true,
            hp: 100,
            maxHp: 100,
          );

      final entity = RemotePlayerEntity(snapshot: snap(100));
      var serverX = 100.0;
      var sinceTick = 0.0;
      var current = snap(serverX);

      void advance(double dt) {
        sinceTick += dt;
        if (sinceTick >= tick) {
          sinceTick -= tick;
          serverX += speed * tick;
          current = snap(serverX);
        }
        entity.applySnapshot(current);
        entity.update(dt);
      }

      for (var i = 0; i < 40; i++) {
        advance(1 / 60);
      }
      final lengths = stepLengths(advance, entity.grid);

      expect(stalledRatio(lengths), lessThan(0.1));
      expect(
        speedVariation(lengths),
        lessThan(0.2),
        reason: '갱신 주기마다 빨라졌다 느려진다 — 보간 구간이 리셋되고 있다',
      );
    });
  });

  group('다른 요원', () {
    RemotePlayer snapshot(double x, {Vector2? facing}) => RemotePlayer(
          characterId: 7,
          name: '동료',
          kind: 'male_cyborg',
          level: 3,
          grid: Vector2(x, 100),
          alive: true,
          hp: 100,
          maxHp: 100,
          facing: facing,
        );

    test('보고 사이가 고른 속도로 메워진다', () {
      const tick = 1 / 24;
      const speed = 3.0;
      final entity = RemotePlayerEntity(snapshot: snapshot(100));
      var serverX = 100.0;
      var sinceTick = 0.0;

      void advance(double dt) {
        entity.update(dt);
        sinceTick += dt;
        if (sinceTick >= tick) {
          sinceTick -= tick;
          serverX += speed * tick;
          entity.applySnapshot(snapshot(serverX));
        }
      }

      for (var i = 0; i < 40; i++) {
        advance(1 / 60);
      }
      final lengths = stepLengths(advance, entity.grid);

      expect(
        stalledRatio(lengths),
        lessThan(0.1),
        reason: '보고 사이에 멈춰 서는 프레임이 많다 — 남들이 끊겨 보인다',
      );
    });

    test('멈춰 서서 몸만 돌려도 방향이 따라온다', () {
      final entity = RemotePlayerEntity(snapshot: snapshot(100));
      for (var i = 0; i < 20; i++) {
        entity.update(1 / 60);
      }

      // 좌표는 그대로, 방향만 바뀐 보고.
      entity.applySnapshot(snapshot(100, facing: Vector2(1, 0)));
      for (var i = 0; i < 5; i++) {
        entity.update(1 / 60);
      }
      final right = entity.renderYaw;

      entity.applySnapshot(snapshot(100, facing: Vector2(-1, 0)));
      for (var i = 0; i < 5; i++) {
        entity.update(1 / 60);
      }
      expect(
        entity.renderYaw,
        isNot(closeTo(right, 0.05)),
        reason: '제자리에서 몸을 돌린 것이 남의 화면에 반영되지 않는다',
      );
    });
  });
}
