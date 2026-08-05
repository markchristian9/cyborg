import 'package:flutter/material.dart';

/// 게임 전체에서 사용하는 색상 팔레트.
///
/// 세계관: AI 로봇이 점령한 것은 물리 도시가 아니라 세계를 굴리는 전산망 그 자체다.
/// 플레이어는 그 안으로 잠입한 사이보그이며, 무대는 눈부시게 밝은 데이터 공간이다.
///
/// 톤: 흰빛에 가까운 데이터 플레이트 위에 청록(아군)과 마젠타(적)의 발광이 흐른다.
/// 어두운 폐허가 아니라 "빛으로 가득 찬 사이버 스페이스"가 기준이다.
class GamePalette {
  GamePalette._();

  // ── 공간(하늘/보이드) ────────────────────────────────────────────────
  /// 데이터 공간의 상단. 거의 흰색에 가까운 하늘빛.
  static const Color skyHigh = Color(0xFFF4FBFF);

  /// 데이터 공간의 하단. 옅은 청록으로 지평선을 만든다.
  static const Color skyLow = Color(0xFFCFEDF8);

  /// 지평선에서 번지는 발광.
  static const Color horizonGlow = Color(0xFF7FE9FF);

  /// 격자 바깥의 비어 있는 영역(데이터 공백).
  static const Color voidColor = Color(0xFFDCEFF8);

  /// 공백 위를 떠다니는 데이터 입자.
  static const Color dataMote = Color(0xFF35D8F5);

  // ── 지형 ────────────────────────────────────────────────────────────
  /// 기본 데이터 플레이트.
  static const Color floorBase = Color(0xFFF7FCFF);

  /// 체커 대비를 만드는 보조 플레이트.
  static const Color floorAlt = Color(0xFFE9F6FD);

  /// 플레이트 사이의 격자선.
  static const Color floorGrid = Color(0xFF9FDCEF);

  /// 방화벽 구역 바닥.
  static const Color floorHazard = Color(0xFFFFE1EC);

  /// 방화벽의 맥동 발광.
  static const Color floorHazardGlow = Color(0xFFFF2E77);

  /// 에너지 도관이 흐르는 바닥.
  static const Color floorCircuit = Color(0xFFDDF8FE);

  /// 도관 회로의 발광.
  static const Color floorCircuitGlow = Color(0xFF00C8E6);

  /// 고속 데이터 스트림 바닥(연산 대역).
  static const Color floorStream = Color(0xFFE6ECFF);

  /// 데이터 스트림의 발광.
  static const Color floorStreamGlow = Color(0xFF6E7BFF);

  // ── 구조물 ──────────────────────────────────────────────────────────
  /// 데이터 타워 상단면(빛을 정면으로 받는 면).
  static const Color wallTop = Color(0xFFFFFFFF);

  /// 데이터 타워 좌측면(그늘).
  static const Color wallLeft = Color(0xFFBFE2F2);

  /// 데이터 타워 우측면.
  static const Color wallRight = Color(0xFFD9F0FA);

  /// 타워 모서리의 발광 윤곽선.
  static const Color wallEdge = Color(0xFF35D8F5);

  /// 데이터 캐시(파괴 가능) 상단면.
  static const Color crateTop = Color(0xFFFFE9A8);

  /// 데이터 캐시 좌측면.
  static const Color crateLeft = Color(0xFFE0B658);

  /// 데이터 캐시 우측면.
  static const Color crateRight = Color(0xFFF2D083);

  // ── 플레이어(인간 사이보그) ─────────────────────────────────────────
  // 밝은 배경 위에서 실루엣이 죽지 않도록 본체는 짙게 유지한다.
  static const Color playerArmor = Color(0xFF17364F);
  static const Color playerArmorLight = Color(0xFF2C6A93);
  static const Color playerAccent = Color(0xFF00E5FF);
  static const Color playerVisor = Color(0xFFB9FBFF);
  static const Color playerSkin = Color(0xFFCB9E7E);
  static const Color bladeCore = Color(0xFFFFFFFF);
  static const Color bladeGlow = Color(0xFF00E5FF);

  // ── 적(AI 로봇) ─────────────────────────────────────────────────────
  // 밝은 공간에서 즉시 식별되도록 마젠타 계열의 발광을 쓴다.
  static const Color robotShell = Color(0xFF4B5573);
  static const Color robotShellLight = Color(0xFF7C89AD);
  static const Color robotShellDark = Color(0xFF2B3248);
  static const Color robotEye = Color(0xFFFF1F6B);
  static const Color robotEyeGlow = Color(0xFFFF8FB4);
  static const Color robotEnergy = Color(0xFFFF4D9E);

  // ── 안전지대 ────────────────────────────────────────────────────────
  // 적의 마젠타와 정반대편에 놓이도록 민트-그린 계열로 통일한다.
  /// 안전지대 바닥에 덧입히는 옅은 보호막.
  static const Color safeZoneFill = Color(0xFF7BFFD1);

  /// 안전지대 경계의 발광.
  static const Color safeZoneGlow = Color(0xFF00E2A0);

  /// 안전지대 경계선과 모서리 기둥의 진한 톤.
  static const Color safeZoneEdge = Color(0xFF00A876);

  // ── 이펙트 ──────────────────────────────────────────────────────────
  /// 밝은 공간의 그림자는 검정이 아니라 푸른 기가 도는 반투명이다.
  static const Color shadow = Color(0x552A5C7A);
  static const Color hitSpark = Color(0xFFFFC46B);
  static const Color healGlow = Color(0xFF00D98A);
  static const Color xpGlow = Color(0xFF8A5CFF);

  // ── UI ──────────────────────────────────────────────────────────────
  /// 밝은 월드 위에 얹는 반투명 글래스 패널.
  static const Color hudBackground = Color(0xE6F2FAFE);

  /// 패널 안쪽에 파인 홈(게이지 트랙 등).
  static const Color hudInset = Color(0xFFD3E9F4);
  static const Color hudBorder = Color(0xFF00B8D9);
  static const Color hpFill = Color(0xFF16C98D);
  static const Color hpFillLow = Color(0xFFFF2E77);
  static const Color energyFill = Color(0xFF2E86FF);

  /// 마력 게이지. 스킬 자원이라 스태미나(EN)와 뚜렷이 구분되는 청록을 쓴다.
  static const Color mpFill = Color(0xFF00D8E8);
  static const Color xpFill = Color(0xFF8A5CFF);
  /// 같은 월드의 다른 요원. 내 몸의 청록과 확실히 갈리는 호박색이다.
  ///
  /// 적(마젠타)·아군 자신(청록)·안전지대(민트) 어디와도 겹치지 않아야
  /// 미니맵에서 한눈에 구별된다.
  static const Color remotePlayer = Color(0xFFFFA53D);

  static const Color textPrimary = Color(0xFF0C2A3D);
  static const Color textDim = Color(0xFF5C86A0);
}
