@Tags(['integration'])
library;

/// **움직이지 않는 몹이 화면에서 사라지는가**를 실측한다.
///
/// 제기된 가설: 플레이어가 멈춰 서고 몹이 사거리 안에 붙으면 서버가 좌표를
/// 갱신하지 않는다 → 구독으로 아무 이벤트도 오지 않는다 → 클라이언트 화면에서
/// 몹이 사라진다.
///
/// 앞의 두 단계는 코드상 사실이다(`monster_ai` 는 사거리 안에서 `step_toward`
/// 를 아예 거치지 않는다). 확인할 것은 **세 번째 단계**다 — 갱신이 없을 때
/// 구독 캐시에서 행이 사라지는지, 아니면 그대로 남는지.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart';

import 'package:actionrpg/spacetime/cyborg_connection.dart';
import 'package:actionrpg/spacetime/generated/client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const center = 503.0;

  test(
    '멈춰 선 몹도 구독 캐시에 남는다',
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
        email: 'idle-${DateTime.now().microsecondsSinceEpoch}@cyborg.test',
        password: 'hunter2!!',
      );
      await _until(() => client.myAccount != null);
      await client.reducers.createCharacter(name: '멈춘자', kind: 'male_cyborg');
      await _until(() => client.myCharacters.count() == 1);

      // 서쪽 구역 — 다른 통합 테스트와 겹치지 않는 자리다.
      const spawnX = center - 120;
      const spawnY = center;
      await client.subscriptions.subscribe(worldSubscriptionsFor(spawnX, spawnY));
      await client.reducers.enterWorld(gridX: spawnX, gridY: spawnY);
      await _until(() => client.myWorldPlayer != null);
      await _until(() => client.monster.count() > 0);

      // 가장 가까운 살아 있는 몹에게 붙는다. 사거리 안에 서면 서버는 그 몹을
      // 더 이상 움직이지 않는다 — 바로 그 상태를 만들려는 것이다.
      int? preyId;
      var bestD2 = double.infinity;
      for (final m in client.monster.iter()) {
        if (!m.alive) continue;
        final dx = m.gridX - spawnX;
        final dy = m.gridY - spawnY;
        final d2 = dx * dx + dy * dy;
        if (d2 < bestD2) {
          bestD2 = d2;
          preyId = m.id.toInt();
        }
      }
      expect(preyId, isNotNull, reason: '주변에 살아 있는 몹이 없다');

      for (var i = 0; i < 60; i++) {
        final rows = client.monster.iter().where((m) => m.id.toInt() == preyId);
        final meRow = client.myWorldPlayer;
        if (rows.isEmpty || meRow == null) break;
        final m = rows.first;
        final dx = m.gridX - meRow.gridX;
        final dy = m.gridY - meRow.gridY;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist <= 1.5) break;
        final step = math.min(2.5, dist);
        await client.reducers.moveTo(
          gridX: meRow.gridX + dx / dist * step,
          gridY: meRow.gridY + dy / dist * step,
          facingX: dx / dist,
          facingY: dy / dist,
        );
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }

      // 이제 **아무것도 하지 않는다.** 좌표 보고도 멈춘다 — 실제로 손을 놓은
      // 플레이어와 같은 상태다.
      final startRow =
          client.monster.iter().firstWhere((m) => m.id.toInt() == preyId);
      // ignore: avoid_print
      print('감시 시작 — 몹 #$preyId at (${startRow.gridX}, ${startRow.gridY}), '
          '주변 몹 ${client.monster.count()} 기');

      var vanished = false;
      var moves = 0;
      var lastX = startRow.gridX;
      var lastY = startRow.gridY;
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        final rows = client.monster.iter().where((m) => m.id.toInt() == preyId);
        if (rows.isEmpty) {
          vanished = true;
          // ignore: avoid_print
          print('${i + 1}초: 몹 행이 캐시에서 사라졌다');
          break;
        }
        final m = rows.first;
        if (m.gridX != lastX || m.gridY != lastY) {
          moves++;
          lastX = m.gridX;
          lastY = m.gridY;
        }
        if (i % 5 == 4) {
          // ignore: avoid_print
          print('${i + 1}초: 전체 ${client.monster.count()} 기 · '
              '이 몹 살아있음=${m.alive} 좌표변화 $moves 회 '
              'hp=${m.hp}/${m.maxHp}');
        }
      }

      await client.disconnect();

      expect(
        vanished,
        isFalse,
        reason: '움직이지 않는 몹의 행이 구독 캐시에서 사라진다 — 가설이 사실이다',
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
