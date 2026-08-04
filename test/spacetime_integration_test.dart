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
    await client.connect();
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
    expect(
      () => client.reducers.createCharacter(name: '강철', kind: 'male_cyborg'),
      throwsA(isA<SpacetimeDbReducerException>()),
    );
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
