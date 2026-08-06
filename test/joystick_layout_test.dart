import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:actionrpg/game/action_rpg_game.dart';
import 'package:actionrpg/game/net/world_presence.dart';
import 'package:actionrpg/game/ui/touch_controls.dart';

/// 조이스틱의 **테두리와 손잡이가 같은 자리를 가리키는지** 고정한다.
///
/// [JoystickComponent] 는 손잡이의 기준점을 자기가 정하지만
/// (`onMount` 에서 `knob.anchor = Anchor.center`), 배경은 `add` 하기만 하고
/// 손대지 않는다. 그래서 배경은 기본값인 좌상단 기준으로 남아 있어야 조이스틱
/// 상자를 (0,0) 부터 가득 채운다.
///
/// [JoystickBase] 에 `Anchor.center` 를 주면 배경이 상자의 **모서리**를 중심으로
/// 그려져 반경만큼(62픽셀) 왼쪽 위로 밀린다 — 손잡이는 제자리인데 테두리만
/// 어긋난, 실제로 화면에 나왔던 모습이다. 생성자의 `assert` 는 `position` 이
/// 0 인지만 보므로 이것을 잡지 않고 예외도 나지 않는다.
///
/// **위젯으로 띄워서 본다.** 조이스틱은 `onMount` 에서 자리를 잡으므로 붙이지
/// 않고는 검사할 값이 서지 않는다.
class _JoystickHarness extends FlameGame {
  _JoystickHarness({required this.radius, required this.knobRadius});

  final double radius;
  final double knobRadius;

  late final JoystickComponent joystick;

  @override
  Future<void> onLoad() async {
    joystick = JoystickComponent(
      knob: JoystickKnob(radius: knobRadius),
      background: JoystickBase(radius: radius),
      margin: const EdgeInsets.only(left: 40, bottom: 40),
    );
    camera.viewport.add(joystick);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 게임을 실제로 띄우고 조이스틱이 자리를 잡을 때까지 기다린다.
  Future<_JoystickHarness> mounted(WidgetTester tester, Size surface) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final game = _JoystickHarness(radius: 62, knobRadius: 26);
    await tester.pumpWidget(GameWidget(game: game));
    await tester.pump();
    await tester.pump();
    return game;
  }

  /// 화면 크기 몇 가지. 조이스틱은 왼쪽·아래 여백을 기준으로 놓이므로 크기가
  /// 달라지면 자리가 통째로 움직인다.
  const surfaces = <Size>[
    Size(720, 592),
    Size(500, 900),
    Size(1280, 800),
    Size(1920, 1080),
  ];

  for (final surface in surfaces) {
    testWidgets(
      '${surface.width.toInt()}x${surface.height.toInt()} 에서 '
      '테두리와 손잡이가 같은 중심에 선다',
      (tester) async {
        final game = await mounted(tester, surface);

        final base =
            game.joystick.children.whereType<JoystickBase>().single;
        final knob =
            game.joystick.children.whereType<JoystickKnob>().single;

        // 손잡이는 손대지 않았으므로 원점에 쉬고 있다. 그 자리가 곧 조이스틱의
        // 중심이고, 테두리도 같은 곳을 중심으로 삼아야 한다.
        final drift = (base.absoluteCenter - knob.absoluteCenter).length;
        expect(
          drift,
          lessThan(0.001),
          reason: '테두리가 손잡이에서 ${drift.toStringAsFixed(1)}픽셀 어긋났다',
        );
      },
    );
  }

  testWidgets('테두리가 조이스틱 상자를 그대로 채운다', (tester) async {
    // 중심이 같아도 크기나 기준점이 어긋나면 원이 상자 밖으로 나간다.
    final game = await mounted(tester, const Size(720, 592));
    final base = game.joystick.children.whereType<JoystickBase>().single;

    expect(base.anchor, Anchor.topLeft, reason: '배경의 기준점은 조이스틱이 정하지 않는다');
    expect(base.position, Vector2.zero());
    expect(base.size, game.joystick.size);
  });

  // 배율 버튼은 조이스틱 원 밖에 서야 한다. 겹치면 걷는 동안 손이 지나가는
  // 자리를 가릴 뿐 아니라, 그 위에 덮인 조이스틱 탭 차폐막 때문에 **눌러도
  // 반응하지 않는다.** 한때 좌표를 손으로 적어 두어 원 안에 파묻혀 있었다.
  for (final surface in surfaces) {
    // 🛑 `testWidgets` 가 아니라 평범한 `test` 다. `testWidgets` 의 가짜 시계
    // 안에서는 `onLoad` 가 기다리는 플랫폼 채널이 영영 답하지 않아 멎는다.
    test(
      '${surface.width.toInt()}x${surface.height.toInt()} 에서 '
      '배율 버튼이 조이스틱을 덮지 않는다',
      () async {
        // autoStart 로 만든다. 메인 메뉴 오버레이는 테스트 위젯 트리에 등록되어
        // 있지 않아, 띄우려 하면 그 자리에서 죽는다.
        //
        // 위젯으로 띄우지 않는 이유는 조이스틱 검사와 다르다 — 여기서 보는
        // 것은 `_layoutTouchControls` 가 정한 버튼 자리이고, 그것은 `onLoad`
        // 에서 이미 선다. 게임 전체를 위젯 트리에 올리면 `onLoad` 가 플랫폼
        // 채널을 기다리다 테스트 안에서 영영 끝나지 않는다.
        final game = ActionRpgGame(
          presence: const OfflineWorldPresence(),
          autoStart: true,
        );
        game.onGameResize(Vector2(surface.width, surface.height));
        await game.onLoad();

        final zooms = game.camera.viewport.children
            .whereType<ActionButton>()
            .where((b) => b.id == 'zoomIn' || b.id == 'zoomOut')
            .toList();
        expect(zooms.length, 2, reason: '배율 버튼을 찾지 못했다');

        for (final button in zooms) {
          // 조이스틱 자리는 게임이 쥔 값을 그대로 쓴다. 여기서 다시 계산하면
          // 둘이 함께 틀렸을 때 이 시험이 통과해 버린다.
          final gap = (button.position - game.joystickCenter).length;
          expect(
            gap,
            greaterThan(game.joystickRadius + button.radius),
            reason: '${button.id} 가 조이스틱 원과 겹친다 '
                '(중심 거리 ${gap.toStringAsFixed(1)}, '
                '합친 반경 ${game.joystickRadius + button.radius})',
          );
        }
      },
    );
  }
}
