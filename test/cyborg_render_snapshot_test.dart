import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:actionrpg/game/entities/cyborg_design.dart';
import 'package:actionrpg/game/entities/cyborg_renderer.dart';
import 'package:actionrpg/game/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 사이보그 프레임 렌더링을 PNG 로 뽑아 눈으로 검수한다.
///
/// 렌더러는 방향을 양자화하지 않으므로 "N 방향 스프라이트"가 존재하지 않는다.
/// 여기서 뽑는 각도는 **표본**이며, 회전이 이어지는지 보려면 표본을 촘촘히
/// 해야 한다. 그래서 8방향이 아니라 16방향을 기본으로 뽑는다.
///
/// 축소 내성도 함께 본다. 게임 최소 배율은 0.55(`ActionRpgGame._zoomForSize`)라
/// 키 108px 캐릭터가 화면에서 약 59px 가 된다 — 이 크기에서 살아남지 못하는
/// 디테일은 플레이 중에는 없는 것이다.
///
/// ```sh
/// CYBORG_SNAPSHOT_DIR=/tmp/shots flutter test test/cyborg_render_snapshot_test.dart
/// ```
/// 환경변수가 없으면 파일을 남기지 않고 렌더링이 예외 없이 끝나는지만 본다.
void main() {
  final outputDir = Platform.environment['CYBORG_SNAPSHOT_DIR'];

  testWidgets('16방향 회전이 예외 없이 렌더링된다', (tester) async {
    // Picture.toImage()는 실제 비동기 이벤트 루프를 필요로 하므로
    // 테스트의 FakeAsync 밖(runAsync)에서 실행해야 데드락에 걸리지 않는다.
    await tester.runAsync(() async {
      final sheet = await _renderRotationSheet(steps: 16, scale: 1.9);
      expect(sheet.width, greaterThan(0));
      await _save(sheet, outputDir, 'cyborg_rotation.png');

      // 기본 상태의 하한 배율. 캐릭터 108px 가 약 59px 이 된다.
      final tiny = await _renderRotationSheet(steps: 16, scale: 0.55);
      await _save(tiny, outputDir, 'cyborg_rotation_min_zoom.png');

      // 사용자가 축소를 끝까지 눌렀을 때의 실효 배율.
      // `_zoomForSize()` 가 `clamp(0.55, 1.6) * _zoomScale` 이고 `_zoomScale`
      // 하한이 0.5 라, 실제로는 0.275 까지 내려간다 — 캐릭터가 약 30px 이다.
      // 이 시트에서 사라지는 디테일은 그 상태에서는 없는 것과 같다.
      final micro = await _renderRotationSheet(steps: 16, scale: 0.275);
      await _save(micro, outputDir, 'cyborg_rotation_micro_zoom.png');

      // 보행 위상까지 섞어 다리·팔이 각도별로 어떻게 움직이는지 본다.
      final walk = await _renderRotationSheet(
        steps: 8,
        scale: 1.9,
        walking: true,
      );
      await _save(walk, outputDir, 'cyborg_walk.png');
    });
  });

  test('실루엣 프로필이 설계 의도대로 구분된다', () {
    // 여성형은 가슴보다 허리가 뚜렷하게 좁아 오목한 실루엣이 된다.
    expect(CyborgDesign.infiltrator.hasConcaveWaist, isTrue);
    // 남성형은 허리가 가슴과 비슷해 볼록한 실루엣을 유지한다.
    expect(CyborgDesign.assault.hasConcaveWaist, isFalse);

    // 어깨 폭은 남성형이 확실히 넓다.
    expect(
      CyborgDesign.assault.shoulderWidth,
      greaterThan(CyborgDesign.infiltrator.shoulderWidth),
    );

    // 여성형은 골반이 허리보다 넓어야 모래시계가 된다.
    final f = CyborgDesign.infiltrator;
    expect(f.waistWidth, lessThan(f.hipWidth));
  });
}

Future<void> _save(ui.Image image, String? dir, String name) async {
  if (dir == null) return;
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('$dir/$name');
  await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('스냅샷 저장: ${file.path}');
}

/// 한 바퀴를 [steps]개로 끊어 두 프레임을 나란히 그린다.
Future<ui.Image> _renderRotationSheet({
  required int steps,
  required double scale,
  bool walking = false,
}) async {
  // 배율에 맞춰 칸 크기를 정한다. 축소 시트는 칸도 작아야 실제 크기가 보인다.
  final cellWidth = (110 * scale).clamp(60.0, 190.0);
  final cellHeight = (150 * scale).clamp(90.0, 300.0);
  final width = cellWidth * steps;
  final height = cellHeight * CyborgDesign.all.length;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

  canvas.drawRect(
    Rect.fromLTWH(0, 0, width, height),
    Paint()..color = GamePalette.voidColor,
  );

  for (var row = 0; row < CyborgDesign.all.length; row++) {
    final design = CyborgDesign.all[row];
    for (var col = 0; col < steps; col++) {
      final yaw = col * 2 * math.pi / steps;
      // 보행 위상을 각도마다 어긋나게 줘서 한 시트에서 여러 순간을 본다.
      final swing = walking ? math.sin(col * 1.7) : 0.0;
      final originX = cellWidth * col + cellWidth / 2;
      final originY = cellHeight * row + cellHeight * 0.88;

      canvas.drawRect(
        Rect.fromLTWH(cellWidth * col, cellHeight * row, cellWidth, cellHeight),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = GamePalette.floorGrid.withValues(alpha: 0.5),
      );

      // 배율이 작으면 라벨이 칸을 잡아먹으므로 큰 시트에만 적는다.
      if (scale >= 1.0) {
        _label(
          canvas,
          '${(col * 360 / steps).round()}°',
          Offset(cellWidth * col + 6, cellHeight * row + 6),
          design.accent,
        );
      }

      canvas.save();
      canvas.translate(originX, originY);
      canvas.scale(scale);

      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: design.hipWidth * 2.4,
          height: design.hipWidth * 1.1,
        ),
        Paint()..color = GamePalette.shadow.withValues(alpha: 0.4),
      );

      CyborgRenderer.drawBody(
        canvas,
        design: design,
        yaw: yaw,
        swing: swing,
        armSwing: -swing * 6,
        // 맥동 위상을 고정해 두 시트를 비교할 수 있게 한다.
        time: 0.4,
      );
      canvas.restore();
    }
  }

  final picture = recorder.endRecording();
  return picture.toImage(width.toInt(), height.toInt());
}

void _label(Canvas canvas, String text, Offset at, Color color) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: 10),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, at);
}
