import 'package:flutter/foundation.dart';

/// 리더보드에 표시할 한 줄.
///
/// 서버가 보내는 타입을 그대로 쓰지 않고 게임 쪽 표현으로 옮겨 담는다.
/// 그래야 리더보드 화면이 SpacetimeDB 생성 코드를 몰라도 되고, 백엔드가
/// 바뀌어도 화면은 그대로 남는다.
class LeaderboardRow {
  const LeaderboardRow({
    required this.rank,
    required this.name,
    required this.kind,
    required this.level,
    required this.xp,
    required this.totalXp,
    required this.isMine,
  });

  /// 1 부터 시작하는 순위.
  final int rank;

  final String name;

  /// 캐릭터 외형(`male_cyborg` · `female_cyborg`).
  final String kind;

  final int level;

  /// 지금 레벨에서 다음 레벨까지 쌓은 진행도.
  final int xp;

  /// 지금까지 얻은 경험치의 총합. 순위를 정하는 값이다.
  final int totalXp;

  /// 지금 플레이 중인 내 캐릭터인지. 목록에서 강조하는 데 쓴다.
  final bool isMine;
}

/// 리더보드가 어디서 오는지 감춘 공급자.
///
/// 게임은 이 인터페이스만 알고 있으므로 서버에 붙지 않아도 화면이 뜬다 —
/// 그때는 [isAvailable] 이 false 이고 화면이 그 사실을 알린다.
abstract class LeaderboardSource {
  const LeaderboardSource();

  /// 순위표를 받기 시작한다. 화면을 열 때 부른다.
  ///
  /// 보고 있지 않은 동안까지 순위 갱신을 받아 둘 이유가 없으므로, 공급자는
  /// 이 시점에 서버 구독을 건다.
  Future<void> attach() async {}

  /// 순위표 받기를 멈춘다. 화면을 닫을 때 부른다.
  void detach() {}

  /// 서버에서 받은 순위표. 순위 오름차순으로 정렬되어 있다.
  List<LeaderboardRow> get rows;

  /// 내 캐릭터의 순위. [rows] 밖(하위권)일 수도 있고, 로그인하지 않았거나
  /// 캐릭터를 고르지 않았으면 null 이다.
  LeaderboardRow? get myRank;

  /// 순위표를 읽을 수 있는 상태인지. 서버에 붙지 못했으면 false.
  bool get isAvailable;

  /// 순위표가 바뀔 때 알리는 신호. 화면은 여기에 귀를 붙인다.
  Listenable get changes;
}

/// 서버가 없을 때 쓰는 빈 공급자.
class EmptyLeaderboardSource extends LeaderboardSource {
  const EmptyLeaderboardSource();

  @override
  List<LeaderboardRow> get rows => const [];

  @override
  LeaderboardRow? get myRank => null;

  @override
  bool get isAvailable => false;

  /// 영영 바뀌지 않으므로 아무에게도 알리지 않는 신호를 준다.
  @override
  Listenable get changes => _never;

  static final Listenable _never = Listenable.merge(const []);
}
