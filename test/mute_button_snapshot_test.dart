import 'dart:io';
import 'dart:ui' as ui;

import 'package:actionrpg/game/palette.dart';
import 'package:actionrpg/game/ui/mute_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 음소거 버튼의 두 상태를 PNG 로 뽑아 눈으로 검수한다.
///
/// [MuteButton.paint] 를 **그대로** 부른다 — 테스트가 아이콘 수식을 복제하면
/// 본체가 바뀔 때 조용히 어긋나 검수가 거짓말을 하게 된다.
///
/// ```sh
/// CYBORG_SNAPSHOT_DIR=/tmp/shots flutter test test/mute_button_snapshot_test.dart
/// ```
void main() {
  final outputDir = Platform.environment['CYBORG_SNAPSHOT_DIR'];

  testWidgets('음소거 버튼이 켜짐·꺼짐 모두 예외 없이 렌더링된다', (tester) async {
    await tester.runAsync(() async {
      final image = await _renderButtonSheet();
      expect(image.width, greaterThan(0));

      if (outputDir != null) {
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('$outputDir/mute_button.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        // ignore: avoid_print
        print('스냅샷 저장: ${file.path}');
      }
    });
  });
}

Future<ui.Image> _renderButtonSheet() async {
  const side = MuteButton.buttonSize;
  const scale = 3.0;
  const gap = 24.0;
  const width = side * 2 * scale + gap * 3;
  const height = side * scale + gap * 2;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, width, height));
  // 밝은 월드 위에 얹히는 버튼이라 배경도 그 톤으로 깐다.
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, width, height),
    Paint()..color = GamePalette.floorBase,
  );

  // 왼쪽이 소리 켜짐, 오른쪽이 음소거. 눌림 정도도 나눠 담아 축소 연출까지 본다.
  for (final (index, muted) in const [(0, false), (1, true)]) {
    canvas.save();
    canvas.translate(gap + index * (side * scale + gap), gap);
    canvas.scale(scale);
    MuteButton.paint(canvas, side: side, muted: muted, press: index * 1.0);
    canvas.restore();
  }

  final picture = recorder.endRecording();
  return picture.toImage(width.toInt(), height.toInt());
}
