import '../action_rpg_game.dart';

/// 게임 진행 상황을 백엔드(SpacetimeDB)에 보고하는 연동 지점.
///
/// 게임 로직은 이 인터페이스만 알고 있으므로, 백엔드가 없거나 연결이
/// 끊겨도 게임은 그대로 동작한다. 실제 구현은
/// `lib/game/net/spacetime_game_sync.dart`에 있다.
abstract class GameSync {
  const GameSync();

  /// 매 프레임 호출된다. 위치 스트리밍처럼 주기적인 전송에 쓴다.
  void tick(double dt, ActionRpgGame game) {}

  /// 새 런이 시작되었을 때.
  void reportRunStarted() {}

  /// 웨이브가 시작되었을 때.
  void reportWaveStarted(int wave) {}

  /// 웨이브를 정리했을 때.
  void reportWaveCleared(int wave, int score) {}

  /// 적을 처치했을 때.
  void reportKill(String enemyKind, int score) {}

  /// 레벨업했을 때.
  void reportLevel(int level) {}

  /// 몸체가 파괴되어 안전지대에서 재가동했을 때.
  ///
  /// 사망은 런의 끝이 아니라 위치 이동이므로, 같은 월드를 보고 있는 다른
  /// 플레이어에게도 전달되어야 한다.
  void reportDeath({required int deaths, required int score}) {}

  /// 런이 끝났을 때(로비 복귀·재시작 등).
  void reportRunFinished({
    required int wave,
    required int kills,
    required int score,
    required double survivalTime,
  }) {}
}

/// 아무것도 전송하지 않는 오프라인 구현.
class OfflineGameSync extends GameSync {
  const OfflineGameSync();
}
