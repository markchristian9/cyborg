import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:actionrpg/game/action_rpg_game.dart';
import 'package:actionrpg/game/entities/remote_player.dart';
import 'package:actionrpg/game/net/world_presence.dart';

/// 다른 요원 목록을 **읽는 쪽이 지켜야 하는 약속**을 고정한다.
///
/// [WorldPresence.others] 는 한 프레임에 네댓 번 불린다 — 게임 루프, 레이더,
/// HUD 인원수, 추종 대상 찾기, 고른 요원 찾기가 저마다 부른다. 그래서 실제
/// 구현([SpacetimeWorldPresence])은 행이 바뀔 때까지 **같은 목록 인스턴스**를
/// 돌려준다. 매번 새로 지으면 사람 수만큼 객체가 초당 수만 개씩 태어난다.
///
/// 그 대가로 읽는 쪽에는 의무가 생긴다: **받은 목록을 고쳐 쓰면 안 된다.**
/// 한때 게임 루프가 그 자리에서 `sort` 를 했는데, 그렇게 하면 레이더와 HUD 가
/// 보는 목록까지 함께 뒤집힌다.
class _SharedListPresence extends WorldPresence {
  _SharedListPresence(this.people);

  /// **언제나 같은 인스턴스를 돌려준다.** 실제 구현의 캐시와 같은 모습이다.
  final List<RemotePlayer> people;

  final _notifier = ValueNotifier<int>(0);

  /// [others] 가 몇 번 불렸는지. 프레임마다 새로 짓지 않는지 보는 데 쓴다.
  int reads = 0;

  @override
  List<RemotePlayer> get others {
    reads++;
    return people;
  }

  @override
  Listenable get changes => _notifier;

  @override
  bool get isAvailable => true;
}

RemotePlayer _agent(int id, Vector2 grid) => RemotePlayer(
      characterId: id,
      name: 'UNIT-$id',
      kind: 'male_cyborg',
      level: 1,
      grid: grid,
      alive: true,
      hp: 100,
      maxHp: 100,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 요원 [count] 명을 세운 게임.
  ///
  /// 🛑 **목록 순서와 거리 순서를 일부러 어긋나게 놓는다.** 가까운 사람부터
  /// 차례로 담으면 거리순 정렬이 아무것도 바꾸지 않아, 목록을 그 자리에서
  /// 뒤집는 잘못을 저질러도 시험이 알아채지 못한다. 번호가 **클수록 가깝게**
  /// 세워 두 순서를 정반대로 만든다.
  ///
  /// 번호와 거리가 일대일로 이어지므로 "가까운 쪽만 골랐는가" 도 번호로 본다.
  Future<(ActionRpgGame, _SharedListPresence)> gameWithAgents(int count) async {
    final presence = _SharedListPresence([]);
    // autoStart 로 만든다. 메인 메뉴 오버레이는 테스트 위젯 트리에 등록되어
    // 있지 않아, 띄우려 하면 그 자리에서 죽는다.
    final game = ActionRpgGame(presence: presence, autoStart: true);
    game.onGameResize(Vector2(1280, 800));
    await game.onLoad();

    // 조이스틱은 실제 레이아웃을 거쳐야 내부 상태가 서므로 테스트에서 돌리면
    // 죽는다. 검증 대상이 아니니 걷어낸다.
    for (final joystick
        in game.descendants().whereType<JoystickComponent>().toList()) {
      joystick.removeFromParent();
    }

    final origin = game.player.grid;
    for (var i = 0; i < count; i++) {
      // 앞번호일수록 멀다 — 목록 순서와 거리 순서가 정반대다.
      final distance = 1.0 + (count - 1 - i) * 0.5;
      presence.people.add(_agent(i, origin + Vector2(distance, 0)));
    }
    return (game, presence);
  }

  test('게임 루프는 남에게서 받은 요원 목록을 뒤집지 않는다', () async {
    // 정원(50)을 훌쩍 넘겨야 줄 세우기 경로로 들어간다.
    final (game, presence) = await gameWithAgents(120);
    final before = List<RemotePlayer>.of(presence.people);

    for (var i = 0; i < 10; i++) {
      game.update(1 / 60);
    }

    expect(
      presence.people,
      orderedEquals(before),
      reason: '받은 목록을 그 자리에서 정렬했다 — 이 목록은 레이더와 HUD 도 '
          '함께 읽으므로, 여기서 뒤집으면 그쪽 화면까지 흔들린다',
    );
  });

  test('정원을 넘으면 가까운 쪽부터 그린다', () async {
    // 번호가 **클수록 가깝게** 세웠으므로, 살아남아야 하는 것은 뒷번호 50 명이다.
    final (game, _) = await gameWithAgents(120);

    for (var i = 0; i < 10; i++) {
      game.update(1 / 60);
    }

    expect(
      game.remotePlayerCount,
      50,
      reason: '표시 상한(50)만큼 그려야 한다',
    );

    final drawn = game.world.children
        .whereType<RemotePlayerEntity>()
        .map((e) => e.characterId)
        .toSet();
    expect(drawn.length, 50, reason: '월드에 붙은 몸의 수가 목록과 어긋난다');
    expect(
      drawn,
      // 120 명 중 가장 가까운 50 명 = 번호 70..119.
      equals({for (var i = 70; i < 120; i++) i}),
      reason: '가까운 쪽이 아니라 목록에 먼저 담긴 쪽을 골랐다 — 눈앞에 선 '
          '사람이 안 보이고 화면 밖 사람이 그려진다',
    );
  });

  test('정원 안이면 모두 그린다', () async {
    final (game, _) = await gameWithAgents(12);

    for (var i = 0; i < 10; i++) {
      game.update(1 / 60);
    }

    expect(game.remotePlayerCount, 12);
  });

  /// 목록이 그대로면 **몸을 다시 만들지 않는지** 본다.
  ///
  /// 매 프레임 새로 만들면 보간 상태가 사라져 남들이 초당 60번 제자리에서 다시
  /// 태어나고, 걸어오는 모습이 나오지 않는다.
  test('같은 사람은 같은 몸을 계속 쓴다', () async {
    final (game, _) = await gameWithAgents(3);

    for (var i = 0; i < 10; i++) {
      game.update(1 / 60);
    }
    final first =
        game.world.children.whereType<RemotePlayerEntity>().toList();

    for (var i = 0; i < 10; i++) {
      game.update(1 / 60);
    }
    final second =
        game.world.children.whereType<RemotePlayerEntity>().toList();

    expect(first.length, 3);
    expect(
      second.map(identityHashCode),
      orderedEquals(first.map(identityHashCode)),
      reason: '같은 사람인데 몸을 새로 만들었다 — 보간 상태가 매 프레임 지워진다',
    );
  });
}
