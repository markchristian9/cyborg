import 'dart:async';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart';

import '../game/net/world_presence.dart';
import 'cyborg_connection.dart';
import 'generated/client.dart';
import 'generated/loot.dart';
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

  /// 좌표를 서버에 올리는 간격(초). **20 Hz** — 서버 월드 틱과 같다.
  ///
  /// 매 프레임 보내면 초당 60번 트랜잭션이 되고, 접속자 수만큼 곱해진다.
  /// 사람이 걷는 속도(초당 3.6타일)에서 0.05초면 0.18타일 — 남의 화면에서
  /// 보간이 메워야 할 구간이 몸 반 칸도 되지 않는다.
  ///
  /// **0.2초(5 Hz)에서 올렸다.** 보간은 갱신 간격만큼의 지연을 반드시 안고
  /// 가므로, 5 Hz 에서는 아무리 매끄럽게 그려도 남이 방향을 튼 것이 0.2초 뒤에
  /// 닿았다. MMORPG 가 보통 쓰는 10~30 Hz 의 한가운데이며, 서버
  /// `MONSTER_AI_MILLIS`(50ms)와 같은 리듬이라 PC 와 몹이 함께 갱신된다.
  static const Duration _interval = Duration(milliseconds: 50);

  /// 이 거리(타일)보다 적게 움직였으면 보내지 않는다.
  ///
  /// 가만히 서 있는 사람이 초당 스무 번씩 같은 좌표를 보낼 이유가 없다.
  ///
  /// **주기를 20 Hz 로 올리면서 함께 낮췄다.** 한 틱에 걷는 거리가 0.18타일뿐이라
  /// 문턱이 0.15 면 걸을 때조차 아슬아슬하게 걸려, 주기를 올려 놓고도 실제
  /// 전송은 띄엄띄엄해진다. 0.04 는 그 4분의 1 남짓이라 움직이는 동안에는
  /// 확실히 통과하고, 멈춰 서면 여전히 한 번도 보내지 않는다.
  static const double _minStep = 0.04;

  /// 방향이 이만큼 돌아가면 다시 보낸다(두 방향 내적의 문턱값).
  ///
  /// 0.985 는 약 10 도다. 더 작게 잡으면 조이스틱이 미세하게 떨릴 때마다
  /// 전송이 일어나고, 더 크게 잡으면 몸을 돌린 것이 남의 화면에 늦게 닿는다.
  static const double _facingCosThreshold = 0.985;

  /// 새 청크 안쪽으로 이만큼 들어온 뒤에야 구독을 옮긴다(타일).
  ///
  /// 경계선 위를 왕복하면 재구독이 진동한다. 보행 3.6 타일/초에서 최소 2.2 초,
  /// 최대 속도 14 타일/초에서도 0.57 초 간격이 보장된다.
  static const double _chunkHysteresis = 8.0;

  /// 재구독 최소 간격. 넉백·대시로 경계를 스치는 경우까지 흡수한다.
  static const Duration _resubCooldown = Duration(milliseconds: 1500);

  int? _querySetId;
  bool _subscribing = false;

  /// 열고 닫을 때마다 오르는 번호. 늦게 도착한 구독 완료가 이미 떠난 월드에
  /// 남지 않도록 막는다.
  int _generation = 0;

  /// 지금 구독이 기준으로 삼은 청크. 실제 좌표가 아니라 **구독을 건 시점**의 것이다.
  int? _subCx;
  int? _subCy;
  DateTime? _lastResubAt;

  DateTime? _lastSentAt;
  Vector2? _lastSentGrid;

  /// 마지막으로 보낸 방향(정규화됨).
  Vector2? _lastSentFacing;
  bool _inFlight = false;

  /// 월드에 들어가 있는지. 들어가기 전에는 좌표를 보내도 서버가 거절한다.
  bool _entered = false;

  ValueListenable<List<WorldPlayer>> get _rows => _client.worldPlayer.rows;

  ValueListenable<List<Monster>> get _monsterRows => _client.monster.rows;

  ValueListenable<List<Loot>> get _lootRows => _client.loot.rows;

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
  Listenable get changes =>
      Listenable.merge([_rows, _monsterRows, _lootRows]);

  @override
  Future<void> enter(Vector2 grid) async {
    final generation = ++_generation;

    // 구독을 먼저 건다. 입장부터 하면 내가 들어간 사실이 화면에 오기까지
    // 한 왕복이 더 걸리고, 그 사이 다른 사람이 갑자기 나타나는 것처럼 보인다.
    if (_querySetId == null && !_subscribing) {
      _subscribing = true;
      try {
        final id = await _client.subscriptions
            .subscribe(worldSubscriptionsFor(grid.x, grid.y));
        if (generation != _generation) {
          _client.subscriptions.unsubscribe(id);
          return;
        }
        _querySetId = id;
        _subCx = grid.x ~/ kPlayerSubChunkTiles;
        _subCy = grid.y ~/ kPlayerSubChunkTiles;
        _lastResubAt = DateTime.now();
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
      _subCx = null;
      _subCy = null;
      _client.subscriptions.unsubscribe(id);
    }

    // 나가는 것은 결과를 기다리지 않는다. 실패해도 연결이 끊기면 서버가
    // `on_disconnect` 에서 지운다.
    _client.reducers.leaveWorld().ignore();
  }

  @override
  void report(Vector2 grid, Vector2 facing) {
    if (!_entered) return;

    // 좌표 보고와 **별개로** 확인한다. 아래 `_inFlight`·주기 검사에 걸려 보고를
    // 건너뛰는 동안에도 청크는 넘어갈 수 있고, 그때 재구독을 놓치면 주변이
    // 통째로 비어 보인다.
    //
    // 기준은 **서버가 아는 내 자리**다. 화면의 예측 좌표를 쓰면, 서버가 나를
    // 옮겼을 때(입장 좌표 보정·사망 재가동·텔레포트) 구독만 옛 자리에 남는다.
    // 그러면 자기 자신조차 구독 범위 밖이 되어 주변이 영영 비어 보인다.
    unawaited(_maybeResubscribe(_myRow == null
        ? grid
        : Vector2(_myRow!.gridX, _myRow!.gridY)));

    if (_inFlight) return;

    final now = DateTime.now();
    final last = _lastSentAt;
    if (last != null && now.difference(last) < _interval) return;

    // 자리도 방향도 그대로면 보낼 것이 없다. 둘 중 하나만 바뀌어도 보낸다 —
    // **제자리에서 몸만 도는 것도 남에게 보여야 하는 움직임이다.**
    final previous = _lastSentGrid;
    final movedEnough =
        previous == null || previous.distanceTo(grid) >= _minStep;
    final turnedEnough = _lastSentFacing == null ||
        _lastSentFacing!.dot(facing.length2 > 0.0001
                ? facing.normalized()
                : _lastSentFacing!) <
            _facingCosThreshold;
    if (!movedEnough && !turnedEnough) return;

    _lastSentAt = now;
    _lastSentGrid = grid.clone();
    if (facing.length2 > 0.0001) {
      _lastSentFacing = facing.normalized();
    }
    _send(grid, _lastSentFacing ?? Vector2(0, 1));
  }

  /// 청크를 넘었으면 구독을 옮긴다.
  ///
  /// **새 구독을 먼저 걸고 옛 것을 나중에 푼다.** 순서를 뒤집으면 그 왕복 동안
  /// 주변 사람과 몹이 통째로 사라졌다 나타난다. 겹치는 구간은 SpacetimeDB 가
  /// 행 소유권을 함께 들고 있으므로, 옛 구독을 풀어도 겹친 행은 남는다.
  ///
  /// 전환 조건이 "청크가 달라졌다" 가 아니라 "새 청크 안쪽으로 [`_chunkHysteresis`]
  /// 만큼 들어왔다" 인 이유는 경계선 위를 왕복할 때의 진동을 막기 위해서다.
  /// 다만 **한 청크를 통째로 건너뛴 이동**(텔레포트·사망 재가동)은 히스테리시스도
  /// 쿨다운도 무시한다 — 그 경우 옛 구독은 이미 아무 쓸모가 없다.
  Future<void> _maybeResubscribe(Vector2 grid) async {
    if (_subscribing || _querySetId == null) return;

    final cx = grid.x ~/ kPlayerSubChunkTiles;
    final cy = grid.y ~/ kPlayerSubChunkTiles;
    final fromCx = _subCx;
    final fromCy = _subCy;
    if (fromCx == null || fromCy == null) return;
    if (cx == fromCx && cy == fromCy) return;

    // 3×3 밖으로 나갔다면 옛 구독에는 지금 주변이 한 칸도 없다. 즉시 옮긴다.
    final jumped = (cx - fromCx).abs() > 1 || (cy - fromCy).abs() > 1;

    if (!jumped) {
      final localX = grid.x - cx * kPlayerSubChunkTiles;
      final localY = grid.y - cy * kPlayerSubChunkTiles;
      final inset = math.min(
        math.min(localX, kPlayerSubChunkTiles - localX),
        math.min(localY, kPlayerSubChunkTiles - localY),
      );
      if (inset < _chunkHysteresis) return;

      final last = _lastResubAt;
      if (last != null && DateTime.now().difference(last) < _resubCooldown) {
        return;
      }
    }

    final generation = _generation;
    _subscribing = true;
    final old = _querySetId;
    try {
      final id = await _client.subscriptions
          .subscribe(worldSubscriptionsFor(grid.x, grid.y));
      if (generation != _generation) {
        // 그 사이 월드를 떠났다. 새로 건 것만 정리한다 — 옛 것은 `leave` 가 이미 풀었다.
        _client.subscriptions.unsubscribe(id);
        return;
      }
      _querySetId = id;
      _subCx = cx;
      _subCy = cy;
      _lastResubAt = DateTime.now();
      if (old != null) _client.subscriptions.unsubscribe(old);
    } on SpacetimeDbException {
      // 옛 구독을 그대로 둔 채 다음 기회를 기다린다. 화면이 조금 낡을 뿐,
      // 아무것도 안 보이는 것보다 낫다.
    } finally {
      _subscribing = false;
    }
  }

  Future<void> _send(Vector2 grid, Vector2 facing) async {
    _inFlight = true;
    try {
      await _client.reducers.moveTo(
        gridX: grid.x,
        gridY: grid.y,
        facingX: facing.x,
        facingY: facing.y,
      );
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
          facing: Vector2(row.faceX, row.faceY),
          lastAttackAtMicros: row.lastAttackAt.toInt(),
        ),
    ];
  }

  @override
  List<ServerLoot> get loots {
    final mine = _myCharacterId;
    // 서버 시각은 마이크로초다. 우선권이 아직 살아 있는지 재는 데만 쓴다.
    final nowMicros = DateTime.now().toUtc().microsecondsSinceEpoch;
    return [
      for (final row in _lootRows.value)
        ServerLoot(
          id: row.id.toInt(),
          kind: row.kind,
          amount: row.amount,
          grid: Vector2(row.gridX, row.gridY),
          reservedForMe: mine != null &&
              row.reservedFor?.toInt() == mine &&
              row.reservedUntil.toInt() > nowMicros,
          reservedForOther: row.reservedFor != null &&
              row.reservedFor?.toInt() != mine &&
              row.reservedUntil.toInt() > nowMicros,
        ),
    ];
  }

  @override
  Future<bool> pickLoot(int lootId) async {
    if (!_entered) return false;
    try {
      await _client.reducers.pickLoot(lootId: Int64(lootId));
      return true;
    } on SpacetimeDbException {
      // 남이 먼저 가져갔거나, 우선권이 남아 있거나, 너무 멀다. 어느 쪽이든
      // 내 것이 아니므로 조용히 빈손으로 돌아간다.
      return false;
    }
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
  /// 서버가 아는 내 행.
  ///
  /// **청크 구독이 아니라 `my_world_player` view 에서 읽는다.** 그쪽은 내가
  /// 어디에 있든 언제나 한 줄을 주므로, 서버가 나를 옮겨도 새 자리를 알 수 있다.
  /// 청크 구독에서 읽으면 옮겨진 순간 내 행이 사라져 옛 자리에 갇힌다.
  WorldPlayer? get _myRow {
    final mine = _client.myWorldPlayer;
    if (mine != null) return mine;
    // view 가 아직 안 왔을 때를 위한 대비책. 월드 구독에도 내 행은 들어 있다.
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
      lastDamagedAtMicros: row.lastDamagedAt.toInt(),
    );
  }

  @override
  int? get serverTotalXp {
    final id = _myCharacterId;
    if (id == null) return null;
    for (final row in _client.myCharacters.iter()) {
      if (row.id.toInt() == id) return row.totalXp;
    }
    return null;
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
            lastAttackAtMicros: row.lastAttackAt.toInt(),
            attackDir: Vector2(row.attackDirX, row.attackDirY),
            attackSkill: row.attackSkill,
            facing: Vector2(row.facingX, row.facingY),
          ),
    ];
  }
}
