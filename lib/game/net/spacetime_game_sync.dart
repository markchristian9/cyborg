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
  SpacetimeGameSync(this._client, {int startTotalXp = 0})
      : _totalXp = startTotalXp,
        _sentTotalXp = startTotalXp;

  final SpacetimeDbClient _client;

  /// 주기적으로 보내는 간격(초).
  ///
  /// 레벨업은 [reportLevel] 이 즉시 보내므로 이 주기는 "레벨은 그대로인데
  /// 경험치만 오른" 경우를 따라잡는 용도다. 매 프레임 보내면 초당 60번
  /// 트랜잭션을 만든다.
  static const double _interval = 5;

  double _elapsed = 0;

  /// 게임이 마지막으로 알려 준 누적 경험치.
  int _totalXp;

  /// 마지막으로 서버에 올린 누적.
  ///
  /// 출격 시점의 서버 값으로 시작한다. 0 부터 시작하면 접속하자마자 서버가 이미
  /// 아는 값을 한 번 더 보내게 된다 — 단조 가드에 막혀 아무 일도 일어나지 않는
  /// 트랜잭션이지만, 접속자 수만큼 생긴다.
  int _sentTotalXp;

  /// 서버가 기록을 받지 않는 상태(로그인 전, 캐릭터 미선택)인지.
  ///
  /// 한 번 거절당하면 조건이 바뀌기 전까지 계속 거절당한다. 그때마다 요청을
  /// 보내면 서버 로그만 더럽히므로 멈춘다. 게임 화면은 캐릭터를 고른 뒤에만
  /// 뜨고 로그아웃하면 통째로 사라지므로, 한 번 거절당한 뒤 같은 화면에서
  /// 조건이 다시 갖춰지는 경우는 없다.
  bool _rejected = false;

  bool _inFlight = false;

  /// 전송 중에 들어온 최신 값. 전송이 끝나면 이어서 보낸다.
  ///
  /// 이게 없으면 전송 중에 일어난 레벨업이 그냥 버려지고 다음 주기까지 기다려야
  /// 한다. 평소에는 [tick] 이 따라잡아 주지만, 로그아웃처럼 **뒤에 tick 이 오지
  /// 않는** 경로에서는 그대로 유실된다.
  int? _pending;

  @override
  void tick(double dt, ActionRpgGame game) {
    _totalXp = game.player.totalXp;

    _elapsed += dt;
    if (_elapsed < _interval) return;
    _elapsed = 0;
    _send(_totalXp);
  }

  @override
  void reportLevel(int level, int totalXp) {
    // 레벨업은 순위가 실제로 바뀌는 순간이라 주기를 기다리지 않는다.
    _totalXp = totalXp;
    _send(totalXp);
  }

  @override
  Future<void> flushProgress() async {
    // 마지막으로 아는 상태를 확실히 올린다. 전송 중이면 그 전송이 끝나고
    // 이어지는 것까지 기다린다.
    await _send(_totalXp);
  }

  Future<void> _send(int totalXp) async {
    if (_rejected) return;

    // 전송 중이면 최신 값만 남겨 둔다. 값이 여러 번 바뀌어도 서버에 필요한 것은
    // 마지막 하나뿐이다.
    if (_inFlight) {
      _pending = totalXp;
      return;
    }

    var next = totalXp;

    // 대기 중인 값이 생기면 이어서 보낸다. 보통 한 바퀴로 끝난다.
    while (true) {
      if (next > _sentTotalXp) {
        _inFlight = true;
        try {
          await _client.reducers.reportProgress(totalXp: next);
          _sentTotalXp = next;
        } on SpacetimeDbReducerException {
          // 로그인하지 않았거나 캐릭터를 고르지 않았다. 게임은 그대로 진행하고
          // 기록만 남기지 않는다.
          _rejected = true;
          _pending = null;
          return;
        } on SpacetimeDbException {
          // 연결이 끊긴 것뿐이다. 다음 주기에 다시 시도한다.
          return;
        } finally {
          _inFlight = false;
        }
      }

      final queued = _pending;
      if (queued == null) return;
      _pending = null;
      next = queued;
    }
  }
}
