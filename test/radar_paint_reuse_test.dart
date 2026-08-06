import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:actionrpg/game/action_rpg_game.dart';
import 'package:actionrpg/game/net/world_presence.dart';
import 'package:actionrpg/game/palette.dart';
import 'package:actionrpg/game/ui/hud.dart';

/// 레이더가 **붓을 돌려 쓰면서도 색을 헷갈리지 않는지** 고정한다.
///
/// 레이더는 매 프레임 점 수백 개를 찍는다 — 몹 360 기, 사람 50 명, 전리품까지.
/// 점 하나에 [Paint] 를 새로 지으면 그것만으로 초당 수만 개가 태어나므로 붓
/// 하나를 색만 바꿔 가며 돌려 쓴다.
///
/// 그 대가로 **쓰기 직전에 색을 지정해야 하는** 의무가 생긴다. 빠뜨리면 앞선
/// loop 가 남긴 색이 그대로 묻어 온다 — 사람이 몹 색으로 찍히거나 그 반대다.
/// 예외도 로그도 없이 레이더의 뜻만 조용히 뒤집히는 종류의 결함이라, 눈으로
/// 보지 않으면 알아채기 어렵다.
///
/// 그래서 `drawCircle` 에 실제로 넘어간 색을 받아 적어 센다.
class _RecordingCanvas implements Canvas {
  final List<({double radius, int argb})> circles = [];

  @override
  void drawCircle(Offset c, double radius, Paint paint) {
    // **그 자리에서 색을 읽어 둔다.** 붓은 다음 점을 그리기 전에 색이 바뀌므로,
    // 붓을 그대로 들고 있으면 나중에는 전부 마지막 색으로 보인다.
    //
    // 🛑 [Color] 를 그대로 들고 비교하지 않는다. 요즘 [Color] 는 성분이 실수라
    // `Paint` 를 한 번 거쳐 나온 값이 `==` 로는 원본과 같지 않다 — 눈에 보이는
    // 색은 같은데 시험만 조용히 어긋난다. 32비트 정수로 굳혀 둔다.
    circles.add((radius: radius, argb: paint.color.toARGB32()));
  }

  /// 나머지 그리기는 이 시험의 관심 밖이라 조용히 흘려보낸다.
  @override
  void noSuchMethod(Invocation invocation) {}
}

class _FakePresence extends WorldPresence {
  _FakePresence(this.monsterList, this.people);

  final List<ServerMonster> monsterList;
  final List<RemotePlayer> people;
  final _notifier = ValueNotifier<int>(0);

  @override
  List<ServerMonster> get monsters => monsterList;

  @override
  List<RemotePlayer> get others => people;

  @override
  Listenable get changes => _notifier;

  @override
  bool get isAvailable => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('레이더의 몹·사람 점이 서로의 색으로 새지 않는다', () async {
    const monsterCount = 12;
    const agentCount = 5;

    final presence = _FakePresence([], []);
    final game = ActionRpgGame(presence: presence, autoStart: true);
    game.onGameResize(Vector2(1280, 800));
    await game.onLoad();
    for (final j
        in game.descendants().whereType<JoystickComponent>().toList()) {
      j.removeFromParent();
    }

    final origin = game.player.grid;
    for (var i = 0; i < monsterCount; i++) {
      presence.monsterList.add(
        ServerMonster(
          id: 900 + i,
          // 지휘급(보스)이 섞이지 않도록 낮은 레벨로 고정한다. 보스는 점이
          // 커질 뿐 색은 같지만, 반지름으로 세는 것을 헷갈리게 한다.
          level: 1,
          grid: origin + Vector2(2.0 + i * 0.4, 1.0),
          hp: 100,
          maxHp: 100,
          alive: true,
          taggedByMe: false,
        ),
      );
    }
    for (var i = 0; i < agentCount; i++) {
      presence.people.add(
        RemotePlayer(
          characterId: i,
          name: 'U$i',
          kind: 'male_cyborg',
          level: 1,
          grid: origin + Vector2(-2.0 - i * 0.4, 1.0),
          alive: true,
          hp: 100,
          maxHp: 100,
        ),
      );
    }

    // 스트리밍 주기(0.3초)를 넘겨 돌려 몹이 실제 몸을 얻게 한다.
    for (var i = 0; i < 30; i++) {
      game.update(1 / 60);
    }
    expect(
      game.enemies.where((e) => e.isAlive).length,
      monsterCount,
      reason: '몹이 몸을 얻지 못했다 — 이 시험의 전제가 무너졌다',
    );

    final hud = game.camera.viewport.children.whereType<Hud>().single;
    final canvas = _RecordingCanvas();
    hud.render(canvas);

    int countOf(Color c) =>
        canvas.circles.where((d) => d.argb == c.toARGB32()).length;

    expect(
      countOf(GamePalette.robotEye),
      monsterCount,
      reason: '몹 점의 수가 몹 수와 다르다 — 돌려 쓰는 붓의 색이 새고 있다',
    );
    expect(
      countOf(GamePalette.remotePlayer),
      agentCount,
      reason: '사람 점의 수가 사람 수와 다르다 — 앞선 loop 의 색이 묻어 왔다',
    );
    expect(
      countOf(GamePalette.playerAccent),
      1,
      reason: '내 몸을 가리키는 점이 하나가 아니다',
    );
  });
}
