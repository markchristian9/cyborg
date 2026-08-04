import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 몬스터 어그로 범위의 하한(미터).
const double kAggroMinMeters = 1.0;

/// 몬스터 어그로 범위의 상한(미터).
///
/// 군집으로 모여 있으므로 이 값이 곧 "한 마리를 건드리면 몇 마리가 함께
/// 달려오는가" 를 정한다. 군집 반경(9m)과 같은 자릿수로 맞춰, 무리 가장자리를
/// 건드리면 그 무리 일부가 반응하되 전부가 쏟아지지는 않게 한다.
///
/// 네 계통이 이 구간을 나눠 갖는다 — 보병형이 하한(1~3), 공성형이 가운데(3.5~6),
/// 정찰·지휘형이 상한(7~9)이다. 계통을 보고 "저건 멀리서도 달려든다" 를 예측할
/// 수 있어야 접근 경로를 고르는 판단이 생긴다.
const double kAggroMaxMeters = 9.0;

/// 한 종의 전투 수치.
class MonsterStats {
  const MonsterStats({
    required this.maxHp,
    required this.speed,
    required this.damage,
    required this.attackRange,
    required this.aggroMinMeters,
    required this.aggroMaxMeters,
    required this.telegraphTime,
    required this.strikeTime,
    required this.recoverTime,
    required this.xp,
    required this.bodyRadius,
    required this.hoverHeight,
    required this.ranged,
    this.scale = 1.0,
  });

  final double maxHp;
  final double speed;
  final double damage;
  final double attackRange;

  /// 개체별 어그로 범위를 뽑을 구간의 하한(미터).
  ///
  /// 계통마다 감지 성능이 다르지만, 모든 값은
  /// [kAggroMinMeters]~[kAggroMaxMeters] 안에 들어간다.
  final double aggroMinMeters;

  /// 개체별 어그로 범위를 뽑을 구간의 상한(미터).
  final double aggroMaxMeters;

  final double telegraphTime;
  final double strikeTime;
  final double recoverTime;
  final int xp;
  final double bodyRadius;
  final double hoverHeight;
  final bool ranged;
  final double scale;
}

/// 몬스터의 골격 계통. 실루엣과 전투 성향을 함께 결정한다.
enum MonsterBuild {
  /// 공중에 뜬 소형 기체. 빠르고 약하다.
  drone,

  /// 두 발로 걷는 보병형. 근접 강타를 쓴다.
  walker,

  /// 중장갑 포격형. 느리지만 원거리로 두들긴다.
  siege,

  /// 구역 지휘 유닛. 거대하고 위압적이다.
  sovereign,
}

/// 한 계열(생김새·역할이 같은 20개 묶음)의 정의.
class MonsterFamily {
  const MonsterFamily({
    required this.name,
    required this.codeName,
    required this.build,
    required this.hue,
  });

  /// 한글 이름. 화면에 표시되는 이름의 앞부분이다.
  final String name;

  /// 영문 코드명. 서버 전송·로그용 식별자에 쓴다.
  final String codeName;

  final MonsterBuild build;

  /// 계열 고유의 색조(도 단위).
  ///
  /// 적 진영 대역인 남보라(252°)~마젠타(347°) 안에서만 움직인다.
  /// 아군의 시안(186°)이나 안전지대의 민트(162°)를 침범하면
  /// 밝은 데이터 공간에서 적아 식별이 무너진다.
  final double hue;

  /// 20개 계열 표. 한 등급 안에서 뒤로 갈수록 상위 계열이다.
  ///
  /// 레벨은 `등급 * 20 + 계열 + 1`로 정해진다. 지휘 계열을 10번째와
  /// 20번째에 둔 덕분에 지휘급은 열 레벨마다 하나씩 나타나며,
  /// 어떤 레벨대에서도 그 언저리의 구역 보스를 구할 수 있다.
  static const List<MonsterFamily> all = [
    // ── 비행 계열 ─────────────────────────────────────────────────────
    MonsterFamily(
        name: '정찰기', codeName: 'scout', build: MonsterBuild.drone, hue: 252),
    MonsterFamily(
        name: '말벌', codeName: 'wasp', build: MonsterBuild.drone, hue: 257),
    MonsterFamily(
        name: '감시안',
        codeName: 'watcher',
        build: MonsterBuild.drone,
        hue: 262),
    MonsterFamily(
        name: '추적자',
        codeName: 'stalker',
        build: MonsterBuild.drone,
        hue: 267),
    MonsterFamily(
        name: '섬광기',
        codeName: 'flare',
        build: MonsterBuild.drone,
        hue: 272),

    // ── 보행 계열 ─────────────────────────────────────────────────────
    MonsterFamily(
        name: '순찰병',
        codeName: 'patroller',
        build: MonsterBuild.walker,
        hue: 277),
    MonsterFamily(
        name: '파쇄기',
        codeName: 'shredder',
        build: MonsterBuild.walker,
        hue: 282),
    MonsterFamily(
        name: '도끼병',
        codeName: 'axeman',
        build: MonsterBuild.walker,
        hue: 287),
    MonsterFamily(
        name: '창병',
        codeName: 'lancer',
        build: MonsterBuild.walker,
        hue: 292),

    // ── 구역 보스(10, 30, 50 … 레벨) ──────────────────────────────────
    MonsterFamily(
        name: '군주',
        codeName: 'overlord',
        build: MonsterBuild.sovereign,
        hue: 297),

    // ── 포격 계열 ─────────────────────────────────────────────────────
    MonsterFamily(
        name: '방벽',
        codeName: 'bulwark',
        build: MonsterBuild.siege,
        hue: 302),
    MonsterFamily(
        name: '포탑',
        codeName: 'turret',
        build: MonsterBuild.siege,
        hue: 307),
    MonsterFamily(
        name: '화염기',
        codeName: 'igniter',
        build: MonsterBuild.siege,
        hue: 312),
    MonsterFamily(
        name: '저격수',
        codeName: 'sniper',
        build: MonsterBuild.siege,
        hue: 317),
    MonsterFamily(
        name: '공성기',
        codeName: 'siege',
        build: MonsterBuild.siege,
        hue: 322),

    // ── 정예 계열 ─────────────────────────────────────────────────────
    MonsterFamily(
        name: '사냥개',
        codeName: 'hound',
        build: MonsterBuild.walker,
        hue: 327),
    MonsterFamily(
        name: '결전병',
        codeName: 'vanguard',
        build: MonsterBuild.walker,
        hue: 332),
    MonsterFamily(
        name: '수확자',
        codeName: 'reaper',
        build: MonsterBuild.siege,
        hue: 337),
    MonsterFamily(
        name: '처형자',
        codeName: 'executioner',
        build: MonsterBuild.siege,
        hue: 342),

    // ── 구역 대군주(20, 40, 60 … 레벨) ────────────────────────────────
    MonsterFamily(
        name: '종말',
        codeName: 'omega',
        build: MonsterBuild.sovereign,
        hue: 347),
  ];
}

/// 한 종이 쓰는 도색. 계열 색조와 등급 광택으로 200종이 서로 구분된다.
class MonsterPalette {
  const MonsterPalette({
    required this.shell,
    required this.shellLight,
    required this.shellDark,
    required this.eye,
    required this.eyeGlow,
    required this.energy,
  });

  final Color shell;
  final Color shellLight;
  final Color shellDark;
  final Color eye;
  final Color eyeGlow;
  final Color energy;
}

/// 몬스터 한 종(種)의 정의. 레벨 1~200에 하나씩 존재한다.
class MonsterSpecies {
  MonsterSpecies({
    required this.level,
    required this.family,
    required this.tier,
    required this.name,
    required this.codeName,
    required this.stats,
    required this.palette,
    required this.eyeCount,
    required this.crestCount,
  });

  /// 이 종의 고유 레벨(1~200). 도감의 색인이기도 하다.
  final int level;

  final MonsterFamily family;

  /// 등급(0~9). 화면에는 MK-I ~ MK-X로 표시된다.
  final int tier;

  /// 화면에 표시되는 한글 이름. 예: `수확자 MK-VII`.
  final String name;

  /// 서버 전송용 영문 식별자. 예: `reaper_mk7`.
  final String codeName;

  final MonsterStats stats;
  final MonsterPalette palette;

  /// 센서 아이의 개수(1~3). 상위 등급일수록 눈이 많다.
  final int eyeCount;

  /// 발밑에 깔리는 등급 문양 고리의 수(0~4). 멀리서도 격을 알아볼 수 있다.
  final int crestCount;

  MonsterBuild get build => family.build;

  /// 구역을 지배하는 지휘급인지 여부.
  bool get isSovereign => build == MonsterBuild.sovereign;

  /// 등급 표기. `MK-I` ~ `MK-X`.
  String get tierLabel => 'MK-${MonsterCodex.numerals[tier]}';

  @override
  String toString() => 'Lv.$level $name';
}

/// 레벨 1부터 200까지의 몬스터 도감.
///
/// 20개 계열 × 10개 등급으로 200종이 빠짐없이 채워지며,
/// `레벨 = 등급 * 20 + 계열 + 1`이라 어떤 레벨에도 정확히 한 종이 대응한다.
class MonsterCodex {
  MonsterCodex._();

  /// 도감이 다루는 최대 몬스터 레벨.
  static const int maxLevel = 200;

  static const List<String> numerals = [
    'I',
    'II',
    'III',
    'IV',
    'V',
    'VI',
    'VII',
    'VIII',
    'IX',
    'X',
  ];

  /// 레벨 오름차순으로 정렬된 200종 전체.
  static final List<MonsterSpecies> all = List.unmodifiable(
    List.generate(maxLevel, (index) => _build(index + 1)),
  );

  /// [level]에 해당하는 종. 범위를 벗어난 값은 양끝으로 잘린다.
  static MonsterSpecies byLevel(int level) =>
      all[level.clamp(1, maxLevel) - 1];

  /// [build] 계통에 속하는 종만 모아 준다.
  static Iterable<MonsterSpecies> ofBuild(MonsterBuild build) =>
      all.where((species) => species.build == build);

  /// [center] 레벨 근처에서 한 종을 무작위로 고른다.
  ///
  /// [spread]는 위아래로 허용할 레벨 폭이다. 지역·웨이브가 요구하는
  /// 난이도 주변에서 종이 매번 달라지도록 하는 것이 목적이다.
  /// [allowSovereign]이 false면 지휘급은 뽑히지 않는다. 지휘급은
  /// 잡졸에 섞여 나오는 것이 아니라 따로 주둔시키는 편이 낫다.
  static MonsterSpecies roll(
    math.Random random,
    int center, {
    int spread = 3,
    bool allowSovereign = false,
  }) {
    final low = math.max(1, center - spread);
    final high = math.min(maxLevel, center + spread);

    for (var attempt = 0; attempt < 8; attempt++) {
      final species = byLevel(low + random.nextInt(high - low + 1));
      if (allowSovereign || !species.isSovereign) return species;
    }
    // 구간이 온통 지휘급인 드문 경우엔 바로 아래 레벨로 물러선다.
    return byLevel(math.max(1, low - 2));
  }

  /// [level]에 가장 가까운 지휘급 종. 구역 보스를 세울 때 쓴다.
  ///
  /// 위아래가 똑같이 가까우면 위쪽을 택한다. 그래야 보스 웨이브가
  /// 거듭될 때 같은 보스가 두 번 내려오지 않는다.
  static MonsterSpecies sovereignNear(int level) {
    MonsterSpecies? best;
    var bestGap = 1 << 30;
    for (final species in all) {
      if (!species.isSovereign) continue;
      final gap = (species.level - level).abs();
      if (gap <= bestGap) {
        bestGap = gap;
        best = species;
      }
    }
    return best!;
  }

  /// 시작 지점에서 [distanceTiles]만큼 떨어진 구역의 위험 등급(1~200).
  ///
  /// 중심부는 갓 각성한 사이보그도 버틸 수준이고, 외곽으로 갈수록
  /// AI 주력군이 주둔한 죽음의 구역이 된다.
  ///
  /// 거리에 정비례시키면 안전지대를 나서자마자 10레벨대와 마주치므로,
  /// 시작 근처가 완만해지도록 [_regionCurve]만큼 눌러 준다.
  static int regionLevel(double distanceTiles, double halfSpanTiles) {
    if (halfSpanTiles <= 0) return 1;
    final depth = (distanceTiles / halfSpanTiles).clamp(0.0, 1.0);
    final eased = math.pow(depth, _regionCurve).toDouble();
    return (1 + eased * (maxLevel - 1)).round().clamp(1, maxLevel);
  }

  /// 구역 등급 곡선의 지수. 1이면 거리에 정비례한다.
  static const double _regionCurve = 1.6;

  // ── 생성 ────────────────────────────────────────────────────────────

  static MonsterSpecies _build(int level) {
    final familyIndex = (level - 1) % MonsterFamily.all.length;
    final tier = (level - 1) ~/ MonsterFamily.all.length;
    final family = MonsterFamily.all[familyIndex];

    // 등급이 오를수록 센서가 늘고 발밑 문양이 겹겹이 깔린다.
    final eyeCount = 1 + tier ~/ 4;
    final crestCount = tier ~/ 2;

    return MonsterSpecies(
      level: level,
      family: family,
      tier: tier,
      name: '${family.name} MK-${numerals[tier]}',
      codeName: '${family.codeName}_mk${tier + 1}',
      stats: _statsFor(level, family, tier),
      palette: _paletteFor(family, tier),
      eyeCount: eyeCount,
      crestCount: crestCount,
    );
  }

  /// 계통별 성향과 레벨 곡선을 합쳐 전투 수치를 만든다.
  ///
  /// 레벨 200까지 뻗어야 하므로 곡선은 지수가 아니라 선형이다.
  /// 지수 곡선이면 후반 체력이 천문학적으로 불어나 손을 댈 수 없다.
  static MonsterStats _statsFor(int level, MonsterFamily family, int tier) {
    final step = level - 1;
    final baseHp = 26 + step * 23.0;
    final baseXp = 10 + step * 9;

    // 공격력은 곡선이 아니라 레벨 그 자체다.
    //
    // "3레벨 몬스터는 3, 10레벨 몬스터는 10을 준다" 는 규격을 수식이 아닌
    // 항등식으로 못 박는다. 계통(drone·walker·siege·sovereign)마다 배율을
    // 두지 않는 이유도 같다 — 배율이 하나라도 끼면 레벨과 피해가 어긋난다.
    // 계통별 개성은 체력·속도·사거리·연발 수가 이미 나눠 갖고 있다.
    final attackDamage = level.toDouble();

    // 등급이 오르면 덩치도 조금씩 커진다.
    final tierScale = 1 + tier * 0.035;

    return switch (family.build) {
      MonsterBuild.drone => MonsterStats(
          maxHp: baseHp * 0.72,
          speed: 2.9 + tier * 0.03,
          damage: attackDamage,
          attackRange: 1.0,
          // 센서 특화 기체. 상한 가까이에서 반응한다.
          aggroMinMeters: 7.0,
          aggroMaxMeters: 9.0,
          telegraphTime: 0.32,
          strikeTime: 0.12,
          recoverTime: 0.5,
          xp: (baseXp * 0.8).round(),
          bodyRadius: 0.28,
          hoverHeight: 0.85,
          ranged: false,
          scale: 0.9 * tierScale,
        ),
      MonsterBuild.walker => MonsterStats(
          maxHp: baseHp * 1.15,
          speed: 2.1 + tier * 0.02,
          damage: attackDamage,
          attackRange: 1.25,
          // 둔한 보병형. 코앞까지 와야 알아챈다. 범위의 하한을 맡는다.
          aggroMinMeters: 1.0,
          aggroMaxMeters: 3.0,
          telegraphTime: 0.5,
          strikeTime: 0.16,
          recoverTime: 0.7,
          xp: baseXp,
          bodyRadius: 0.34,
          hoverHeight: 0,
          ranged: false,
          scale: 1.0 * tierScale,
        ),
      MonsterBuild.siege => MonsterStats(
          maxHp: baseHp * 1.6,
          speed: 1.35 + tier * 0.015,
          damage: attackDamage,
          attackRange: 7.5,
          // 사거리는 길지만 탐지는 중간이다.
          aggroMinMeters: 3.5,
          aggroMaxMeters: 6.0,
          telegraphTime: 0.7,
          strikeTime: 0.45,
          recoverTime: 1.1,
          xp: (baseXp * 1.45).round(),
          bodyRadius: 0.46,
          hoverHeight: 0,
          ranged: true,
          scale: 1.25 * tierScale,
        ),
      MonsterBuild.sovereign => MonsterStats(
          // 보스답게 두껍되, 같은 레벨대의 플레이어가 손도 못 댈 벽은 아니다.
          maxHp: baseHp * 2.8,
          speed: 1.6 + tier * 0.02,
          damage: attackDamage,
          attackRange: 9.0,
          // 지휘 유닛은 상한까지 예민하다.
          aggroMinMeters: 8.0,
          aggroMaxMeters: 9.0,
          telegraphTime: 0.75,
          strikeTime: 0.6,
          recoverTime: 1.0,
          xp: (baseXp * 4.0).round(),
          bodyRadius: 0.72,
          hoverHeight: 0,
          ranged: true,
          scale: 1.75 * tierScale,
        ),
    };
  }

  /// 계열 색조 + 등급 채도로 200종의 도색을 만든다.
  ///
  /// 색조는 계열이 정하고 등급은 채도로만 드러낸다. 등급까지 색조를
  /// 밀면 계열 대역을 넘어 아군 색으로 새어 나간다.
  static MonsterPalette _paletteFor(MonsterFamily family, int tier) {
    final hue = family.hue;
    // 상위 기종일수록 짙게 물든다.
    final saturation = (0.18 + tier * 0.042).clamp(0.0, 0.60);

    // 발광부는 진영 식별색인 마젠타 대역에 묶어 두고 등급만큼만 진해진다.
    final glowHue = _glowHueBase + tier * 2.4;

    return MonsterPalette(
      // 밝은 데이터 공간 위에서 실루엣이 죽지 않도록 외피는 짙게 유지한다.
      shell: HSLColor.fromAHSL(1, hue, saturation, 0.34).toColor(),
      shellLight: HSLColor.fromAHSL(1, hue, saturation, 0.48).toColor(),
      shellDark: HSLColor.fromAHSL(1, hue, saturation, 0.21).toColor(),
      eye: HSLColor.fromAHSL(1, glowHue, 1.0, 0.56).toColor(),
      eyeGlow: HSLColor.fromAHSL(1, glowHue, 1.0, 0.78).toColor(),
      energy: HSLColor.fromAHSL(1, glowHue - 8, 0.95, 0.62).toColor(),
    );
  }

  /// 적 발광의 기준 색조. 팔레트의 `robotEye`(340°)와 같은 대역이다.
  static const double _glowHueBase = 328;
}
