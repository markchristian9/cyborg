import 'package:actionrpg/spacetime/cyborg_connection.dart';
import 'package:flutter_test/flutter_test.dart';

/// 관심 영역(AOI) 구독이 만드는 SQL 을 지킨다.
///
/// 이 구독은 **서버 스키마와 글자 단위로 맞아야 한다.** 컬럼 이름이 하나만
/// 어긋나도 구독은 조용히 빈 결과를 내고, 화면에는 "아무도 없는 월드" 가 된다.
/// 오류가 나지 않고 그냥 비어 보이기 때문에 눈으로는 원인을 찾기 어렵다.
void main() {
  group('구독 청크 격자', () {
    test('플레이어 청크는 최대 축소 화면이 덮는 반경을 보장한다', () {
      // **인원이 아니라 화면에서 역산한다.** 예전에는 "동접 1,000 명이 고르게
      // 퍼졌을 때 3×3 에 50 명"(C ≈ 74.5)에서 뽑았지만, 인원 상한은 이미
      // `ActionRpgGame._maxRemotePlayers` 가 거리순으로 만들고 있다. 화면 밖
      // 사람의 좌표는 받아도 그릴 곳이 없으므로 면적은 화면에 맞추는 것이 옳다.
      //
      // 3×3 구독에서 **어디에 서 있든 반드시 들어오는 반경은 청크 한 변**이다.
      // 그보다 화면이 넓으면 청크 경계에 선 사람이 화면 안쪽의 요원을 놓치고,
      // 그것은 "월드에서 나갔다" 와 구별되지 않아 조용히 사라진다.
      //
      // 최대 축소(줌 = clamp(h/760, .55, 1.6) × .5)에서 화면이 덮는 반경은
      // 1080p 에서 21~34 타일이다. 32 는 그 위쪽에 맞춘 값이며, 몹 격자가
      // 같은 근거로 이미 쓰고 있는 값이기도 하다.
      const maxZoomOutScreenRadiusTiles = 32;
      expect(
        kPlayerSubChunkTiles,
        greaterThanOrEqualTo(maxZoomOutScreenRadiusTiles),
        reason: '보장 반경이 화면보다 좁다 — 화면 안의 요원이 조용히 사라진다',
      );
    });

    test('몬스터 청크는 서버 CHUNK_TILES 와 같다', () {
      // 몹은 밀도가 자리마다 열 배 넘게 달라 면적으로 마릿수를 자를 수 없다.
      // 그래서 인원이 아니라 기존 격자를 그대로 쓴다.
      expect(kMonsterSubChunkTiles, 32);
    });

    test('한 줄 청크 수는 월드 크기에서 나온다', () {
      // 서버 WORLD_TILES = 1006.
      expect(kPlayerSubChunksPerRow, (1006 ~/ kPlayerSubChunkTiles) + 1);
      expect(kMonsterSubChunksPerRow, (1006 ~/ kMonsterSubChunkTiles) + 1);
    });
  });

  group('worldSubscriptionsFor', () {
    test('세 표를 모두 건다 — 하나라도 빠지면 그것만 안 보인다', () {
      final queries = worldSubscriptionsFor(500, 500);
      expect(queries.length, 3);
      expect(queries.any((q) => q.contains('FROM world_player')), isTrue);
      expect(queries.any((q) => q.contains('FROM monster')), isTrue);
      expect(queries.any((q) => q.contains('FROM loot')), isTrue);
    });

    test('구독 컬럼은 서버가 갱신하는 것과 같아야 한다', () {
      final queries = worldSubscriptionsFor(500, 500);
      final player = queries.firstWhere((q) => q.contains('world_player'));
      final monster = queries.firstWhere((q) => q.contains('monster'));
      final loot = queries.firstWhere((q) => q.contains('loot'));

      expect(player, contains('sub_chunk ='));
      // **집 청크(chunk)가 아니라 현재 위치(pos_chunk)여야 한다.** 집으로 고르면
      // 확실히 잡히는 것이 반경 6 타일 안의 몹뿐이라 화면 구석이 빈다.
      expect(monster, contains('pos_chunk ='));
      expect(monster, isNot(contains('WHERE chunk =')));
      expect(loot, contains('chunk ='));
    });

    test('월드 한복판에서는 3×3 = 아홉 칸을 건다', () {
      final queries = worldSubscriptionsFor(500, 500);
      for (final query in queries) {
        expect(' OR '.allMatches(query).length, 8, reason: query);
      }
    });

    test('월드 모서리에서는 바깥 칸을 버려 네 칸만 남는다', () {
      // 없는 청크를 구독해도 오류는 아니지만, 조건이 늘수록 서버가 헛일을 한다.
      final queries = worldSubscriptionsFor(0, 0);
      for (final query in queries) {
        expect(' OR '.allMatches(query).length, 3, reason: query);
      }
    });

    test('산술식을 쓰지 않는다 — 구독 SQL 이 지원하지 않는다', () {
      for (final query in worldSubscriptionsFor(500, 500)) {
        expect(query, isNot(contains('+')));
        expect(query, isNot(contains('BETWEEN')));
        expect(query, isNot(contains('LIMIT')));
        expect(query, isNot(contains('ORDER BY')));
      }
    });

    test('같은 청크 안에서는 어디에 서 있든 같은 구독이 나온다', () {
      // 이것이 성립해야 재구독이 청크 단위로만 일어난다. 좌표마다 달라지면
      // 한 발짝 걸을 때마다 다시 구독하게 된다.
      final a = worldSubscriptionsFor(300, 300);
      final b = worldSubscriptionsFor(
        300 + kPlayerSubChunkTiles / 2,
        300,
      );
      final sameChunk =
          (300 ~/ kPlayerSubChunkTiles) ==
          ((300 + kPlayerSubChunkTiles / 2) ~/ kPlayerSubChunkTiles);
      if (sameChunk) {
        expect(a.first, b.first);
      }
    });

    test('이웃한 두 청크의 구독은 여섯 칸을 공유한다', () {
      // 겹치는 칸이 있어야 "새 구독 먼저, 옛 구독 나중" 전환에서 화면이 비지 않는다.
      final tile = kPlayerSubChunkTiles.toDouble();
      final here = _chunkKeys(worldSubscriptionsFor(tile * 5, tile * 5).first);
      final next = _chunkKeys(worldSubscriptionsFor(tile * 6, tile * 5).first);
      expect(here.intersection(next).length, 6);
    });
  });
}

/// `... WHERE sub_chunk = 1 OR sub_chunk = 2` 에서 번호만 뽑는다.
Set<int> _chunkKeys(String query) => RegExp(r'= (\d+)')
    .allMatches(query)
    .map((m) => int.parse(m.group(1)!))
    .toSet();
