import 'package:spacetimedb_sdk/spacetimedb_sdk.dart';

import '../../spacetime/generated/client.dart';
import '../action_rpg_game.dart';
import 'game_sync.dart';

/// 게임의 성장 상황을 SpacetimeDB 에 올려 리더보드에 반영하는 구현.
///
/// 올리는 것은 **레벨과 경험치뿐**이다. 웨이브·점수·처치 수는 리더보드가 쓰지
/// 않으므로 보내지 않는다. 쓰지 않는 값을 보내면 서버는 그것을 저장할 곳을
/// 마련해야 하고, 그때부터 아무도 보지 않는 열이 늘어난다.
class SpacetimeGameSync extends GameSync {
  SpacetimeGameSync(this._client);

  final SpacetimeDbClient _client;

  /// 주기적으로 보내는 간격(초).
  ///
  /// 레벨업은 [reportLevel] 이 즉시 보내므로 이 주기는 "레벨은 그대로인데
  /// 경험치만 오른" 경우를 따라잡는 용도다. 매 프레임 보내면 초당 60번
  /// 트랜잭션을 만든다.
  static const double _interval = 5;

  double _elapsed = 0;

  /// 게임이 마지막으로 알려 준 성장 상태.
  ///
  /// 사망 시점에는 게임 루프가 멈춰 [tick] 이 더 오지 않으므로, 그때 올릴 값을
  /// 여기서 들고 있어야 한다.
  int _level = 1;
  int _xp = 0;

  /// 마지막으로 서버에 올린 값. 같은 값을 두 번 보내지 않기 위해 기억한다.
  int _sentLevel = 0;
  int _sentXp = -1;

  /// 서버가 기록을 받지 않는 상태(로그인 전, 캐릭터 미선택)인지.
  ///
  /// 한 번 거절당하면 조건이 바뀌기 전까지 계속 거절당한다. 그때마다 요청을
  /// 보내면 서버 로그만 더럽히므로 멈춘다. 캐릭터를 고른 뒤 [resume] 으로
  /// 다시 켠다.
  bool _rejected = false;

  bool _inFlight = false;

  @override
  void tick(double dt, ActionRpgGame game) {
    _level = game.player.level;
    _xp = game.player.xp;

    _elapsed += dt;
    if (_elapsed < _interval) return;
    _elapsed = 0;
    _send(_level, _xp);
  }

  @override
  void reportLevel(int level) {
    // 레벨업은 순위가 실제로 바뀌는 순간이라 주기를 기다리지 않는다.
    // 경험치는 레벨업 직후 0 부터 다시 쌓이므로 0 으로 보낸다.
    _level = level;
    _xp = 0;
    _send(level, 0);
  }

  @override
  void reportRunFinished({
    required int wave,
    required int kills,
    required int score,
    required double survivalTime,
  }) {
    // 죽어도 도달한 레벨은 남는다. 게임 루프가 멈추기 전에 마지막 상태를 올린다.
    _send(_level, _xp);
  }

  /// 거절 상태를 풀고 다음 보고부터 다시 시도한다.
  ///
  /// 캐릭터를 고른 직후처럼 서버가 기록을 받을 수 있게 된 시점에 부른다.
  void resume() {
    _rejected = false;
  }

  Future<void> _send(int level, int xp) async {
    if (_rejected || _inFlight) return;
    if (level < _sentLevel || (level == _sentLevel && xp <= _sentXp)) return;

    _inFlight = true;
    try {
      await _client.reducers.reportProgress(level: level, xp: Int64(xp));
      _sentLevel = level;
      _sentXp = xp;
    } on SpacetimeDbReducerException {
      // 로그인하지 않았거나 캐릭터를 고르지 않았다. 게임은 그대로 진행하고
      // 기록만 남기지 않는다.
      _rejected = true;
    } on SpacetimeDbException {
      // 연결이 끊긴 것뿐이다. 다음 주기에 다시 시도한다.
    } finally {
      _inFlight = false;
    }
  }
}
