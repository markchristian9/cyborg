// 사이보그 한 몸을 그리는 데 드는 시간을 잰다.
//
// 이 게임은 MMORPG 라 화면에 최대 [_maxRemotePlayers](50) 명이 함께 선다.
// 한 몸의 비용이 60fps 예산(16.6ms)을 인원수로 나눈 값을 넘으면, 사람이 몰리는
// 곳에서 프레임이 무너진다. 그 경계를 눈으로 보기 위한 벤치다.
//
// 🛑 **여기서 찍히는 밀리초를 실제 프레임 시간으로 읽지 말 것.** 세 가지가
// 다르다.
//
//  1. `flutter test` 는 JIT 로 돈다. 출시 빌드는 AOT 라 훨씬 빠르다.
//  2. 재는 것은 **표시 목록을 만드는 비용**(Paint·셰이더·경로 생성)뿐이다.
//     실제 래스터화는 [ui.Picture] 를 그릴 때 GPU 스레드에서 따로 일어나고,
//     `MaskFilter.blur` 처럼 비싼 것은 그쪽에 있다.
//  3. 같은 기계에서도 부하에 따라 두 배까지 흔들린다(실측 327~620us).
//
// 그러므로 이 수는 **절대값이 아니라 변화를 보는 자**다. 렌더러를 손본 앞뒤로
// 같은 조건에서 돌려 비교하는 데 쓴다. 진짜 프레임 시간이 궁금하면 프로파일
// 빌드로 앱을 띄워 DevTools 의 프레임 차트를 봐야 한다.
//
// 그래서 단언하지 않고 숫자만 찍는다. 부하에 흔들리는 값에 문턱을 걸면 CI 가
// 이유 없이 빨개진다.
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
