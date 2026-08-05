<!-- cowork:codex | 2026-08-05 14:36:24 | exit=0 | 743s -->
# codex 분석 — character-art-overhaul

> 요청: 남/녀 캐릭터가 너무 이쁘지 않습니다. 그냥 동그라미, 네모를 붙여 넣은 형태로 디자인이 너무 허접하고, 못생겼습니다.

참고 URL:
- https://github.com/RafaelBarbosatec/bonfire
- https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator

위 두 URL 을 참고하여 정적 이미지 애셋 없이, 동적 코드/위젯/컴포넌트로 미리 캐릭터를 만들어 놓고 로직/동적 생성해서 사용할 수 있도록 해 주세요.

그래서 캐릭터/몬스터의 비주얼적 디자인을 아주 예쁘고, 멋지고, 화려하게 해 주세요.
> 생성: 2026-08-05 14:36:24 · 소요 743s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

현재 병목은 아키텍처가 아니라 **파츠 어휘·실루엣 설계·명암 단계·관절 변형의 부족**이다. `CyborgDesign → CyborgRenderer → 인게임/Flutter` 공유 구조는 이미 완성돼 있다.  
캐릭터는 규칙적인 `RRect`와 사각 폴리곤이 반복되고, 남녀가 같은 세로 골격 비율을 써서 “원·네모를 조립한 인형”으로 읽힌다. 몬스터 200종도 실루엣은 네 `MonsterBuild`뿐이다.  
기존 연속 방향 투영은 유지하면서 `CyborgDesign`에 슬롯형 파츠 스키마를 추가하고, 렌더러에 베지에 실루엣·3~5단계 명암·배율별 LOD를 도입하는 것이 맞다. `CustomPainterComponent`나 신체별 Flame 자식 컴포넌트로 전면 재구축할 이유는 없다.  
코드 드로잉만으로 59px에서도 고급스러운 스타일라이즈드 메카 디자인은 가능하지만, 복잡한 관절·천·머리카락·표정 애니메이션까지 요구하면 `flame_rive` 또는 제한적 런타임 래스터 캐시가 별도 판단 지점이다.

## 2. 근거

- `lib/game/entities/cyborg_design.dart:26-52`, `lib/game/entities/cyborg_design.dart:138-218` — 외형 SSOT는 이미 `CyborgDesign`이고, 현재 선택 가능한 완성 프로필은 `assault`·`infiltrator` 두 개다.
- `lib/game/entities/cyborg_renderer.dart:12-24`, `lib/game/entities/cyborg_renderer.dart:877-940` — 타원기둥 투영으로 임의의 실수 `yaw`를 처리하며, 파츠의 화면 x와 깊이를 함께 계산한다.
- `lib/game/entities/cyborg_renderer.dart:145-200`, `lib/game/entities/cyborg_renderer.dart:476-513`, `lib/game/entities/cyborg_renderer.dart:566-613`, `lib/game/entities/cyborg_renderer.dart:654-720` — 다리·팔은 사각 폴리곤, 무릎·어깨·헬멧은 `RRect`, 코어·구동기는 원형 중심이다.
- `lib/game/entities/cyborg_renderer.dart:244-289`, `lib/game/entities/cyborg_renderer.dart:800-823` — 몸통과 포니테일에는 이미 베지에가 있으므로 “Path가 전혀 없다”가 아니라, 곡선 사용 범위와 곡률 변화가 부족한 상태다.
- `lib/game/entities/cyborg_design.dart:43-47`, `lib/game/entities/cyborg_renderer.dart:72-76` — 장갑 재질은 사실상 `armorBase`·`armorLight`와 공통 `_deepShade` 세 평면색이며, 캐릭터 렌더러에는 `Gradient`가 없다.
- `lib/game/entities/cyborg_renderer.dart:195-200`, `lib/game/entities/cyborg_renderer.dart:337-350`, `lib/game/entities/cyborg_renderer.dart:424-435`, `lib/game/entities/cyborg_renderer.dart:693-699`; `lib/game/entities/iso_entity.dart:55-68` — 본체와 그림자에 캐릭터당 3~6회의 `MaskFilter.blur`가 발생할 수 있다.
- `lib/game/entities/player.dart:1115-1131`, `lib/game/ui/cyborg_preview.dart:14-61`, `lib/auth/cyborg_portrait.dart:80-129` — 인게임·프리뷰·초상이 이미 같은 `CyborgRenderer.drawBody()`를 직접 재사용한다.
- `lib/game/systems/monster_codex.dart:106-212`, `lib/game/systems/monster_codex.dart:283-309` — 도감은 20계열×10등급=200종이다.
- `lib/game/systems/monster_codex.dart:234-269`, `lib/game/systems/monster_codex.dart:379-398` — 종별 시각 데이터는 팔레트·눈 개수·발밑 문양 개수뿐이며 파츠나 종별 실루엣 데이터가 없다.
- `lib/game/entities/enemy.dart:620-629`, `lib/game/entities/enemy.dart:715-1029` — 실제 본체 렌더링은 `drone`·`walker`·`siege`·`sovereign` 네 메서드로만 분기된다.
- `lib/game/palette.dart:79-96` — 밝은 배경에서 짙은 본체, 아군 청록·적 마젠타라는 시각 규칙이 이미 팔레트에 정의돼 있다.
- `test/cyborg_render_snapshot_test.dart:11-19`, `test/cyborg_render_snapshot_test.dart:28-47` — 16방향과 1.9배·0.55배 스냅샷 검수가 이미 마련돼 있다.
- `spacetimedb/src/lib.rs:91-108`, `spacetimedb/src/character.rs:17-31`, `lib/auth/cyborg_session.dart:170-178` — 서버가 저장·전송하는 외형은 현재 `kind` 문자열 하나뿐이어서 파츠 선택을 영속화할 스키마가 없다.
- 참고 자료는 스프라이트 자체보다 “호환되는 베이스·애니메이션·레이어 규약”을 가져오는 것이 타당하다. ULPC는 애셋별 라이선스가 서로 다름을 명시하므로 이미지 복사는 요구 위반과 라이선스 부담을 동시에 만든다. [Bonfire](https://github.com/RafaelBarbosatec/bonfire), [Universal LPC Generator](https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator)

## 3. 상세 분석

### 3.1 왜 못생겨 보이는가

**실루엣과 비율**

두 프레임은 폭 수치는 다르지만 발목·무릎·골반·허리·어깨·머리 위치를 같은 키 비율로 계산한다. `neckLength`는 데이터에 존재하지만 렌더러에서 사용되지 않고, 모든 프레임의 세로 리듬은 `_ankleRatio`부터 `_headBottomRatio`까지 동일하다. 따라서 남녀 차이가 대부분 가로 폭과 포니테일에 한정된다. `lib/game/entities/cyborg_design.dart:86-99`, `lib/game/entities/cyborg_renderer.dart:38-47`, `lib/game/entities/cyborg_renderer.dart:968-980`

팔은 팔꿈치 없이 어깨부터 손까지 이어지는 사각 기둥이고, 다리도 무릎 장식 아래에서 실제 방향이 꺾이지 않는다. 보행 시 끝점만 움직여 팔다리가 휘지 않는 막대처럼 보인다. `lib/game/entities/cyborg_renderer.dart:145-178`, `lib/game/entities/cyborg_renderer.dart:561-613`

[판단] VULCAN은 넓은 쐐기형 어깨→작은 머리→굵은 전완→좁은 발목의 `큰-작은-큰` 덩어리 리듬이 필요하다. WRAITH는 후방으로 흐르는 헬멧·긴 목·오목한 허리·높은 골반·역테이퍼 부츠를 연결하는 S자 리듬이 필요하다. 단순히 남성 폭을 넓히고 여성 허리를 줄이는 것만으로는 부족하다.

**곡률**

몸통 양쪽에는 각각 한 번의 `quadraticBezierTo`만 있고, 헬멧·어깨·관절은 일정 반경의 `RRect`다. 이 때문에 이마·관자놀이·턱, 흉곽·옆구리·골반처럼 서로 다른 재질과 긴장도를 가져야 할 부분이 모두 같은 “말랑한 캡슐” 곡률로 읽힌다. `lib/game/entities/cyborg_renderer.dart:244-262`, `lib/game/entities/cyborg_renderer.dart:476-504`, `lib/game/entities/cyborg_renderer.dart:654-662`

[판단] 헬멧은 완만한 이마 곡선→날카로운 관자놀이→안쪽으로 파인 턱, 몸통은 볼록한 흉곽→오목한 허리→다시 벌어지는 골반처럼 최소 두 번 곡률이 변해야 한다. `cubicTo` 또는 두 개 이상의 연결 베지에를 쓰되 접선이 갑자기 꺾이지 않도록 해야 한다.

**명암·재질·초점**

현재 흉갑 하이라이트는 평면 폴리곤 한 장이고, 헬멧과 어깨 전체가 같은 `armorLight`다. 빛 방향에 따른 면 전환보다 “밝은 파츠를 위에 붙인 것”에 가깝다. `lib/game/entities/cyborg_renderer.dart:265-289`, `lib/game/entities/cyborg_renderer.dart:475-513`, `lib/game/entities/cyborg_renderer.dart:654-679`

반대로 발광은 이미 충분히 많다. 코어는 두 번의 블러와 세 겹의 원을 사용하고 바이저·부츠·척추 레일까지 빛난다. 더 많은 글로우를 추가하는 것만으로는 조형이 좋아지지 않는다. `lib/game/entities/cyborg_renderer.dart:330-365`, `lib/game/entities/cyborg_renderer.dart:191-201`, `lib/game/entities/cyborg_renderer.dart:424-443`

[판단] 명암은 `deep shadow → armor base → plane mid → edge highlight → emissive core`의 5역할로 나누되, 새 색은 모두 `GamePalette`에 추가해야 한다. 얼굴/바이저와 흉부 코어에 대비를 집중하고 팔·부츠의 미세 회로는 낮춰야 시선의 초점이 생긴다.

**축소 내성**

0.55배에서는 현재 1.2~1.8px 선이 화면상 0.66~0.99px가 된다. 바이저 주사선, 안테나, 림 라이트, 척추 노드 중 상당수는 플레이 중 불안정하거나 사라진다. `lib/game/entities/cyborg_renderer.dart:281-289`, `lib/game/entities/cyborg_renderer.dart:431-441`, `lib/game/entities/cyborg_renderer.dart:700-710`, `lib/game/entities/cyborg_renderer.dart:756-772`

[판단] 0.55배용 실루엣 홈·돌출부는 원본 기준 최소 4px, 중요 간격은 3.6px 이상, 주요 강조선은 2~2.5px로 잡아야 한다. 작은 나사·점·얇은 데칼은 프리뷰 LOD에만 남겨야 한다.

### 3.2 코드 파츠 시스템

새 아키텍처를 옆에 세우기보다 `lib/game/entities/cyborg_design.dart` 안에서 기존 SSOT를 다음 네 역할로 확장하는 것이 적합하다.

| 역할 | 제안 데이터 | 책임 |
|---|---|---|
| 골격 | `CyborgFrameSpec` | 키, 관절 높이, 어깨·가슴·허리·골반, 팔·다리 분절 길이 |
| 선택값 | `CyborgAppearance` | `frame`, 슬롯별 파츠 ID, `implants`, `paletteId`, `variantSeed`, `schemaVersion` |
| 파츠 카탈로그 | `CyborgPartSpec` | 슬롯, 허용 프레임, 앵커, 크기 보정, LOD, 비대칭 여부 |
| 해석 결과 | `CyborgDesign` | 골격+선택값을 검증·결합해 렌더러에 전달하는 불변 데이터 |

권장 슬롯은 `hair/backCable → backWeapon → backUnit → rearArm/rearLeg → pelvis → torso → chestOverlay → shoulderL/R → frontArm/frontLeg → neck → helmet → face/visor → weapon → emissiveOverlay` 순서다. 레이어 순서는 사용자 데이터가 아니라 렌더러 상수로 고정해야 가림 순서가 깨지지 않는다. 기존 뒤쪽 팔→몸통→앞쪽 팔 순서는 이미 이 원칙을 구현한다. `lib/game/entities/cyborg_renderer.dart:78-100`

`CyborgImplant`는 생체·기계적 기능 오버레이로 유지하되, 헬멧·장갑·부츠 같은 상호배타적 장비 선택까지 `Set<CyborgImplant>`로 표현해서는 안 된다. 현재 `Set`은 슬롯 충돌, 좌우 비대칭, 호환 프레임, “없음” 선택을 표현하지 못한다. `lib/game/entities/cyborg_design.dart:118-136`, `lib/game/entities/cyborg_design.dart:227-260`

[판단] Flame 신체 자식 컴포넌트는 기본 선택이 아니다. 30명×약 12파츠면 360개 자식의 갱신·정렬·수명주기가 생긴다. 기존 `_View.project()`와 `Canvas.save/translate/rotate`를 활용한 `PartPose` 목록이 더 가볍고 연속 방향도 보존한다. 독립 충돌·투사체·별도 수명이 필요한 무기나 드론만 컴포넌트로 분리하는 편이 맞다. `lib/game/entities/cyborg_renderer.dart:83-100`, `lib/game/entities/cyborg_renderer.dart:929-940`

### 3.3 몬스터 다양성

현재 종의 색·눈·문양은 달라지지만 같은 `MonsterBuild`끼리는 본체 윤곽이 같다. 예를 들어 정찰기·말벌·감시안·추적자·섬광기가 모두 `_renderScout()`를 사용한다. `lib/game/systems/monster_codex.dart:106-127`, `lib/game/entities/enemy.dart:620-629`

`MonsterFamily`에 다음 `MonsterVisualSpec`을 연결해야 한다.

- 골격: `droneOrb`, `insectDrone`, `biped`, `hound`, `tripodSiege`, `fortress` 등.
- 파츠: chassis, locomotion, sensor, left/right weapon, back rig, crest/horn, wing/tail, armor overlay.
- 비율: 머리·몸통·다리 길이, 폭, 부양 높이, 무게중심.
- 등급 변형: 장갑판 수, 포신 길이, 뿔 단계, 에너지 링 수.
- 결정적 시드: 케이블 방향·비대칭 장갑·센서 간격의 작은 변주.

`MonsterCodex._build()`가 `family.visual + tier modifier`를 합성해 `MonsterSpecies.visual`을 만들고, `Enemy.render()`는 네 메서드 스위치 대신 `MonsterRenderer.draw(species, pose)`로 위임하는 구조가 적합하다. 전투용 `MonsterBuild`는 계속 유지해야 한다. 현재 속도·사거리·체력과 실루엣 계통이 연결되어 있기 때문이다. `lib/game/systems/monster_codex.dart:62-75`, `lib/game/systems/monster_codex.dart:379-398`, `lib/game/systems/monster_codex.dart:421-490`

[판단] 200종 각각을 독립 디자인하면 관리가 불가능하다. 20가족에 큰 실루엣 차이를 주고, 10등급은 같은 가족임을 유지한 채 장갑·센서·에너지 계층을 증설해야 한다. 59px에서는 색상보다 날개·뿔·포신·다리 수처럼 윤곽을 바꾸는 요소가 먼저 읽힌다.

### 3.4 Flutter 커스터마이저와 공용 렌더러

Flame의 `CustomPainterComponent`는 Flutter `CustomPainter`를 게임 캔버스에서도 공유하기 위한 공식 수단이다. 그러나 이 프로젝트는 더 낮은 수준의 상태 없는 `CyborgRenderer.drawBody()`를 이미 세 표면에서 공유하므로 전환 자체가 시각 품질을 높이지 않는다. [Flame CustomPainterComponent 문서](https://docs.flame-engine.org/latest/flame/components/utility_components.html#custompaintercomponent), `lib/game/entities/player.dart:1123-1131`, `lib/game/ui/cyborg_preview.dart:53-61`, `lib/auth/cyborg_portrait.dart:124-129`

커스터마이저 상태는 변경 가능한 `CyborgAppearance` 초안이어야 한다. 슬롯 탭에서 파츠를 선택할 때마다 `CyborgDesign.resolve(appearance)`를 만들고 기존 `CyborgPreviewPainter`에 넘기면 된다. 기존 UI에는 정면/후면 토글과 1.0~3.5배 확대만 있으므로, 드래그 기반 연속 `yaw`, 슬롯별 선택 목록, 호환성 필터, 0.55배 동시 썸네일이 추가로 필요하다. `lib/game/ui/cyborg_preview.dart:280-299`, `lib/game/ui/cyborg_preview.dart:374-409`

온라인 MMORPG에서는 UI만 확장해서 끝나지 않는다. `PlayerCharacter`와 월드 표시 데이터에 버전이 있는 외형 선택값을 저장하고, 원격 플레이어도 이를 해석해야 한다. 현재 원격 플레이어는 `female_cyborg`인지 여부만 직접 검사하므로 파츠 SSOT에서 벗어나 있다. `spacetimedb/src/lib.rs:91-108`, `lib/game/entities/remote_player.dart:115-123`, `lib/game/entities/remote_player.dart:311-322`

### 3.5 렌더링 비용과 LOD

현재 플레이어 정면은 그림자 1회, 양쪽 부츠 2회, 코어 2회, 바이저 1회로 총 6회의 블러를 실행한다. 후면은 프레임에 따라 3~4회다. 따라서 30명은 본체·그림자만으로 프레임당 90~180회 블러가 된다. 버프·잔상은 여기에 추가된다. `lib/game/entities/iso_entity.dart:55-68`, `lib/game/entities/cyborg_renderer.dart:191-201`, `lib/game/entities/cyborg_renderer.dart:337-350`, `lib/game/entities/cyborg_renderer.dart:424-435`, `lib/game/entities/cyborg_renderer.dart:693-699`

몬스터도 그림자와 눈마다 블러를 사용하며, 정찰기는 링과 부스터 두 개가 추가된다. 종의 눈은 1~3개이므로 정찰기 한 대는 5~7회 블러다. `lib/game/entities/enemy.dart:606-629`, `lib/game/entities/enemy.dart:670-689`, `lib/game/entities/enemy.dart:725-778`

권장 예산은 다음과 같다. `Canvas.draw*` 수는 논리 연산 수이며 실제 GPU draw call은 엔진 배칭에 따라 달라진다.

| LOD | 사용처 | 1개 목표 | 30개 목표 | 효과 |
|---|---|---:|---:|---|
| LOD0 | 0.55~0.85 | 26~34 draw, 블러 0, `saveLayer` 0 | 780~1,020 draw | 큰 실루엣, 3~4단계 평면 명암, 굵은 발광 심지 |
| LOD1 | 0.85~1.4 | 38~50 draw, 그룹 글로우 최대 1 | 1,140~1,500 draw, layer 최대 30 | 큰 면에만 선형/방사형 그라디언트 |
| LOD2 | 초상·커스터마이저 | 55~70 draw, gradient 2~3, layer 1~2 | 통상 1~2명만 표시 | 미세 패널선, 재질 하이라이트, 부드러운 글로우 |

[추측] 중급 모바일에서 블러 한 번을 0.03~0.12ms로 가정하면 현재 캐릭터 30명의 블러만 2.7~21.6ms가 된다. 이는 실측값이 아니라 위험 범위를 계산한 것이며, 60fps 전체 예산은 16.6ms다. LOD0 목표는 [추측] 1명 0.04~0.12ms, 30명 1.2~3.6ms이며 실제 승인 기준은 프로파일링으로 확정해야 한다.

`Path`와 큰 면의 `LinearGradient`·`RadialGradient`는 사용할 수 있지만, 팔다리마다 별도 셰이더를 만들지 말고 헬멧·흉갑·코어 정도로 제한해야 한다. `saveLayer`는 공식 문서도 렌더 타깃 전환과 메모리 churn 때문에 상대적으로 비싸다고 명시한다. 따라서 최소 배율에서는 사용하지 말고, 확대 LOD에서 모든 발광 마스크를 한 경계 레이어에 묶는 경우만 검토해야 한다. [Flutter `saveLayer` 문서](https://api.flutter.dev/flutter/dart-ui/Canvas/saveLayer.html), [Flutter `RadialGradient` 문서](https://api.flutter.dev/flutter/painting/RadialGradient-class.html)

런타임 `ui.Image` 캐시는 정적 애셋은 아니지만, 연속 방향과 외형 조합 때문에 기본 해법으로 부적합하다. 128×160 RGBA8888 한 장을 0.078125MiB로 가정하면 다음과 같다.

| 캐시 구성 | 이미지 수 | 원시 메모리 | 워밍업 [추측] |
|---|---:|---:|---:|
| 16방향×6프레임×2 기본 프레임 | 192 | 15MiB | 38~154ms |
| 32방향×8프레임×2 기본 프레임 | 512 | 40MiB | 102~410ms |
| 16방향×6프레임×30개 고유 외형 | 2,880 | 225MiB | 0.58~2.30초 |
| 16방향×6프레임×200 몬스터 종 | 19,200 | 1,500MiB≈1.46GiB | 3.84~15.36초 |

워밍업은 장당 0.2~0.8ms라는 [추측]을 사용했고 atlas padding·mipmap·엔진 객체 비용을 제외했다. 전면 래스터 캐시보다 정규화된 `Path`·`Paint`·파츠 `ui.Picture`를 공유하고 연속 투영은 매 프레임 유지하는 편이 우선이다. `quantizeYaw()`도 캐시가 연속 방향을 이산화한다는 대가를 이미 문서화한다. `lib/game/iso.dart:128-137`

## 4. 리스크 · 함정

- 실제 카메라는 기본 배율을 0.55로 제한한 뒤 사용자 배율 0.5를 다시 곱한다. 따라서 유효 최소는 0.275이며 108px 캐릭터가 약 30px까지 줄어든다. 스냅샷 테스트는 0.55까지만 검사한다. 이 불일치를 방치하면 59px 기준으로 만든 디테일도 사라진다. `lib/game/action_rpg_game.dart:317-353`, `test/cyborg_render_snapshot_test.dart:17-19`
- 파츠별 `PositionComponent`와 독립 `priority`를 도입하면 기존 `_View.project()`의 연속 깊이 정렬과 구현이 중복된다. 월드 깊이 정렬도 이미 `x+y` 기반 `depthPriority()`로 처리하므로 단순 `priority=y` 제안은 현재 좌표계에 맞지 않는다. `lib/game/iso.dart:80-85`, `lib/game/entities/iso_entity.dart:39-44`
- 화면 y에 따라 캐릭터 크기를 바꾸는 것은 현재의 직교 2:1 아이소메트릭 규칙과 충돌한다. [판단] 원근감을 위해 크기를 바꾸기보다 카메라 배율에 따른 렌더 LOD만 바꿔야 한다. `GAME-DESIGN.md:18-24`, `lib/game/iso.dart:80-125`
- 몬스터 팔레트는 현재 `monster_codex.dart` 내부의 HSL 숫자로 생성되어 엄격한 `GamePalette` SSOT와 어긋난다. 파츠 개편 시 색 계산과 색조 범위도 `GamePalette`로 이동해야 한다. `lib/game/systems/monster_codex.dart:494-518`, `lib/game/palette.dart:89-96`
- 캐릭터 생성 reducer는 `kind` 두 값만 화이트리스트로 받는다. 외형 필드를 추가하지 않고 클라이언트 로컬에만 저장하면 원격 플레이어·재접속·다른 기기에서 외형이 달라진다. `spacetimedb/src/character.rs:17-31`, `spacetimedb/src/character.rs:58-95`
- `GAME-DESIGN.md`는 렌더러를 626줄이라고 기록하지만 실제 파일은 994줄이고, “새 프레임은 디자인 항목 하나면 된다”고 적었지만 렌더러에는 `design.frame == CyborgFrame.assault` 분기가 있다. 문서가 현 구조의 확장성을 과대평가한다. `GAME-DESIGN.md:904-908`, `lib/game/entities/cyborg_renderer.dart:488-504`
- `flame_rive`는 복잡한 관절과 상태 머신에는 유효하지만 현재 `pubspec.yaml`에 없고 `.riv`라는 별도 저작 애셋이 필요하다. 정적 비트맵은 아니어도 “모든 외형 코드 SSOT”에서는 벗어나므로 사람의 명시적 경계 결정이 필요하다. `pubspec.yaml:30-40`, [flame_rive 패키지](https://pub.dev/packages/flame_rive)
- 런타임 스프라이트 캐시는 조합 수만큼 메모리가 증가하고 기존 연속 방향을 양자화한다. 품질 개선 수단이 아니라 프로파일링 후 적용할 성능 수단으로만 다뤄야 한다. `lib/game/entities/cyborg_renderer.dart:12-24`, `lib/game/iso.dart:128-137`

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | VULCAN·WRAITH 두 프레임을 기존 렌더러 안에서 먼저 재조형한다. 세로 골격을 분리하고 헬멧·몸통·팔·다리에 다중 베지에, 비대칭 대형 파츠, 4~5단계 명암을 적용한다. | `cyborg_design.dart`, `cyborg_renderer.dart`, `palette.dart` | `lib/game/entities/cyborg_renderer.dart:145-289`, `lib/game/entities/cyborg_renderer.dart:654-720` | 조형 기준 없이 파츠 수부터 늘리면 못생긴 조합만 폭증한다. |
| 2 | `CyborgDesign` 파일 안에 `FrameSpec`·`Appearance`·`PartSpec`·고정 레이어 순서를 추가하고 `CyborgImplant`와 일반 장비 슬롯을 분리한다. | 캐릭터 외형 SSOT | `lib/game/entities/cyborg_design.dart:18-52`, `lib/game/entities/cyborg_design.dart:118-136` | 호환성·기본값·스키마 버전이 없으면 저장 데이터 마이그레이션이 깨진다. |
| 3 | 0.55배 LOD에서는 블러·`saveLayer`를 제거하고 굵은 평면 명암을 사용한다. 확대 LOD에서만 헬멧/흉갑 gradient와 그룹 글로우를 허용한다. 유효 최소 배율 0.275 문제도 함께 결정한다. | 렌더링·카메라·성능 | `lib/game/action_rpg_game.dart:317-353`, `test/cyborg_render_snapshot_test.dart:17-47` | 카메라 축소 범위를 바꾸면 시야와 게임플레이에도 영향이 있다. |
| 4 | `MonsterFamily`에 `MonsterVisualSpec`을 추가하고 20가족의 chassis·이동부·센서·무기·장식 조합을 정의한다. 등급은 장갑·뿔·에너지 단계로 변형한다. | `monster_codex.dart`, `enemy.dart`, 신규 몬스터 렌더러 | `lib/game/systems/monster_codex.dart:106-212`, `lib/game/entities/enemy.dart:620-1029` | 200종 개별 제작 또는 종별 래스터 캐시는 유지비·메모리가 과도하다. |
| 5 | 커스터마이저를 `CyborgAppearance` 초안 기반 슬롯 UI로 확장하고 연속 yaw·정면/후면·확대/0.55배를 동시에 검수한다. | Flutter 프리뷰·선택 화면 | `lib/game/ui/cyborg_preview.dart:280-409`, `lib/auth/character_select_screen.dart:502-605` | 프리뷰만 바꾸고 서버·원격 렌더를 빠뜨리면 MMORPG에서 외형이 불일치한다. |
| 6 | 파츠 선택값을 서버의 별도 저빈도 외형 행 또는 버전 있는 압축 필드로 저장하고, `Player`·`RemotePlayer`·초상 모두 같은 resolver를 사용하게 한다. | SpacetimeDB·동기화 | `spacetimedb/src/lib.rs:91-108`, `lib/game/entities/remote_player.dart:115-123` | 공개 위치 행에 긴 JSON을 직접 넣으면 네트워크 행 크기가 커진다. |
| 7 | 30개 액터 벤치마크에서 p95 렌더 예산을 정한 뒤에만 `ui.Picture`·`ui.Image` 캐시를 채택한다. 기본값은 Path/파츠 캐시이며 전면 프레임 캐시는 피한다. | 성능·테스트 | `lib/game/iso.dart:128-137`, `test/cyborg_render_snapshot_test.dart:78-152` | 캐시가 방향·프레임·고유 외형 수의 곱으로 폭증한다. |
| 8 | 팔꿈치·무릎 관절, 천·머리카락 물리, 표정 상태 머신이 실제 품질 목표가 된 시점에만 `flame_rive`를 비교 시제품으로 평가한다. | 애니메이션 기술 결정 | `pubspec.yaml:30-40`, [flame_rive](https://pub.dev/packages/flame_rive) | `.riv` 저작 파이프라인과 코드 SSOT가 이원화된다. |

## 6. 불확실 · 미확인

- 시각적 “예쁨”은 코드만으로 최종 판정할 수 없다. 제공된 규칙 때문에 스냅샷 생성·`flutter analyze`·성능 프로파일링은 실행하지 않았으며, 실제 16방향 PNG와 저사양 모바일 GPU 타이밍은 미확인이다.
- 논리적 `Canvas.draw*` 호출 수는 계산할 수 있지만 실제 GPU draw call·배칭·블러 비용은 Impeller/Skia·플랫폼·기기에 따라 달라진다. §3.5의 ms는 모두 `[추측]`이며 프로파일 결과로 교체해야 한다.
- Bonfire 저장소 자체와 LPC README는 확인했지만, 요청문에 제시된 Bonfire LPC 예제 세 파일의 현재 브랜치상 정확한 내용은 웹 조회 실패로 독립 재확인하지 못했다. 레이어 합성 구조는 요청문이 제공한 사실과 저장소 수준 자료를 전제로 분석했다.
- 0.55가 제품상 절대 최소인지, 사용자 축소 배수까지 포함해 0.275가 의도된 최소인지 사람의 결정이 필요하다. 이 선택은 모든 최소 디테일 규격을 바꾼다. `lib/game/action_rpg_game.dart:317-353`
- 커스터마이징 파츠가 단순 미용인지, 장비·능력치와 연결되는지 정의되지 않았다. 후자라면 외형 스키마뿐 아니라 서버 권위 장비·인벤토리 계층까지 함께 설계해야 한다.
