import 'dart:io';
import 'dart:ui' as ui;

import 'package:actionrpg/game/entities/cyborg_design.dart';
import 'package:actionrpg/game/entities/cyborg_renderer.dart';
import 'package:actionrpg/game/palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 사이보그 프레임 렌더링 결과를 PNG로 뽑아 실루엣을 눈으로 확인한다.
///
/// 출력 경로는 환경 변수 `CYBORG_SNAPSHOT_DIR`로 지정하며,
/// 지정하지 않으면 스냅샷을 저장하지 않고 렌더링이 예외 없이
/// 끝나는지만 검증한다.
void main() {
  final outputDir = Platform.environment['CYBORG_SNAPSHOT_DIR'];

  testWidgets('남성형·여성형 프레임이 예외 없이 렌더링된다', (tester) async {
    // Picture.toImage()는 실제 비동기 이벤트 루프를 필요로 하므로
    // 테스트의 FakeAsync 밖(runAsync)에서 실행해야 데드락에 걸리지 않는다.
    await tester.runAsync(() async {
      final image = await _renderComparisonSheet();
      expect(image.width, greaterThan(0));
      expect(image.height, greaterThan(0));

      if (outputDir != null) {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$outputDir/cyborg_frames.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        // ignore: avoid_print
        print('스냅샷 저장: ${file.path}');
      }
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

    // 여성형은 어깨보다 골반 대비 허리가 좁아 모래시계 비율을 갖는다.
    final f = CyborgDesign.infiltrator;
    expect(f.waistWidth, lessThan(f.hipWidth));
  });
}

/// 두 프레임을 정면/뒷면·대기/보행 조합으로 한 장에 그린다.
Future<ui.Image> _renderComparisonSheet() async {
  const cellWidth = 220.0;
  const cellHeight = 300.0;
  const columns = 4;
  const rows = 2;
  const width = cellWidth * columns;
  const height = cellHeight * rows;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
    const Rect.fromLTWH(0, 0, width, height),
  );

  // 배경
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, width, height),
    Paint()..color = GamePalette.voidColor,
  );

  const variants = [
    (label: '정면 · 대기', back: false, swing: 0.0),
    (label: '정면 · 보행', back: false, swing: 0.85),
    (label: '뒷면 · 대기', back: true, swing: 0.0),
    (label: '뒷면 · 보행', back: true, swing: -0.85),
  ];

  for (var row = 0; row < rows; row++) {
    final design = CyborgDesign.all[row];
    for (var col = 0; col < columns; col++) {
      final variant = variants[col];
      final originX = cellWidth * col + cellWidth / 2;
      final originY = cellHeight * row + cellHeight * 0.88;

      // 셀 구분선
      canvas.drawRect(
        Rect.fromLTWH(cellWidth * col, cellHeight * row, cellWidth, cellHeight),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = GamePalette.floorGrid.withValues(alpha: 0.5),
      );

      _label(
        canvas,
        '${design.codename} · ${variant.label}',
        Offset(cellWidth * col + 10, cellHeight * row + 10),
        design.accent,
      );

      canvas.save();
      canvas.translate(originX, originY);
      canvas.scale(1.9);

      // 그림자
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
        swing: variant.swing,
        back: variant.back,
        armSwing: -variant.swing * 6,
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
      style: TextStyle(color: color, fontSize: 11),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, at);
}
