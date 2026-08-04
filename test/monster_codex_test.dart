import 'dart:math' as math;

import 'package:actionrpg/game/systems/monster_codex.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MonsterCodex', () {
    test('레벨 1부터 200까지 빠짐없이 한 종씩 존재한다', () {
      expect(MonsterCodex.all.length, 200);
      for (var level = 1; level <= 200; level++) {
        expect(MonsterCodex.byLevel(level).level, level);
      }
    });

    test('200종의 이름과 코드명이 모두 고유하다', () {
      final names = MonsterCodex.all.map((s) => s.name).toSet();
      final codes = MonsterCodex.all.map((s) => s.codeName).toSet();
      expect(names.length, 200);
      expect(codes.length, 200);
    });

    test('레벨이 오르면 체력과 경험치가 단조 증가한다', () {
      for (final build in MonsterBuild.values) {
        final line = MonsterCodex.ofBuild(build).toList();
        for (var i = 1; i < line.length; i++) {
          expect(
            line[i].stats.maxHp,
            greaterThan(line[i - 1].stats.maxHp),
            reason: '${line[i]}의 체력이 이전 등급보다 낮다',
          );
          expect(line[i].stats.xp, greaterThan(line[i - 1].stats.xp));
        }
      }
    });

    test('모든 종의 도색이 아군·안전지대 색 대역을 침범하지 않는다', () {
      // 무대가 밝은 데이터 공간이라 색이 곧 진영 표시다.
      // 아군은 시안(186°), 안전지대는 민트(162°)를 쓰므로
      // 적은 남보라~마젠타(240° 이상)에만 머물러야 한다.
      for (final species in MonsterCodex.all) {
        final palette = species.palette;
        for (final color in [
          palette.shell,
          palette.shellLight,
          palette.shellDark,
          palette.eye,
          palette.eyeGlow,
          palette.energy,
        ]) {
          expect(
            HSLColor.fromColor(color).hue,
            greaterThanOrEqualTo(240),
            reason: '$species의 도색이 아군 색 대역으로 새어 나갔다',
          );
        }
      }
    });

    test('외피는 밝은 바닥 위에서 실루엣이 남을 만큼 어둡다', () {
      for (final species in MonsterCodex.all) {
        expect(
          HSLColor.fromColor(species.palette.shellLight).lightness,
          lessThan(0.6),
          reason: '$species가 흰 바닥에 묻힌다',
        );
      }
    });

    test('범위를 벗어난 레벨은 양끝으로 잘린다', () {
      expect(MonsterCodex.byLevel(0).level, 1);
      expect(MonsterCodex.byLevel(-5).level, 1);
      expect(MonsterCodex.byLevel(999).level, 200);
    });

    test('roll은 기본적으로 지휘급을 뽑지 않는다', () {
      final random = math.Random(1234);
      for (var center = 1; center <= 200; center++) {
        for (var i = 0; i < 5; i++) {
          final species = MonsterCodex.roll(random, center, spread: 5);
          expect(species.isSovereign, isFalse);
          expect(species.level, inInclusiveRange(1, 200));
        }
      }
    });

    test('sovereignNear는 어느 레벨에서도 지휘급을 돌려준다', () {
      for (var level = 1; level <= 200; level++) {
        expect(MonsterCodex.sovereignNear(level).isSovereign, isTrue);
      }
    });

    test('구역 보스는 요청 레벨에서 열 단계 넘게 벗어나지 않는다', () {
      // 이 여유가 무너지면 초반 보스 웨이브에 손댈 수 없는 개체가 나온다.
      for (var level = 1; level <= 200; level++) {
        final boss = MonsterCodex.sovereignNear(level);
        expect(
          (boss.level - level).abs(),
          lessThanOrEqualTo(10),
          reason: 'Lv.$level 구역에 $boss가 배정됐다',
        );
      }
    });

    test('지휘급 체력이 같은 레벨 일반 개체의 다섯 배를 넘지 않는다', () {
      for (final boss in MonsterCodex.all.where((s) => s.isSovereign)) {
        final peer = MonsterCodex.byLevel(boss.level - 1);
        expect(
          boss.stats.maxHp,
          lessThan(peer.stats.maxHp * 5),
          reason: '$boss가 이웃한 $peer보다 지나치게 두껍다',
        );
      }
    });

    test('구역 위험 등급은 중심 1에서 외곽 200까지 이어진다', () {
      expect(MonsterCodex.regionLevel(0, 500), 1);
      expect(MonsterCodex.regionLevel(500, 500), 200);
      expect(MonsterCodex.regionLevel(9999, 500), 200);
    });

    test('구역 등급은 거리에 따라 단조 증가한다', () {
      var previous = 0;
      for (var d = 0.0; d <= 500; d += 5) {
        final level = MonsterCodex.regionLevel(d, 500);
        expect(level, greaterThanOrEqualTo(previous));
        previous = level;
      }
    });

    test('안전지대 바로 밖은 갓 시작한 플레이어가 감당할 수준이다', () {
      // 상주 개체가 배치되기 시작하는 26 m 지점.
      expect(MonsterCodex.regionLevel(26, 500), lessThanOrEqualTo(5));
      // 50 m를 나가도 아직 한 자릿수여야 한다.
      expect(MonsterCodex.regionLevel(50, 500), lessThanOrEqualTo(9));
    });
  });
}
