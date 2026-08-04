import 'package:shared_preferences/shared_preferences.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart';

/// 접속할 SpacetimeDB 호스트.
///
/// `spacetime.json` 의 `server` 와 같은 곳을 가리켜야 한다. 서버를 바꾸면
/// 여기와 `spacetime.json` 을 함께 고친다.
const String kCyborgHost = 'maincloud.spacetimedb.com';

/// 데이터베이스 이름. `spacetime.json` 의 `database` 와 같다.
const String kCyborgDatabase = 'withcenter-cyborg';

/// maincloud 는 wss/https 로만 받는다. 로컬 서버로 바꾸면 `false` 로 둔다.
const bool kCyborgSsl = true;

/// SpacetimeDB 접속 토큰을 기기에 저장한다.
///
/// 이 토큰은 곧 **이 기기의 identity** 이고, 서버의 `session` 표가 identity 를
/// 계정에 연결한다. 즉 토큰을 유지하는 것이 곧 "로그인 상태 유지" 다. 토큰이
/// 사라지면 새 identity 를 받게 되어 다시 로그인해야 한다.
///
/// 저장소로 `shared_preferences` 를 쓴다. 키체인(`flutter_secure_storage`)이
/// 더 안전하지만 플랫폼마다 별도 설정이 필요하고, 여기 담기는 값은 계정
/// 비밀번호가 아니라 **이 기기의 세션 토큰**이다. 기기 저장소를 읽을 수 있는
/// 공격자는 이미 앱 데이터 전체에 접근할 수 있다.
class PrefsTokenStore implements AuthTokenStore {
  static const String _key = 'spacetimedb_token';

  @override
  Future<String?> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  @override
  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, token);
  }

  @override
  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
