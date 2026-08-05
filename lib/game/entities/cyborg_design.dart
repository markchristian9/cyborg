import 'package:flutter/material.dart';

import '../palette.dart';

/// 인간 저항군 사이보그의 신체 프레임 종류.
///
/// AI에 점령된 세계에서 살아남은 인간은 각자 다른 규격의 군용 프레임을
/// 이식받았다. 프레임은 성별에 따른 골격 차이를 그대로 반영해 제작되므로
/// 실루엣만으로 두 캐릭터를 구분할 수 있다.
enum CyborgFrame {
  /// 남성형 — 강습 프레임. 정면 화력과 방어를 담당한다.
  assault,

  /// 여성형 — 침투 프레임. 기동과 은신에 특화되어 있다.
  infiltrator,
}

/// 사이보그 한 명의 외형을 결정하는 모든 수치와 색상.
///
/// 렌더러는 이 값만 보고 그리므로, 새 캐릭터를 추가할 때는
/// 렌더링 코드를 건드리지 않고 프로필만 정의하면 된다.
///
/// 모든 치수의 단위는 화면 픽셀이며, 원점은 캐릭터의 발밑이다.
/// y축은 위로 갈수록 음수다.
@immutable
class CyborgDesign {
  const CyborgDesign({
    required this.frame,
    required this.codename,
    required this.tagline,
    required this.totalHeight,
    required this.shoulderWidth,
    required this.chestWidth,
    required this.waistWidth,
    required this.hipWidth,
    required this.legThickness,
    required this.armThickness,
    required this.neckLength,
    this.ankleRatio = 0.075,
    this.kneeRatio = 0.215,
    this.hipRatio = 0.385,
    this.waistRatio = 0.500,
    this.chestRatio = 0.625,
    this.shoulderRatio = 0.700,
    required this.headWidth,
    required this.headHeight,
    required this.shoulderPadSize,
    required this.torsoTaper,
    required this.accent,
    required this.accentSoft,
    required this.armorBase,
    required this.armorLight,
    required this.visorColor,
    required this.implants,
    required this.hairStyle,
    required this.strideScale,
    required this.bobScale,
  });

  /// 프레임 종류.
  final CyborgFrame frame;

  /// 캐릭터 코드명. UI에 표시된다.
  final String codename;

  /// 한 줄 소개.
  final String tagline;

  // ── 골격 치수 ───────────────────────────────────────────────────────

  /// 발끝부터 정수리까지의 총 높이.
  final double totalHeight;

  /// 어깨 패드를 포함한 최대 어깨 폭(중심에서 한쪽 끝까지의 2배).
  final double shoulderWidth;

  /// 흉곽 폭.
  final double chestWidth;

  /// 허리 폭. [chestWidth]보다 작을수록 잘록한 실루엣이 된다.
  final double waistWidth;

  /// 골반 폭.
  final double hipWidth;

  /// 다리 한 짝의 두께.
  final double legThickness;

  /// 팔 한 짝의 두께.
  final double armThickness;

  /// 목 길이. 총 키에 대한 비율로 목 구간을 늘린다.
  ///
  /// 침투 프레임은 목이 길어 머리가 조금 더 높이 얹힌다 — 같은 키라도
  /// 목이 길면 어깨가 상대적으로 내려가 실루엣이 가늘어 보인다.
  final double neckLength;

  // ── 세로 골격 리듬 ──────────────────────────────────────────────────
  //
  // 예전에는 두 프레임이 같은 높이 비율을 공유해, 남녀 차이가 가로 폭과
  // 머리 모양에만 갇혀 있었다. 세로 리듬이 같으면 폭만 다른 같은 인형이다.

  /// 발목 높이(총 키 대비).
  final double ankleRatio;

  /// 무릎 높이. 높을수록 종아리가 짧고 허벅지가 길어 보인다.
  final double kneeRatio;

  /// 골반(다리가 갈라지는 지점) 높이.
  final double hipRatio;

  /// 허리(가장 잘록한 지점) 높이.
  final double waistRatio;

  /// 가슴 높이.
  final double chestRatio;

  /// 어깨선 높이. 몸통의 위 끝이다.
  final double shoulderRatio;

  /// 머리 아래(턱 밑) 높이. [neckLength]가 이 값을 밀어 올린다.
  double get headBottomRatio => shoulderRatio + neckLength / totalHeight;

  /// 헬멧 폭.
  final double headWidth;

  /// 헬멧 높이.
  final double headHeight;

  /// 어깨 패드의 크기. 0이면 패드가 없다.
  final double shoulderPadSize;

  /// 몸통이 아래로 갈수록 좁아지는 정도(0 = 직사각형, 1 = 강한 역삼각형).
  final double torsoTaper;

  // ── 색상 ────────────────────────────────────────────────────────────

  /// 발광 임플란트와 에너지 라인의 주 색상.
  final Color accent;

  /// 잔광·글로우에 쓰는 보조 색상.
  final Color accentSoft;

  /// 장갑의 기본 색.
  final Color armorBase;

  /// 장갑의 밝은 면.
  final Color armorLight;

  /// 바이저 발광색.
  final Color visorColor;

  // ── 특징 ────────────────────────────────────────────────────────────

  /// 이 프레임이 장착한 사이버네틱 임플란트.
  final Set<CyborgImplant> implants;

  /// 헬멧 뒤로 드러나는 헤어/케이블 형태.
  final CyborgHair hairStyle;

  /// 달릴 때 보폭의 배율. 클수록 성큼성큼 걷는다.
  final double strideScale;

  /// 달릴 때 상하 반동의 배율.
  final double bobScale;

  /// 어깨에서 허리로 이어지는 실루엣이 오목한지(여성형) 볼록한지(남성형).
  bool get hasConcaveWaist => waistWidth < chestWidth * 0.86;

  /// 특정 임플란트를 장착했는지 여부.
  bool has(CyborgImplant implant) => implants.contains(implant);

  /// 남성형 — 강습 프레임.
  ///
  /// 넓은 어깨와 두꺼운 사지로 볼록한(convex) 실루엣을 만든다.
  /// 승모근과 흉곽을 덮는 각진 장갑판이 특징이며, 흉골 프레임과
  /// 어깨 구동기가 겉으로 드러난다.
  static const CyborgDesign assault = CyborgDesign(
    frame: CyborgFrame.assault,
    codename: 'VULCAN',
    tagline: '전선을 여는 강습 프레임',
    totalHeight: 108,
    shoulderWidth: 34,
    chestWidth: 23,
    waistWidth: 20,
    hipWidth: 19,
    legThickness: 9,
    armThickness: 7.5,
    // 짧고 굵은 목. 어깨가 목을 먹어 들어가 육중해 보인다.
    neckLength: 5.5,
    // 강습 프레임의 세로 리듬: 골반이 낮고 몸통이 길다. 무게중심이 아래로
    // 내려가 버티고 선 인상을 준다.
    ankleRatio: 0.080,
    kneeRatio: 0.225,
    hipRatio: 0.370,
    waistRatio: 0.480,
    chestRatio: 0.620,
    shoulderRatio: 0.705,
    headWidth: 21,
    headHeight: 19,
    shoulderPadSize: 11.5,
    torsoTaper: 0.18,
    accent: GamePalette.playerAccent,
    accentSoft: GamePalette.playerVisor,
    armorBase: GamePalette.playerArmor,
    armorLight: GamePalette.playerArmorLight,
    visorColor: GamePalette.playerVisor,
    implants: {
      CyborgImplant.sternalFrame,
      CyborgImplant.shoulderActuator,
      CyborgImplant.spinalPowerPack,
      CyborgImplant.corticalModule,
    },
    hairStyle: CyborgHair.napeCable,
    strideScale: 1.0,
    bobScale: 1.0,
  );

  /// 여성형 — 침투 프레임.
  ///
  /// 좁은 어깨와 잘록한 허리로 오목한(concave) 실루엣을 만든다.
  /// 장갑을 최소화한 대신 척추를 따라 흐르는 발광 라인과
  /// 복부 생명유지 흡입구가 노출되어 있다.
  static const CyborgDesign infiltrator = CyborgDesign(
    frame: CyborgFrame.infiltrator,
    codename: 'WRAITH',
    tagline: '전선을 넘는 침투 프레임',
    totalHeight: 102,
    shoulderWidth: 25,
    chestWidth: 18,
    waistWidth: 13.5,
    // 골반이 가슴보다 넓어야 실제로 모래시계가 된다. 같으면 "잘록한 원통"에
    // 그쳐 축소했을 때 남성형과 구분되지 않는다.
    hipWidth: 21,
    legThickness: 7,
    armThickness: 5.5,
    // 길고 가는 목. 머리가 높이 얹혀 실루엣이 가늘어 보인다.
    neckLength: 9.5,
    // 침투 프레임의 세로 리듬: 골반이 높고 다리가 길다. 무게중심이 위로
    // 올라가 가볍고 날렵한 인상을 준다 — 폭만 줄인 것과는 다른 차이다.
    ankleRatio: 0.070,
    kneeRatio: 0.235,
    hipRatio: 0.415,
    waistRatio: 0.520,
    chestRatio: 0.640,
    shoulderRatio: 0.715,
    headWidth: 18.5,
    headHeight: 18,
    shoulderPadSize: 6.5,
    torsoTaper: -0.32,
    // 색은 남성형과 동일하게 진영색(청록)을 따른다. 두 프레임은 색이 아니라
    // 실루엣·임플란트·헤어의 형태로 구분되므로, 팔레트가 바뀌어도
    // 아군 식별색이 흐트러지지 않는다.
    accent: GamePalette.playerAccent,
    accentSoft: GamePalette.playerVisor,
    armorBase: GamePalette.playerArmor,
    armorLight: GamePalette.playerArmorLight,
    visorColor: GamePalette.playerVisor,
    implants: {
      CyborgImplant.spinalLightRail,
      CyborgImplant.vitalIntake,
      CyborgImplant.corticalModule,
      CyborgImplant.legTendon,
    },
    hairStyle: CyborgHair.ponytail,
    strideScale: 1.18,
    bobScale: 0.82,
  );

  /// 선택 가능한 모든 프레임.
  static const List<CyborgDesign> all = [assault, infiltrator];

  /// [frame]에 해당하는 프로필을 반환한다.
  static CyborgDesign of(CyborgFrame frame) => switch (frame) {
        CyborgFrame.assault => assault,
        CyborgFrame.infiltrator => infiltrator,
      };
}

/// 사이보그가 이식받은 사이버네틱 부품.
///
/// 원작 설정상 인간이 AI 로봇과 맞서기 위해 이식한 군용 장기다.
enum CyborgImplant {
  /// 흉골 프레임 — 가슴 중앙을 가로지르는 노출 골격.
  sternalFrame,

  /// 어깨 구동기 — 어깨 관절에 드러난 유압 실린더.
  shoulderActuator,

  /// 척추 동력팩 — 등에 업은 대형 배터리.
  spinalPowerPack,

  /// 척추 발광 레일 — 등을 따라 흐르는 얇은 발광 라인.
  spinalLightRail,

  /// 생명유지 흡입구 — 복부에 뚫린 냉각/호흡 포트.
  vitalIntake,

  /// 대뇌피질 모듈 — 관자놀이에 박힌 연산 유닛.
  corticalModule,

  /// 다리 건 강화 — 종아리에 노출된 인공 힘줄.
  legTendon,
}

/// 헬멧 뒤로 보이는 형태.
enum CyborgHair {
  /// 뒤통수에서 목으로 이어지는 접속 케이블.
  napeCable,

  /// 하나로 묶어 뒤로 흘린 머리채.
  ponytail,
}
