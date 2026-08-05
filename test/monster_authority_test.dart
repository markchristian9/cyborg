@Tags(['integration'])
library;

/// 실제 maincloud 에서 **몬스터가 서버 권위인지** 확인한다.
///
/// 확인하는 것은 세 가지다.
/// 1. 두 접속이 **같은 몬스터**를 본다 (각자 만들어 낸 것이 아니다)
/// 2. 서버가 몬스터를 **움직인다** (플레이어가 다가가면 쫓아온다)
/// 3. 한쪽이 때린 결과를 **다른 쪽도 본다** (체력이 함께 줄어든다)
///
/// 이 셋이 서지 않으면 파티도 협업 레이드도 성립하지 않는다 — A 가 잡은 몹이
/// B 화면에 살아 있고, A 를 쫓는 몹이 B 화면에서는 제자리이기 때문이다.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart';

import 'package:actionrpg/spacetime/cyborg_connection.dart';
import 'package:actionrpg/spacetime/generated/client.dart';
import 'package:actionrpg/spacetime/generated/monster.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String uniqueEmail() =>
      'mon-${DateTime.now().microsecondsSinceEpoch}@cyborg.test';

  /// 월드 중심. 안전지대 한가운데다.
  const center = 503.0;

  Future<SpacetimeDbClient> joinWorld(String name, {double? x, double? y}) async {
    final client = await SpacetimeDbClient.create(
      host: kCyborgHost,
      database: kCyborgDatabase,
      ssl: kCyborgSsl,
      authStorage: InMemoryTokenStore(),
    );
    await client.connect(initialSubscriptions: kCyborgViewSubscriptions);

    await client.reducers
        .registerAccount(email: uniqueEmail(), password: 'hunter2!!');
    await pumpUntil(() => client.myAccount != null);

    await client.reducers.createCharacter(name: name, kind: 'male_cyborg');
    await pumpUntil(() => client.myCharacters.count() == 1);

    // 구독은 자기 주변 청크만 건다 — **어디에 서느냐가 무엇을 보느냐**를 정한다.
    // 특정 몹을 함께 봐야 하는 테스트는 그 몹 근처를 넘겨 받는다.
    final sx = x ?? center;
    final sy = y ?? center;
    await client.subscriptions.subscribe(worldSubscriptionsFor(sx, sy));
    await client.reducers.enterWorld(gridX: sx, gridY: sy);

    // 내 행이 실제로 도착할 때까지 기다린다. 이걸 빠뜨리면 뒤따르는 코드가
    // "나는 월드에 없다" 고 판단해 조용히 아무것도 하지 않는다.
    await pumpUntil(() => client.worldPlayer
        .iter()
        .any((p) => p.identity == client.identity));
    return client;
  }

  /// 이 파일이 쓰는 사냥 구역의 기준점.
  ///
  /// **파일마다 다른 방향을 본다.** 통합 테스트들이 병렬로 돌면서 모두 "안전지대
  /// 밖 가장 가까운 몹" 을 고르면 같은 한 마리에 몰려, 한쪽이 잡아 버린 몹을
  /// 다른 쪽이 계속 기다리다 실패한다. 기능이 멀쩡한데 테스트만 깨진다.
  //
  // **구독 범위 안이어야 한다.** 청크가 32 타일이라 3×3 의 보장 반경은 48
  // 타일이다. 예전에 쓰던 120 타일은 청크가 74 였을 때는 범위 안이었지만 지금은
  // 밖이라, 그 구역 몹은 아예 구독으로 오지 않는다.
  const huntX = center;
  const huntY = center - 40;

  /// 안전지대 밖, 이 파일의 구역에서 가장 가까운 살아 있는 몬스터.
  Monster? nearestLiveMonster(SpacetimeDbClient client) {
    Monster? best;
    var bestD2 = double.infinity;
    for (final m in client.monster.iter()) {
      if (!m.alive) continue;
      final dx = m.gridX - huntX;
      final dy = m.gridY - huntY;
      // 안전지대에서 **넉넉히** 떨어진 몹이어야 한다. 경계에 붙은 몹을 고르면
      // 그 앞에 선 플레이어가 아직 안전지대 안이고, 서버는 쉬는 곳까지 몹을
      // 들이지 않으므로 추격이 일어나지 않는다.
      // 안전지대(중심 ±25)에서 벗어나야 한다. 그 안에 선 플레이어는 몹이
      // 쫓지 않으므로 추격도 공격도 일어나지 않는다.
      if ((m.gridX - center).abs() < 30 && (m.gridY - center).abs() < 30) {
        continue;
      }
      final d2 = dx * dx + dy * dy;
      if (d2 < bestD2) {
        bestD2 = d2;
        best = m;
      }
    }
    return best;
  }

  test('두 접속이 같은 몬스터를 본다', () async {
    // 같은 자리에 선 둘은 같은 청크를 구독하므로 같은 몹을 받아야 한다.
    final alice = await joinWorld('몹관찰A');
    final bob = await joinWorld('몹관찰B');
    addTearDown(() async {
      await alice.disconnect();
      await bob.disconnect();
    });

    await pumpUntil(() => alice.monster.count() > 0);
    await pumpUntil(() => bob.monster.count() > 0);

    // 같은 번호의 몹이 같은 자리에 있어야 한다. 각자 만들어 낸 것이라면
    // 번호부터 겹치지 않는다.
    final fromAlice = alice.monster.iter().take(20).toList();
    var matched = 0;
    for (final m in fromAlice) {
      final theirs = bob.monster.iter().where((o) => o.id == m.id);
      if (theirs.isEmpty) continue;
      final other = theirs.first;
      expect(other.level, m.level, reason: '같은 번호인데 레벨이 다르다');
      matched++;
    }
    expect(matched, greaterThan(10), reason: '두 접속이 보는 몬스터가 겹치지 않는다');
  });

  test('서버가 몬스터를 움직인다 — 다가가면 쫓아온다', timeout: const Timeout(Duration(minutes: 2)), () async {
    final client = await joinWorld('추격유도');
    addTearDown(() async => client.disconnect());

    await pumpUntil(() => client.monster.count() > 0);

    final target = nearestLiveMonster(client);
    expect(target, isNotNull, reason: '안전지대 밖에 살아 있는 몹이 없다');
    final id = target!.id;
    final startX = target.gridX;
    final startY = target.gridY;
    // ignore: avoid_print
    print('목표 몹 #$id Lv.${target.level} at ($startX, $startY)');

    // 어그로 범위(9타일) 안까지 다가간다.
    //
    // **서버가 아는 내 좌표**를 기준으로 걷는다. 내가 보낸 값을 그대로 믿으면
    // 안 된다 — 서버는 속도 상한(14타일/초)으로 잘라 받으므로, 보낸 좌표와
    // 실제로 선 자리가 벌어진 채 "도착했다" 고 착각하게 된다.
    for (var i = 0; i < 60; i++) {
      final meRows =
          client.worldPlayer.iter().where((p) => p.identity == client.identity);
      if (meRows.isEmpty) break;
      final me = meRows.first;
      final dx = startX - me.gridX;
      final dy = startY - me.gridY;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (i % 10 == 0) {
        // ignore: avoid_print
        print('  걸음 $i: 내 위치 (${me.gridX.toStringAsFixed(1)}, '
            '${me.gridY.toStringAsFixed(1)}) 남은거리 ${dist.toStringAsFixed(1)}');
      }
      if (dist <= 4) break;
      final step = math.min(2.5, dist);
      await client.reducers.moveTo(
        gridX: me.gridX + dx / dist * step,
        gridY: me.gridY + dy / dist * step,
        facingX: dx / dist,
        facingY: dy / dist,
      );
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }

    // 서버 AI 가 도는 동안 기다린다. 몹이 제자리를 벗어나야 한다.
    var moved = false;
    final deadline = DateTime.now().add(const Duration(seconds: 12));
    while (DateTime.now().isBefore(deadline)) {
      final now = client.monster.iter().where((m) => m.id == id);
      if (now.isNotEmpty) {
        final m = now.first;
        if ((m.gridX - startX).abs() > 0.3 || (m.gridY - startY).abs() > 0.3) {
          moved = true;
          break;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    expect(
      moved,
      isTrue,
      reason: '서버가 몬스터를 움직이지 않는다 — AI 틱이 돌지 않거나 어그로가 잡히지 않는다',
    );
  });

  test('한쪽이 때린 결과를 다른 쪽도 본다', timeout: const Timeout(Duration(minutes: 2)), () async {
    final attacker = await joinWorld('때리는쪽');
    addTearDown(() async => attacker.disconnect());
    await pumpUntil(() => attacker.monster.count() > 0);

    final target = nearestLiveMonster(attacker);
    expect(target, isNotNull);
    final id = target!.id;

    // 보는 쪽은 그 몹 **근처**에 입장한다. 관심 영역 구독이라 멀리 있으면
    // 애초에 그 몹의 행을 받지 않는다.
    final watcher =
        await joinWorld('보는쪽', x: target.gridX, y: target.gridY);
    addTearDown(() async => watcher.disconnect());
    await pumpUntil(() => watcher.monster.iter().any((m) => m.id == id));

    // 사거리(2.2타일) 안으로 붙는다. 여기서도 서버 좌표를 기준으로 걷는다.
    for (var i = 0; i < 70; i++) {
      final live = attacker.monster.iter().where((m) => m.id == id);
      if (live.isEmpty) break;
      final meRows = attacker.worldPlayer
          .iter()
          .where((p) => p.identity == attacker.identity);
      if (meRows.isEmpty) break;
      final m = live.first;
      final me = meRows.first;
      final dx = m.gridX - me.gridX;
      final dy = m.gridY - me.gridY;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist <= 1.5) break;
      final step = math.min(2.5, dist);
      await attacker.reducers.moveTo(
        gridX: me.gridX + dx / dist * step,
        gridY: me.gridY + dy / dist * step,
        facingX: dx / dist,
        facingY: dy / dist,
      );
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }

    final before = watcher.monster.iter().firstWhere((m) => m.id == id).hp;

    // 여러 번 때린다. 쿨다운(0.35초)을 지키며.
    for (var i = 0; i < 8; i++) {
      try {
        await attacker.reducers.attackMonster(monsterId: id);
      } on SpacetimeDbException {
        // 사거리 밖이거나 쿨다운이면 서버가 거절한다. 다음 번에 다시 시도한다.
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }

    // **보는 쪽**의 화면에서 체력이 줄었어야 한다. 이것이 협업의 최소 조건이다.
    await pumpUntil(
      () {
        final rows = watcher.monster.iter().where((m) => m.id == id);
        if (rows.isEmpty) return false;
        final m = rows.first;
        return m.hp < before || !m.alive;
      },
      timeout: const Duration(seconds: 12),
    );
  });
}

Future<void> pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('조건이 ${timeout.inSeconds}초 안에 만족되지 않았다');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
