import 'dart:io';
import 'dart:ui' as ui;

import 'package:actionrpg/game/entities/cyborg_design.dart';
import 'package:actionrpg/game/entities/cyborg_renderer.dart';
import 'package:actionrpg/game/level/world_tree.dart';
import 'package:actionrpg/game/palette.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 월드 중앙 나무를 PNG 로 뽑아 눈으로 검수한다.
///
/// [WorldTree]를 **그대로** 그린다 — 테스트가 렌더 수식을 복제하면 본체가
/// 바뀔 때 조용히 어긋나 검수가 거짓말을 하게 된다.
///
/// 나무 옆에 사이보그를 같은 배율로 세워 사람 키에 견준 크기를 함께 본다.
///
/// ```sh
/// CYBORG_SNAPSHOT_DIR=/tmp/shots flutter test test/world_tree_snapshot_test.dart
/// ```
void main() {
  final outputDir = Platform.environment['CYBORG_SNAPSHOT_DIR'];

  testWidgets('월드 나무가 예외 없이 렌더링된다', (tester) async {
    await tester.runAsync(() async {
      final image = await _renderTreeSheet();
      expect(image.width, greaterThan(0));

      if (outputDir != null) {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$outputDir/world_tree.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        // ignore: avoid_print
        print('스냅샷 저장: ${file.path}');
      }
    });
  });

  test('나무는 사이보그보다 확실히 크다', () {
    final tree = WorldTree(grid: Vector2.zero());
    // 사람 키의 두 배는 넘어야 "큰 나무"로 읽힌다.
    expect(tree.treeHeight, greaterThan(CyborgDesign.assault.totalHeight * 2));
  });
}

Future<ui.Image> _renderTreeSheet() async {
  const width = 900.0;
  const height = 430.0;
  const groundY = height * 0.86;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, width, height),
    Paint()..color = GamePalette.floorBase,
  );

  // 아이소메트릭 바닥 마름모. 나무가 땅에 서 있는지 보려면 기준면이 필요하다.
  final ground = Path()
    ..moveTo(width / 2, groundY - 62)
    ..lineTo(width / 2 + 380, groundY)
    ..lineTo(width / 2, groundY + 62)
    ..lineTo(width / 2 - 380, groundY)
    ..close();
  canvas.drawPath(ground, Paint()..color = GamePalette.floorAlt);
  canvas.drawPath(
    ground,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = GamePalette.floorGrid,
  );

  // 같은 나무를 서로 다른 바람 시각으로 세 그루. 흔들림이 통짜가 아닌지 본다.
  for (var i = 0; i < 3; i++) {
    final tree = WorldTree(grid: Vector2.zero())..advance(i * 1.7);
    canvas.save();
    canvas.translate(200.0 + i * 250, groundY);
    tree.render(canvas);
    canvas.restore();
  }

  // 크기 비교용 사이보그.
  canvas.save();
  canvas.translate(330, groundY);
  CyborgRenderer.drawBody(
    canvas,
    design: CyborgDesign.assault,
    yaw: 0.6,
    time: 0.4,
  );
  canvas.restore();

  canvas.save();
  canvas.translate(580, groundY);
  CyborgRenderer.drawBody(
    canvas,
    design: CyborgDesign.infiltrator,
    yaw: -0.5,
    time: 1.1,
  );
  canvas.restore();

  final picture = recorder.endRecording();
  return picture.toImage(width.toInt(), height.toInt());
}
