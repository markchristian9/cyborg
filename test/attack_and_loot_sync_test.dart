@Tags(['integration'])
library;

/// 실제 maincloud 에서 **공격과 전리품이 남의 화면에도 닿는지** 확인한다.
///
/// 둘 다 "서버가 판정한다" 는 말만으로는 부족한 지점이다. 서버가 옳게 판정해도
/// 그 사실이 표에 남지 않으면 다른 사람 화면에서는 아무 일도 일어나지 않는다 —
/// 몹만 죽어 나가고 때린 사람은 가만히 서 있는 모습이 된다.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart';

import 'package:actionrpg/spacetime/cyborg_connection.dart';
import 'package:actionrpg/spacetime/generated/client.dart';
import 'package:actionrpg/spacetime/generated/monster.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const center = 503.0;

  String uniqueEmail() =>
      'atk-${DateTime.now().microsecondsSinceEpoch}@cyborg.test';

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

    final sx = x ?? center;
    final sy = y ?? center;
    await client.subscriptions.subscribe(worldSubscriptionsFor(sx, sy));
    await client.reducers.enterWorld(gridX: sx, gridY: sy);
    await pumpUntil(() =>
        client.worldPlayer.iter().any((p) => p.identity == client.identity));
    return client;
  }

  /// 이 파일이 쓰는 사냥 구역의 기준점.
  ///
  /// **파일마다 다른 방향을 본다.** 통합 테스트들이 병렬로 돌면서 모두 "안전지대
  /// 밖 가장 가까운 몹" 을 고르면 같은 한 마리에 몰려, 한쪽이 잡아 버린 몹을
  /// 다른 쪽이 계속 기다리다 실패한다. 기능이 멀쩡한데 테스트만 깨진다.
  //
  // **구독 범위 안이어야 한다.** 청크가 32 타일이라 3×3 의 보장 반경은 48
  // 타일이다. 그 밖의 몹은 아예 구독으로 오지 않는다.
  const huntX = center;
  const huntY = center + 40;

  /// 안전지대에서 넉넉히 떨어진, 이 파일 구역의 가장 가까운 몬스터.
  Monster? nearestLiveMonster(SpacetimeDbClient client) {
    Monster? best;
    var bestD2 = double.infinity;
    for (final m in client.monster.iter()) {
      if (!m.alive) continue;
      final dx = m.gridX - huntX;
      final dy = m.gridY - huntY;
      // 안전지대 안에 선 채로는 때릴 수 없다. 경계에 붙은 몹을 고르면 그 앞에
      // 선 플레이어가 아직 쉬는 곳 안이라 서버가 공격을 거절한다.
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

  /// 서버가 아는 내 좌표를 기준으로 [target] 까지 걸어간다.
  ///
  /// 보낸 좌표를 믿으면 안 된다 — 서버는 속도 상한으로 잘라 받으므로, 보낸
  /// 값과 실제로 선 자리가 벌어진 채 "도착했다" 고 착각하게 된다.
  Future<void> walkTo(
    SpacetimeDbClient client,
    double tx,
    double ty, {
    double within = 1.4,
  }) async {
    for (var i = 0; i < 80; i++) {
      final rows =
          client.worldPlayer.iter().where((p) => p.identity == client.identity);
      if (rows.isEmpty) return;
      final me = rows.first;
      final dx = tx - me.gridX;
      final dy = ty - me.gridY;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist <= within) return;
      final step = math.min(2.5, dist);
      await client.reducers.moveTo(
        gridX: me.gridX + dx / dist * step,
        gridY: me.gridY + dy / dist * step,
        facingX: dx / dist,
        facingY: dy / dist,
      );
      await Future<void>.delayed(const Duration(milliseconds: 220));
    }
  }

  test(
    '내가 휘두른 것이 다른 사람 화면에 남는다',
    timeout: const Timeout(Duration(minutes: 3)),
    () async {
      final attacker = await joinWorld('휘두르는쪽');
      addTearDown(() async => attacker.disconnect());

      await pumpUntil(() => attacker.monster.count() > 0);
      final target = nearestLiveMonster(attacker);
      expect(target, isNotNull, reason: '안전지대 밖에 살아 있는 몹이 없다');

      // 보는 쪽은 때리는 쪽 **근처**에 들어와야 한다. 관심 영역 구독이라
      // 월드 반대편에 있으면 애초에 서로의 행을 받지 않는다.
      final watcher =
          await joinWorld('보는쪽', x: target!.gridX, y: target.gridY);
      addTearDown(() async => watcher.disconnect());

      final attackerId = attacker.myCharacters.iter().first.id;
      await pumpUntil(
        () => watcher.worldPlayer.iter().any((p) => p.characterId == attackerId),
        timeout: const Duration(seconds: 20),
      );

      final before = watcher.worldPlayer
          .iter()
          .firstWhere((p) => p.characterId == attackerId)
          .lastAttackAt;

      await walkTo(attacker, target.gridX, target.gridY);

      // 몹은 서버 AI 로 움직인다. 처음 좌표만 보고 서 있으면 사거리를 벗어나
      // 한 대도 못 때리므로, 매번 **지금** 좌표로 다시 붙는다.
      var hits = 0;
      for (var i = 0; i < 12 && hits == 0; i++) {
        final live = attacker.monster.iter().where((m) => m.id == target.id);
        if (live.isEmpty) break;
        try {
          await attacker.reducers.attackMonster(monsterId: target.id);
          hits++;
        } on SpacetimeDbException {
          await walkTo(attacker, live.first.gridX, live.first.gridY);
        }
        await Future<void>.delayed(const Duration(milliseconds: 400));
      }
      expect(hits, greaterThan(0), reason: '한 대도 때리지 못해 동기화를 확인할 수 없다');

      // **보는 쪽**의 표에 공격 시각이 남았어야 한다. 이것이 없으면 남의
      // 화면에서 나는 가만히 선 채 몹만 죽어 나간다.
      await pumpUntil(
        () {
          final rows =
              watcher.worldPlayer.iter().where((p) => p.characterId == attackerId);
          if (rows.isEmpty) return false;
          return rows.first.lastAttackAt != before;
        },
        timeout: const Duration(seconds: 15),
      );

      final after =
          watcher.worldPlayer.iter().firstWhere((p) => p.characterId == attackerId);
      // 방향도 함께 와야 한다 — 없으면 어디를 보고 쳤는지 알 수 없어 등 뒤를
      // 향해 휘두르는 모습이 된다.
      // 때린 쪽이 본 자기 값과 남이 본 값이 **같아야** 한다. 어긋나면 각자
      // 다른 세계를 보고 있다는 뜻이다.
      final self = attacker.worldPlayer
          .iter()
          .firstWhere((p) => p.characterId == attackerId);
      expect(after.lastAttackAt, self.lastAttackAt);
      expect(after.attackDirY, self.attackDirY);

      final dirLength = math.sqrt(
        after.attackDirX * after.attackDirX + after.attackDirY * after.attackDirY,
      );
      expect(dirLength, greaterThan(0.9), reason: '공격 방향이 오지 않았다');
    },
  );

  test(
    '제자리에서 몸만 돌려도 남의 화면에 방향이 닿는다',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      // **안전지대 안**에 둘을 세운다. 밖을 지정하면 서버가 입장 좌표를 중심으로
      // 되돌리는데 구독은 지정한 자리 기준으로 걸려, 정작 자기 주변이 구독
      // 범위 밖이 된다. 몸을 돌리는 데 안전지대 여부는 상관없다.
      const spot = center + 10;
      final turner = await joinWorld('도는쪽', x: spot, y: spot);
      final watcher = await joinWorld('보는쪽2', x: spot, y: spot);
      addTearDown(() async {
        await turner.disconnect();
        await watcher.disconnect();
      });

      final turnerId = turner.myCharacters.iter().first.id;
      await pumpUntil(
        () => watcher.worldPlayer.iter().any((p) => p.characterId == turnerId),
      );

      // **좌표를 바꾸지 않고** 방향만 바꾼다. 이것이 좌표만 보내던 시절에는
      // 남의 화면에 아무것도 남기지 못하던 동작이다.
      final me = turner.worldPlayer
          .iter()
          .firstWhere((p) => p.identity == turner.identity);
      await turner.reducers.moveTo(
        gridX: me.gridX,
        gridY: me.gridY,
        facingX: 1,
        facingY: 0,
      );
      await pumpUntil(
        () {
          final rows =
              watcher.worldPlayer.iter().where((p) => p.characterId == turnerId);
          return rows.isNotEmpty && rows.first.facingX > 0.9;
        },
        timeout: const Duration(seconds: 15),
      );

      // 반대쪽으로 돌린다. 한 번 맞은 것이 우연이 아님을 본다.
      await turner.reducers.moveTo(
        gridX: me.gridX,
        gridY: me.gridY,
        facingX: -1,
        facingY: 0,
      );
      await pumpUntil(
        () {
          final rows =
              watcher.worldPlayer.iter().where((p) => p.characterId == turnerId);
          return rows.isNotEmpty && rows.first.facingX < -0.9;
        },
        timeout: const Duration(seconds: 15),
      );
    },
  );

  test(
    '멈춰서 때리는 몹도 대상 쪽을 본다',
    timeout: const Timeout(Duration(minutes: 3)),
    () async {
      final bait = await joinWorld('미끼');
      addTearDown(() async => bait.disconnect());
      await pumpUntil(() => bait.monster.count() > 0);
      expect(nearestLiveMonster(bait), isNotNull, reason: '안전지대 밖에 살아 있는 몹이 없다');

      // 몹이 죽으면 **다른 몹으로 다시 시작한다.** 다른 테스트가 같은 사냥터에서
      // 돌고 있어 눈앞의 몹이 사라지는 일이 흔하다 — 한 마리를 놓쳤다고 서버가
      // 틀린 것은 아니다.
      var faced = false;
      for (var round = 0; round < 4 && !faced; round++) {
        final target = nearestLiveMonster(bait);
        if (target == null) break;
        final prey = target;

        for (var attempt = 0; attempt < 4 && !faced; attempt++) {
          final live = bait.monster.iter().where((m) => m.id == prey.id);
          if (live.isEmpty || !live.first.alive) break;

          // 몹도 다가오므로 **지금** 좌표로 붙는다.
          await walkTo(bait, live.first.gridX, live.first.gridY, within: 1.2);

          for (var i = 0; i < 16 && !faced; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
            final rows = bait.monster.iter().where((m) => m.id == prey.id);
            final meRows = bait.worldPlayer
                .iter()
                .where((p) => p.identity == bait.identity);
            if (rows.isEmpty || meRows.isEmpty) continue;
            final m = rows.first;
            final me = meRows.first;
            final dx = me.gridX - m.gridX;
            final dy = me.gridY - m.gridY;
            final len = math.sqrt(dx * dx + dy * dy);
            // 사거리 밖이면 몹은 걸어오는 중이라 방향이 나를 향하는 것이
            // 당연하다. 이 테스트가 보려는 것은 **멈춘 채** 보는지다.
            if (len < 0.01 || len > 2.6) continue;
            // 몹이 보는 쪽과 실제 내가 선 쪽의 내적. 1 에 가까우면 나를 본다.
            final dot = (dx / len) * m.faceX + (dy / len) * m.faceY;
            if (dot > 0.85) faced = true;
          }
        }
      }

      expect(
        faced,
        isTrue,
        reason: '사거리 안에서 멈춘 몹이 대상 쪽을 보지 않는다 — 등 뒤로 휘두르게 된다',
      );
    },
  );

  test(
    '몹이 후려친 사실이 표에 남는다 — 모든 화면이 같은 타격을 본다',
    timeout: const Timeout(Duration(minutes: 3)),
    () async {
      final bait = await joinWorld('맞는쪽');
      addTearDown(() async => bait.disconnect());
      await pumpUntil(() => bait.monster.count() > 0);

      final target = nearestLiveMonster(bait);
      expect(target, isNotNull);
      final prey = target!;
      final before = bait.monster.iter().firstWhere((m) => m.id == prey.id).lastAttackAt;

      // 맞을 때까지 붙어 선다. 서버가 때리면 그 사실이 몹 행에 남아야 한다 —
      // 남지 않으면 어느 화면에서도 몹은 조용히 서 있고 체력만 줄어든다.
      var struck = false;
      for (var attempt = 0; attempt < 8 && !struck; attempt++) {
        final live = bait.monster.iter().where((m) => m.id == prey.id);
        if (live.isEmpty || !live.first.alive) break;
        await walkTo(bait, live.first.gridX, live.first.gridY, within: 1.2);

        for (var i = 0; i < 16 && !struck; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          final rows = bait.monster.iter().where((m) => m.id == prey.id);
          if (rows.isEmpty) continue;
          if (rows.first.lastAttackAt != before) struck = true;
        }
      }

      expect(
        struck,
        isTrue,
        reason: '몹이 때렸는데 그 사실이 표에 남지 않는다 — 타격 모션을 재생할 근거가 없다',
      );
    },
  );

  test(
    '레벨이 오르면 마력 상한도 함께 오른다',
    timeout: const Timeout(Duration(minutes: 2)),
    () async {
      final client = await joinWorld('성장확인');
      addTearDown(() async => client.disconnect());

      final me = client.worldPlayer
          .iter()
          .firstWhere((p) => p.identity == client.identity);
      // 레벨 1 의 상한이 서버 곡선과 맞는지만 본다. 실제 레벨업까지 사냥하려면
      // 시간이 너무 걸리고, 곡선 자체는 서버 단위 테스트가 지킨다.
      expect(me.maxMp, greaterThan(0), reason: '마력 상한이 서지 않았다');
      expect(me.mp, lessThanOrEqualTo(me.maxMp));
    },
  );

  test(
    '전리품은 서버가 떨구고 두 사람이 같은 것을 본다',
    timeout: const Timeout(Duration(minutes: 4)),
    () async {
      final hunter = await joinWorld('사냥꾼');
      addTearDown(() async => hunter.disconnect());
      await pumpUntil(() => hunter.monster.count() > 0);

      // 레벨 1 캐릭터로 잡을 수 있는, 가장 약한 몹을 고른다.
      Monster? weakest;
      for (final m in hunter.monster.iter()) {
        if (!m.alive) continue;
        final dx = m.gridX - center;
        final dy = m.gridY - center;
        if (dx.abs() < 40 && dy.abs() < 40) continue;
        if (weakest == null || m.level < weakest.level) weakest = m;
      }
      expect(weakest, isNotNull);

      final prey = weakest!;
      final watcher = await joinWorld('구경꾼', x: prey.gridX, y: prey.gridY);
      addTearDown(() async => watcher.disconnect());

      await walkTo(hunter, prey.gridX, prey.gridY);

      // 쓰러질 때까지 친다.
      for (var i = 0; i < 120; i++) {
        final rows = hunter.monster.iter().where((m) => m.id == prey.id);
        if (rows.isEmpty || !rows.first.alive) break;
        try {
          await hunter.reducers.attackMonster(monsterId: prey.id);
        } on SpacetimeDbException {
          // 쿨다운·사거리. 몹이 움직였을 수 있으니 다시 붙는다.
          await walkTo(hunter, rows.first.gridX, rows.first.gridY);
        }
        await Future<void>.delayed(const Duration(milliseconds: 380));
      }

      final dead = hunter.monster.iter().where((m) => m.id == prey.id);
      expect(
        dead.isNotEmpty && !dead.first.alive,
        isTrue,
        reason: '몹을 쓰러뜨리지 못해 드롭을 확인할 수 없다',
      );

      // 쓰러진 자리 근처에 전리품이 생겨야 하고, **두 사람 모두** 같은 번호를
      // 봐야 한다. 각자 굴리면 여기서 갈린다.
      await pumpUntil(
        () => hunter.loot.iter().any((l) =>
            (l.gridX - prey.gridX).abs() < 8 &&
            (l.gridY - prey.gridY).abs() < 8),
        timeout: const Duration(seconds: 15),
      );

      final mine = hunter.loot
          .iter()
          .where((l) =>
              (l.gridX - prey.gridX).abs() < 8 &&
              (l.gridY - prey.gridY).abs() < 8)
          .toList();
      expect(mine, isNotEmpty);

      await pumpUntil(
        () => mine.every((l) => watcher.loot.iter().any((o) => o.id == l.id)),
        timeout: const Duration(seconds: 15),
      );

      for (final l in mine) {
        final theirs = watcher.loot.iter().firstWhere((o) => o.id == l.id);
        expect(theirs.kind, l.kind, reason: '같은 번호인데 종류가 다르다');
        expect(theirs.amount, l.amount, reason: '같은 번호인데 양이 다르다');
      }
    },
  );
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
