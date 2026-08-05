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

/// 접속하자마자 거는 구독.
///
/// **view 도 구독해야 행이 온다.** 이름이 `my_*` 라 서버가 알아서 밀어 줄 것
/// 같지만 그렇지 않다 — 구독하지 않으면 reducer 는 멀쩡히 성공하는데 클라이언트
/// 캐시는 영원히 비어 있어, "가입은 됐는데 로그인 화면에 그대로 있는" 증상이
/// 된다(`test/spacetime_integration_test.dart` 가 이 조합을 지킨다).
///
/// 실제 테이블(`account`·`account_secret`·`session`·`player_character`)은 모두
/// 비공개라 구독 대상이 아니다.
///
/// 여기 있는 셋은 앱이 켜져 있는 내내 필요하다. 리더보드는 볼 때만 필요하므로
/// 따로 뺐다([kLeaderboardSubscriptions]).
const List<String> kCyborgViewSubscriptions = [
  'SELECT * FROM my_account',
  'SELECT * FROM my_session',
  'SELECT * FROM my_characters',
];

/// 월드에 들어가 있는 동안 거는 구독.
///
/// `world_player` 는 공개 표라 **모든 접속자의 좌표**가 온다. 하나의 월드를
/// 여럿이 공유하므로 서로 어디 있는지는 보여야 하는 정보다. 월드 밖(로그인·
/// 캐릭터 선택 화면)에서는 필요 없으므로 입장할 때 걸고 나갈 때 푼다.
const List<String> kWorldSubscriptions = [
  'SELECT * FROM world_player',
  // 몬스터도 **서버가 진실**이다. 클라이언트가 따로 만들어 내면 A 가 잡은 몹이
  // B 화면에 살아 있게 되고, 그러면 같은 대상을 함께 때리는 일이 성립하지 않는다.
  'SELECT * FROM monster',
];

/// 파티에 관한 구독. 월드에 들어가 있는 동안 함께 건다.
///
/// [kWorldSubscriptions] 와 한 배열로 합치지 않는다. 파티 표는 공개 표가 아니라
/// **자기 파티만 보여 주는 view** 라 성격이 다르고, 무엇보다 두 목록을 한 곳에
/// 두면 월드와 파티를 각각 손보는 사람이 같은 줄에서 부딪친다.
///
/// view 도 구독해야 행이 온다 — 걸지 않으면 서버에 파티가 있어도 화면에는
/// 아무것도 없는, "파티가 없는 것" 과 구별되지 않는 상태가 된다.
const List<String> kPartySubscriptions = [
  'SELECT * FROM my_party',
  'SELECT * FROM my_party_members',
  'SELECT * FROM my_party_invites',
];

/// 리더보드 화면이 떠 있는 동안에만 거는 구독.
///
/// 순위표는 **누가 레벨업하든** 다시 계산되어 구독자 전원에게 밀려온다. 월드에
/// 사람이 많을수록 그 빈도가 올라가므로, 아무도 보고 있지 않은 동안까지 받아 둘
/// 이유가 없다. 화면을 열 때 걸고 닫을 때 푼다.
const List<String> kLeaderboardSubscriptions = [
  'SELECT * FROM leaderboard',
  'SELECT * FROM my_rank',
];

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
