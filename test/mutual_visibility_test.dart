@Tags(['integration'])
library;

/// **실제 앱과 같은 경로로** 두 사람이 서로를 보는지 확인한다.
///
/// 기존 `world_presence_test.dart` 는 SDK 를 직접 써서 같은 좌표에 입장한다.
/// 실제 게임은 그렇지 않다 — `SpacetimeWorldPresence.enter` 가 구독을 걸고,
/// 스폰 자리는 안전지대 안 **무작위**이며, 그 뒤로는 `report` 가 좌표를 민다.
/// 그 차이 어딘가에서 끊기면 테스트는 통과하는데 화면에는 아무도 없다.
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart';

import 'package:actionrpg/spacetime/cyborg_connection.dart';
import 'package:actionrpg/spacetime/generated/client.dart';
import 'package:actionrpg/spacetime/spacetime_world_presence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 안전지대 중심과 반폭 — `LevelMap.respawnPoint` 가 쓰는 범위와 같다.
  const center = 503.0;
  const halfExtent = 23.5;

  Future<SpacetimeWorldPresence> joinLikeTheApp(
    String name,
    Vector2 spawn,
  ) async {
    final client = await SpacetimeDbClient.create(
      host: kCyborgHost,
      database: kCyborgDatabase,
      ssl: kCyborgSsl,
      authStorage: InMemoryTokenStore(),
    );
    await client.connect(initialSubscriptions: kCyborgViewSubscriptions);
    await client.reducers.registerAccount(
      email: 'vis-${DateTime.now().microsecondsSinceEpoch}-$name@cyborg.test',
      password: 'hunter2!!',
    );
    await _until(() => client.myAccount != null);
    await client.reducers.createCharacter(name: name, kind: 'male_cyborg');
    await _until(() => client.myCharacters.count() == 1);

    // 실제 앱과 같은 진입점. 구독도 이 안에서 건다.
    final presence = SpacetimeWorldPresence(client);
    await presence.enter(spawn);
    return presence;
  }

  test(
    '안전지대에 함께 선 두 사람은 서로를 본다',
    timeout: const Timeout(Duration(minutes: 3)),
    () async {
      // 안전지대 안 무작위 두 자리 — 실제 스폰과 같은 방식이다. 시드를 고정해
      // 실패했을 때 같은 자리를 다시 만들 수 있게 한다.
      final rng = math.Random(20260805);
      Vector2 spawn() => Vector2(
            center + (rng.nextDouble() * 2 - 1) * halfExtent,
            center + (rng.nextDouble() * 2 - 1) * halfExtent,
          );

      final aSpawn = spawn();
      final bSpawn = spawn();
      // ignore: avoid_print
      print('A 스폰 (${aSpawn.x.toStringAsFixed(1)}, ${aSpawn.y.toStringAsFixed(1)}) · '
          'B 스폰 (${bSpawn.x.toStringAsFixed(1)}, ${bSpawn.y.toStringAsFixed(1)}) · '
          '거리 ${(aSpawn - bSpawn).length.toStringAsFixed(1)} 타일');

      final alice = await joinLikeTheApp('가시성A', aSpawn);
      final bob = await joinLikeTheApp('가시성B', bSpawn);
      addTearDown(() {
        alice.leave();
        bob.leave();
      });

      // 게임 루프가 하는 일을 흉내 낸다 — 매 프레임 좌표를 민다.
      var aliceSeesBob = false;
      var bobSeesAlice = false;
      for (var i = 0; i < 100; i++) {
        alice.report(aSpawn, Vector2(0, 1));
        bob.report(bSpawn, Vector2(0, 1));
        await Future<void>.delayed(const Duration(milliseconds: 100));

        aliceSeesBob = alice.others.isNotEmpty;
        bobSeesAlice = bob.others.isNotEmpty;
        if (aliceSeesBob && bobSeesAlice) break;

        if (i % 20 == 19) {
          // ignore: avoid_print
          print('${(i + 1) * 100}ms: A 가 보는 사람 ${alice.others.length} 명 · '
              'B 가 보는 사람 ${bob.others.length} 명');
        }
      }

      expect(
        aliceSeesBob,
        isTrue,
        reason: 'A 화면에 B 가 없다 — 같은 안전지대에 서 있는데도 보이지 않는다',
      );
      expect(
        bobSeesAlice,
        isTrue,
        reason: 'B 화면에 A 가 없다',
      );
    },
  );
}

Future<void> _until(bool Function() c) async {
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  while (!c()) {
    if (DateTime.now().isAfter(deadline)) fail('시간 초과');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
