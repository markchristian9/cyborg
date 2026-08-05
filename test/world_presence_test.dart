@Tags(['integration'])
library;

/// 실제 maincloud 에서 **두 접속이 서로를 보는지** 확인한다.
///
/// 이 파일이 통과하지 못하면 "여럿이 하나의 월드를 공유한다" 는 전제가 성립하지
/// 않는다. 표와 reducer 가 다 있어도 클라이언트가 부르지 않으면 아무도 서로를
/// 볼 수 없고, 그 상태는 화면만 봐서는 "아직 아무도 접속하지 않았다" 와 구별되지
/// 않는다 — 그래서 사람 눈이 아니라 테스트가 지켜야 한다.
import 'package:flutter_test/flutter_test.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart';

import 'package:actionrpg/spacetime/cyborg_connection.dart';
import 'package:actionrpg/spacetime/generated/client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String uniqueEmail() =>
      'world-${DateTime.now().microsecondsSinceEpoch}@cyborg.test';

  /// 안전지대 안의 한 지점. 클라이언트가 지형을 보고 고르는 자리를 흉내낸다.
  ///
  /// 월드 중심은 (503, 503) 이고 안전지대는 한 변 50 타일이라, 중심에서 조금
  /// 벗어난 이 좌표도 안전지대 안이다.
  ({double x, double y}) spawnPoint(double dx, double dy) =>
      (x: 503 + dx, y: 503 + dy);

  /// 새 계정으로 접속해 캐릭터까지 만들고 월드에 들어간다.
  Future<SpacetimeDbClient> joinWorld(
    String name, {
    double dx = 0,
    double dy = 0,
  }) async {
    final client = await SpacetimeDbClient.create(
      host: kCyborgHost,
      database: kCyborgDatabase,
      ssl: kCyborgSsl,
      authStorage: InMemoryTokenStore(),
    );
    await client.connect(initialSubscriptions: kCyborgViewSubscriptions);

    await client.reducers.registerAccount(
      email: uniqueEmail(),
      password: 'hunter2!!',
    );
    await pumpUntil(() => client.myAccount != null);

    await client.reducers.createCharacter(name: name, kind: 'male_cyborg');
    await pumpUntil(() => client.myCharacters.count() == 1);

    final at = spawnPoint(dx, dy);
    // 구독은 이제 **자기 주변 청크만** 건다. 입장 좌표를 먼저 정해야 어느 청크를
    // 구독할지 알 수 있으므로, 좌표 계산이 구독보다 앞선다.
    await client.subscriptions.subscribe(worldSubscriptionsFor(at.x, at.y));
    await client.reducers.enterWorld(gridX: at.x, gridY: at.y);
    return client;
  }

  test('두 접속이 월드에서 서로를 본다', () async {
    final alice = await joinWorld('앨리스');
    final bob = await joinWorld('밥돌이');

    addTearDown(() async {
      await alice.reducers.leaveWorld();
      await bob.reducers.leaveWorld();
      await alice.disconnect();
      await bob.disconnect();
    });

    // 각자 자기 자신이 월드에 있는 것을 본다.
    await pumpUntil(() => alice.worldPlayer.iter().any(
          (p) => p.identity == alice.identity,
        ));
    await pumpUntil(() => bob.worldPlayer.iter().any(
          (p) => p.identity == bob.identity,
        ));

    // **서로**를 본다. 이것이 이 테스트의 전부다.
    await pumpUntil(() => alice.worldPlayer.iter().any(
          (p) => p.identity == bob.identity,
        ));
    await pumpUntil(() => bob.worldPlayer.iter().any(
          (p) => p.identity == alice.identity,
        ));

    final bobSeenByAlice =
        alice.worldPlayer.iter().firstWhere((p) => p.identity == bob.identity);
    expect(bobSeenByAlice.name, '밥돌이');
    expect(bobSeenByAlice.alive, isTrue);
  });

  test('입장하자마자 실제 스폰 자리에 보인다', () async {
    // 서버가 임의로 월드 중심에 세우면, 실제 몸이 선 자리와 어긋난 채로
    // 남의 화면에 나타난다. 그 간격은 속도 상한 때문에 몇 초에 걸쳐서야
    // 좁혀지고, 그동안 "움직여야 비로소 보이는" 증상이 된다.
    final watcher = await joinWorld('지켜보는자');
    final newcomer = await joinWorld('막들어온자', dx: -14, dy: -21);

    addTearDown(() async {
      await watcher.reducers.leaveWorld();
      await newcomer.reducers.leaveWorld();
      await watcher.disconnect();
      await newcomer.disconnect();
    });

    await pumpUntil(() => watcher.worldPlayer.iter().any(
          (p) => p.identity == newcomer.identity,
        ));

    final seen = watcher.worldPlayer
        .iter()
        .firstWhere((p) => p.identity == newcomer.identity);

    // 보고를 한 번도 하지 않았는데도 실제 스폰 자리에 있어야 한다.
    expect(
      seen.gridX,
      closeTo(503 - 14, 0.01),
      reason: '입장 좌표가 무시되고 월드 중심에 세워졌다',
    );
    expect(seen.gridY, closeTo(503 - 21, 0.01));
  });

  test('안전지대 밖 입장 좌표는 중심으로 떨어진다', () async {
    // 입장이 곧 무제한 텔레포트가 되면 안 된다.
    final client = await joinWorld('먼곳에서온자', dx: 300, dy: 300);
    addTearDown(() async {
      await client.reducers.leaveWorld();
      await client.disconnect();
    });

    // **`my_world_player` view 로 확인한다.** 청크 구독은 요청한 좌표 둘레를
    // 가져오는데 서버는 나를 중심으로 옮겨 세우므로, 그쪽에는 내 행이 없다 —
    // 바로 그 어긋남 때문에 이 view 가 필요했다.
    await pumpUntil(() => client.myWorldPlayer != null);

    final me = client.myWorldPlayer!;
    expect(me.gridX, closeTo(503, 0.01));
    expect(me.gridY, closeTo(503, 0.01));
  });

  test('한쪽이 움직이면 다른 쪽이 그 좌표를 받는다', () async {
    final alice = await joinWorld('이동자');
    final bob = await joinWorld('관찰자');

    addTearDown(() async {
      await alice.reducers.leaveWorld();
      await bob.reducers.leaveWorld();
      await alice.disconnect();
      await bob.disconnect();
    });

    await pumpUntil(() => bob.worldPlayer.iter().any(
          (p) => p.identity == alice.identity,
        ));

    final before = bob.worldPlayer
        .iter()
        .firstWhere((p) => p.identity == alice.identity);

    // 안전지대 중심에서 조금 걸어 나간다. 속도 상한(14타일/초)에 걸리지
    // 않도록 한 걸음만 옮긴다.
    final target = before.gridX + 3;
    await alice.reducers.moveTo(
      gridX: target,
      gridY: before.gridY,
      facingX: 1,
      facingY: 0,
    );

    await pumpUntil(() {
      final now = bob.worldPlayer
          .iter()
          .firstWhere((p) => p.identity == alice.identity);
      return (now.gridX - before.gridX).abs() > 0.5;
    });

    final after = bob.worldPlayer
        .iter()
        .firstWhere((p) => p.identity == alice.identity);
    expect(after.gridX, greaterThan(before.gridX));
  });

  test('월드를 나가면 상대 목록에서 사라진다', () async {
    final alice = await joinWorld('떠나는자');
    final bob = await joinWorld('남는자');

    addTearDown(() async {
      await bob.reducers.leaveWorld();
      await alice.disconnect();
      await bob.disconnect();
    });

    await pumpUntil(() => bob.worldPlayer.iter().any(
          (p) => p.identity == alice.identity,
        ));

    await alice.reducers.leaveWorld();

    // 조종하는 사람이 없는 몸이 사냥터에 남아 있으면 안 된다.
    await pumpUntil(() => !bob.worldPlayer.iter().any(
          (p) => p.identity == alice.identity,
        ));
  });
}

/// [condition] 이 참이 될 때까지 기다린다.
Future<void> pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('조건이 ${timeout.inSeconds}초 안에 만족되지 않았다');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
