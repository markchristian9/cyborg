import '../game/entities/cyborg_design.dart';

/// 서버가 아는 캐릭터 종류와 게임의 신체 프레임을 잇는 다리.
///
/// 외형에 관한 수치·색·설명은 하나도 갖지 않는다. 전부 [CyborgDesign] 에 있고
/// 여기는 **서버 문자열 ↔ 프레임** 대응만 담당한다. 선택 화면에서 본 몸과 게임
/// 안에서 조종하는 몸이 어긋나지 않으려면 출처가 하나여야 한다.
///
/// `id` 는 서버가 아는 값과 **글자 그대로** 같아야 한다
/// (`spacetimedb/src/character.rs` 의 `CHARACTER_KINDS`). 여기서 오타가 나면
/// 서버가 화이트리스트로 걸러 캐릭터 생성이 거절된다.
enum CyborgKind {
  male(
    id: 'male_cyborg',
    label: '남성 사이보그',
    frame: CyborgFrame.assault,
  ),
  female(
    id: 'female_cyborg',
    label: '여성 사이보그',
    frame: CyborgFrame.infiltrator,
  );

  const CyborgKind({
    required this.id,
    required this.label,
    required this.frame,
  });

  /// 서버에 보내는 값.
  final String id;

  /// 화면에 보여주는 이름.
  final String label;

  /// 이 종류가 쓰는 신체 프레임.
  final CyborgFrame frame;

  /// 외형 수치와 색을 담은 프로필.
  CyborgDesign get design => CyborgDesign.of(frame);

  String get codename => design.codename;
  String get tagline => design.tagline;

  /// 서버가 준 문자열을 종류로 되돌린다.
  ///
  /// 모르는 값이면 [CyborgKind.male] 로 떨어뜨린다. 서버에 새 외형이 생겼는데
  /// 클라이언트가 낡은 경우에도 캐릭터 칸이 비어 보이지 않게 하기 위해서다.
  static CyborgKind fromId(String id) {
    for (final kind in CyborgKind.values) {
      if (kind.id == id) return kind;
    }
    return CyborgKind.male;
  }
}
