import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:actionrpg/game/ui/hud.dart';

/// 상단 세 패널이 **서로를 덮지 않는** 것을 고정한다.
///
/// 생존 정보(좌)·월드 배너(중앙)·미니맵(우)이 화면 위쪽 같은 띠를 나눠 쓴다.
/// 배너는 셋 중 마지막에 그려지므로, 겹치는 순간 앞의 것을 조용히 덮는다 —
/// 예외도 로그도 없이 **체력·마력 숫자만 잘린 채로 남는다.**
///
/// 실제로 그랬다. 배너를 `size.x / 2` 에 고정해 두어서, 창이 792 픽셀보다 좁으면
/// 생존 정보 패널(오른쪽 끝 278)과 배너 왼쪽 끝(`size.x / 2 - 118`)이 겹쳤다.
/// 두 클라이언트를 720 픽셀로 띄우자 양쪽 화면에서 `10000 / 1000` 처럼 잘린
/// 숫자가 나왔다.
///
/// 숫자를 눈으로 확인하는 일은 스크린샷이 아니면 못 하지만, **겹쳤는지**는
/// 사각형끼리 물어보면 된다.
void main() {
  Hud hudOfWidth(double width) => Hud()..size = Vector2(width, 620);

  /// 검사할 창 너비. 좁은 쪽은 결함이 실제로 나왔던 크기이고, 넓은 쪽은
  /// 고치면서 무엇도 밀려나지 않았음을 확인하는 쪽이다.
  const widths = <double>[420, 500, 620, 720, 792, 900, 1280, 1920, 2560];

  group('상단 HUD 패널', () {
    for (final width in widths) {
      test('${width.toInt()}px 창에서 배너가 생존 정보를 덮지 않는다', () {
        final hud = hudOfWidth(width);
        expect(
          hud.worldBannerRect.overlaps(hud.vitalsRect),
          isFalse,
          reason: '배너가 나중에 그려져 체력·마력 숫자를 덮는다',
        );
      });

      test('${width.toInt()}px 창에서 배너가 미니맵을 덮지 않는다', () {
        final hud = hudOfWidth(width);
        expect(
          hud.worldBannerRect.overlaps(hud.minimapRect),
          isFalse,
          reason: '배너가 나중에 그려져 레이더를 덮는다',
        );
      });
    }

    test('자리가 넉넉하면 배너는 화면 한복판에 그대로 선다', () {
      // 좁은 화면을 위한 보정이 넓은 화면까지 밀어 놓으면 안 된다 — 중앙
      // 정렬은 이 배너가 원래 지키던 것이다.
      for (final width in [900.0, 1280.0, 1920.0, 2560.0]) {
        final hud = hudOfWidth(width);
        expect(
          hud.worldBannerRect.center.dx,
          closeTo(width / 2, 0.001),
          reason: '$width px 에서 배너가 이유 없이 옆으로 밀렸다',
        );
      }
    });

    test('좁아지면 배너는 빈 구간 안으로 밀려 들어간다', () {
      // 720 픽셀은 결함이 나왔던 크기다. 중앙(360)에 두면 왼쪽 끝이 242 라
      // 생존 정보 패널(오른쪽 끝 278)과 겹친다.
      final hud = hudOfWidth(720);
      expect(hud.worldBannerRect.center.dx, greaterThan(360));
      expect(
        hud.worldBannerRect.left,
        greaterThanOrEqualTo(hud.vitalsRect.right),
      );
    });
  });
}
