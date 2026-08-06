import 'package:flame/game.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:actionrpg/game/palette.dart';
import 'package:actionrpg/game/ui/touch_controls.dart';

/// 액션 버튼 **한 번 누름은 한 번 발동**이어야 한다.
///
/// [ActionButton] 은 `TapCallbacks` 와 `DragCallbacks` 를 함께 쓴다. 두 가지가
/// 다 필요해서다 — 손가락을 대는 순간 나가야 하고(탭), 조이스틱을 쥔 손이
/// 버튼 위로 미끄러져 들어와도 나가야 한다(드래그).
///
/// 그런데 둘은 같은 손가락 하나에 **함께** 반응한다. 손가락이 슬롭(18px)을
/// 넘어 움직이면 제스처 아레나에서 드래그가 이기고, 그때 흐름은 이렇다.
///
/// ```text
///   onTapDown   → 발동 1
///   onTapCancel → (드래그가 이겨 탭이 취소된다)
///   onDragStart → 발동 2   ← 같은 손가락, 같은 누름인데 두 번째
/// ```
///
/// 손가락을 대고 조금이라도 끌면 한 번 누른 것이 두 번 나간다. 화면에서는
/// 배율 버튼이 두 칸씩 뛰고, 칼은 한 번 눌렀는데 두 번 휘둘러진다.
class _ButtonHarness extends FlameGame {
  _ButtonHarness({required this.onPressed});

  final VoidCallback onPressed;

  late final ActionButton button;

  @override
  Future<void> onLoad() async {
    button = ActionButton(
      icon: ActionIcon.blade,
      color: GamePalette.hudBorder,
      radius: 40,
      onPressed: onPressed,
      position: Vector2(100, 100),
    );
    camera.viewport.add(button);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(_ButtonHarness, List<int>)> mounted(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final presses = <int>[];
    final game = _ButtonHarness(onPressed: () => presses.add(presses.length));
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.pump();
    return (game, presses);
  }

  /// 버튼 한복판. 반경 40 이라 중심에서 조금 움직여도 아직 버튼 안이다.
  const center = Offset(100, 100);

  /// 손을 뗀 뒤 제스처 인식기가 걸어 둔 시계가 끝나기를 기다린다.
  ///
  /// `MultiTapGestureRecognizer` 는 손가락마다 40ms 짜리 시계를 건다(긴 탭
  /// 판정용). 그것이 남은 채로 시험이 끝나면 "위젯 트리를 버렸는데 시계가
  /// 남아 있다" 로 실패한다 — 버튼이 몇 번 나갔는지와는 아무 상관이 없다.
  Future<void> settle(WidgetTester tester) =>
      tester.pump(const Duration(milliseconds: 60));

  testWidgets('가만히 눌렀다 떼면 한 번 나간다', (tester) async {
    final (_, presses) = await mounted(tester);

    final gesture = await tester.startGesture(center);
    await tester.pump();
    await gesture.up();
    await settle(tester);

    expect(presses.length, 1);
  });

  testWidgets('누른 채 손가락이 밀려도 한 번만 나간다', (tester) async {
    final (_, presses) = await mounted(tester);

    // 슬롭(kTouchSlop = 18)을 넘겨 끈다. 이때 드래그가 아레나를 이기고
    // 탭은 취소된다 — 사람에게는 여전히 **한 번 누른 것**이다.
    final gesture = await tester.startGesture(center);
    await tester.pump();
    await gesture.moveBy(const Offset(kTouchSlop + 6, 0));
    await tester.pump();
    await gesture.up();
    await settle(tester);

    expect(
      presses.length,
      1,
      reason: '탭이 취소되고 드래그가 이어받는 동안 같은 누름이 두 번 세어졌다',
    );
  });

  testWidgets('길게 누르고 있으면 이어서 나간다', (tester) async {
    final (_, presses) = await mounted(tester);

    final gesture = await tester.startGesture(center);
    await tester.pump();

    // 연타는 프레임마다 한 번씩만 나가므로 시간을 잘게 흘려보낸다. 0.5 초를
    // 한 번에 밀면 update 한 번에 0.5 초가 실려 연타가 한 번밖에 세어지지 않는다.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    final whileHeld = presses.length;
    await gesture.up();
    await settle(tester);

    expect(whileHeld, greaterThan(1), reason: '길게 누르면 연속 발동해야 한다');
  });

  testWidgets('떼고 나면 더 나가지 않는다', (tester) async {
    final (_, presses) = await mounted(tester);

    final gesture = await tester.startGesture(center);
    await tester.pump();
    await gesture.up();
    await settle(tester);

    final afterRelease = presses.length;
    await tester.pump(const Duration(milliseconds: 600));

    expect(presses.length, afterRelease, reason: '손을 뗐는데 계속 나갔다');
  });
}
