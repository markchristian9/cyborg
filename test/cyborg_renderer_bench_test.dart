// 사이보그 한 몸을 그리는 데 드는 시간을 잰다.
//
// 이 게임은 MMORPG 라 화면에 최대 [_maxRemotePlayers](50) 명이 함께 선다.
// 한 몸의 비용이 60fps 예산(16.6ms)을 인원수로 나눈 값을 넘으면, 사람이 몰리는
// 곳에서 프레임이 무너진다. 그 경계를 눈으로 보기 위한 벤치다.
import 'dart:ui' as ui;

import 'package:actionrpg/game/entities/cyborg_design.dart';
import 'package:actionrpg/game/entities/cyborg_renderer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('사이보그 한 몸을 그리는 비용', () {
    const bodies = 50; // 화면 정원
    const frames = 60; // 1 초

    // 워밍업 — 첫 호출의 지연을 측정에서 뺀다.
    for (var i = 0; i < 200; i++) {
      _drawOnce(i * 0.01);
    }

    final sw = Stopwatch()..start();
    for (var f = 0; f < frames; f++) {
      for (var b = 0; b < bodies; b++) {
        _drawOnce(f * 0.016 + b);
      }
    }
    sw.stop();

    final perFrameMs = sw.elapsedMicroseconds / frames / 1000;
    final perBodyUs = sw.elapsedMicroseconds / (frames * bodies);
    // ignore: avoid_print
    print('몸 하나 $perBodyUs us · 50 명 한 프레임 $perFrameMs ms '
        '(60fps 예산 16.6ms)');
  });
}

void _drawOnce(double time) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  CyborgRenderer.drawBody(
    canvas,
    design: CyborgDesign.assault,
    yaw: time,
    swing: 0.4,
    armSwing: 12,
    time: time,
  );
  recorder.endRecording().dispose();
}
