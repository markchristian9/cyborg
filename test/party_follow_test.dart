import 'package:actionrpg/game/systems/party_follow.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

/// 따라갈 상대를 좌표와 생사만으로 만든다.
///
/// 원격 플레이어 객체도 서버 타입도 쓰지 않는다 — 판단 규칙은 그 둘 중 무엇도
/// 알 필요가 없고, 알게 만들면 이 검사를 돌리는 데 게임 전체가 필요해진다.
FollowTarget _leader(double x, double y, {bool alive = true, int id = 7}) =>
    FollowTarget(
      characterId: id,
      grid: Vector2(x, y),
      alive: alive,
    );

PartyFollowDecision _step(
  PartyFollowController follow, {
  required Vector2 self,
  FollowTarget? leader,
  bool following = true,
  double dt = 1 / 60,
}) {
  return follow.update(
    dt,
    following: following,
    leader: leader,
    selfGrid: self,
  );
}

void main() {
  group('추종 — 따라가지 않을 때', () {
    test('추종이 꺼져 있으면 아무 판단도 하지 않는다', () {
      final follow = PartyFollowController();
      final decision = _step(
        follow,
        following: false,
        leader: _leader(100, 100),
        self: Vector2(0, 0),
      );

      expect(decision.action, PartyFollowAction.none);
      expect(decision.destination, isNull);
    });
  });

  group('추종 — 상대를 잃었을 때', () {
    test('잠깐 목록에서 사라진 것은 끊지 않는다', () {
      final follow = PartyFollowController();
      final decision = _step(follow, leader: null, self: Vector2(10, 10));

      // 주변만 받아 오는 구독은 상대가 경계를 넘을 때 잠깐 빈다. 그 한 프레임을
      // "떠났다" 로 읽으면 이끌기가 경계마다 끊긴다.
      expect(decision.action, PartyFollowAction.hold);
    });

    test('유예가 지나도 안 보이면 끊는다', () {
      final follow = PartyFollowController();

      PartyFollowAction? last;
      final steps = (PartyFollowController.missingGrace / (1 / 60)).ceil() + 5;
      for (var i = 0; i < steps; i++) {
        last = _step(follow, leader: null, self: Vector2(10, 10)).action;
        if (last == PartyFollowAction.lost) break;
      }

      expect(last, PartyFollowAction.lost);
    });

    test('사라졌다 다시 보이면 아무 일도 없던 것처럼 잇는다', () {
      final follow = PartyFollowController();

      // 유예의 절반쯤 비어 있다가
      final half = (PartyFollowController.missingGrace / 2 / (1 / 60)).ceil();
      for (var i = 0; i < half; i++) {
        _step(follow, leader: null, self: Vector2(0, 0));
      }

      // 다시 나타난다.
      final decision = _step(follow, leader: _leader(3, 0), self: Vector2(0, 0));
      expect(decision.action, PartyFollowAction.anchor);

      // 그리고 유예는 처음부터 다시 센다.
      for (var i = 0; i < half; i++) {
        final d = _step(follow, leader: null, self: Vector2(0, 0));
        expect(d.action, PartyFollowAction.hold);
      }
    });

    test('손쓸 수 없이 멀면 따라붙기를 시도하지도 않는다', () {
      final follow = PartyFollowController();
      // 안전지대에서 되살아났는데 상대가 월드 반대편에 있는 상황.
      final far = PartyFollowController.giveUpDistanceTiles + 10;
      final decision = _step(
        follow,
        leader: _leader(far, 0),
        self: Vector2(0, 0),
      );

      expect(decision.action, PartyFollowAction.lost);
    });
  });

  group('추종 — 상대가 쓰러졌을 때', () {
    test('사냥 중심을 옮기지 않고 하던 것을 잇는다', () {
      final follow = PartyFollowController();
      final decision = _step(
        follow,
        leader: _leader(5, 5, alive: false),
        self: Vector2(0, 0),
      );

      // 끊지 않는다 — 상대가 곧 안전지대에서 되살아나면 그리로 모이게 된다.
      expect(decision.action, PartyFollowAction.hold);
      expect(decision.destination, isNull);
    });

    test('쓰러진 상대가 멀리 있어도 추종을 끊지 않는다', () {
      final follow = PartyFollowController();
      final decision = _step(
        follow,
        leader: _leader(PartyFollowController.rejoinDistanceTiles + 20, 0,
            alive: false),
        self: Vector2(0, 0),
      );

      expect(decision.action, PartyFollowAction.hold);
    });
  });

  group('추종 — 따라붙기', () {
    test('멀어지면 사냥보다 따라붙기가 먼저다', () {
      final follow = PartyFollowController();
      final decision = _step(
        follow,
        leader: _leader(PartyFollowController.rejoinDistanceTiles + 5, 0),
        self: Vector2(0, 0),
      );

      expect(decision.action, PartyFollowAction.rejoin);
      expect(decision.destination, isNotNull);
      expect(follow.isRejoining, isTrue);
    });

    test('다가가는 동안에는 포기하지 않는다', () {
      final follow = PartyFollowController();
      var distance = PartyFollowController.rejoinDistanceTiles + 40;

      // 제한 시간을 훌쩍 넘도록 걸어가되, 매번 조금씩 가까워진다.
      final steps = (PartyFollowController.rejoinTimeout / (1 / 60)).ceil() * 2;
      late PartyFollowDecision decision;
      for (var i = 0; i < steps && distance > 20; i++) {
        decision = _step(
          follow,
          leader: _leader(distance, 0),
          self: Vector2(0, 0),
        );
        expect(decision.action, PartyFollowAction.rejoin,
            reason: '다가가는 중에는 끊기면 안 된다');
        distance -= 0.6;
      }
    });

    test('진전이 없으면 제한 시간 뒤 포기한다', () {
      final follow = PartyFollowController();
      // 벽 뒤라 거리가 줄지 않는 상황.
      final stuck = _leader(PartyFollowController.rejoinDistanceTiles + 5, 0);

      PartyFollowAction? last;
      final steps = (PartyFollowController.rejoinTimeout / (1 / 60)).ceil() + 10;
      for (var i = 0; i < steps; i++) {
        last = _step(follow, leader: stuck, self: Vector2(0, 0)).action;
        if (last == PartyFollowAction.lost) break;
      }

      expect(last, PartyFollowAction.lost);
    });

    test('따라붙는 기준과 그만두는 기준이 달라 경계에서 떨리지 않는다', () {
      final follow = PartyFollowController();

      // 기준을 갓 넘어 따라붙기 시작한다.
      var decision = _step(
        follow,
        leader: _leader(PartyFollowController.rejoinDistanceTiles + 1, 0),
        self: Vector2(0, 0),
      );
      expect(decision.action, PartyFollowAction.rejoin);

      // 기준 바로 안쪽으로 들어와도 아직 따라붙는 중이다.
      decision = _step(
        follow,
        leader: _leader(PartyFollowController.rejoinDistanceTiles - 1, 0),
        self: Vector2(0, 0),
      );
      expect(decision.action, PartyFollowAction.rejoin,
          reason: '한 기준만 쓰면 여기서 사냥과 복귀가 매 프레임 뒤바뀐다');

      // 충분히 붙으면 사냥을 다시 연다.
      decision = _step(
        follow,
        leader: _leader(PartyFollowController.resumeDistanceTiles - 1, 0),
        self: Vector2(0, 0),
      );
      expect(decision.action, PartyFollowAction.anchor);
      expect(follow.isRejoining, isFalse);
    });
  });

  group('추종 — 따라붙은 뒤', () {
    test('사냥 중심을 상대 위치로 준다', () {
      final follow = PartyFollowController();
      final decision = _step(
        follow,
        leader: _leader(3, 4),
        self: Vector2(0, 0),
      );

      expect(decision.action, PartyFollowAction.anchor);
      expect(decision.destination, Vector2(3, 4));
    });

    test('돌려준 좌표를 고쳐도 상대의 위치가 바뀌지 않는다', () {
      final follow = PartyFollowController();
      final leader = _leader(3, 4);
      final decision = _step(follow, leader: leader, self: Vector2(0, 0));

      decision.destination!.setValues(999, 999);

      expect(leader.grid, Vector2(3, 4), reason: '사본을 줘야 원본이 안전하다');
    });
  });

  group('추종 — 따라갈 사람이 바뀌었을 때', () {
    test('파티장이 자리를 넘기면 진전을 처음부터 다시 잰다', () {
      final follow = PartyFollowController();
      final stuck = _leader(PartyFollowController.rejoinDistanceTiles + 5, 0);

      // 옛 파티장에게 다가가지 못한 채 제한 시간 직전까지 버틴다.
      final steps = (PartyFollowController.rejoinTimeout / (1 / 60)).ceil() - 5;
      for (var i = 0; i < steps; i++) {
        _step(follow, leader: stuck, self: Vector2(0, 0));
      }

      // 자리가 넘어갔다. 새 파티장이 더 멀더라도 곧바로 포기하면 안 된다.
      final handedOver = _leader(
        PartyFollowController.rejoinDistanceTiles + 30,
        0,
        id: 99,
      );
      final decision =
          _step(follow, leader: handedOver, self: Vector2(0, 0));

      expect(decision.action, PartyFollowAction.rejoin,
          reason: '옛 사람에게 다가가던 기록을 그대로 쓰면 새 사람은 시작하자마자 놓친 것이 된다');
    });

    test('바뀐 뒤에도 제 시간을 다 쓰고 나서야 포기한다', () {
      final follow = PartyFollowController();
      final first = _leader(PartyFollowController.rejoinDistanceTiles + 5, 0);

      for (var i = 0; i < 200; i++) {
        _step(follow, leader: first, self: Vector2(0, 0));
      }

      final second = _leader(
        PartyFollowController.rejoinDistanceTiles + 5,
        0,
        id: 99,
      );

      // 바뀐 직후 몇 프레임은 반드시 살아 있어야 한다.
      for (var i = 0; i < 30; i++) {
        final decision = _step(follow, leader: second, self: Vector2(0, 0));
        expect(decision.action, PartyFollowAction.rejoin);
      }
    });
  });

  group('추종 — 쓰러졌다 되살아난 뒤', () {
    test('되살아난 자리까지의 거리를 진전으로 오해하지 않는다', () {
      final follow = PartyFollowController();

      // 가까이 붙어 사냥하다가 파티장이 쓰러진다.
      _step(follow, leader: _leader(3, 0), self: Vector2(0, 0));
      _step(follow, leader: _leader(3, 0, alive: false), self: Vector2(0, 0));

      // 안전지대에서 되살아나 멀어졌다. 따라붙기가 시작되고, 다가가는 동안
      // 끊기지 않아야 한다.
      var distance = PartyFollowController.rejoinDistanceTiles + 30;
      for (var i = 0; i < 60; i++) {
        final decision = _step(
          follow,
          leader: _leader(distance, 0),
          self: Vector2(0, 0),
        );
        expect(decision.action, PartyFollowAction.rejoin);
        distance -= 0.6;
      }
    });
  });

  group('추종 — 내가 쓰러졌다 되살아난 뒤', () {
    test('안전지대로 튕겨 나가도 곧바로 놓치지 않는다', () {
      final follow = PartyFollowController();
      final leader = _leader(3, 0);

      // 리더 옆에 붙어 사냥하던 중이라 진전 기준이 아주 작다.
      _step(follow, leader: leader, self: Vector2(0, 0));

      // 쓰러져 안전지대로 되살아났다 — 거리가 통째로 달라진다.
      follow.noteSelfMoved();

      // 다가가는 동안 끊기지 않아야 한다.
      var distance = PartyFollowController.rejoinDistanceTiles + 40;
      for (var i = 0; i < 60; i++) {
        final decision = _step(
          follow,
          leader: _leader(distance, 0),
          self: Vector2(0, 0),
        );
        expect(decision.action, PartyFollowAction.rejoin,
            reason: '되살아난 자리까지의 거리를 진전 없음으로 읽으면 안 된다');
        distance -= 0.6;
      }
    });

    test('알리지 않으면 제한 시간 뒤 놓친다 — 이 알림이 필요한 이유', () {
      final follow = PartyFollowController();

      // 따라붙는 중이라 진전 기준이 실제 거리로 좁혀져 있다. (붙어 있는 동안에는
      // 이 기준이 매 프레임 무한대로 풀리므로, 결함은 이 구간에서만 드러난다.)
      var distance = PartyFollowController.rejoinDistanceTiles + 20;
      for (var i = 0; i < 20; i++) {
        _step(follow, leader: _leader(distance, 0), self: Vector2(0, 0));
        distance -= 1.0;
      }
      expect(follow.isRejoining, isTrue);

      // 여기서 쓰러져 안전지대로 되살아났다 — 훨씬 멀어졌는데 알리지 않는다.
      var far = PartyFollowController.giveUpDistanceTiles - 10;
      PartyFollowAction? last;
      final steps = (PartyFollowController.rejoinTimeout / (1 / 60)).ceil() + 10;
      for (var i = 0; i < steps; i++) {
        last = _step(follow, leader: _leader(far, 0), self: Vector2(0, 0)).action;
        if (last == PartyFollowAction.lost) break;
        far -= 0.05; // 걸어가지만 옛 기준에 닿기엔 턱없이 느리다
      }

      expect(last, PartyFollowAction.lost,
          reason: '옛 기준이 남아 있으면 다가가는 중에도 놓친 것이 된다');
    });

    test('따라갈 상대는 그대로 둔다', () {
      final follow = PartyFollowController();
      _step(follow, leader: _leader(3, 0), self: Vector2(0, 0));
      follow.noteSelfMoved();

      // reset 과 달리 대상 기억을 지우지 않으므로, 같은 상대에 대해 '바뀌었다'
      // 로 오인하지 않는다.
      final decision = _step(follow, leader: _leader(4, 0), self: Vector2(0, 0));
      expect(decision.action, PartyFollowAction.anchor);
    });
  });

  group('추종 — 상태 초기화', () {
    test('추종을 끄면 다가가던 기록이 남지 않는다', () {
      final follow = PartyFollowController();
      final far = _leader(PartyFollowController.rejoinDistanceTiles + 5, 0);

      // 벽에 막힌 채 시간을 절반쯤 흘려보낸다.
      for (var i = 0; i < 120; i++) {
        _step(follow, leader: far, self: Vector2(0, 0));
      }
      expect(follow.isRejoining, isTrue);

      // 껐다 켜면 처음부터 다시 센다.
      _step(follow, following: false, leader: far, self: Vector2(0, 0));
      expect(follow.isRejoining, isFalse);

      final decision = _step(follow, leader: far, self: Vector2(0, 0));
      expect(decision.action, PartyFollowAction.rejoin,
          reason: '기록이 남아 있으면 켜자마자 포기한다');
    });
  });
}
