import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:actionrpg/game/action_rpg_game.dart';
import 'package:actionrpg/game/net/world_presence.dart';
import 'package:actionrpg/game/ui/hud.dart';

/// 레이더 지형을 **굳혀 두고 밀어 쓰는** 방식이 어긋나지 않는지 고정한다.
///
/// 지형은 월드에 붙박여 있으므로 매 프레임 2,200 칸을 다시 그릴 이유가 없다.
/// 한 번 그려 [Picture] 로 굳혀 두고 그 뒤로는 밀어서 쓴다 — 실측하면 HUD 한
/// 프레임이 924 µs 에서 265 µs 로 준다.
///
/// 그 대가로 **밀어내는 거리가 정확해야 하는** 의무가 생긴다. 어긋나면 지형만
/// 조금씩 흘러 몹 점과 따로 논다. 예외도 로그도 없이 레이더가 거짓말을 하는
/// 종류의 결함이라, 화면을 오래 들여다보기 전에는 알아채기 어렵다.
class _TrackingCanvas implements Canvas {
  /// 지금까지 쌓인 평행이동. `save`/`restore` 를 따라 오르내린다.
  double _tx = 0;
  double _ty = 0;
  final List<(double, double)> _stack = [];

  /// `drawPicture` 가 불린 시점의 누적 평행이동.
  final List<(double, double)> pictureAt = [];

  @override
  void save() => _stack.add((_tx, _ty));

  @override
  void restore() {
    if (_stack.isEmpty) return;
    final (x, y) = _stack.removeLast();
    _tx = x;
    _ty = y;
  }

  @override
  void translate(double dx, double dy) {
    _tx += dx;
    _ty += dy;
  }

  @override
  void drawPicture(Picture picture) => pictureAt.add((_tx, _ty));

  @override
  void noSuchMethod(Invocation invocation) {}
}

class _FakePresence extends WorldPresence {
  final _notifier = ValueNotifier<int>(0);
  @override
  Listenable get changes => _notifier;
  @override
  bool get isAvailable => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ActionRpgGame, Hud)> freshGame() async {
    final game = ActionRpgGame(presence: _FakePresence(), autoStart: true);
    game.onGameResize(Vector2(1280, 800));
    await game.onLoad();
    for (final j
        in game.descendants().whereType<JoystickComponent>().toList()) {
      j.removeFromParent();
    }
    final hud = game.camera.viewport.children.whereType<Hud>().single;
    return (game, hud);
  }

  test('가까이 움직이는 동안에는 지형을 다시 굳히지 않는다', () async {
    final (game, hud) = await freshGame();

    hud.render(_TrackingCanvas());
    final first = hud.terrainPicture;
    expect(first, isNotNull, reason: '첫 판에서 지형을 굳혀야 한다');

    // 여유(12 타일) 안쪽으로만 걷는다.
    game.player.grid.x += 5;
    game.player.grid.y += 4;
    hud.render(_TrackingCanvas());

    expect(
      identical(hud.terrainPicture, first),
      isTrue,
      reason: '여유 안에서 움직였는데 지형을 다시 그렸다 — 굳혀 둔 뜻이 없다',
    );
  });

  test('여유 밖으로 나가면 지형을 다시 굳힌다', () async {
    final (game, hud) = await freshGame();

    hud.render(_TrackingCanvas());
    final first = hud.terrainPicture;

    // 여유(12 타일)를 확실히 넘긴다. 넘고도 다시 그리지 않으면 레이더
    // 가장자리가 비어 버린다.
    game.player.grid.x += 40;
    hud.render(_TrackingCanvas());

    expect(
      identical(hud.terrainPicture, first),
      isFalse,
      reason: '여유 밖으로 나갔는데 옛 그림을 그대로 썼다 — 가장자리가 빈다',
    );
  });

  test('굳혀 둔 지형은 걸어간 만큼 정확히 밀린다', () async {
    final (game, hud) = await freshGame();

    // 첫 판에서 굳힌다. 이때가 기준 자리다.
    final atRef = _TrackingCanvas();
    hud.render(atRef);
    expect(atRef.pictureAt, hasLength(1));
    final (refX, refY) = atRef.pictureAt.single;

    // 여유 안쪽으로 걸어간다.
    const movedX = 5.0;
    const movedY = -3.0;
    game.player.grid.x += movedX;
    game.player.grid.y += movedY;

    final moved = _TrackingCanvas();
    hud.render(moved);
    expect(moved.pictureAt, hasLength(1));
    final (nowX, nowY) = moved.pictureAt.single;

    // 걸어간 만큼 **거꾸로** 밀려야 세상이 제자리에 머문다.
    final scale = Hud.radarScale;
    expect(
      nowX - refX,
      closeTo(-movedX * scale, 0.001),
      reason: '지형이 가로로 어긋나 몹 점과 따로 논다',
    );
    expect(
      nowY - refY,
      closeTo(-movedY * scale, 0.001),
      reason: '지형이 세로로 어긋나 몹 점과 따로 논다',
    );
  });
}
