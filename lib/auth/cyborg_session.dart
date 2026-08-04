import 'package:flutter/foundation.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart';

import '../spacetime/cyborg_connection.dart';
import '../spacetime/generated/account.dart';
import '../spacetime/generated/client.dart';
import '../spacetime/reducer_error.dart';
import '../spacetime/generated/player_character.dart' as gen;
import '../spacetime/generated/session.dart' as gen;

/// 서버 연결이 어느 단계에 있는지.
enum ConnectionPhase {
  /// 아직 붙는 중. 화면은 부팅 상태를 보여준다.
  connecting,

  /// 연결됨. 이제 [CyborgSession.account] 로 로그인 여부를 판단한다.
  ready,

  /// 붙지 못했다. [CyborgSession.error] 에 이유가 있다.
  failed,
}

/// 계정·캐릭터 상태를 한곳에서 들고 있는 앱 전역 컨트롤러.
///
/// 서버의 view 세 개(`my_account`·`my_session`·`my_characters`)를 그대로
/// 비춘다. **로컬에 따로 상태를 두지 않는다** — reducer 를 부르면 서버가 view 를
/// 갱신하고, 그 갱신이 도착하면 화면이 바뀐다. 낙관적으로 미리 바꿔 두면
/// 서버가 거절했을 때 화면과 서버가 어긋나며, 그 어긋남은 "로그인한 줄 알았는데
/// 아니었다" 같은 형태로 나타나 디버깅이 어렵다.
class CyborgSession extends ChangeNotifier {
  /// [tokenStore] 를 넘기지 않으면 기기 저장소([PrefsTokenStore])를 쓴다.
  ///
  /// 테스트가 저장소를 갈아끼워 "토큰이 남아 있는 재시작" 과 "토큰이 없는 첫
  /// 실행" 을 모두 재현할 수 있도록 열어 두었다. 이 갈래가 곧 로그인 유지
  /// 동작이므로 실제로 검증할 수 있어야 한다.
  CyborgSession({AuthTokenStore? tokenStore})
    : _tokenStore = tokenStore ?? PrefsTokenStore();

  final AuthTokenStore _tokenStore;

  SpacetimeDbClient? _client;

  /// 연결된 클라이언트. 붙기 전이거나 실패했으면 null.
  ///
  /// 계정·캐릭터는 이 클래스의 메서드로만 다루지만, 게임 안에서 쓰는 연동
  /// (진행도 보고, 리더보드 열람)은 자기 화면을 직접 그리므로 클라이언트가
  /// 필요하다. 그 연결은 게임 껍데기(`GameScreen`)가 맡는다.
  SpacetimeDbClient? get client => _client;

  ConnectionPhase _phase = ConnectionPhase.connecting;
  ConnectionPhase get phase => _phase;

  String? _error;

  /// 마지막으로 실패한 이유. 화면에 그대로 보여줄 수 있는 문장이다.
  String? get error => _error;

  /// reducer 호출이 진행 중인지. 버튼 중복 클릭을 막는 데 쓴다.
  bool _busy = false;
  bool get busy => _busy;

  /// 로그인한 계정. 로그인하지 않았으면 null.
  Account? get account => _client?.myAccount;

  /// 로그인 여부. [account] 가 있다는 것과 같은 말이다.
  bool get isLoggedIn => account != null;

  /// 계정이 가진 캐릭터. 최근에 만든 것이 뒤로 가도록 정렬한다.
  ///
  /// 서버는 순서를 보장하지 않는다. 정렬하지 않으면 갱신이 올 때마다 목록이
  /// 뒤섞여 보인다.
  List<gen.PlayerCharacter> get characters {
    final client = _client;
    if (client == null) return const [];
    final list = client.myCharacters.iter().toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  gen.Session? get session => _client?.mySession;

  /// 지금 고른 캐릭터. 아직 안 골랐거나 그 캐릭터가 지워졌으면 null.
  gen.PlayerCharacter? get selectedCharacter {
    final id = session?.selectedCharacterId;
    if (id == null) return null;
    for (final character in characters) {
      if (character.id == id) return character;
    }
    return null;
  }

  /// 서버에 붙고 view 를 지켜보기 시작한다. 앱 시작 시 한 번 부른다.
  Future<void> boot() async {
    _phase = ConnectionPhase.connecting;
    _error = null;
    notifyListeners();

    try {
      final client = await SpacetimeDbClient.create(
        host: kCyborgHost,
        database: kCyborgDatabase,
        ssl: kCyborgSsl,
        authStorage: _tokenStore,
      );

      // view 도 테이블과 똑같이 **구독해야** 행이 온다. 구독하지 않으면 reducer
      // 는 성공하는데 화면은 영원히 로그아웃 상태로 남는다(실측으로 확인했다).
      // 실제 테이블은 모두 비공개라 구독할 것이 없고, 구독 대상은 이 세 view 뿐이다.
      await client.connect(initialSubscriptions: kCyborgViewSubscriptions);

      _client = client;
      _watchViews(client);
      _phase = ConnectionPhase.ready;
    } on Object catch (e) {
      _phase = ConnectionPhase.failed;
      _error = '서버에 연결하지 못했다: $e';
    }
    notifyListeners();
  }

  /// view 캐시가 바뀔 때마다 화면을 다시 그리게 한다.
  ///
  /// 세 view 모두 하나의 리스너로 묶는다. 한 트랜잭션이 계정과 캐릭터를 함께
  /// 바꾸는 경우(가입, 캐릭터 생성)가 흔한데, 따로 처리하면 화면이 중간 상태를
  /// 한 프레임 보여주게 된다.
  void _watchViews(SpacetimeDbClient client) {
    final cache = client.subscriptions.cache;
    cache
        .getTableByTypedName<Account>('my_account')
        .rows
        .addListener(_onViewChanged);
    cache
        .getTableByTypedName<gen.Session>('my_session')
        .rows
        .addListener(_onViewChanged);
    cache
        .getTableByTypedName<gen.PlayerCharacter>('my_characters')
        .rows
        .addListener(_onViewChanged);
  }

  void _onViewChanged() => notifyListeners();

  // ── 계정 ──────────────────────────────────────────────────────────────

  Future<bool> register(String email, String password) {
    return _call(() async {
      await _requireClient().reducers.registerAccount(
        email: email.trim(),
        password: password,
      );
    });
  }

  Future<bool> login(String email, String password) {
    return _call(() async {
      await _requireClient().reducers.login(
        email: email.trim(),
        password: password,
      );
    });
  }

  Future<bool> logout() {
    return _call(() async {
      await _requireClient().reducers.logout();
    });
  }

  // ── 캐릭터 ────────────────────────────────────────────────────────────

  Future<bool> createCharacter({required String name, required String kind}) {
    return _call(() async {
      await _requireClient().reducers.createCharacter(
        name: name.trim(),
        kind: kind,
      );
    });
  }

  Future<bool> selectCharacter(Int64 characterId) {
    return _call(() async {
      await _requireClient().reducers.selectCharacter(characterId: characterId);
    });
  }

  Future<bool> deleteCharacter(Int64 characterId) {
    return _call(() async {
      await _requireClient().reducers.deleteCharacter(characterId: characterId);
    });
  }

  // ── 공통 ──────────────────────────────────────────────────────────────

  SpacetimeDbClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError('연결되기 전에 호출했다');
    }
    return client;
  }

  /// reducer 호출을 감싼다. 진행 상태와 에러 메시지를 한곳에서 관리한다.
  ///
  /// 성공하면 true. 실패하면 [error] 에 사람이 읽을 메시지를 담고 false 를
  /// 돌려준다. 화면은 이 bool 만 보고 다음 단계로 갈지 정한다.
  Future<bool> _call(Future<void> Function() action) async {
    if (_busy) return false;
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      await action();
      return true;
    } on SpacetimeDbReducerException catch (e) {
      // 서버 모듈이 한국어 문장을 돌려주므로 사용자에게 그대로 보여준다.
      // 다만 전송 과정에서 붙는 찌꺼기는 벗겨야 한다([cleanReducerError]).
      _error = cleanReducerError(e.message);
      return false;
    } on Object catch (e) {
      _error = '요청을 처리하지 못했다: $e';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// 표시 중인 오류를 지운다.
  ///
  /// 화면이 모드를 바꿀 때(로그인 ↔ 가입, 목록 ↔ 만들기) 부른다. 지우지 않으면
  /// 직전 화면에서 받은 거절 사유가 새 화면에 그대로 남아, 아직 아무것도 하지
  /// 않았는데 실패한 것처럼 보인다.
  void clearError() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    final client = _client;
    if (client != null) {
      final cache = client.subscriptions.cache;
      cache
          .getTableByTypedName<Account>('my_account')
          .rows
          .removeListener(_onViewChanged);
      cache
          .getTableByTypedName<gen.Session>('my_session')
          .rows
          .removeListener(_onViewChanged);
      cache
          .getTableByTypedName<gen.PlayerCharacter>('my_characters')
          .rows
          .removeListener(_onViewChanged);
      client.disconnect();
    }
    super.dispose();
  }
}
