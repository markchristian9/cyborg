import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:actionrpg/game/entities/cyborg_design.dart';
import 'package:actionrpg/game/entities/player.dart';

/// **뒤처진 서버 좌표가 화면을 뒤로 끌지 않는지** 확인한다.
///
/// 서버 좌표는 언제나 내 과거다. 보낸 값이 처리되어 구독으로 돌아오기까지 한
/// 왕복이 걸리고(실측 300~500 ms), 그동안 나는 계속 걷는다. 그래서 지금 위치와
/// 견주면 늘 한두 타일 벌어져 있는데, 그것은 어긋남이 아니라 지연이다.
///
/// 그 간격을 오차로 보고 당기면 걸을수록 뒤로 끌린다 — 사용자가 "고무줄" 이라
/// 부른 증상이다. 그래서 지금 위치가 아니라 **지나온 자취**와 견뎌야 한다.
void main() {
  /// [seconds] 동안 오른쪽으로 걸으며 보고한다. 서버는 [lagSeconds] 만큼
  /// 뒤처져 그 자취를 따라온다.
  Player walkWithLaggingServer({
    required double seconds,
    required double lagSeconds,
    double speed = 3.6,
    double reportHz = 10,
  }) {
    final player = Player(grid: Vector2(100, 100), design: CyborgDesign.assault);
    final reported = <Vector2>[];

    final frames = (seconds * reportHz).round();
    final lagFrames = (lagSeconds * reportHz).round();
    final step = speed / reportHz;
    final dt = 1 / reportHz;

    for (var i = 0; i < frames; i++) {
      // 예측: 내 화면은 계속 나아간다.
      player.grid.x += step;
      player.recordReportedGrid(player.grid);
      reported.add(player.grid.clone());

      // 서버가 아는 자리는 그만큼 과거다.
      final serverIndex = i - lagFrames;
      if (serverIndex >= 0) {
        player.reconcileServerGrid(reported[serverIndex], dt);
      }
    }
    return player;
  }

  test('서버가 반 초 뒤처져도 화면이 끌려가지 않는다', () {
    const seconds = 3.0;
    const speed = 3.6;
    final player = walkWithLaggingServer(seconds: seconds, lagSeconds: 0.5);

    // 3 초 걸었으면 10.8 타일 나아가 있어야 한다. 뒤로 끌렸다면 그보다 적다.
    final travelled = player.grid.x - 100;
    expect(
      travelled,
      closeTo(seconds * speed, 0.4),
      reason: '서버 지연만큼 뒤로 끌렸다 — 걸을수록 느려지는 고무줄이다',
    );
  });

  test('왕복이 1.5 초로 늘어져도 마찬가지다', () {
    const seconds = 4.0;
    const speed = 3.6;
    final player = walkWithLaggingServer(seconds: seconds, lagSeconds: 1.5);

    expect(
      player.grid.x - 100,
      closeTo(seconds * speed, 0.4),
      reason: '지연이 클수록 더 끌린다면 자취가 아니라 현재 위치와 견주고 있다',
    );
  });

  test('자취에서 벗어난 좌표는 여전히 보정한다', () {
    final player =
        Player(grid: Vector2(100, 100), design: CyborgDesign.assault);

    // 오른쪽으로 걸어온 자취를 남긴다.
    for (var i = 0; i < 10; i++) {
      player.grid.x += 0.36;
      player.recordReportedGrid(player.grid);
    }
    final before = player.grid.x;

    // 서버가 **전혀 다른 곳**을 가리킨다 — 벽에 막혔거나 속도 상한에 잘렸다.
    // 자취 어디에도 없는 자리이므로 당겨져야 한다.
    for (var i = 0; i < 60; i++) {
      player.reconcileServerGrid(Vector2(100, 108), 1 / 60);
    }

    expect(
      player.grid.y,
      greaterThan(100.5),
      reason: '자취를 벗어난 서버 좌표인데 보정하지 않는다 — 벽 통과가 방치된다',
    );
    expect(player.grid.x, lessThan(before));
  });

  /// **한 번 보정한 뒤에도 자취 판정이 계속 살아 있는지** 본다.
  ///
  /// 보정이 자취를 지워 버리면, 바로 다음 프레임에는 견줄 자취가 없어 다시
  /// **지금 위치**와 견주게 된다. 그런데 지금 위치와 서버 사이에는 언제나 왕복
  /// 지연만큼의 간격이 있으므로 그것이 또 어긋남으로 읽히고, 또 지운다 —
  /// 한 번 걸리면 빠져나오지 못하는 덫이다. 고무줄이 그대로 돌아온다.
  ///
  /// 어긋남은 실제로 한 번씩 일어난다(넉백, 몹에게 밀림, 잘린 보고 한 번).
  /// 그때마다 이후의 이동이 통째로 느려지면 안 된다.
  test('한 번 어긋난 뒤에도 걸음이 느려지지 않는다', () {
    const speed = 3.6;
    const reportHz = 10.0;
    const dt = 1 / reportHz;
    const step = speed / reportHz;
    const lagFrames = 5; // 0.5 초

    final player =
        Player(grid: Vector2(100, 100), design: CyborgDesign.assault);
    final reported = <Vector2>[];

    // 1) 1 초 걷는다 — 자취를 쌓는다.
    for (var i = 0; i < 10; i++) {
      player.grid.x += step;
      player.recordReportedGrid(player.grid);
      reported.add(player.grid.clone());
    }

    // 2) 어긋남 한 번. 자취에서 벗어난 좌표가 한 번 들어온다.
    player.reconcileServerGrid(Vector2(player.grid.x, 102), dt);

    // 3) 다시 2 초를 같은 속도로 걷는다. 서버는 정상적으로 자취를 따라온다.
    final resumeAt = player.grid.x;
    for (var i = 0; i < 20; i++) {
      player.grid.x += step;
      player.recordReportedGrid(player.grid);
      reported.add(player.grid.clone());

      final serverIndex = reported.length - 1 - lagFrames;
      if (serverIndex >= 0) {
        player.reconcileServerGrid(reported[serverIndex], dt);
      }
    }

    final travelled = player.grid.x - resumeAt;
    expect(
      travelled,
      closeTo(2.0 * speed, 0.4),
      reason: '어긋남 한 번 뒤로 걸음이 $travelled 타일밖에 안 된다 '
          '(2 초면 ${2.0 * speed} 타일) — 보정이 자취를 지워 고무줄이 되살아났다',
    );
  });

  test('아주 멀리 떨어지면 즉시 옮긴다 — 텔레포트·재가동', () {
    final player =
        Player(grid: Vector2(100, 100), design: CyborgDesign.assault);
    player.recordReportedGrid(player.grid);

    player.reconcileServerGrid(Vector2(503, 503), 1 / 60);

    expect(
      player.grid.x,
      closeTo(503, 0.01),
      reason: '월드를 가로지르는 거리는 걸어서 좁히면 안 된다',
    );
  });
}
