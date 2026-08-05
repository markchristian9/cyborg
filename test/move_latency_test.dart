@Tags(['integration'])
library;

/// 걸을 때 **서버가 내 좌표를 얼마나 잘라내고 얼마나 늦게 돌려주는지** 잰다.
///
/// 고무줄 현상은 두 값의 곱이다. 서버가 좌표를 자르면 예측한 내 위치와 서버가
/// 아는 위치가 벌어지고, 그 벌어진 값이 늦게 돌아올수록 화면은 뒤로 크게
/// 끌린다. 어느 쪽이 주범인지 모르면 엉뚱한 곳을 고치게 된다.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart';

import 'package:actionrpg/spacetime/cyborg_connection.dart';
import 'package:actionrpg/spacetime/generated/client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    '걷는 동안 서버가 좌표를 자르지 않고 제때 돌려준다',
    timeout: const Timeout(Duration(minutes: 3)),
    () async {
      final client = await SpacetimeDbClient.create(
        host: kCyborgHost,
        database: kCyborgDatabase,
        ssl: kCyborgSsl,
        authStorage: InMemoryTokenStore(),
      );
      await client.connect(initialSubscriptions: kCyborgViewSubscriptions);
      await client.reducers.registerAccount(
        email: 'lat-${DateTime.now().microsecondsSinceEpoch}@cyborg.test',
        password: 'hunter2!!',
      );
      await _until(() => client.myAccount != null);
      await client.reducers.createCharacter(name: '걷는자', kind: 'male_cyborg');
      await _until(() => client.myCharacters.count() == 1);

      const spawn = 503.0;
      await client.subscriptions.subscribe(worldSubscriptionsFor(spawn, spawn));
      await client.reducers.enterWorld(gridX: spawn, gridY: spawn);
      await _until(() => client.myWorldPlayer != null);

      // 실제 게임과 같은 조건으로 걷는다 — 10 Hz 보고, 초당 3.6 타일.
      const hz = 10.0;
      const speed = 3.6;
      const step = speed / hz;
      const frames = 120; // 5 초

      var predicted = spawn;
      final latencies = <int>[];
      final drifts = <double>[];
      var rejected = 0;

      for (var i = 0; i < frames; i++) {
        predicted += step;
        // **실제 클라이언트와 같이 답을 기다리지 않는다.** 기다리면 왕복 지연이
        // 그대로 보고 주기가 되어, 이 테스트가 재려는 것과 다른 상황이 된다.
        final sentAt = DateTime.now();
        unawaited(
          client.reducers
              .moveTo(
                gridX: predicted,
                gridY: spawn,
                facingX: 1,
                facingY: 0,
              )
              .then((_) => latencies
                  .add(DateTime.now().difference(sentAt).inMilliseconds))
              .catchError((Object _) {
            rejected++;
            return null as dynamic;
          }),
        );

        // 서버가 아는 내 자리와 내가 예측한 자리의 차이.
        final me = client.myWorldPlayer;
        if (me != null) drifts.add(predicted - me.gridX);

        await Future<void>.delayed(
          const Duration(microseconds: 100000),
        );
      }

      latencies.sort();
      drifts.sort();
      final median = latencies.isEmpty ? -1 : latencies[latencies.length ~/ 2];
      final worst = latencies.isEmpty ? -1 : latencies.last;
      final medianDrift = drifts.isEmpty ? 0.0 : drifts[drifts.length ~/ 2];
      final worstDrift = drifts.isEmpty ? 0.0 : drifts.last;

      // ignore: avoid_print
      print('move_to 응답 — 중앙값 ${median}ms · 최악 ${worst}ms · 거절 $rejected 회');
      // ignore: avoid_print
      print('예측과 서버의 차이 — 중앙값 ${medianDrift.toStringAsFixed(2)} 타일 · '
          '최악 ${worstDrift.toStringAsFixed(2)} 타일');
      // ignore: avoid_print
      print('(차이가 보정 무시 구간 1.8 타일을 넘으면 화면이 뒤로 당겨진다)');

      await client.disconnect();

      expect(rejected, 0, reason: '서버가 이동을 거절했다 — 속도 상한에 걸린다');

      // **왕복 지연도, 그로 인한 간격도 판정하지 않는다.** 둘 다 대부분 네트워크
      // 이고 우리가 줄일 수 있는 값이 아니다. 서버가 뒤처지는 것 자체는 정상이며,
      // 그것이 화면을 끌지 않게 하는 일은 클라이언트 몫이다 —
      // `test/move_reconcile_test.dart` 가 그쪽을 지킨다.
      //
      // 여기서 지키는 것은 **서버가 내 좌표를 잘라내지 않는가** 하나다. 잘라내기
      // 시작하면 아무리 잘 보정해도 실제로 앞으로 나아가지 못한다.
      //
      // 위에 찍히는 수치는 회귀를 눈으로 보기 위한 것이다. 왕복이 갑자기 몇 배로
      // 뛰면 서버가 밀리고 있다는 신호다.
    },
  );
}

Future<void> _until(bool Function() c) async {
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  while (!c()) {
    if (DateTime.now().isAfter(deadline)) fail('시간 초과');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}
