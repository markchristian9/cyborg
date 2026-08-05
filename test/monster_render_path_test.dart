import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:actionrpg/game/action_rpg_game.dart';
import 'package:actionrpg/game/entities/enemy.dart';
import 'package:actionrpg/game/net/world_presence.dart';

/// 서버가 준 몬스터가 **실제로 화면의 몸이 되는지** 확인한다.
///
/// 서버에 몹이 있고 구독으로 행도 오는데 화면에는 아무것도 없던 일이 있었다.
/// 데이터가 온다는 것과 그려진다는 것은 다른 문제이고, 그 사이를 잇는 것이
/// 스트리밍이다. 여기서 끊기면 "서버 권위" 는 화면에 아무 의미가 없다.
class _FakePresence extends WorldPresence {
  _FakePresence(this._monsters);

  final List<ServerMonster> _monsters;
  final _notifier = ValueNotifier<int>(0);

  @override
  List<ServerMonster> get monsters => _monsters;

  @override
  Listenable get changes => _notifier;

  @override
  bool get isAvailable => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 월드 중심 근처에 몹 [count] 기를 세운 게임.
  Future<ActionRpgGame> gameWithServerMonsters(int count) async {
    // autoStart 로 만든다. 메인 메뉴 오버레이는 테스트 위젯 트리에 등록되어
    // 있지 않아, 띄우려 하면 그 자리에서 죽는다.
    final game = ActionRpgGame(presence: _FakePresence([]), autoStart: true);
    game.onGameResize(Vector2(1280, 800));
    await game.onLoad();

    // 조이스틱은 실제 레이아웃을 거쳐야 내부 상태가 서므로 테스트에서 돌리면
    // 죽는다. 검증 대상이 아니니 걷어낸다.
    for (final joystick
        in game.descendants().whereType<JoystickComponent>().toList()) {
      joystick.removeFromParent();
    }

    final origin = game.player.grid;
    final monsters = [
      for (var i = 0; i < count; i++)
        ServerMonster(
          id: 1000 + i,
          level: 1 + i % 30,
          // 반경 안에 고르게 흩는다.
          grid: origin + Vector2(3.0 + i % 20, 3.0 + (i ~/ 20) * 2.0),
          hp: 500,
          maxHp: 500,
          alive: true,
          taggedByMe: false,
        ),
    ];
    (game.presence as _FakePresence)._monsters.addAll(monsters);
    return game;
  }

  test('서버 몬스터는 화면의 몸이 된다', () async {
    final game = await gameWithServerMonsters(30);

    // 스트리밍 주기(0.3초)를 넘겨 돌린다.
    for (var i = 0; i < 30; i++) {
      game.update(1 / 60);
    }

    final drawn = game.world.children.whereType<Enemy>().toList();
    expect(
      drawn,
      isNotEmpty,
      reason: '서버가 몹을 주는데도 월드에 몸이 하나도 붙지 않았다',
    );
    expect(game.enemies, isNotEmpty, reason: '전투 대상 목록이 비어 있다');
    expect(
      drawn.every((e) => e.isServerDriven),
      isTrue,
      reason: '서버 몹인데 로컬 AI 로 도는 몸이 섞였다',
    );
  });

  test('조밀한 사냥터에서도 화면 안 몹은 전부 그린다', () async {
    // 실측: 가장 조밀한 저레벨 사냥터는 화면 반폭(약 22 타일) 안에만 66 기가
    // 있다. 표시 상한이 그보다 낮으면 눈앞의 몹이 그려지지 않아 화면이 성기게
    // 비어 보인다 — "몬스터가 투명하다" 로 읽히던 증상이다.
    final game = ActionRpgGame(presence: _FakePresence([]), autoStart: true);
    game.onGameResize(Vector2(1280, 800));
    await game.onLoad();
    for (final joystick
        in game.descendants().whereType<JoystickComponent>().toList()) {
      joystick.removeFromParent();
    }

    // 플레이어 둘레 반경 12 타일 안에 80 기를 촘촘히 세운다. 이 범위는 어떤
    // 배율에서도 화면 안이다.
    final origin = game.player.grid;
    final monsters = <ServerMonster>[];
    for (var i = 0; i < 80; i++) {
      final angle = i * 2.399963; // 황금각 — 고르게 흩어진다
      final radius = 2.0 + (i % 10);
      monsters.add(
        ServerMonster(
          id: 5000 + i,
          level: 1 + i % 5,
          grid: origin +
              Vector2(math.cos(angle) * radius, math.sin(angle) * radius),
          hp: 100,
          maxHp: 100,
          alive: true,
          taggedByMe: false,
        ),
      );
    }
    (game.presence as _FakePresence)._monsters.addAll(monsters);

    for (var i = 0; i < 30; i++) {
      game.update(1 / 60);
    }

    final drawn = game.world.children.whereType<Enemy>().length;
    expect(
      drawn,
      greaterThanOrEqualTo(80),
      reason: '화면 안 몹 80 기 중 $drawn 기만 그렸다 — 표시 상한이 화면을 굶긴다',
    );
  });

  test('몸의 화면 좌표가 그리드를 따라간다', () async {
    final game = await gameWithServerMonsters(5);
    for (var i = 0; i < 30; i++) {
      game.update(1 / 60);
    }

    final drawn = game.world.children.whereType<Enemy>().toList();
    expect(drawn, isNotEmpty);
    // position 이 원점에 머물러 있으면 화면 밖에 그려진다 — 데이터는 맞는데
    // 눈에는 아무것도 안 보이는 증상이 정확히 이 모습이다.
    expect(
      drawn.every((e) => e.position.length > 1),
      isTrue,
      reason: '몸이 붙었지만 화면 좌표가 갱신되지 않았다',
    );
  });
}
