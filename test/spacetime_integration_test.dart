@Tags(['integration'])
library;

/// 실제 maincloud 의 `withcenter-cyborg` 에 붙어서 인증·캐릭터 흐름을 확인한다.
///
/// 네트워크가 필요하므로 기본 테스트에서 제외한다:
///
/// ```sh
/// flutter test --tags integration test/spacetime_integration_test.dart
/// ```
///
/// 서버가 실제로 무엇을 돌려주는지 확인하는 것이 목적이다. 이 흐름이 통과하는
/// 한 화면 코드는 view 세 개(`my_account`·`my_session`·`my_characters`)만
/// 믿으면 된다.
import 'package:flutter_test/flutter_test.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart';

import 'package:actionrpg/game/systems/level_system.dart';
import 'package:actionrpg/spacetime/cyborg_connection.dart';
import 'package:actionrpg/spacetime/generated/client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 매 실행마다 새 계정을 만든다. 테스트가 서로의 결과에 기대지 않게 한다.
  String uniqueEmail() =>
      'test-${DateTime.now().microsecondsSinceEpoch}@cyborg.test';

  late SpacetimeDbClient client;

  setUp(() async {
    // 토큰을 저장하지 않으므로 매번 새 identity 로 접속한다 = 매번 로그아웃 상태.
    client = await SpacetimeDbClient.create(
      host: kCyborgHost,
      database: kCyborgDatabase,
      ssl: kCyborgSsl,
      authStorage: InMemoryTokenStore(),
    );
    await client.connect(initialSubscriptions: kCyborgViewSubscriptions);
  });

  tearDown(() async {
    await client.disconnect();
  });

  test('가입하면 곧바로 로그인 상태가 되고 캐릭터는 비어 있다', () async {
    final email = uniqueEmail();

    expect(client.myAccount, isNull, reason: '접속 직후에는 로그아웃 상태여야 한다');

    await client.reducers.registerAccount(email: email, password: 'hunter2!!');
    await pumpUntil(() => client.myAccount != null);

    expect(client.myAccount!.email, email);
    expect(client.mySession, isNotNull);
    expect(client.mySession!.selectedCharacterId, isNull);
    expect(client.myCharacters.count(), 0);
  });

  test('같은 이메일로 두 번 가입할 수 없다', () async {
    final email = uniqueEmail();
    await client.reducers.registerAccount(email: email, password: 'hunter2!!');
    await pumpUntil(() => client.myAccount != null);

    expect(
      () => client.reducers.registerAccount(email: email, password: 'other123!'),
      throwsA(isA<SpacetimeDbReducerException>()),
    );
  });

  test('비밀번호가 틀리면 로그인에 실패한다', () async {
    final email = uniqueEmail();
    await client.reducers.registerAccount(email: email, password: 'hunter2!!');
    await pumpUntil(() => client.myAccount != null);
    await client.reducers.logout();
    await pumpUntil(() => client.myAccount == null);

    expect(
      () => client.reducers.login(email: email, password: 'wrongpassword'),
      throwsA(isA<SpacetimeDbReducerException>()),
    );
  });

  test('로그아웃 후 같은 계정으로 다시 로그인할 수 있다', () async {
    final email = uniqueEmail();
    await client.reducers.registerAccount(email: email, password: 'hunter2!!');
    await pumpUntil(() => client.myAccount != null);

    await client.reducers.logout();
    await pumpUntil(() => client.myAccount == null);

    // 이메일 대소문자가 달라도 같은 계정이어야 한다.
    await client.reducers.login(email: email.toUpperCase(), password: 'hunter2!!');
    await pumpUntil(() => client.myAccount != null);
    expect(client.myAccount!.email, email);
  });

  test('캐릭터를 만들면 목록에 나타나고 자동으로 선택된다', () async {
    await client.reducers.registerAccount(
      email: uniqueEmail(),
      password: 'hunter2!!',
    );
    await pumpUntil(() => client.myAccount != null);

    await client.reducers.createCharacter(name: '강철', kind: 'male_cyborg');
    await pumpUntil(() => client.myCharacters.count() == 1);

    final created = client.myCharacters.iter().first;
    expect(created.name, '강철');
    expect(created.kind, 'male_cyborg');
    expect(created.level, 1);

    await pumpUntil(() => client.mySession?.selectedCharacterId != null);
    expect(client.mySession!.selectedCharacterId, created.id);
  });

  test('두 번째 캐릭터를 만들고 골라서 바꿀 수 있다', () async {
    await client.reducers.registerAccount(
      email: uniqueEmail(),
      password: 'hunter2!!',
    );
    await pumpUntil(() => client.myAccount != null);

    await client.reducers.createCharacter(name: '강철', kind: 'male_cyborg');
    await pumpUntil(() => client.myCharacters.count() == 1);
    final first = client.myCharacters.iter().first;

    await client.reducers.createCharacter(name: '유나', kind: 'female_cyborg');
    await pumpUntil(() => client.myCharacters.count() == 2);

    await client.reducers.selectCharacter(characterId: first.id);
    await pumpUntil(() => client.mySession?.selectedCharacterId == first.id);
    expect(client.mySession!.selectedCharacterId, first.id);
  });

  test('서버가 모르는 캐릭터 종류는 거절한다', () async {
    await client.reducers.registerAccount(
      email: uniqueEmail(),
      password: 'hunter2!!',
    );
    await pumpUntil(() => client.myAccount != null);

    expect(
      () => client.reducers.createCharacter(name: '침입자', kind: 'robot_overlord'),
      throwsA(isA<SpacetimeDbReducerException>()),
    );
  });

  test('로그인하지 않으면 캐릭터를 만들 수 없다', () async {
    // 구독이 자리잡기 전에 부르면 "로그인이 없어서" 가 아니라 "연결이 덜 돼서"
    // 다른 예외가 날 수 있다. 초기 데이터가 도착한 뒤에 호출해야 이 테스트가
    // 실제로 재려는 것(권한 검사)을 잰다.
    await client.myCharacters.subscribed;
    expect(client.myAccount, isNull, reason: '이 시점에는 로그아웃 상태여야 한다');

    await expectLater(
      client.reducers.createCharacter(name: '강철', kind: 'male_cyborg'),
      throwsA(isA<SpacetimeDbReducerException>()),
    );
  });

  // ── 리더보드 ───────────────────────────────────────────────────────────

  group('리더보드', () {
    /// 가입하고 캐릭터를 하나 만든 뒤 순위표를 구독한다.
    ///
    /// 순위표는 공용이라 이 테스트가 만든 캐릭터도 실제 순위에 오른다. 그래서
    /// 누적을 낮게 쓰고 끝나면 지운다([cleanup]).
    Future<Int64> prepare({required String name}) async {
      await client.reducers.registerAccount(
        email: uniqueEmail(),
        password: 'hunter2!!',
      );
      await pumpUntil(() => client.myAccount != null);

      await client.reducers.createCharacter(name: name, kind: 'male_cyborg');
      await pumpUntil(() => client.myCharacters.count() == 1);

      await client.subscriptions.subscribe(kLeaderboardSubscriptions);
      return client.myCharacters.iter().first.id;
    }

    Future<void> cleanup(Int64 characterId) async {
      await client.reducers.deleteCharacter(characterId: characterId);
    }

    /// 레벨 N 에 막 도달하는 누적 경험치.
    ///
    /// 클라이언트 `LevelSystem` 을 그대로 쓴다. 여기서 식을 베껴 두면 곡선이
    /// 바뀔 때 조용히 어긋나고, 그러면 이 테스트가 **틀린 값을 보내면서**
    /// 서버를 탓하게 된다(실제로 70 이후 가속항을 빠뜨려 한 번 겪었다).
    int totalXpForLevel(int level) => LevelSystem.totalXpForLevel(level);

    test('보고한 누적이 레벨·진행도로 풀려 순위표와 내 순위에 함께 반영된다', () async {
      final id = await prepare(name: '순위시험');
      addTearDown(() => cleanup(id));

      // 4 레벨 시작점(285)에서 60 을 더 쌓은 상태. 서버가 이 하나에서
      // 레벨 4 와 진행도 60 을 스스로 계산해야 한다.
      final total = totalXpForLevel(4) + 60;
      await client.reducers.reportProgress(totalXp: total);

      // 캐릭터 표가 먼저 갱신되고, 그 위에서 계산되는 두 view 가 뒤따른다.
      await pumpUntil(() => client.myRank?.totalXp == total);

      final mine = client.myRank!;
      expect(mine.characterId, id);
      expect(mine.level, 4, reason: '서버가 누적에서 레벨을 유도해야 한다');
      expect(mine.xp, 60, reason: '진행도도 누적에서 나온다');
      expect(mine.rank, greaterThanOrEqualTo(1));

      // 같은 캐릭터가 전체 순위표에도 같은 값으로 있어야 한다. 상위 100 위
      // 밖이면 목록에 없을 수 있으므로 있을 때만 확인한다.
      final listed = client.leaderboard
          .iter()
          .where((row) => row.characterId == id);
      for (final row in listed) {
        expect(row.level, 4);
        expect(row.totalXp, total);
        expect(row.rank, mine.rank);
      }
    });

    test('뒤로 가는 보고는 무시된다', () async {
      final id = await prepare(name: '후퇴시험');
      addTearDown(() => cleanup(id));

      final high = totalXpForLevel(6) + 10;
      await client.reducers.reportProgress(totalXp: high);
      await pumpUntil(() => client.myRank?.totalXp == high);

      // 늦게 도착한 옛 보고. 서버는 조용히 버린다(에러가 아니다).
      await client.reducers.reportProgress(totalXp: totalXpForLevel(2));

      // 무시되었는지 확인하려면 "바뀌지 않았음" 을 봐야 한다. 반영에 걸리는
      // 시간만큼 기다린 뒤에도 그대로여야 한다.
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(client.myRank!.totalXp, high);
      expect(client.myRank!.level, 6);
    });

    test('캐릭터를 고르지 않으면 진행도를 보고할 수 없다', () async {
      await client.reducers.registerAccount(
        email: uniqueEmail(),
        password: 'hunter2!!',
      );
      await pumpUntil(() => client.myAccount != null);

      expect(
        () => client.reducers.reportProgress(totalXp: 500),
        throwsA(isA<SpacetimeDbReducerException>()),
      );
    });

    test('70 을 넘는 고레벨도 누적에서 정확히 풀린다', () async {
      final id = await prepare(name: '고레벨시험');
      addTearDown(() => cleanup(id));

      // 137 은 가속 구간(71~) 한복판이다. 서버와 클라이언트가 같은 가속항을
      // 쓰지 않으면 레벨이 어긋난다.
      final total = totalXpForLevel(137);
      await client.reducers.reportProgress(totalXp: total);
      await pumpUntil(() => client.myRank?.totalXp == total);

      expect(client.myRank!.level, 137, reason: '서버 곡선이 클라이언트와 어긋났다');
      expect(client.myRank!.xp, 0, reason: '레벨 시작점이면 진행도는 0 이다');
    });

    test('만렙 999 에서 레벨이 멈추고 누적만 더 쌓인다', () async {
      final id = await prepare(name: '만렙시험');
      addTearDown(() => cleanup(id));

      final atMax = totalXpForLevel(LevelSystem.maxLevel);
      final beyond = atMax + 5000000;
      await client.reducers.reportProgress(totalXp: beyond);
      await pumpUntil(() => client.myRank?.totalXp == beyond);

      expect(client.myRank!.level, LevelSystem.maxLevel);
      expect(
        client.myRank!.xp,
        5000000,
        reason: '만렙 이후 누적이 순위를 가르므로 진행도로 남아야 한다',
      );
    });

    test('거대한 누적은 상한까지만 저장된다', () async {
      final id = await prepare(name: '상한시험');
      addTearDown(() => cleanup(id));

      // 조작 클라이언트가 보낼 법한 값. 누적은 u32 상한에서 멈추고 레벨은
      // 만렙에서 멈춘다 — 둘 다 넘어가면 표시가 깨지거나 순위가 고착된다.
      await client.reducers.reportProgress(totalXp: LevelSystem.maxTotalXp);
      await pumpUntil(() => (client.myRank?.totalXp ?? 0) > 0);

      expect(client.myRank!.totalXp, LevelSystem.maxTotalXp);
      expect(client.myRank!.level, LevelSystem.maxLevel);
    });

    test('누적이 많은 쪽이 앞선다', () async {
      final id = await prepare(name: '동점시험');
      addTearDown(() => cleanup(id));

      final low = totalXpForLevel(5) + 10;
      await client.reducers.reportProgress(totalXp: low);
      await pumpUntil(() => client.myRank?.totalXp == low);
      final lowRank = client.myRank!.rank;

      // 누적만 올린다. 순위는 올라가거나 최소한 유지돼야 한다.
      final high = totalXpForLevel(5) + 130;
      await client.reducers.reportProgress(totalXp: high);
      await pumpUntil(() => client.myRank?.totalXp == high);

      expect(
        client.myRank!.rank,
        lessThanOrEqualTo(lowRank),
        reason: '누적이 늘었는데 순위가 내려갔다',
      );

      // 순위표는 누적 내림차순이어야 한다.
      final rows = client.leaderboard.iter().toList()
        ..sort((a, b) => a.rank.compareTo(b.rank));
      for (var i = 1; i < rows.length; i++) {
        expect(
          rows[i - 1].totalXp,
          greaterThanOrEqualTo(rows[i].totalXp),
          reason: '${rows[i - 1].rank}위의 누적이 ${rows[i].rank}위보다 적다',
        );
      }
    });

    test('순위표는 누적이 많은 순으로 온다', () async {
      final id = await prepare(name: '정렬시험');
      addTearDown(() => cleanup(id));

      await pumpUntil(() => client.leaderboard.count() > 0);

      final rows = client.leaderboard.iter().toList()
        ..sort((a, b) => a.rank.compareTo(b.rank));
      for (var i = 1; i < rows.length; i++) {
        expect(
          rows[i - 1].totalXp,
          greaterThanOrEqualTo(rows[i].totalXp),
          reason: '${rows[i - 1].rank}위의 누적이 ${rows[i].rank}위보다 적다',
        );
        // 레벨은 누적의 함수이므로 순위가 앞서면 레벨도 뒤지지 않는다.
        expect(rows[i - 1].level, greaterThanOrEqualTo(rows[i].level));
      }
    });
  });
}

/// [condition] 이 참이 될 때까지 기다린다.
///
/// reducer 가 성공해도 그 결과가 view 에 반영되어 클라이언트 캐시까지 오는 데는
/// 한 왕복이 더 걸린다. 고정 시간 `delay` 로 때우면 느린 날에 깨지고 빠른 날에
/// 느려지므로, 조건을 짧은 간격으로 확인한다.
Future<void> pumpUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('조건이 ${timeout.inSeconds}초 안에 만족되지 않았다');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
