import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart'
    show AuthTokenStore, Int64;

import 'package:actionrpg/auth/character_select_screen.dart';
import 'package:actionrpg/spacetime/generated/player_character.dart';
import 'package:actionrpg/auth/cyborg_kind.dart';
import 'package:actionrpg/auth/cyborg_portrait.dart';
import 'package:actionrpg/auth/cyborg_session.dart';
import 'package:actionrpg/auth/login_screen.dart';
import 'package:actionrpg/game/entities/cyborg_design.dart';

/// 계정·캐릭터 화면이 네트워크 없이도 그려지는지 확인한다.
///
/// [CyborgSession] 을 `boot()` 하지 않고 넘기면 연결이 없는 상태가 되므로,
/// 서버 없이 화면 코드만 검증할 수 있다. 서버까지 포함한 흐름은
/// `spacetime_integration_test.dart` 가 맡는다.
/// [CyborgSession.clearError] 가 실제로 불렸는지 세는 스파이.
///
/// 화면을 오갈 때 직전 거절 사유를 지우는 것은 눈에 보이지 않는 동작이라
/// 회귀해도 알아채기 어렵다. 호출 여부를 고정해 둔다.
class SpySession extends CyborgSession {
  SpySession({this.stubCharacters = const []})
      : super(tokenStore: _NullTokenStore());

  int clearErrorCalls = 0;

  /// 서버 없이 목록 화면을 그리기 위한 가짜 캐릭터들.
  final List<PlayerCharacter> stubCharacters;

  @override
  List<PlayerCharacter> get characters => stubCharacters;

  @override
  void clearError() {
    clearErrorCalls++;
    super.clearError();
  }
}

/// 목록 화면에 세울 캐릭터 하나.
PlayerCharacter stubCharacter(String name) => PlayerCharacter(
      id: Int64(1),
      accountId: Int64(1),
      name: name,
      kind: 'male_cyborg',
      level: 1,
      xp: 0,
      createdAt: Int64(0),
      lastPlayedAt: Int64(0),
      // 성장의 진실은 누적 경험치 하나이고 level·xp 는 거기서 나온 사본이다.
      totalXp: 0,
    );

/// 아무것도 저장하지 않는 토큰 저장소. 테스트가 기기 저장소를 건드리지 않게 한다.
class _NullTokenStore implements AuthTokenStore {
  @override
  Future<String?> loadToken() async => null;

  @override
  Future<void> saveToken(String token) async {}

  @override
  Future<void> clearToken() async {}
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  group('사이보그 초상', () {
    testWidgets('두 프레임이 예외 없이 그려진다', (tester) async {
      for (final kind in CyborgKind.values) {
        await tester.pumpWidget(
          wrap(
            Center(
              child: SizedBox(
                width: 200,
                height: 300,
                child: CyborgPortrait(kind: kind),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: '${kind.id} 렌더 실패');
      }
    });

    testWidgets('선택 해제 상태도 그려진다', (tester) async {
      await tester.pumpWidget(
        wrap(
          const SizedBox(
            width: 120,
            height: 180,
            child: CyborgPortrait(
              kind: CyborgKind.female,
              selected: false,
              animate: false,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('종류와 프레임 대응', () {
    test('서버 문자열이 게임 프레임으로 이어진다', () {
      expect(CyborgKind.fromId('male_cyborg').frame, CyborgFrame.assault);
      expect(CyborgKind.fromId('female_cyborg').frame, CyborgFrame.infiltrator);
    });

    test('모르는 값은 기본 프레임으로 떨어진다', () {
      // 서버에 새 외형이 생겼는데 클라이언트가 낡았을 때 칸이 비지 않아야 한다.
      expect(CyborgKind.fromId('robot_overlord').frame, CyborgFrame.assault);
      expect(CyborgKind.fromId('').frame, CyborgFrame.assault);
    });

    test('id 가 서버 화이트리스트와 글자 그대로 같다', () {
      // `spacetimedb/src/character.rs` 의 CHARACTER_KINDS 와 대응한다.
      expect(
        CyborgKind.values.map((k) => k.id),
        containsAll(<String>['male_cyborg', 'female_cyborg']),
      );
    });
  });

  group('화면', () {
    testWidgets('로그인 화면이 그려지고 가입 모드로 바뀐다', (tester) async {
      final session = CyborgSession();
      addTearDown(session.dispose);

      await tester.pumpWidget(wrap(LoginScreen(session: session)));

      expect(find.text('접속'), findsOneWidget);
      expect(find.text('비밀번호 확인'), findsNothing);

      await tester.tap(find.text('계정이 없다 — 새 요원 등록'));
      await tester.pumpAndSettle();

      // 가입 모드에서는 비밀번호 확인칸이 늘어난다.
      expect(find.text('비밀번호 확인'), findsOneWidget);
      expect(find.text('등록하고 시작'), findsOneWidget);
    });

    testWidgets('빈 입력으로 제출하면 화면이 먼저 막는다', (tester) async {
      final session = CyborgSession();
      addTearDown(session.dispose);

      await tester.pumpWidget(wrap(LoginScreen(session: session)));
      await tester.tap(find.text('접속'));
      await tester.pump();

      // 연결이 없는데도 서버 오류가 아니라 입력 안내가 나와야 한다.
      expect(find.text('이메일과 비밀번호를 모두 입력해라.'), findsOneWidget);
    });

    testWidgets('캐릭터가 없으면 만들기 화면으로 시작한다', (tester) async {
      final session = CyborgSession();
      addTearDown(session.dispose);

      await tester.pumpWidget(
        wrap(
          CharacterSelectScreen(session: session, onStart: (_) {}),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('요원 등록'), findsOneWidget);
      // 두 프레임이 나란히 서 있어야 고를 수 있다.
      expect(find.byType(CyborgPortrait), findsNWidgets(2));
      expect(find.text('VULCAN'), findsOneWidget);
      expect(find.text('WRAITH'), findsOneWidget);
    });

    testWidgets('로그인과 가입을 오갈 때 이전 거절 사유를 지운다', (tester) async {
      final session = SpySession();
      addTearDown(session.dispose);

      await tester.pumpWidget(wrap(LoginScreen(session: session)));
      expect(session.clearErrorCalls, 0);

      await tester.tap(find.text('계정이 없다 — 새 요원 등록'));
      await tester.pumpAndSettle();
      expect(session.clearErrorCalls, 1);

      await tester.tap(find.text('이미 계정이 있다 — 접속하기'));
      await tester.pumpAndSettle();
      expect(session.clearErrorCalls, 2);
    });

    testWidgets('요원 등록 화면에도 오른쪽 위 메뉴가 있다', (tester) async {
      // 첫 캐릭터를 만드는 중에는 목록으로 돌아갈 수도 없다. 여기 메뉴가 없으면
      // 계정을 잘못 고른 사용자가 빠져나갈 길이 사라진다.
      final session = SpySession();
      addTearDown(session.dispose);

      await tester.pumpWidget(
        wrap(CharacterSelectScreen(session: session, onStart: (_) {})),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('요원 등록'), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsOneWidget);

      await tester.tap(find.byIcon(Icons.menu));
      // 초상이 계속 숨을 쉬므로 pumpAndSettle 은 영원히 끝나지 않는다.
      // 팝업이 열릴 만큼만 시간을 준다.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('로그아웃'), findsOneWidget);
    });

    testWidgets('캐릭터 목록 화면에도 같은 자리에 메뉴가 있다', (tester) async {
      final session = SpySession(stubCharacters: [stubCharacter('강철')]);
      addTearDown(session.dispose);

      await tester.pumpWidget(
        wrap(CharacterSelectScreen(session: session, onStart: (_) {})),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('요원 선택'), findsOneWidget);
      expect(find.byIcon(Icons.menu), findsOneWidget);

      await tester.tap(find.byIcon(Icons.menu));
      // 초상이 계속 숨을 쉬므로 pumpAndSettle 은 영원히 끝나지 않는다.
      // 팝업이 열릴 만큼만 시간을 준다.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('로그아웃'), findsOneWidget);
    });

    testWidgets('짧은 이름은 서버에 보내기 전에 막는다', (tester) async {
      final session = CyborgSession();
      addTearDown(session.dispose);

      await tester.pumpWidget(
        wrap(
          CharacterSelectScreen(session: session, onStart: (_) {}),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.enterText(find.byType(TextField), '강');
      await tester.tap(find.text('등록'));
      await tester.pump();

      expect(find.text('이름은 2자 이상이다.'), findsOneWidget);
    });
  });
}
