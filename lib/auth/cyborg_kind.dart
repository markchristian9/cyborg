import 'package:flutter/material.dart';

import '../game/palette.dart';

/// 고를 수 있는 사이보그 외형.
///
/// `id` 는 서버가 아는 값과 **글자 그대로** 같아야 한다
/// (`spacetimedb/src/character.rs` 의 `CHARACTER_KINDS`). 서버가 화이트리스트로
/// 판정하므로 여기서 오타가 나면 캐릭터 생성이 거절된다.
enum CyborgKind {
  male(
    id: 'male_cyborg',
    label: '남성 사이보그',
    codename: 'VANGUARD',
    tagline: '중장갑 전위. 맞고 버티며 앞으로 밀고 들어간다.',
    accent: GamePalette.playerAccent,
    visor: GamePalette.playerVisor,
  ),
  female(
    id: 'female_cyborg',
    label: '여성 사이보그',
    codename: 'WRAITH',
    tagline: '경장갑 침투. 짧게 치고 빠지며 전선을 흔든다.',
    // 청록(아군 기본)과도, 로봇의 적색과도 구별되는 보라 계열을 쓴다.
    accent: Color(0xFFB388FF),
    visor: Color(0xFFE3D4FF),
  );

  const CyborgKind({
    required this.id,
    required this.label,
    required this.codename,
    required this.tagline,
    required this.accent,
    required this.visor,
  });

  /// 서버에 보내는 값.
  final String id;

  /// 화면에 보여주는 이름.
  final String label;

  final String codename;
  final String tagline;

  /// 발광부(코어·안테나·블레이드) 색.
  final Color accent;

  /// 바이저 색.
  final Color visor;

  /// 어깨가 넓은지. 실루엣 차이를 만드는 값이다.
  bool get isHeavy => this == CyborgKind.male;

  /// 서버가 준 문자열을 외형으로 되돌린다.
  ///
  /// 모르는 값이면 [CyborgKind.male] 로 떨어뜨린다. 서버에 새 외형이 생겼는데
  /// 클라이언트가 낡은 경우에도 화면이 비어 보이지 않게 하기 위해서다.
  static CyborgKind fromId(String id) {
    for (final kind in CyborgKind.values) {
      if (kind.id == id) return kind;
    }
    return CyborgKind.male;
  }
}
