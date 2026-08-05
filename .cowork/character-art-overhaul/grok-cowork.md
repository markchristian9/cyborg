<!-- cowork:grok | 2026-08-05 14:30:21 | exit=0 | 380s -->
# grok 분석 — character-art-overhaul

> 요청: 남/녀 캐릭터가 너무 이쁘지 않습니다. 그냥 동그라미, 네모를 붙여 넣은 형태로 디자인이 너무 허접하고, 못생겼습니다.

참고 URL:
- https://github.com/RafaelBarbosatec/bonfire
- https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator

위 두 URL 을 참고하여 정적 이미지 애셋 없이, 동적 코드/위젯/컴포넌트로 미리 캐릭터를 만들어 놓고 로직/동적 생성해서 사용할 수 있도록 해 주세요.

그래서 캐릭터/몬스터의 비주얼적 디자인을 아주 예쁘고, 멋지고, 화려하게 해 주세요.
> 생성: 2026-08-05 14:30:21 · 소요 380s · 읽기 전용 분석(작업공간 미수정)

---

# Cyborg 캐릭터·몬스터 비주얼 분석 보고서

**역할:** 2D 캐릭터 아트 디렉터 + 절차적 렌더링 엔지니어 (읽기 전용)  
**대상:** 코드 드로잉 기반 사이보그/몬스터 외형  
**한 줄 판결:** 병목은 “레이어 시스템 없음”이 아니라 **같은 스펙→렌더러 골격을 프리미티브·2톤으로만 채운 것**, 그리고 **몬스터 200종을 그림 4종으로 접는 것**이다. `CyborgDesign`/`CyborgRenderer`/연속 yaw를 유지한 채 **조형·명암·얇은 파츠 레지스트리·LOD·선택적 bake**를 올리는 길이 제약 안에서 성립한다.

---

## 1. 현황 요약 (확인된 사실)

| 항목 | 확인 내용 | 근거 |
|---|---|---|
| SSOT 골격 | 치수·색·임플란트=`CyborgDesign`, 그리기=`CyborgRenderer.drawBody` 정적 메서드 하나 | `cyborg_design.dart:18-52`, `cyborg_renderer.dart:25-66` |
| 3표면 공유 | 플레이어·원격·초상·프리뷰 모두 `CyborgRenderer.drawBody` | `player.dart:1123-1131`, `remote_player.dart:311-322`, `cyborg_portrait.dart:12-14,124`, `cyborg_preview.dart:53-61` |
| 방향 | 양자화 없는 연속 yaw, 타원기둥 `_View.project` | `cyborg_renderer.dart:12-21,873-940`, `iso.dart:114-126` |
| 명암 | `armorBase`/`armorLight` 2톤 `Paint` 평면 채색. **Gradient 사용 0회** | `cyborg_renderer.dart:72-76` (grep: `LinearGradient`/`RadialGradient` 없음) |
| 프리미티브 | 사지=사다리꼴 `Path`, 헬멧·무릎·부츠·어깨=`RRect`/`drawCircle` | `145-190`, `548-612`, `654-662` |
| Blur | 본체 기준 `MaskFilter.blur` **최대 5지점**(부츠×2, 코어×2, 바이저; 임플란트 조건부 추가) | `200`, `342-349`, `434`, `697` |
| 몬스터 종 | 20 family × 10 tier = 200 `MonsterSpecies` | `monster_codex.dart:234-309,379-398` |
| 몬스터 그림 | `MonsterBuild` 4값 → `_renderScout/Sentry/Heavy/Commander` | `enemy.dart:620-629,715-1030` |
| 종 간 시각 차 | eyeCount·crestCount·palette·scale만 변조. 실루엣 템플릿은 build 고정 | `monster_codex.dart:384-398`, `enemy.dart:670-712` |
| 서버 외형 | `CHARACTER_KINDS` 2종 문자열만 저장 | `spacetimedb/src/character.rs:17-23` |
| 줌 | 최소 0.55 → 키 108px ≈ **59px** | `action_rpg_game.dart:350-353`, `test/cyborg_render_snapshot_test.dart:17-19` |
| 비교 사례 | `WorldTree`도 코드 드로잉·베지에·2톤 lit face. 그라디언트는 없음 | `world_tree.dart:156-186` |
| 정적 애셋 | 캐릭터 이미지 없음(지침·`assets/` 오디오 중심) | Instructions 3 |

---

## 2. 질문별 분석

### 2.1 지금 그림이 왜 못생겼는가 (조형 언어)

사람의 “동그라미·네모를 붙여 넣었다”는 지적은 **아키텍처 부재가 아니라 조형 어휘의 빈곤**으로 번역된다.

| 조형 축 | 부족 내용 | 코드 근거 |
|---|---|---|
| **실루엣 리듬** | 다리는 hip→foot 직선 사다리꼴 2개. 허벅지/종아리 곡률 변화·S자 윤곽 없음. 축소 시 “막대 2개” | `_drawLegs` `145-151` |
| **비율·덩어리** | 골격 수치는 있음(어깨/허리/골반). 그러나 표면이 둥근 박스로 채워져 **덩어리 대비**(헬멧 질량 vs 가느다란 목 vs 장갑 판)가 “박스 스택”으로 읽힘 | design `143-215` vs head `654-662`, arm `566-572` |
| **곡률** | 몸통만 허리 `quadraticBezierTo` (`244-261`). 팔·다리·헬멧·어깨는 일정 반경 `RRect` → 곡률이 전 부위 동일 리듬 | torso vs arm/leg/head |
| **명암 단계** | shade/base 또는 base/light **2단**. 원통형 하이라이트 밴드·림·캐비티 없음. 흉갑 “하이라이트”도 평면 `armorLight` 폴리곤 클립 (`266-278`) | paint `72-76` |
| **디테일 밀도** | 초점(얼굴·코어)에 디테일이 모이긴 함(바이저 주사선 `700-709`, 코어 5겹 `337-365`). 사지·헬멧 본체는 비어 있어 **초점과 주변의 밀도 대비가 “원+박스 vs 빈 면”** | — |
| **색 단계** | 팔레트 자체는 밝은 바닥용 짙은 본체 (`palette.dart:79-87`). 문제는 색 수 부족이 아니라 **같은 2색을 면 전체에 칠함** | — |

**남/녀 구분 의도 vs 체감:**  
`hasConcaveWaist`, hip>waist, 비대칭 어깨 증설 등은 설계되어 있다 (`cyborg_design.dart:132-133,188-190`, `cyborg_renderer.dart:488-504`, 스냅샷 테스트 `50-65`). 그러나 **표면 어휘가 동일 프리미티브**라, 확대 선택 화면에서도 “예쁜 캐릭터”가 아니라 “치수만 다른 레고”로 읽힌다. 59px에서는 허리 오목함·비대칭 어깨가 겨우 남고, 헬멧 리지·갈비선·포트는 거의 소실한다 (`test/...:17-19`).

**몬스터 쪽 동일 병:**  
Scout=역삼각+RRect 캡, Sentry/Heavy=RRect 다리·몸·머리, Commander=Heavy+원 글로우+뿔 (`enemy.dart:715-1030`). 계열명 “말벌/창병/수확자”는 전투·색·눈 개수만 다르고 **실루엣 문법이 4문장**이다.

---

### 2.2 코드만으로 “예쁜” 캐릭터 — 쓸 것 / 비용

| 기법 | 이 프로젝트 적합성 | 59px | 비용 메모 (추정) |
|---|---|---|---|
| **베지에 실루엣 Path** (사지·헬멧 외곽) | **필수 1순위.** 이미 torso/ponytail/WorldTree 선례 | 외곽만 살아남으면 충분 | Path 구성 저렴. 드로우 1~2/부위 |
| **3~4단 명암** (shade/base/light/rim) 또는 **축 정렬 LinearGradient** | 원통 팔·다리·몸통에 수직/수평 gradient 1회/부위 | 큰 면 그라데이션은 59px에서도 읽힘 | GPU fill. blur보다 저렴 |
| **clip + 하이라이트 판** | torso에 이미 있음 (`275-278`) → 헬멧·어깨로 확장 | 중간 | clipPath 비용 있음, saveLayer 없이 가능 |
| **MaskFilter.blur** | 코어·바이저·부츠 thruster에 이미 다수. **늘리면 안 됨** | 글로우는 59px에서 뭉개져 실루엣만 키움 | **비쌈.** 캐릭터당 현재 blur 페인트 ≤5 (+임플란트). 30명×5=150 soft mask |
| **saveLayer 합성** | portrait 비선택 시에만 (`cyborg_portrait.dart:115-118`). 인게임 본체에 상시 금지 권고 | — | offscreen + 합성, 30명에 치명 |
| **Picture / ui.Image bake** | ground_layer·safe_zone 선례. 연속 yaw와 충돌 → **quantizeYaw 필요** | bake 해상도 조절 | 아래 §2.6 |

**드로우콜·시간 추정** (프로파일 실측 아님 → `[추정]`)

현재 `drawBody` 정면 assault 대략:
- 기하 호출 ~35–50회 (`drawPath/RRect/Circle/Line` 합, implant·blade 포함 시 상단)
- blur 페인트 3–5회
- 1명: 대략 **0.2–0.6ms** (모바일 GPU 가정, blur가 지배)
- 30명(로컬+원격+혼잡): blur만 90–150회 → **수 ms~10ms+** 가능. 60fps 예산 16.6ms 중 캐릭터만으로 절반 잠식 위험

**권장 예산 규칙**
1. 인게임 기본: blur는 **코어 1 + 바이저 1** 이하. 부츠 thruster blur는 LOD에서 제거.
2. 59px LOD: 실루엣 Path + 2톤 + 림 1 + 코어 점 1.
3. 선택/프리뷰(scale≥1.5~2.0, `cyborg_preview.dart:286`): 베지에·4단 명암·디테일 전부 ON.

---

### 2.3 LPC/Bonfire 레이어 → 코드 파츠 시스템

**검증:** 제안된 `Spec → CustomPainter → Flame/Flutter 공유`는 **이미 구현됨.**  
`CustomPainterComponent` 신설이나 자식 `PositionComponent` 트리로 눈·뿔·팔을 나누는 안은, 연속 yaw 투영·깊이 정렬(`_armsByDepth`, depth sort)과 **중복·충돌**한다. 관절을 컴포넌트 트리로 돌리면 `_View.project` 이점을 버리고 8방향 스프라이트식 정렬로 퇴행하기 쉽다.

**가져올 것 = 이미지 레이어가 아니라 “교체 단위 + 그리 순서”.**

| LPC 레이어 개념 | 코드 파츠 대응 | 기존 자산 |
|---|---|---|
| body | `FrameHull` (골격 치수 + torso/leg/arm 페인터) | `CyborgDesign` 치수 15종 |
| head / helmet | `HeadPart` | `_drawHead` |
| hair | `HairPart` | `CyborgHair` enum 2종 |
| armor / torso detail | `Implant` / `PlatePart` | `CyborgImplant` 7종 + `has()` |
| weapon | blade holster / future | `_drawHolsteredBlade` |
| (없음→추가) gloves/boots style | optional enum | 현재 하드코드 RRect |

**권장 스키마 (기존 확장, 신규 엔진 금지)**

```text
CyborgDesign  (SSOT 유지)
  + optional PartIds: helmetId, armSilhouetteId, shoulderKitId, ...
  implants: Set<CyborgImplant>  // 유지
  hairStyle: CyborgHair         // 유지·확장

PartRegistry: PartId → void paint(Canvas, CyborgDesign, _Levels, _View, paints…)
drawBody: 고정 레이어 순서만 오케스트레이션
  backRig → far arm → legs → pelvis → torso → details → shoulders → near arm → neck → head
```

- **교체 단위:** 헬멧 실루엣, 어깨 키트, 바이저 컷, 헤어, implant 세트. 프레임(assault/infiltrator)은 골격 프리셋.
- **새 구조 전면 교체 불필요.** implant 패턴(`has(...)`)이 이미 조건부 레이어다 (`306-383`, `398-445`).
- **주의:** 파츠만 늘리고 조형을 안 바꾸면 “동그라미 파츠 조합” = 여전히 허접. **레이어 시스템 ≠ 예쁨.**

**연속 yaw 유지 조건:** 파츠 페인터는 반드시 `_View`/`_Levels`를 인자로 받고, 자체 `canvas.scale(-1,1)` 미러를 쓰지 않는다 (몬스터는 아직 미러: `enemy.dart:619` — 플레이어와 비대칭).

---

### 2.4 몬스터 다양성

**현재 접기 맵**

```
MonsterSpecies (200)
  └ family.build ∈ {drone, walker, siege, sovereign}  → 렌더 4종
  └ eyeCount, crestCount, palette, stats.scale          → 디테일·색·크기만
```

`MonsterFamily.all`은 이름·hue·build만 다르고 **시각 파츠 필드가 없다** (`monster_codex.dart:78-100,106+`).

**권장: Family kit + tier 변조 (200 전용 렌더 금지)**

```text
MonsterVisualSpec {
  hull: enum { wedgeHover, bipedBox, wideSiege, ... }  // build 기본값
  deco: Set { wings, antenna, claw, cannon, crown, orbitDrones, ... }
  eyeLayout, crestStyle
  // palette/scale/eyeCount/crestCount 는 기존 Species 필드 재사용
}
MonsterFamily += visual defaults
MonsterSpecies.tier → deco 밀도, 스파이크 수, glow 강도 (이미 eye/crest 패턴)
Enemy.render → MonsterRenderer.draw(species, anim)  // 4메서드 흡수
```

- **family 20개**에 hull+1~2 deco 조합이면 “말벌 vs 순찰병”이 실루엣에서 갈린다.
- **tier**는 크기·채도·눈·문양(기존) + deco 스케일.
- **sovereign**은 siege hull + crown/orbit 레이어 (지금 Commander가 Heavy 위에 올리는 패턴 `985-1029`을 데이터화).

성능: 적 동시 표시가 캐릭터보다 많을 수 있음. 몬스터도 **blur 상한·LOD** 동일 적용. crest 고리(`693-712`)는 원거리 식별용이라 유지 가치 높음.

---

### 2.5 커스터마이저 UI

**이미 된 것**
- 동일 렌더러 재사용 (`cyborg_preview.dart:12-13,53-61`, `cyborg_portrait.dart:12-14`)
- 프리뷰 페이지: 걷기/뒷모습/scale 2.0, implant **표시 전용** 칩 (`232-266`, `273-336`)
- 선택 화면 초상: scale-to-fit, 호흡, 선택 시 saveLayer 페이드

**파츠 선택 UI로 확장 시 필요**
1. `CyborgDesign`을 const 2개 프리셋만이 아니라 **복사·with 변형** 가능하게 (현재 `static const assault/infiltrator` + `all`).
2. 칩을 read-only → `PartId` 토글; `setState`로 같은 `CyborgPreviewPainter(design: modified)`.
3. **SSOT:** 저장 단위는 design 스냅샷(또는 part id 맵). 렌더 분기 금지.
4. **서버:** `kind` 2종만 (`character.rs:23`). 파츠 저장은 2단계 — 클라 로컬/`shared_preferences` 또는 서버 컬럼 확장 후에야 재접속 유지. 확장 시 `CHARACTER_KINDS` 또는 별도 part 필드 + 클라 `CyborgKind` 동기화.
5. 확대 배율(프리뷰 2.0, 스냅샷 1.9)에서 검수 + 0.55 스냅샷 회귀 (`test/cyborg_render_snapshot_test.dart`).

Flame `CustomPainterComponent` 도입은 **불필요** — Flutter `CustomPaint` + 인게임 직접 `drawBody`가 이미 공유 모델.

---

### 2.6 현실성 상한 — 코드 드로잉 vs Rive vs bake

| 수준 | 달성 가능? | 수단 |
|---|---|---|
| “레고 탈출” — 읽히는 실루엣, 금속 원통감, 남/녀·프레임 구분 | **예, 코드만** | 베지에 + 3~4톤 + 초점 디테일 |
| 선택 화면 “멋짐” (1.9×~2×) | **예, 코드만** | 동일 + 디테일 레이어 ON |
| 인게임 30명 “아주 화려” (파티클·다층 글로우·세밀 패널라인) | **아니오 / 역효과** | 59px에서 소실 + blur 폭발 |
| 관절 IK·복잡한 천 물리·페이스 리그 | 코드 즉시모드 한계 | **Rive 등** — 아래 보류 사유 |
| 인게임 안정 60fps + 디테일 유지 | **bake** | quantizeYaw 16~32 × pose key × 2 frame |

**런타임 bake 수치 예시** (제안 시 필수 형식)

가정: RGBA8888, 캐릭터 셀 128×144, 2 design, yaw 16, walk 4 phase, idle 1  
→ 2 × 16 × 5 = **160 장**  
→ 128×144×4 × 160 ≈ **11.3 MB** (여유 있게 ≤10MB 목표면 셀 96×112 또는 yaw 12로 조정)  
워밍업: 160회 `PictureRecorder`+`toImage` — 프레임당 4~8장 청크 bake로 스터터 분산 (`ground_layer` 청크 패턴).  
**pulse 코어는 bake 제외**하고 위에 점만 실시간.

**`flame_rive` 보류 사유 (코드 근거)**
- `pubspec`에 Rive 없음; 연속 yaw·단일 `CyborgRenderer` SSOT와 파이프라인 충돌.
- 방향 이산 + 아트 파이프라인 + 라이선스/툴체인. “무 정적 이미지” 정책과도 어긋나기 쉬움(벡터 런타임 에셋).
- 코드 드로잉 상한을 확인한 **뒤** 선택지.

---

## 3. 설계 제안 검증 (사람 쪽 초안)

| 제안 | 판정 |
|---|---|
| CustomPainter 공유 | **이미 있음** (portrait/preview). 재발명 금지 |
| PositionComponent 자식 합성 | **비권장** — `_View` 깊이 정렬·연속 yaw와 중복/충돌 |
| MonsterSpec→Painter→Component | **방향만 채택.** 데이터(`MonsterVisualSpec`) + 공통 렌더러. Flame 트리 분해는 필수 아님 |
| priority=y, 타원 그림자 | 기존 IsoEntity 패턴 유지 |
| flame_rive | **보류** |

**진짜 병목 = 조형 채움 + 몬스터 접기 + (부차) blur 비용.** 아키텍처 교체가 아님.

---

## 4. 위험 · 안티패턴

| 위험 | 왜 |
|---|---|
| 파츠만 늘리고 조형 안 손댐 | 동그라미 조합 = 허접 유지 |
| 몬스터 200 전용 렌더 | 유지비 폭발 |
| 서버 kind 2종 무시하고 클라만 파츠 저장 | 재접속 초기화 |
| 팔레트 하드코딩·본체 밝게 | 흰 바닥 실루엣 소실 (`palette.dart:79-80`) |
| 인게임 blur/saveLayer 남발 | 30엔티티에서 프레임 붕괴 |
| 연속 yaw 폐기 후 8방향만 | 현재 최대 강점 상실 (`cyborg_renderer.dart:12-21`) |
| 정적 LPC 스프라이트 도입 | Instructions 3 위반 |
| 다른 세션 동시 편집 | `cyborg_renderer.dart`/`enemy.dart` 경합 |

---

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| **1** | **조형 1차:** 사지·헬멧 베지에 실루엣. 명암 3~4단 또는 원통 `LinearGradient`. blur는 코어·바이저 위주 | `cyborg_renderer.dart` | §2.1–2.2 | 회귀 → 스냅샷 1.9×/0.55× |
| **2** | **LOD:** 화면 높이&lt;~70px 또는 scale 인자로 디테일 스킵 | `drawBody` 인자 | zoom `350-353` | 두 배율 품질 괴리(의도) |
| **3** | **얇은 PartRegistry:** `_drawHead/_drawArm` 분리, design에 optional part 필드. 기본=현재 룩 | design+renderer | implant `has` 패턴 | 과설계 시 994줄만 분산 |
| **4** | **`MonsterVisualSpec`:** family hull/deco, Enemy 공통 렌더러. eye/crest/palette 유지 | codex + enemy | 620-629 vs 200종 | 전투/렌더 혼선 주의 |
| **5** | **인게임 quantizeYaw + Picture/Image 캐시** (pulse 제외). 메모리 ≤~10MB/2디자인 | 신규 캐시 + `iso.quantizeYaw` | `iso.dart:128-136`, ground_layer | 워밍업 스터터 → 프레임당 bake 한도 |
| **6** | **커스터마이저:** 프리뷰에 파츠 칩 + 동일 painter. 서버 저장 2단계 | `cyborg_preview.dart` | 이미 재사용 | kind 2종 한계 |
| **7** | **Rive 보류** | 의존성 | 연속 yaw·SSOT·무이미지 | 파이프라인 붕괴 |

**구현 순서:** 1 → 2 → 스냅샷 검수 → 3 → 4 → 5 → 6.  
아키텍처 전면 교체·정적 LPC·엔진 이전은 하지 말 것.

---

## 6. 불확실 · 미확인

- blur·그라디언트 **실측 ms** — 프로파일러 미실행. §2.2는 구조 기반 `[추정]`.
- 화면당 동시 적·원격 플레이어 **하드캡** — 과제 기준 30명 가정.
- Bonfire `lpc/` 소스는 로컬 미열람. LPC 레이어 목록은 공개 생성기 관례 기준.
- “아주 화려”의 레퍼런스 우선순위(선택 화면 vs 인게임 59px) 미확정.
- `.cowork/cowork-prompt.md` 본문 과제 동기화 여부는 분석 범위 밖(수정 안 함).

---

## 7. 필수 질문 체크리스트

1. **왜 못생겼나** — 실루엣=직선 프리미티브, 명암=2톤, 곡률 단조, 디테일 밀도 불균형. `cyborg_renderer.dart` 사지·헬멧·paint 초기화 줄 인용 위.
2. **코드 예쁨 조건** — 베지에+3~4톤/gradient 우선, blur 억제, LOD, 선택적 bake. 30명 예산 포함.
3. **LPC→코드 파츠** — 기존 Design/Renderer/Implant 확장; 레이어 순서 고정; 전면 신구조 불필요.
4. **몬스터** — VisualSpec family kit + tier; 4 하드코딩 메서드 흡수; Species 필드 연결.
5. **커스터마이저** — 이미 공유 중; design 가변 + 칩 UI + 서버 2단계.
6. **현실성** — “읽히는 멋”까지 코드; 과화려·관절 리그는 bake/Rive 영역. Rive는 보류.

---

**최종:** 시스템은 이미 “데이터 스펙 + 공유 즉시모드 렌더러 + 연속 아이소 투영”이다. 사람이 보는 허접함은 그 파이프를 채운 **조형 어휘와 몬스터 접기**에서 온다. 예쁨은 아키텍처 교체가 아니라 **베지에 실루엣·명암 단계·초점 디테일·LOD·(이후) 얇은 파츠/비주얼 스펙**으로 올라간다.
