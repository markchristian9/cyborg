<!-- cowork:grok | 2026-08-04 21:20:28 | exit=0 | 469s -->
# grok 분석 — character-visual-upgrade

> 요청: 남성/여성 캐릭터를 더 멋있게 비주얼 적 디자인을 해 주세요.

1) 남성/여성 캐릭터 비주얼적 디자인을 더 예쁘고, 멋지고, 화려하게 해 주세요.
2) 클릭으로 이동할 수 있도록 해 주세요.
3) 정적 애셋이 아닌, 동적 캐릭터 생성이므로 방향은 256 방향으로 할 수 있나요? 최대한 방향을 많이 해 주세요.
> 생성: 2026-08-04 21:20:28 · 소요 469s · 읽기 전용 분석(작업공간 미수정)

---



## 1. 결론 요약

1차 구현은 **세 요구의 골격은 들어갔지만 “완료”로 보기 어렵다.**  
**방향**: 각도 입력은 연속 실수라 256을 **수치상 이미 초과**한다. 다만 헬멧·비무기 팔·다리가 **yaw에 따라 형태 프로파일이 거의 안 바뀌는 2D 조각**이라, “부드럽게 돈다”는 체감은 **연속 배치·가림은 달성 / 측면 실루엣 충실은 미달**이다.  
**클릭 이동**: WASD·조이스틱 유지 + 수동 입력이 목표 취소로 이기고, 직선·슬라이딩·0.35s stuck·표식·안내선까지 있다. 경로 탐색 없음·적 탭=이동이 실전 약점이며, `nearestWalkable` 실패 시 **스폰 좌표로 목표가 잡히는 함정**이 있다.  
**비주얼**: VULCAN/WRAITH 골격·임플란트·림/코어는 있으나 “더 화려”는 발광 추가보다 **32~64px 실루엣 마디**가 병목. 남/여 **색 동일은 의도**(아군 식별)이지 버그가 아니다.  
**치명 불일치**: 선택 화면은 `character.kind`로 그리지만 인게임 `_spawnPlayer`는 항상 기본 `assault` — 주석(“고른 몸이 넘어온다”)과 코드가 어긋난다.

---

## 2. 근거

- `lib/game/entities/cyborg_renderer.dart:12-21, 51-53` — “양자화 없는 연속 회전”, `yaw`는 256뿐 아니라 **실수 전부**.
- `lib/game/entities/cyborg_renderer.dart:833-839` — `_View.project()`가 화면 `x`와 `depth`를 함께 계산; depth 부호로 앞/뒤 가림.
- `lib/game/entities/cyborg_renderer.dart:817-821` — `halfWidth`가 yaw에 따라 타원 투영으로 **연속 변화**(측면 얇아짐).
- `lib/game/iso.dart:109-123` — `facingYaw()` 연속각; `quantizeYaw`는 캐시용 헬퍼(주석: 256→약 1.4°). **저장소 전체 호출은 정의부 1곳뿐**(미사용).
- `lib/game/entities/player.dart:825-841` — `_drawFrame` → `CyborgRenderer.drawBody` + `facingYaw(dir)`만; 8방향 불리언/`scale(-1)` 없음.
- `lib/game/entities/cyborg_renderer.dart:587-595, 513-521, 139-145` — 헬멧은 원점 중심 RRect(폭만 스케일), 비무기 팔은 세로 RRect, 다리는 사다리꼴+`strideProjection`으로 x 흘림.
- `lib/game/entities/cyborg_renderer.dart:524-546` — 무기 팔은 `lean`+손 `armorLight` 마디 **이미 존재**(“관절 전무”는 과장).
- `lib/game/entities/cyborg_renderer.dart:714-733` — 포니테일 곡선이 항상 `p.x - spread` 쪽으로 치우침(좌/우 측면 비대칭).
- `lib/game/entities/cyborg_design.dart:143-213` — VULCAN 어깨 34·허리 20 vs WRAITH 25·13.5; 색은 **의도적으로** 동일 `GamePalette.player*`(196-198행 주석).
- `lib/game/entities/cyborg_renderer.dart:179, 317, 324, 409, 630` — 본체 `MaskFilter.blur` 코드 위치 5곳; 다리 루프면 부츠 blur×2 + 코어×2 + 바이저(정면) → assault 정면 **약 5회/몸**, infiltrator 레일 시 +1.
- `lib/game/entities/iso_entity.dart:59-67` — 엔티티 그림자 blur 1회 추가.
- `lib/game/input/click_move.dart:12-31, 38-126` — `priority: -1000000` 탭 레이어; `MoveMarker`/`MovePathHint`.
- `lib/game/entities/player.dart:55, 266-337` — `moveSpeed = 3.6` 타일/s; 수동 `moveInput`이 `clearMoveTarget()`; 직선 조향·도착 0.18·stuck 0.35s.
- `lib/game/action_rpg_game.dart:225-228, 391-408, 688-694` — 스폰 시 `design` 미전달; 키보드+조이스틱 합산; 탭→`nearestWalkable`→`moveTo`.
- `lib/main.dart:64-82` — `character.level/xp/name`만 반영, **`kind` 미사용**.
- `lib/spacetime/generated/player_character.dart:10, 36` · `lib/auth/cyborg_kind.dart:39-40, 49-53` — 서버 `kind`·`CyborgKind.design` getter는 **이미 준비**.
- `lib/game/level/level_map.dart:196-212` — `nearestWalkable` 반경 24; 실패 시 **`spawn.clone()` 반환**.
- `lib/game/iso.dart:24-27` · `player.dart:55` — 월드 1000타일; 대각 전장 이론상 \(1000\sqrt{2}/3.6 ≈ 6.5\)분.
- `lib/auth/cyborg_portrait.dart:121` · `lib/game/ui/cyborg_preview.dart:53-60` — 동일 `drawBody`이나 **`time` 미전달**(코어 pulse 고정); 인게임만 `time: _animTime`.
- `lib/game/entities/enemy.dart:412` — 적 `facesRight` + `scale(-1)` 2방향.
- `GAME-DESIGN.md:172-175, 546-554` — 문서 4.3은 구 8방향 모델; 조작표에 클릭 이동 없음.
- `test/cyborg_render_snapshot_test.dart:77-85, 125-131` — 8방위 **표본**; 연속각 렌더러 명시.
- `assets/` — 캐릭터 이미지 없음(오디오만). 스프라이트 시트 비도입 전제와 일치.
- `lib/game/action_rpg_game.dart:142, 230-233` — `_maxActiveMonsters = 140`; 줌 clamp 0.55~1.6.

---

## 3. 상세 분석

### 3.1 범위

| 요구 | 상태 | 경계 |
|---|---|---|
| 남/여 더 멋있게 | 1차 디테일 레이어 있음, “화려/예쁨” 미달 | `CyborgDesign` + `CyborgRenderer` (+ 선택→스폰 파이프) |
| 클릭 이동 | 구현됨, 경로탐색·타겟 탭 없음 | `click_move` + `Player` + `movePlayerToWorldPoint` |
| 256방향 | **각도 입력 충족 / 형태 충실 부분** | 런타임 드로잉 근사; 캐시 양자화 미도입 |

멀티 동기화는 전제상 없음. 렌더 비용은 **화면 캐릭터 30명** 기준으로 본다.

### 3.2 방향 — “256” 판정 (이중 층)

**사실(코드)**  
- 입력: `facing` → `facingYaw` → `drawBody(yaw:)` 실수. 양자화 없음.  
- 기하: 둘레 매개각 `t` + `R_yaw` 투영. 팔·다리·어깨는 depth 정렬.  
- `quantizeYaw`는 미연결.  
- 캐릭터는 여전히 **빌보드 배치**(화면 정면 세움, `GAME-DESIGN` 4.3 상반). 바뀐 것은 좌우 flip 압축이 아니라 **yaw 투영 실루엣**.

| 층 | 연속성 | 판정 |
|---|---|---|
| 각도 샘플링 | 실수 무한 | 256 이상 **충족** |
| 몸통 폭 | `halfWidth(yaw)` | 측면 얇아짐 **동작** |
| 부위 위치·가시성 | `project` + depth 게이트 | 앞/뒤 전환 **동작** |
| 부위 **형태** | 헬멧/비무기팔/다리 자체 메시 없음 | 전이에서 **판때기감** |

사람이 원한 것은 숫자 256이 아니라 **회전 시 계단 없는 부드러움**이다.  
- 각도·위치·폭·가림 층은 이미 연속 → “8방향 스프라이트 계단” 문제는 **해결**.  
- 형태 층은 헬멧이 정면 도형 유지, 비무기 팔이 세로 박스, 다리가 무릎 없이 사다리꼴 → 정면↔측면↔후면에서 **카드보드 회전**으로 읽힐 수 있음.  
- 1차의 “전체 8~16감 빌보드”는 **과한 단일화**. 더 정확히는: **연속 각을 먹는 타원기둥 실루엣 + 일부 부위의 고정 2D 프로파일**.

**사람 눈 한계** (`[추측]`, 본 저장소 실측 아님): 아틀라스 기준 8=계단, 16=허용, 32~64=연속 착시. 즉시 모드 연속 드로잉이면 각도 밀도는 이미 충분; 남는 것은 **근사 형태**.

**어색한 부위 (코드 근거)**

1. **머리** — RRect 중심 고정, 폭만 `headWidthScale`. 바이저만 `project(0)`으로 이동.  
2. **비무기 팔** — 세로 RRect + phase 세로 오프셋만.  
3. **무기 팔** — `lean ∝ sin(yaw)` 수준; 손 마디는 있으나 측면 무기 실루엣 빈약.  
4. **다리** — 보폭이 주로 화면 y, 측면일 때 x 흘림; 무릎 관절 없음.  
5. **포니테일** — 항상 한쪽으로 휜 베지어.  
6. **등 블레이드** — `depth<=0`이면 통째 생략 → 측면 전이에서 툭 사라짐.  
7. **안테나** — 앵커 `-π/2` 고정 규칙.

### 3.3 비주얼 — “화려하다”고 할 수 있는가

**강점**  
- 밝은 배경용 짙은 장갑 + accent 림 스트로크(blur 아님 → 상대적으로 저렴).  
- 코어 3겹+방열 링, 바이저 블러+주사선, 부츠 밑창 발광, 인게임 `time` 맥동.  
- 남/여 **골격·임플란트·헤어** 차등(오목/볼록 허리, 포니테일 vs 네이프 케이블).

**부족(장식≠읽힘)**  

| 문제 | 32~64px | 근거 |
|---|---|---|
| 관절 마디 불균일 | 비무기 팔·다리가 막대 붕괴 | 무기 팔만 손 하이라이트 |
| 무기/홀스터 3px | 원거리 식별 약함 | `_drawHolsteredBlade` |
| 포니테일 1.2px 스트로크 | 소형에서 노이즈 또는 소실 | `_drawPonytail` |
| 프리뷰/초상 `time` 없음 | 코어 pulse 정지 | portrait/preview `drawBody` |
| 남/여 색 동일 | **의도** — 아군 청록 유지 | `cyborg_design` 196-198 |

줌 0.55 × `totalHeight` 102~108 → 화면 높이 대략 56~59px대 → “32~64px 생존”이 실전 조건.  
**발광을 더 얹는 개선은 blur 비용만 키운다.** 어깨-허리-골반 대비, 무릎/손 1~2px, 측면 팔 두께 프로필이 이득.

### 3.4 클릭 이동

**흐름**  
탭(월드 최하층) → `movePlayerToWorldPoint` → `nearestWalkable` → `moveTo` → 직선 `_steerToTarget` → 축 분리 슬라이딩 → 진행 없으면 0.35s 포기.  
수동 입력 시 목표 즉시 취소. 조이스틱/액션은 **viewport**라 월드 탭보다 먼저 소비(주석 의도).

| 상황 | 결과 |
|---|---|
| 벽 너머 | 미끄러지다 stuck → 포기. 우회 없음 |
| 1km 원거리 | 3.6타일/s → 장거리 직진 수분; 장애물 밀집 시 중도 포기 |
| 반경 24 안 비보행 | `nearestWalkable`이 **spawn**으로 떨어짐 → 엉뚱한 장거리 목표 가능 |
| 적/파괴물 탭 | 엔티티 `TapCallbacks` 없음 → **그 좌표로 이동** |
| PK | 멀티 미구현; 탭=이동이면 클릭 전투 UX와 충돌 `[설계 공백]` |
| UI 시트 | 시트 `TapCallbacks`로 대체로 안전 |

**로컬 포인트 앤 클릭**에는 통한다. **장거리 오토패스·클릭 전투**에는 통하지 않는다.  
오프라인 메뉴 조작표(`offline_main.dart:73+`)에도 클릭 이동 미기재 — 문서·온보딩 드리프트.

### 3.5 성능 (추정 — 프로파일 실측 아님)

한 캐릭터 `drawBody` 대략:

- 도형: ~40~55회(임플란트 분기).  
- blur: assault 정면 **~5**(부츠2+코어2+바이저1) + 그림자 1 → **~6**; 레일 시 +1.  
- `clipPath`/`clipRRect`: 흉갑 하이라이트·바이저 주사선.  
- 본체 `saveLayer` 거의 없음(대시 고스트·비선택 초상에서 사용).

| 규모 | blur/프레임 | 거친 예산 `[추측]` |
|---|---|---|
| 1명 | ~6 | 0.3~1.5 ms (데스크톱), 모바일 상위 |
| 30명 | ~180 + 도형 1200+ | blur만으로 수~십수 ms → **60fps 위험** |
| +적 140 상한 | 적 자체 blur 다수 | 캐릭터 고급화와 충돌 |

`Picture` 캐시 메모리(대략 70×120 RGBA ≈ 33.6 KB/장):

| 구성 | 장수 | 메모리 |
|---|---|---|
| 32방향 × 4보행 × 2프레임 | 256 | ~8.6 MB |
| 64 × 4 × 2 | 512 | ~17 MB |
| 256 × 8 × 2 | 4096 | ~138 MB + 워밍업 |

**권장 캐시 밀도 32~64.** 256 아틀라스는 과다. 연속 드로잉 유지 + **LOD(근접 full / 원거리 no-blur)** 가 30명 예산에 맞다.

### 3.6 SSOT

- 렌더 SSOT(`CyborgDesign` + `CyborgRenderer`)는 선택·프리뷰·Player 그리기 경로에서 **코드상 통일**(`_renderBody` 잔존 없음).  
- **데이터 파이프 단절**: `PlayerCharacter.kind` → `CyborgKind.design`이 `Player(...)`에 안 들어감.  
- `player.dart:33-34` 주석(“선택 화면에서 고른 몸이 그대로 넘어온다”)은 **현재 거짓**.  
- `GAME-DESIGN` 4.3·조작표는 코드보다 뒤처짐.

---

## 4. 리스크 · 함정

- **여성 선택 → 인게임 남성 몸**: “비주얼이 안 예뻐졌다”의 1순위 오인 가능.  
- **blur 중첩으로 화려함 해결** → 30인·적 140과 프레임 붕괴.  
- **직선 클릭을 Diablo식 오토패스로 오해** → 벽 stuck이 버그로 보임.  
- **`nearestWalkable` → spawn 폴백** → 허공/두꺼운 벽 탭 시 의도치 않은 장거리 목표.  
- **모든 월드 탭=이동** → 향후 클릭 전투·루팅·PK와 충돌.  
- **문서/테스트 드리프트**: GAME-DESIGN 구 8방향; 스냅샷 8방위만 → 중간각 회귀 약함.  
- **적 2방향 vs 플레이어 연속**: 화면 이질감(플레이어 범위 밖일 수 있음).  
- **색으로 남/여 구분** 제안은 아군 식별 규칙(의도 주석)과 충돌.  
- **SSOT 깨고 `player`에 드로잉 재도입** 유혹 — 1차 통일 후퇴.

---

## 5. 권고안

| 순위 | 권고 | 범위 | 근거 | 리스크 |
|---|---|---|---|---|
| 1 | 출격 시 `CyborgKind.fromId(character.kind).design`을 `Player`에 전달 (`ActionRpgGame`/`_spawnPlayer`, `main.dart`). 오프라인은 토글 또는 기본 assault. 주석과 일치시키기. | 데이터 파이프 | `main.dart:64-82`, `action_rpg_game.dart:225-228`, `player.dart:26-35`, `cyborg_kind.dart:39-40` | kind 누락 시 fallback |
| 2 | 소형 실루엣 강화(**blur 추가 금지 우선**): 비무기 팔 손/무릎 1~2px, 허리 pinch 대비, 측면 팔 두께 프로필, 홀스터 실루엣 굵기. 변경은 `CyborgDesign`+`CyborgRenderer`만. 색 분기 금지. | 아트 읽힘 | `cyborg_design` 196-198, `_drawArm`/`_drawLegs` | 과도 디테일→64px 노이즈 |
| 3 | 방향감 형태 업그레이드(스프라이트 금지, 각도는 연속 유지): (A) 머리/흉갑 yaw 의존 비대칭 프로파일, (B) 포니테일 `sign(sin(yaw))` 대칭, (C) 무기팔 짧은 에너지 엣지. | 렌더 근사 | `_drawHead`, `_drawPonytail`, `_drawArm` | 복잡도↑; 스냅샷 16+ 방위 회귀 |
| 4 | LOD: 내 캐릭터 full / 타인·원거리 no-blur 단순 실루엣. blur 상한 캐릭터당 1~2. | 성능·MMORPG | blur×30, `_maxActiveMonsters` 140 | 원거리 밋밋함 |
| 5 | 클릭 실전화: (a) `nearestWalkable` 실패 시 spawn 대신 **탭 무시 또는 현재 위치 유지**, (b) 적 탭 시 접근+타겟 플래그, (c) 선택적 단거리 A*/웨이포인트 3점. 키보드 우선 유지. | 조작 | `level_map.dart:196-212`, `player.dart:287-337` | A*는 청크 제한 필요 |
| 6 | 캐시 도입 시에만 `quantizeYaw(32\|64)` + `Picture` LRU. 256 캐시 비권장. 워밍업은 유휴 프레임. | 성능 옵션 | `iso.dart:114-123` | 보행 위상 캐시 폭발 |
| 7 | 문서·스냅샷: GAME-DESIGN 4.3을 연속 yaw 모델로; 조작표·오프라인 메뉴에 클릭 이동; 스냅샷 16~32 yaw + stuck/nearestWalkable 단위 테스트. | 검증 | `GAME-DESIGN.md:172`, `cyborg_render_snapshot_test.dart` | 문서만 고치면 코드 이슈 잔존 |

**하지 말 것**: 스프라이트 시트, 팔레트 하드코딩, WASD/조이스틱 제거, Unity/Godot 이전, 남/여 accent 색 분리(아군 식별 의도 깨짐).

---

## 6. 불확실 · 미확인

- **실기기 프레임 타임**: blur/ms는 추정. DevTools Timeline 실측 없음(읽기 전용 분석).  
- **Flame 탭 히트**: `IsoEntity`가 size 없이 이벤트를 가로채는지 런타임 미확인. 코드상 `TapCallbacks`는 UI·`ClickMoveLayer` 위주.  
- **온라인 kind 실값 샘플**: 생성·표시 경로만 확인; DB 샘플 미확인.  
- **사람 눈 방향 구분 한계**: 문헌/실측 없이 `[추측]`. 미세 yaw PNG 시퀀스로 가르면 됨.  
- **PK·다른 PC 엔티티**: 실시간 멀티 미구현 → 탭-PK는 설계 공백.  
- **동시 편집**: 인용은 본 턴에서 읽은 코드 기준.

**살아남은 이중 결론**  
- (A) 각도 파이프는 이미 “256+ 연속”이다.  
- (B) 시각 모델은 “연속 각 + 타원 폭/가림”까지는 성공했고, **일부 부위의 고정 2D 프로파일** 때문에 측면 전이에서 방향감이 약하다.  
결정적 검증: 미세 `yaw` 시퀀스에서 팔/머리 **윤곽이 변형**되는가 vs **폭·가시성 플래그만** 바뀌는가.

---

## 7. 자기 비판으로 바로잡은 것

- ❌ 철회: “시각 전체가 8~16감 빌보드” — `halfWidth`·`project`·depth 정렬은 연속(`cyborg_renderer.dart:817-839`). 빌보드는 **배치 방식**(의도)이지 8방향 압축이 아님. 형태 프로파일 부족과 각도 연속성을 한 바구니에 묶은 과장.  
- 🔁 수정: “관절·마디가 없다” → 무기 팔에 손 `armorLight` 마디 **이미 있음**(`cyborg_renderer.dart:535-546`). 부족한 쪽은 비무기 팔·무릎.  
- 🔁 수정: “남/여 색 동일 = 비주얼 결함” → **의도된 아군 식별**(`cyborg_design.dart:196-198`). 권고에서 색 분리 금지로 전환.  
- 🔁 수정: blur “정면 5~6”을 코드 위치 5곳 + 다리 루프 실행 횟수로 **재계수**; 림 스트로크는 blur가 아님(비용 분리).  
- ➕ 추가: `nearestWalkable` 실패 시 **`spawn` 폴백**(`level_map.dart:212`) — 클릭 이동 UX의 숨은 함정. 1차 미기술.  
- ➕ 추가: `Player` 주석 “고른 몸이 넘어온다”(`player.dart:33-34`) vs `_spawnPlayer`/`main` 미연결 — **주석 허위**까지 명시.  
- ➕ 추가: `cyborg_preview`도 `time` 미전달(`cyborg_preview.dart:53-60`) — portrait만이 아님.  
- ➕ 추가: `CyborgKind.design` getter·`PlayerCharacter.kind`는 이미 존재 — 파이프는 “설계 부재”가 아니라 **연결 누락**.  
- 🔁 수정: 1차 권고 2순위의 “화려함”을 발광이 아닌 **실루엣 읽힘**으로 유지하되, 색 변경 유혹을 명시 차단.
