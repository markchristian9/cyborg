# 사운드 에셋 출처 및 라이선스

이 게임의 모든 사운드는 **Kenney** ([kenney.nl](https://kenney.nl))가 제작해
**CC0 1.0 Universal(퍼블릭 도메인 헌정)** 로 공개한 무료 에셋이다.

> CC0 는 저작권자가 권리를 완전히 포기한 것으로, 상업적 이용을 포함해 어떤
> 용도로든 자유롭게 사용·수정·재배포할 수 있으며 저작자 표시 의무도 없다.
> 그럼에도 이 문서를 남기는 것은 출처를 명확히 하고, 나중에 에셋을 교체하거나
> 추가할 때 어디서 가져왔는지 추적하기 위해서다.

전문: <https://creativecommons.org/publicdomain/zero/1.0/>

## 사용한 팩

| 팩 | 원본 | 내려받은 곳 |
| --- | --- | --- |
| Sci-Fi Sounds | <https://kenney.nl/assets/sci-fi-sounds> | [Boyquotes/kenney-sci-fi-sounds-for-godot](https://github.com/Boyquotes/kenney-sci-fi-sounds-for-godot) |
| Impact Sounds | <https://kenney.nl/assets/impact-sounds> | [Boyquotes/kenney-impact-sounds-for-godot](https://github.com/Boyquotes/kenney-impact-sounds-for-godot) |
| Interface Sounds | <https://kenney.nl/assets/interface-sounds> | [Calinou/kenney-interface-sounds](https://github.com/Calinou/kenney-interface-sounds) |
| Music Jingles | <https://kenney.nl/assets/music-jingles> | [Boyquotes/kenney-music-jingles-for-godot](https://github.com/Boyquotes/kenney-music-jingles-for-godot) |

## 변환

- **효과음**(`sfx/`): 원본 `.ogg`/`.wav` → **모노 44.1kHz 16-bit WAV**.
  iOS·macOS 의 네이티브 플레이어가 ogg 를 재생하지 못하므로 모든 플랫폼에서
  동작하는 WAV 로 통일했다. 게임 효과음은 모노가 표준이고 용량도 절반이다.
- **징글**(`music/levelup.wav`, `music/game_over.wav`): 스테레오 유지, WAV.
- **앰비언스**(`music/ambience_factory.mp3`): `space_engine_low_000` 을 베이스로
  `engine_circular_002` 를 낮게 겹치고, 페이드 구간을 잘라낸 뒤 크로스페이드로
  이어 붙여 25초 무한 루프로 만들었다. 길이 때문에 MP3 로 인코딩했다.

## 파일별 원본 대응표

### 근접 전투

| 게임 에셋 | 원본 파일 | 팩 |
| --- | --- | --- |
| `blade_swing_0/1/2` | `force_field_000/002/003` | Sci-Fi |
| `blade_swing_heavy` | `force_field_004` | Sci-Fi |
| `melee_hit_0/1/2` | `impact_metal_light_000/002/004` | Impact |
| `melee_crit` | `impact_metal_heavy_000` | Impact |

### 원거리 전투

| 게임 에셋 | 원본 파일 | 팩 |
| --- | --- | --- |
| `plasma_shot_0/1/2` | `laser_small_000/002/004` | Sci-Fi |
| `enemy_shot_0/1` | `laser_retro_000/003` | Sci-Fi |
| `boss_shot` | `laser_large_002` | Sci-Fi |
| `bolt_impact_0/1` | `impact_metal_001/003` | Sci-Fi |

### 이동

| 게임 에셋 | 원본 파일 | 팩 |
| --- | --- | --- |
| `dash_0/1` | `thruster_fire_000/002` | Sci-Fi |
| `step_0`~`step_3` | `footstep_concrete_000`~`003` | Impact |

### 피격 / 파괴

| 게임 에셋 | 원본 파일 | 팩 |
| --- | --- | --- |
| `player_hurt_0/1` | `impact_punch_medium_000/002` | Impact |
| `player_death` | `low_frequency_explosion_000` | Sci-Fi |
| `robot_hit_0/1/2` | `impact_metal_000/002/004` | Sci-Fi |
| `explosion_0/1/2` | `explosion_crunch_000/002/004` | Sci-Fi |
| `explosion_boss` | `low_frequency_explosion_001` | Sci-Fi |

### 로봇 AI

| 게임 에셋 | 원본 파일 | 팩 |
| --- | --- | --- |
| `robot_alert_0/1` | `computer_noise_000/002` | Sci-Fi |
| `robot_charge` | `force_field_001` | Sci-Fi |

### 지형 / 구조물

| 게임 에셋 | 원본 파일 | 팩 |
| --- | --- | --- |
| `hazard_burn` | `slime_000` | Sci-Fi |
| `crate_hit_0/1` | `impact_wood_light_000/002` | Impact |
| `crate_break` | `impact_wood_heavy_000` | Impact |

### 아이템 / UI / 음악

| 게임 에셋 | 원본 파일 | 팩 |
| --- | --- | --- |
| `pickup_health` | `confirmation_001` | Interface |
| `pickup_energy` | `bong_001` | Interface |
| `pickup_chip` | `confirmation_003` | Interface |
| `ui_click` | `click_001` | Interface |
| `ui_error` | `error_002` | Interface |
| `levelup` | `Steel jingles/jingles_steel_2` (상승 멜로디) | Music Jingles |
| `game_over` | `Steel jingles/jingles_steel_1` (하강 멜로디) | Music Jingles |
| `ambience_factory` | `space_engine_low_000` + `engine_circular_002` | Sci-Fi |

## 에셋을 추가하거나 바꿀 때

1. 파일을 `assets/audio/sfx/` (또는 `music/`) 에 위 규칙대로 변환해 넣는다.
   ```
   ffmpeg -i 원본.ogg -ac 1 -ar 44100 -c:a pcm_s16le assets/audio/sfx/이름.wav
   ```
2. `lib/game/audio/game_audio.dart` 의 `Sfx` enum 과 스펙 표에 항목을 추가한다.
3. 게임을 켜지 않고 소리만 확인하려면 점검용 진입점을 쓴다. 모든 `Sfx` 를
   차례로 재생하고 초기화 로그를 보여 준다.
   ```
   flutter run -d macos -t tool/audio_check.dart
   ```
4. 새 팩을 쓴다면 이 문서에 출처와 라이선스를 반드시 남긴다. CC0 나 그에 준하는
   라이선스가 아니면 상업적 배포에서 문제가 될 수 있다.
