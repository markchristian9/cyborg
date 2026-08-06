@Tags(['integration'])
library;

/// [SpacetimeWorldPresence.monsters] 가 **행이 바뀔 때만** 목록을 다시 짓는지
/// 확인한다.
///
/// 이 게터는 게임 루프가 프레임마다 부른다
/// (`ActionRpgGame._refreshMonsterStreaming`). 구독 청크 안에는 몹이 수백 기씩
/// 들어오므로, 부를 때마다 다시 지으면 [ServerMonster] 하나와 [Vector2] 둘이
/// 몹 수만큼 태어난다 — 초당 6 만 개가 넘는 쓰레기이고, 그 값은 고스란히 GC 가
/// 프레임을 갉는 것으로 돌아온다.
///
/// 캐시는 두 가지를 **함께** 지켜야 한다. 하나라도 어긋나면 조용히 틀린다.
///
///  - 행이 그대로면 **같은 목록**을 준다 (아끼는 쪽)
///  - 행이 바뀌면 **새 목록**을 준다 (낡지 않는 쪽)
///
/// 뒤엣것이 깨지면 몹이 화면에서 얼어붙는다. 그래서 실제 서버에 붙어 확인한다 —
/// 캐시가 기대는 근거(`TableCache` 가 표가 바뀔 때마다 `rows.value` 에 새 List
/// 를 대입한다)가 SDK 쪽 사정이라, 가짜로는 그 근거째 검증할 수 없다.
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart';

import 'package:actionrpg/game/net/world_presence.dart';
import 'package:actionrpg/spacetime/cyborg_connection.dart';
import 'package:actionrpg/spacetime/generated/client.dart';
import 'package:actionrpg/spacetime/spacetime_world_presence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const center = 503.0;

  test(
    '몹 목록은 행이 바뀔 때만 다시 지어진다',
    timeout: const Timeout(Duration(minutes: 4)),
    () async {
      final client = await SpacetimeDbClient.create(
        host: kCyborgHost,
        database: kCyborgDatabase,
        ssl: kCyborgSsl,
        authStorage: InMemoryTokenStore(),
      );
      await client.connect(initialSubscriptions: kCyborgViewSubscriptions);
      await client.reducers.registerAccount(
        email: 'mcache-${DateTime.now().microsecondsSinceEpoch}@cyborg.test',
        password: 'hunter2!!',
      );
      await _until(() => client.myAccount != null);
      await client.reducers.createCharacter(name: '헤아리는자', kind: 'male_cyborg');
      await _until(() => client.myCharacters.count() == 1);

      // 북쪽 구역 — 다른 통합 테스트와 자리를 겹치지 않게 둔다.
      const spawnX = center;
      const spawnY = center - 120;

      final presence = SpacetimeWorldPresence(client);
      await presence.enter(Vector2(spawnX, spawnY));
      await _until(() => client.monster.count() > 0);

      final first = presence.monsters;
      expect(first, isNotEmpty, reason: '몹이 하나도 구독되지 않았다');

      // ── 아끼는 쪽 ────────────────────────────────────────────────────
      // 사이에 아무 일도 없었으므로 같은 목록이어야 한다.
      expect(
        identical(presence.monsters, first),
        isTrue,
        reason: '행이 그대로인데 목록을 다시 지었다',
      );

      // ── 낡지 않는 쪽 ─────────────────────────────────────────────────
      //
      // 가만히 서 있으면 행은 **영영 바뀌지 않는다.** 서버는 사거리 밖의 조용한
      // 몹을 아예 건드리지 않으므로(`needs_tick`), 그냥 기다리는 것으로는 이쪽을
      // 확인할 수 없다 — `idle_monster_visibility_test` 가 25 초 동안 좌표 변화
      // 0 회를 실측해 둔 그 성질이다. 그래서 직접 몹을 깨우러 간다.
      final prey = _nearestAlive(presence.monsters, Vector2(spawnX, spawnY));
      expect(prey, isNotNull, reason: '살아 있는 몹을 찾지 못했다');

      var here = Vector2(spawnX, spawnY);
      for (var i = 0; i < 60; i++) {
        if (!identical(presence.monsters, first)) break;
        final toPrey = prey!.grid - here;
        if (toPrey.length > 0.1) {
          // 서버가 속도 상한으로 자르지 않도록 한 걸음씩 다가간다.
          final step = math.min(2.5, toPrey.length);
          here = here + toPrey.normalized() * step;
          presence.report(here, toPrey.normalized());
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }

      final changed = !identical(presence.monsters, first);
      expect(
        changed,
        isTrue,
        reason: '행이 바뀌었는데도 옛 목록을 그대로 주고 있다 — 몹이 화면에서 언다',
      );

      // 다시 지어진 목록도 멀쩡해야 한다. 캐시가 빈 목록으로 굳는 실패를 막는다.
      expect(presence.monsters, isNotEmpty);

      presence.leave();
      await client.disconnect();
    },
  );
}

/// [from] 에서 가장 가까운, 살아 있는 몹.
ServerMonster? _nearestAlive(List<ServerMonster> monsters, Vector2 from) {
  ServerMonster? best;
  var bestDistance2 = double.infinity;
  for (final monster in monsters) {
    if (!monster.alive) continue;
    final d2 = (monster.grid - from).length2;
    if (d2 < bestDistance2) {
      bestDistance2 = d2;
      best = monster;
    }
  }
  return best;
}

/// [check] 가 참이 될 때까지 기다린다. 끝내 참이 되지 않으면 실패한다.
Future<void> _until(
  bool Function() check, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final ok = await _waitFor(check, timeout: timeout);
  if (!ok) throw StateError('조건이 $timeout 안에 성립하지 않았다');
}

/// [check] 가 참이 되면 true, 시간이 다하면 false.
Future<bool> _waitFor(
  bool Function() check, {
  required Duration timeout,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (check()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return check();
}
