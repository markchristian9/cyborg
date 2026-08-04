import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart';

import '../game/net/world_presence.dart';
import 'cyborg_connection.dart';
import 'generated/client.dart';
import 'generated/monster.dart';
import 'generated/world_player.dart';

/// SpacetimeDB 의 `world_player` 표로 서로의 존재를 주고받는 구현.
///
/// 표가 공개(public)라 구독하면 **모든 접속자의 좌표가 온다.** 그것이 이 게임의
/// 전제다 — 하나의 월드를 여럿이 공유하므로 다른 요원이 어디 있는지는 서로
/// 보여야 하는 정보다. 대신 이 표에는 계정을 가리키는 값이 한 열도 없다.
class SpacetimeWorldPresence extends WorldPresence {
  SpacetimeWorldPresence(this._client);

  final SpacetimeDbClient _client;

  /// 좌표를 서버에 올리는 간격(초).
  ///
  /// 매 프레임 보내면 초당 60번 트랜잭션이 되고, 접속자 수만큼 곱해진다.
  /// 사람이 걷는 속도(초당 3.6타일)에서 0.2초면 0.7타일 — 화면에서 끊겨
  /// 보이지 않을 만큼 촘촘하고, 서버에는 초당 5번이다.
  static const Duration _interval = Duration(milliseconds: 200);

  /// 이 거리(타일)보다 적게 움직였으면 보내지 않는다.
  ///
  /// 가만히 서 있는 사람이 초당 5번씩 같은 좌표를 보낼 이유가 없다.
  static const double _minStep = 0.15;

  int? _querySetId;
  bool _subscribing = false;

  /// 열고 닫을 때마다 오르는 번호. 늦게 도착한 구독 완료가 이미 떠난 월드에
  /// 남지 않도록 막는다.
  int _generation = 0;

  DateTime? _lastSentAt;
  Vector2? _lastSentGrid;
  bool _inFlight = false;

  /// 월드에 들어가 있는지. 들어가기 전에는 좌표를 보내도 서버가 거절한다.
  bool _entered = false;

  ValueListenable<List<WorldPlayer>> get _rows => _client.worldPlayer.rows;

  ValueListenable<List<Monster>> get _monsterRows => _client.monster.rows;

  /// 지금 조종 중인 캐릭터 번호. 몹의 선점자가 나인지 가릴 때 쓴다.
  int? get _myCharacterId {
    final me = _client.identity;
    for (final row in _rows.value) {
      if (row.identity == me) return row.characterId.toInt();
    }
    return null;
  }

  @override
  bool get isAvailable => _entered;

  /// 요원 목록과 몬스터 표 중 어느 쪽이 바뀌어도 화면을 다시 맞춘다.
  @override
  Listenable get changes => Listenable.merge([_rows, _monsterRows]);

  @override
  Future<void> enter(Vector2 grid) async {
    final generation = ++_generation;

    // 구독을 먼저 건다. 입장부터 하면 내가 들어간 사실이 화면에 오기까지
    // 한 왕복이 더 걸리고, 그 사이 다른 사람이 갑자기 나타나는 것처럼 보인다.
    if (_querySetId == null && !_subscribing) {
      _subscribing = true;
      try {
        final id = await _client.subscriptions.subscribe(kWorldSubscriptions);
        if (generation != _generation) {
          _client.subscriptions.unsubscribe(id);
          return;
        }
        _querySetId = id;
      } finally {
        _subscribing = false;
      }
    }

    try {
      await _client.reducers.enterWorld(gridX: grid.x, gridY: grid.y);
      if (generation != _generation) return;
      _entered = true;

      // 입장 좌표를 서버가 이미 알고 있으므로 여기서부터 시작한다. 비워 두면
      // 첫 `report` 가 "얼마나 움직였나" 를 판단할 기준을 잃는다.
      _lastSentGrid = grid.clone();
      _lastSentAt = DateTime.now();
    } on SpacetimeDbException {
      // 캐릭터를 고르지 않았거나 연결이 끊겼다. 게임은 혼자 플레이하는 모습으로
      // 그대로 돌아가고, 다음에 다시 들어오면 된다.
      _entered = false;
    }
  }

  @override
  void leave() {
    _generation++;
    _entered = false;

    final id = _querySetId;
    if (id != null) {
      _querySetId = null;
      _client.subscriptions.unsubscribe(id);
    }

    // 나가는 것은 결과를 기다리지 않는다. 실패해도 연결이 끊기면 서버가
    // `on_disconnect` 에서 지운다.
    _client.reducers.leaveWorld().ignore();
  }

  @override
  void report(Vector2 grid) {
    if (!_entered || _inFlight) return;

    final now = DateTime.now();
    final last = _lastSentAt;
    if (last != null && now.difference(last) < _interval) return;

    final previous = _lastSentGrid;
    if (previous != null && previous.distanceTo(grid) < _minStep) return;

    _lastSentAt = now;
    _lastSentGrid = grid.clone();
    _send(grid);
  }

  Future<void> _send(Vector2 grid) async {
    _inFlight = true;
    try {
      await _client.reducers.moveTo(gridX: grid.x, gridY: grid.y);
    } on SpacetimeDbException {
      // 한 번 놓쳐도 다음 주기가 따라잡는다. 좌표는 절대값이라 밀린 것을
      // 다시 보낼 필요가 없다.
    } finally {
      _inFlight = false;
    }
  }

  @override
  List<ServerMonster> get monsters {
    final mine = _myCharacterId;
    return [
      for (final row in _monsterRows.value)
        ServerMonster(
          id: row.id.toInt(),
          level: row.level,
          grid: Vector2(row.gridX, row.gridY),
          hp: row.hp,
          maxHp: row.maxHp,
          alive: row.alive,
          taggedByMe: mine != null && row.taggedBy?.toInt() == mine,
        ),
    ];
  }

  @override
  void attack(int monsterId) {
    if (!_entered) return;
    // 결과를 기다리지 않는다. 사거리 밖이거나 쿨다운이면 서버가 거절할 뿐이고,
    // 성공하면 몬스터 표가 바뀌어 화면에 돌아온다.
    _client.reducers.attackMonster(monsterId: Int64(monsterId)).ignore();
  }

  @override
  void castSkill(String skillId, int monsterId) {
    if (!_entered) return;
    // 마력을 여기서 미리 깎지 않는다 — 서버가 거절하면 쓰지도 않은 마력이 사라진다.
    // 소비는 `world_player.mp` 가 줄어드는 것으로 돌아온다.
    _client.reducers
        .castSkill(skillId: skillId, monsterId: Int64(monsterId))
        .ignore();
  }

  @override
  void attackPlayer(int targetCharacterId) {
    if (!_entered) return;
    _client.reducers
        .attackPlayer(targetCharacterId: Int64(targetCharacterId))
        .ignore();
  }

  /// 내 행을 찾는다. 아직 입장 결과가 오지 않았으면 `null`.
  WorldPlayer? get _myRow {
    final me = _client.identity;
    for (final row in _rows.value) {
      if (row.identity == me) return row;
    }
    return null;
  }

  @override
  MyWorldState? get me {
    final row = _myRow;
    if (row == null) return null;
    return MyWorldState(
      grid: Vector2(row.gridX, row.gridY),
      hp: row.hp,
      maxHp: row.maxHp,
      mp: row.mp,
      maxMp: row.maxMp,
      alive: row.alive,
      deaths: row.deaths,
    );
  }

  @override
  List<RemotePlayer> get others {
    final me = _client.identity;
    return [
      for (final row in _rows.value)
        if (row.identity != me)
          RemotePlayer(
            characterId: row.characterId.toInt(),
            name: row.name,
            kind: row.kind,
            level: row.level,
            grid: Vector2(row.gridX, row.gridY),
            alive: row.alive,
            hp: row.hp,
            maxHp: row.maxHp,
          ),
    ];
  }
}
