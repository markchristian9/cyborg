@Tags(['integration'])
library;

/// 이메일·비밀번호 로그인을 **앱이 실제로 쓰는 경로**([CyborgSession])로 검증한다.
///
/// `spacetime_integration_test.dart` 가 서버 계약(리듀서·view)을 확인한다면,
/// 이쪽은 그 위에 얹힌 앱 상태를 확인한다 — 로그인하면 화면이 넘어갈 조건이
/// 실제로 참이 되는지, 실패하면 사람이 읽을 문장이 남는지, 앱을 껐다 켜도
/// 로그인이 유지되는지.
///
/// ```sh
/// flutter test --tags integration test/login_flow_test.dart
/// ```
import 'package:flutter_test/flutter_test.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart';

import 'package:actionrpg/auth/cyborg_session.dart';

/// 토큰을 밖에서 들여다보고 갈아끼울 수 있는 저장소.
///
/// 실제 앱은 기기 저장소(`PrefsTokenStore`)를 쓴다. 여기서는 그 자리에 이것을
/// 넣어 "토큰이 남아 있는 재시작" 과 "토큰이 없는 첫 실행" 을 재현한다.
class FakeTokenStore implements AuthTokenStore {
  FakeTokenStore([this.token]);

  String? token;

  @override
  Future<String?> loadToken() async => token;

  @override
  Future<void> saveToken(String value) async => token = value;

  @override
  Future<void> clearToken() async => token = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 매 실행마다 새 계정을 만들어 테스트가 서로에게 기대지 않게 한다.
  String uniqueEmail() =>
      'flow-${DateTime.now().microsecondsSinceEpoch}@cyborg.test';

  const password = 'hunter2!!';

  /// 붙은 세션을 만든다. 저장소를 넘기지 않으면 토큰 없는 첫 실행이다.
  Future<CyborgSession> boot([FakeTokenStore? store]) async {
    final session = CyborgSession(tokenStore: store ?? FakeTokenStore());
    await session.boot();
    expect(
      session.phase,
      ConnectionPhase.ready,
      reason: '서버에 붙지 못했다: ${session.error}',
    );
    return session;
  }

  group('가입과 로그인', () {
    test('가입하면 곧바로 로그인 상태가 된다', () async {
      final session = await boot();
      addTearDown(session.dispose);

      expect(session.isLoggedIn, isFalse, reason: '붙자마자는 로그아웃 상태여야 한다');

      final email = uniqueEmail();
      expect(await session.register(email, password), isTrue);
      await settle(() => session.isLoggedIn);

      expect(session.account!.email, email);
      expect(session.error, isNull);
      expect(session.characters, isEmpty);
      expect(session.selectedCharacter, isNull);
    });

    test('로그아웃하면 로그인 화면으로 돌아갈 조건이 된다', () async {
      final session = await boot();
      addTearDown(session.dispose);

      await session.register(uniqueEmail(), password);
      await settle(() => session.isLoggedIn);

      expect(await session.logout(), isTrue);
      await settle(() => !session.isLoggedIn);

      expect(session.account, isNull);
      expect(session.characters, isEmpty);
    });

    test('로그아웃 뒤 같은 계정으로 다시 로그인된다', () async {
      final session = await boot();
      addTearDown(session.dispose);

      final email = uniqueEmail();
      await session.register(email, password);
      await settle(() => session.isLoggedIn);
      await session.logout();
      await settle(() => !session.isLoggedIn);

      expect(await session.login(email, password), isTrue);
      await settle(() => session.isLoggedIn);
      expect(session.account!.email, email);
    });

    test('이메일 대소문자와 앞뒤 공백은 무시된다', () async {
      final session = await boot();
      addTearDown(session.dispose);

      final email = uniqueEmail();
      await session.register(email, password);
      await settle(() => session.isLoggedIn);
      await session.logout();
      await settle(() => !session.isLoggedIn);

      // 사용자가 자동완성이나 복사·붙여넣기로 흘린 공백·대문자를 그대로 넣어도
      // 같은 계정으로 들어가야 한다.
      expect(
        await session.login('  ${email.toUpperCase()}  ', password),
        isTrue,
        reason: '거절 사유: ${session.error}',
      );
      await settle(() => session.isLoggedIn);
      expect(session.account!.email, email);
    });
  });

  group('실패했을 때 남는 메시지', () {
    test('비밀번호가 틀리면 읽을 수 있는 문장이 남는다', () async {
      final session = await boot();
      addTearDown(session.dispose);

      final email = uniqueEmail();
      await session.register(email, password);
      await settle(() => session.isLoggedIn);
      await session.logout();
      await settle(() => !session.isLoggedIn);

      expect(await session.login(email, 'wrong-password'), isFalse);
      expect(session.isLoggedIn, isFalse);

      // 길이 프리픽스가 벗겨져 문장이 한글로 시작해야 한다. 이 확인이 없으면
      // "5   이메일 또는..." 같은 문자열이 그대로 화면에 뜬다.
      expect(session.error, '이메일 또는 비밀번호가 올바르지 않다.');
    });

    test('없는 계정도 같은 문장으로 거절한다', () async {
      final session = await boot();
      addTearDown(session.dispose);

      // 계정 존재 여부를 알려 주면 가입된 이메일을 캐낼 수 있다. 두 경우의
      // 문장이 실제로 같은지 확인한다.
      expect(await session.login(uniqueEmail(), password), isFalse);
      expect(session.error, '이메일 또는 비밀번호가 올바르지 않다.');
    });

    test('이미 쓰는 이메일로 가입하면 그 사실을 알려 준다', () async {
      final session = await boot();
      addTearDown(session.dispose);

      final email = uniqueEmail();
      await session.register(email, password);
      await settle(() => session.isLoggedIn);

      expect(await session.register(email, password), isFalse);
      expect(session.error, '이미 가입된 이메일이다.');
    });

    test('짧은 비밀번호는 서버가 자릿수를 알려 준다', () async {
      final session = await boot();
      addTearDown(session.dispose);

      expect(await session.register(uniqueEmail(), '1234567'), isFalse);
      expect(session.error, '비밀번호는 최소 8자다.');
    });

    test('형식이 아닌 이메일은 형식 문제라고 알려 준다', () async {
      final session = await boot();
      addTearDown(session.dispose);

      expect(await session.register('not-an-email', password), isFalse);
      expect(session.error, '이메일 형식이 아니다.');
    });

    test('clearError 로 지우면 다음 화면에 따라오지 않는다', () async {
      final session = await boot();
      addTearDown(session.dispose);

      await session.login(uniqueEmail(), password);
      expect(session.error, isNotNull);

      session.clearError();
      expect(session.error, isNull);
    });

    test('다시 시도하면 이전 실패가 지워진다', () async {
      final session = await boot();
      addTearDown(session.dispose);

      final email = uniqueEmail();
      expect(await session.login(email, password), isFalse);
      expect(session.error, isNotNull);

      // 성공한 호출은 실패 흔적을 남기지 않아야 한다.
      expect(await session.register(email, password), isTrue);
      expect(session.error, isNull);
    });
  });

  group('로그인 유지', () {
    test('앱을 껐다 켜도 토큰이 있으면 로그인 상태로 깨어난다', () async {
      final store = FakeTokenStore();

      final first = await boot(store);
      final email = uniqueEmail();
      await first.register(email, password);
      await settle(() => first.isLoggedIn);
      expect(store.token, isNotNull, reason: '접속하면 토큰이 저장되어야 한다');
      first.dispose();

      // 같은 토큰을 들고 새 세션을 연다 = 앱 재시작.
      final second = await boot(FakeTokenStore(store.token));
      addTearDown(second.dispose);
      await settle(() => second.isLoggedIn);

      expect(
        second.account?.email,
        email,
        reason: '토큰이 남아 있으면 다시 로그인하지 않아도 계정이 붙어 있어야 한다',
      );
    });

    test('캐릭터 선택도 재시작 뒤에 유지된다', () async {
      final store = FakeTokenStore();

      final first = await boot(store);
      await first.register(uniqueEmail(), password);
      await settle(() => first.isLoggedIn);
      await first.createCharacter(name: '유지시험', kind: 'female_cyborg');
      await settle(() => first.selectedCharacter != null);
      final chosen = first.selectedCharacter!.id;
      first.dispose();

      final second = await boot(FakeTokenStore(store.token));
      addTearDown(second.dispose);
      await settle(() => second.selectedCharacter != null);

      expect(second.selectedCharacter!.id, chosen);
      expect(second.selectedCharacter!.name, '유지시험');
      expect(second.selectedCharacter!.kind, 'female_cyborg');
    });

    test('토큰이 없으면 로그아웃 상태로 시작한다', () async {
      final session = await boot();
      addTearDown(session.dispose);

      // 붙고 나서 view 가 도착할 시간을 준 뒤에도 비어 있어야 한다.
      await Future<void>.delayed(const Duration(seconds: 2));
      expect(session.isLoggedIn, isFalse);
    });

    test('로그아웃해도 토큰은 남지만 세션은 끊긴다', () async {
      final store = FakeTokenStore();

      final first = await boot(store);
      final email = uniqueEmail();
      await first.register(email, password);
      await settle(() => first.isLoggedIn);
      await first.logout();
      await settle(() => !first.isLoggedIn);
      first.dispose();

      // 토큰(= 기기 identity)은 그대로 두는 것이 맞다. 지우면 재접속마다 새
      // identity 가 생겨 서버에 쓸모없는 신원이 쌓인다. 로그아웃의 효과는
      // 서버에서 세션이 사라지는 것으로 충분하다.
      expect(store.token, isNotNull);

      final second = await boot(FakeTokenStore(store.token));
      addTearDown(second.dispose);
      await Future<void>.delayed(const Duration(seconds: 2));

      expect(second.isLoggedIn, isFalse, reason: '로그아웃했으면 다시 로그인해야 한다');

      // 같은 기기에서 다시 로그인하면 그대로 들어가야 한다.
      expect(await second.login(email, password), isTrue);
      await settle(() => second.isLoggedIn);
      expect(second.account!.email, email);
    });
  });
}

/// [condition] 이 참이 될 때까지 기다린다.
///
/// reducer 가 성공해도 그 결과가 view 를 거쳐 클라이언트 캐시에 닿는 데 한 왕복이
/// 더 걸린다. 고정 시간으로 때우면 느린 날에 깨지고 빠른 날에 느려진다.
Future<void> settle(
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
