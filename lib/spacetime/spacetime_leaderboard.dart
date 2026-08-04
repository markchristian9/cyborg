import 'package:flutter/foundation.dart';

import '../game/net/leaderboard_source.dart';
import 'cyborg_connection.dart';
import 'generated/client.dart';
import 'generated/leaderboard_entry.dart';

/// SpacetimeDB 의 `leaderboard` · `my_rank` view 를 게임 쪽 표현으로 옮기는 어댑터.
///
/// 두 view 를 함께 본다. `leaderboard` 는 상위권만 담고 있어서, 내 캐릭터가
/// 하위권이면 그 목록에 없다. 그때도 본인 순위는 보여야 하므로 서버가 따로
/// 계산해 주는 `my_rank` 를 함께 읽는다.
///
/// 로컬에 순위를 다시 계산하지 않는다. 순위는 서버가 정하고 여기서는 옮기기만
/// 한다 — 두 곳에서 계산하면 언젠가 서로 다른 답을 낸다.
class SpacetimeLeaderboard extends LeaderboardSource {
  SpacetimeLeaderboard(this._client);

  final SpacetimeDbClient _client;

  ValueListenable<List<LeaderboardEntry>> get _boardRows =>
      _client.leaderboard.rows;

  ValueListenable<List<LeaderboardEntry>> get _myRankRows => _client
      .subscriptions
      .cache
      .getTableByTypedName<LeaderboardEntry>('my_rank')
      .rows;

  /// 지금 걸려 있는 구독의 식별자. 걸려 있지 않으면 null.
  int? _querySetId;

  /// 구독을 거는 중인지. 화면을 빠르게 여닫아도 두 번 걸리지 않게 한다.
  bool _subscribing = false;

  /// 열고 닫을 때마다 오르는 번호.
  ///
  /// 구독을 거는 데는 왕복이 필요한데, 그 사이에 화면이 닫히면 `_querySetId` 가
  /// 아직 없어서 [detach] 가 아무것도 취소하지 못한다. 그러고 나서 구독이
  /// 완료되면 **아무도 보지 않는 순위표가 계속 흘러든다.** 그래서 구독을 걸기
  /// 시작한 시점의 번호를 들고 있다가, 완료 시점에 번호가 달라졌으면 그 구독은
  /// 이미 버려진 것으로 보고 즉시 해제한다.
  int _generation = 0;

  @override
  bool get isAvailable => true;

  /// 순위표를 받기 시작한다. 화면을 열 때 부른다.
  ///
  /// 구독이 자리 잡을 때까지 기다린다. 화면은 이 `Future` 가 끝나는 시점으로
  /// "불러오는 중" 을 푼다 — 캐시 알림만 기다리면 결과가 비었을 때 영영 풀리지
  /// 않는다.
  @override
  Future<void> attach() async {
    if (_querySetId != null || _subscribing) return;

    final generation = ++_generation;
    _subscribing = true;
    try {
      final id = await _client.subscriptions.subscribe(kLeaderboardSubscriptions);
      if (generation != _generation) {
        // 기다리는 사이에 화면이 닫혔(거나 다시 열렸)다. 이 구독은 주인이 없다.
        _client.subscriptions.unsubscribe(id);
        return;
      }
      _querySetId = id;
    } finally {
      _subscribing = false;
    }
  }

  /// 순위표 구독을 푼다. 화면을 닫을 때 부른다.
  @override
  void detach() {
    // 번호를 올려 두면, 아직 오지 않은 구독 완료도 스스로를 취소한다.
    _generation++;

    final id = _querySetId;
    if (id == null) return;
    _querySetId = null;
    _client.subscriptions.unsubscribe(id);
  }

  /// 순위표와 내 순위 중 어느 쪽이 바뀌어도 화면을 다시 그린다.
  ///
  /// 내 레벨이 올라도 상위권 목록은 그대로일 수 있다(내가 100위 밖이면).
  /// 그 경우 `leaderboard` 만 보고 있으면 내 순위가 갱신되지 않는다.
  @override
  Listenable get changes => Listenable.merge([_boardRows, _myRankRows]);

  @override
  LeaderboardRow? get myRank {
    final entry = _client.myRank;
    return entry == null ? null : _toRow(entry, isMine: true);
  }

  @override
  List<LeaderboardRow> get rows {
    final mineId = _client.myRank?.characterId;
    // 서버가 순위 순으로 보내지만 캐시는 순서를 약속하지 않는다.
    final entries = _boardRows.value.toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));
    return [
      for (final entry in entries)
        _toRow(entry, isMine: mineId != null && entry.characterId == mineId),
    ];
  }

  LeaderboardRow _toRow(LeaderboardEntry entry, {required bool isMine}) {
    return LeaderboardRow(
      rank: entry.rank,
      name: entry.name,
      kind: entry.kind,
      level: entry.level,
      xp: entry.xp,
      totalXp: entry.totalXp,
      isMine: isMine,
    );
  }
}
