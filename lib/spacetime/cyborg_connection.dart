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
  // 월드에 선 내 몸. **청크 구독과 별개로** 항상 받아야 한다 — 재구독의 기준이
  // 되는 좌표를 그 구독 안에서 읽으면, 서버가 나를 옮기는 순간(입장 보정·사망
  // 재가동·텔레포트) 내 행이 옛 구독 밖으로 나가 새 자리를 알 길이 없어진다.
  'SELECT * FROM my_world_player',
];

/// 플레이어 구독용 청크 한 변(타일). 서버 `PLAYER_SUB_CHUNK_TILES` 와 같아야 한다.
///
/// 어긋나면 청크 번호가 서로 다른 격자를 가리켜 **아무도 서로를 보지 못한다.**
const int kPlayerSubChunkTiles = 74;

/// 한 줄에 들어가는 플레이어 구독 청크 수. 서버 `PLAYER_SUB_CHUNKS_PER_ROW` 와 같다.
const int kPlayerSubChunksPerRow = 14; // (1006 / 74) + 1

/// 몬스터·전리품 구독용 청크 한 변(타일). 서버 `CHUNK_TILES` 와 같다.
///
/// 플레이어와 격자를 달리 쓰는 이유는 밀도가 여덟 배 다르기 때문이다. 같은 면적에
/// 사람 50 명이 들어오게 맞추면 몹은 400 기가 들어온다.
const int kMonsterSubChunkTiles = 32;

/// 한 줄에 들어가는 몬스터 구독 청크 수. 서버 `CHUNKS_PER_ROW` 와 같다.
const int kMonsterSubChunksPerRow = 32; // (1006 / 32) + 1

/// `(cx, cy)` 를 중심으로 한 3×3 청크 번호. 월드 밖은 버린다.
List<int> _neighborChunks(int cx, int cy, int perRow) {
  final keys = <int>[];
  for (var dy = -1; dy <= 1; dy++) {
    for (var dx = -1; dx <= 1; dx++) {
      final nx = cx + dx;
      final ny = cy + dy;
      if (nx < 0 || ny < 0 || nx >= perRow || ny >= perRow) continue;
      keys.add(ny * perRow + nx);
    }
  }
  return keys;
}

/// 월드에 들어가 있는 동안 거는 구독 — **자기 주변 청크만**.
///
/// 월드 전체를 구독하면 접속자가 늘수록 전송량이 제곱으로 커진다. 1,000 명이
/// 서로를 구독하면 초당 1,000만 행이 오간다(`GAME-SERVER.md` §5). 그래서 자기가
/// 선 청크와 이웃 여덟 칸만 구독한다.
///
/// **등식 나열밖에 쓸 수 없다.** 구독 SQL 에는 `LIMIT` 도 거리 정렬도 산술식도
/// 없어서(`GAME-SERVER.md` §2.4) `WHERE x BETWEEN ...` 같은 자연스러운 범위
/// 질의가 불가능하다. 정수 청크 번호를 `OR` 로 늘어놓는 것이 유일한 길이다.
///
/// **이것은 면적을 자를 뿐 인원을 자르지 않는다.** 안전지대처럼 사람이 몰리면
/// 그 수만큼 그대로 온다. "가까운 50 명" 은 `ActionRpgGame` 이 거리순으로 잘라
/// 만든다.
List<String> worldSubscriptionsFor(double tileX, double tileY) {
  String query(String table, String column, List<int> keys) =>
      'SELECT * FROM $table WHERE '
      '${keys.map((k) => '$column = $k').join(' OR ')}';

  final playerKeys = _neighborChunks(
    tileX ~/ kPlayerSubChunkTiles,
    tileY ~/ kPlayerSubChunkTiles,
    kPlayerSubChunksPerRow,
  );
  // 몹과 전리품은 같은 격자를 쓰므로 청크 번호를 한 번만 계산해 함께 쓴다.
  final fieldKeys = _neighborChunks(
    tileX ~/ kMonsterSubChunkTiles,
    tileY ~/ kMonsterSubChunkTiles,
    kMonsterSubChunksPerRow,
  );

  return [
    query('world_player', 'sub_chunk', playerKeys),
    // 몬스터도 **서버가 진실**이다. 클라이언트가 따로 만들어 내면 A 가 잡은 몹이
    // B 화면에 살아 있게 되고, 그러면 같은 대상을 함께 때리는 일이 성립하지 않는다.
    //
    // 집 청크(`chunk`)가 아니라 `pos_chunk` 로 고르는 것이 중요하다. 집으로 고르면
    // 확실히 잡히는 것이 반경 6 타일 안의 몹뿐이라 화면 구석이 빈다.
    query('monster', 'pos_chunk', fieldKeys),
    // 무엇이 떨어졌는지도 서버가 정한다. 각자 굴리면 같은 몹을 잡고도 서로 다른
    // 것을 보게 되어 "네가 먹어라" 가 성립하지 않는다.
    query('loot', 'chunk', fieldKeys),
  ];
}

/// 파티에 관한 구독. 월드에 들어가 있는 동안 함께 건다.
///
/// [worldSubscriptionsFor] 가 만드는 목록과 한 배열로 합치지 않는다. 파티 표는 공개 표가 아니라
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
