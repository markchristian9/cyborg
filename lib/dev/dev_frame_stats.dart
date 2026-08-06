/// 실제로 프레임이 몇 밀리초에 그려지는지 **돌아가는 앱에서** 잰다.
///
/// 시험(`flutter test`)으로 잰 수는 프레임 시간이 아니다 — JIT 로 돌고, 표시
/// 목록을 만드는 비용만 재며(래스터는 빠진다), 기계 부하에 두 배씩 흔들린다.
/// 렌더러를 손볼지 말지를 그런 수로 정하면 있지도 않은 문제를 고치게 된다.
///
/// 그래서 엔진이 직접 재는 값을 받는다. [FrameTiming] 은 프레임마다 두 구간을
/// 나누어 준다.
///
///  - **build**  — UI 스레드. 위젯·게임 루프·`render` 가 표시 목록을 짓는 시간.
///                 사이보그 한 몸의 `Paint`·셰이더 비용이 여기에 쌓인다.
///  - **raster** — GPU 스레드. 그 표시 목록을 실제로 칠하는 시간. `MaskFilter`
///                 같은 것이 여기에 온다.
///
/// 60fps 예산은 **각각** 16.6ms 다. 둘은 파이프라인으로 겹쳐 도므로 더하지
/// 않는다 — 둘 중 하나만 넘겨도 프레임이 밀린다.
///
/// ```sh
/// CYBORG_FRAME_STATS=5 ./scripts/run.sh --prefix perf --count 8 --profile
/// ```
///
/// 위처럼 주면 5 초마다 한 줄씩 로그에 남는다. 값이 없으면 아무것도 하지 않는다.
library;

import 'package:flutter/scheduler.dart';

import 'dev_env.dart';
import 'dev_login.dart';

/// 몇 초마다 한 줄씩 남길지. 값이 없거나 0 이하면 끈다.
final double kFrameStatsSeconds = () {
  final raw = devEnvironment['CYBORG_FRAME_STATS']?.trim();
  if (raw == null || raw.isEmpty) return 0.0;
  return double.tryParse(raw) ?? 0.0;
}();

bool get frameStatsEnabled => kFrameStatsSeconds > 0;

/// 프레임 시간 수집을 시작한다. 꺼져 있으면 아무 일도 하지 않는다.
void startFrameStats() {
  if (!frameStatsEnabled) return;
  final window = Duration(milliseconds: (kFrameStatsSeconds * 1000).round());
  final collector = _FrameStats(window);
  SchedulerBinding.instance.addTimingsCallback(collector.onTimings);
  devLog('프레임 통계를 $kFrameStatsSeconds 초마다 남긴다');
}

class _FrameStats {
  _FrameStats(this.window);

  final Duration window;

  final List<int> _buildUs = [];
  final List<int> _rasterUs = [];
  DateTime _since = DateTime.now();

  void onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _buildUs.add(t.buildDuration.inMicroseconds);
      _rasterUs.add(t.rasterDuration.inMicroseconds);
    }

    final now = DateTime.now();
    if (now.difference(_since) < window) return;
    _since = now;
    if (_buildUs.isEmpty) return;

    // 평균만 보면 가끔 크게 튀는 프레임이 묻힌다. 사람이 "끊긴다" 고 느끼는
    // 것은 평균이 아니라 그 튐이므로 95 분위와 최댓값을 함께 남긴다.
    final build = _summary(_buildUs);
    final raster = _summary(_rasterUs);
    final janky = _buildUs.indexed
        .where((e) => e.$2 > 16600 || _rasterUs[e.$1] > 16600)
        .length;

    devLog(
      '프레임 ${_buildUs.length}개 · '
      'build $build · raster $raster · '
      '16.6ms 넘긴 프레임 $janky개',
    );
    _buildUs.clear();
    _rasterUs.clear();
  }

  String _summary(List<int> samples) {
    final sorted = [...samples]..sort();
    final avg = samples.reduce((a, b) => a + b) / samples.length / 1000;
    final p95 = sorted[(sorted.length * 0.95).floor().clamp(0, sorted.length - 1)] / 1000;
    final max = sorted.last / 1000;
    return '평균 ${avg.toStringAsFixed(1)} / p95 ${p95.toStringAsFixed(1)} / '
        '최대 ${max.toStringAsFixed(1)}ms';
  }
}
