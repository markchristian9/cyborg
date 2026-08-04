/// 개발 중 로그인·캐릭터 흐름을 **손으로 타이핑하지 않고** 확인하기 위한 주입 값.
///
/// 사람이 쓰고 있는 키보드·마우스를 자동화로 가로채는 대신, 앱이 스스로 값을
/// 채우고 이벤트 핸들러를 부른다.
///
/// 값은 두 경로로 줄 수 있고 **실행 시점 환경변수가 우선**이다.
///
/// ```sh
/// # 1) 실행 시점 환경변수 — 한 번 빌드한 앱을 값만 바꿔 여러 번 띄울 수 있다.
/// DEV_LOGIN_EMAIL=abc1@test.com DEV_LOGIN_PASSWORD='12345a,*' \
/// DEV_CHARACTER_NAME=abc1 DEV_SESSION_SLOT=abc1 \
///   build/macos/Build/Products/Release/actionrpg.app/Contents/MacOS/actionrpg
///
/// # 2) 컴파일 시점 정의 — 한 인스턴스를 개발 중 반복 실행할 때 편하다.
/// flutter run -d macos \
///   --dart-define=DEV_LOGIN_EMAIL=uitest@cyborg.test \
///   --dart-define=DEV_LOGIN_PASSWORD=hunter2!! \
///   --dart-define=DEV_LOGOUT_FIRST=true
/// ```
///
/// 아무 값도 주지 않으면 [devLoginEnabled] 가 거짓이 되어 앱은 평소대로,
/// 즉 사람이 직접 입력하는 화면으로 동작한다.
///
/// 여러 클라이언트를 한꺼번에 띄우는 일은 `scripts/run.sh` 가 맡는다.
library;

import 'package:flutter/foundation.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart' show AuthTokenStore;

import 'dev_env.dart';

// ── 컴파일 시점 기본값 ──────────────────────────────────────────────────

const String _compiledEmail = String.fromEnvironment('DEV_LOGIN_EMAIL');
const String _compiledPassword = String.fromEnvironment('DEV_LOGIN_PASSWORD');
const String _compiledCharacter = String.fromEnvironment('DEV_CHARACTER_NAME');
const String _compiledKind = String.fromEnvironment('DEV_CHARACTER_KIND');
const String _compiledSlot = String.fromEnvironment('DEV_SESSION_SLOT');
const bool _compiledLogoutFirst = bool.fromEnvironment('DEV_LOGOUT_FIRST');

/// 실행 시점 값이 있으면 그걸, 없으면 컴파일 시점 값을 쓴다.
String _setting(String name, String compiled) {
  final runtime = devEnvironment[name]?.trim();
  if (runtime != null && runtime.isNotEmpty) return runtime;
  return compiled;
}

// ── 계정 ────────────────────────────────────────────────────────────────

/// 자동으로 접속할 계정. 없으면 빈 문자열.
final String kDevLoginEmail = _setting('DEV_LOGIN_EMAIL', _compiledEmail);

final String kDevLoginPassword =
    _setting('DEV_LOGIN_PASSWORD', _compiledPassword);

/// 자동 로그인 값이 모두 주어졌는지.
bool get devLoginEnabled =>
    kDevLoginEmail.isNotEmpty && kDevLoginPassword.isNotEmpty;

/// 부팅하자마자 기존 세션을 끊고 로그인 화면부터 시작할지.
///
/// 토큰이 남아 있으면 자동 로그인되어 로그인 화면을 볼 수 없다. 로그인 경로
/// 자체를 확인하려면 먼저 로그아웃해야 한다.
final bool kDevLogoutFirst =
    _setting('DEV_LOGOUT_FIRST', _compiledLogoutFirst ? 'true' : '') == 'true';

// ── 캐릭터 ──────────────────────────────────────────────────────────────

/// 자동으로 고르거나 만들 캐릭터 이름. 없으면 빈 문자열.
final String kDevCharacterName =
    _setting('DEV_CHARACTER_NAME', _compiledCharacter);

/// 캐릭터를 새로 만들 때 쓸 외형. 서버가 아는 값이어야 한다
/// (`male_cyborg` · `female_cyborg`).
final String kDevCharacterKind = () {
  final value = _setting('DEV_CHARACTER_KIND', _compiledKind);
  return value.isEmpty ? 'male_cyborg' : value;
}();

/// 로그인에 이어 캐릭터 선택·출격까지 앱이 스스로 진행할지.
///
/// 캐릭터 이름이 있어야 "어느 캐릭터로 들어갈지" 가 정해진다. 이름이 없으면
/// 로그인까지만 자동으로 하고 선택 화면에서 사람을 기다린다.
bool get devAutopilotEnabled =>
    devLoginEnabled && kDevCharacterName.isNotEmpty;

// ── 인스턴스 격리 ───────────────────────────────────────────────────────

/// 이 인스턴스가 쓸 세션 슬롯 이름.
///
/// 같은 기기에서 여러 클라이언트를 띄울 때 서로의 접속 토큰을 덮어쓰지 않도록
/// 저장소를 나누는 열쇠다. 자세한 이유는 [devSlotTokenStore] 참고.
final String kDevSessionSlot = _setting('DEV_SESSION_SLOT', _compiledSlot);

/// 이 인스턴스 전용 토큰 저장소. 슬롯이 없으면 null(기본 저장소를 쓴다).
AuthTokenStore? get devTokenStore => devSlotTokenStore(kDevSessionSlot);

// ── 로그 ────────────────────────────────────────────────────────────────

/// 개발용 흐름 추적 로그. 실행 로그에서 단계를 눈으로 좇는다.
///
/// 자동 로그인이나 강제 로그아웃이 켜져 있을 때만 찍는다. 평소에는 조용하다.
void devLog(String message) {
  if (!devLoginEnabled && !kDevLogoutFirst) return;
  final tag = kDevSessionSlot.isEmpty ? 'DEV-LOGIN' : 'DEV-LOGIN:$kDevSessionSlot';
  debugPrint('[$tag] $message');
}
