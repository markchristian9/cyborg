import 'dart:async';
import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

/// 게임에서 재생하는 효과음의 종류.
///
/// 각 항목의 실제 파일과 재생 특성은 [GameAudio] 의 스펙 표에 정의되어 있다.
enum Sfx {
  /// 에너지 블레이드 스윙(1·2 타).
  bladeSwing,

  /// 콤보 마무리 강타 스윙.
  bladeSwingHeavy,

  /// 근접 공격 명중.
  meleeHit,

  /// 콤보 마무리 치명타 명중.
  meleeCrit,

  /// 플레이어의 플라즈마 볼트 발사.
  plasmaShot,

  /// 로봇의 플라즈마 발사.
  enemyShot,

  /// 지휘 유닛(보스)의 발사.
  bossShot,

  /// 발사체가 벽이나 대상에 터질 때.
  boltImpact,

  /// 회피 대시(스러스터 점화).
  dash,

  /// 발소리.
  step,

  /// 플레이어 피격.
  playerHurt,

  /// 플레이어 사망.
  playerDeath,

  /// 로봇 장갑 피격.
  robotHit,

  /// 로봇이 플레이어를 발견했을 때의 경보음.
  robotAlert,

  /// 로봇의 공격 예비 동작(충전).
  robotCharge,

  /// 로봇 파괴 폭발.
  explosion,

  /// 보스 파괴 대폭발.
  explosionBoss,

  /// 냉각 폐기물을 밟았을 때.
  hazardBurn,

  /// 보급 상자 타격.
  crateHit,

  /// 보급 상자 파괴.
  crateBreak,

  /// 체력 보급품 획득.
  pickupHealth,

  /// 에너지 셀 획득.
  pickupEnergy,

  /// 데이터 칩 획득.
  pickupChip,

  /// UI 클릭.
  uiClick,

  /// 조작 불가(에너지 부족 등) 알림.
  uiError,

  /// 레벨업 징글.
  levelUp,

  /// 게임 오버 징글.
  gameOver,
}

/// 배경으로 흐르는 음악 트랙.
enum MusicTrack {
  /// 기본 전투 테마. 로봇 전장의 인더스트리얼 비트(167 BPM).
  battle,

  /// 잠행·탐색 구간에 어울리는 느린 테마(125 BPM).
  prowl,

  /// 음악 없이 로봇 공장의 저주파 험만 흐르는 앰비언스.
  ambience,
}

/// 사운드 하나의 재생 특성.
class _SfxSpec {
  const _SfxSpec(
    this.files, {
    this.volume = 1.0,
    this.throttleMs = 0,
    this.maxPlayers = 2,
    this.volumeJitter = 0.12,
    this.music = false,
  });

  /// 재생할 때마다 무작위로 하나가 선택되는 배리에이션 목록.
  final List<String> files;

  /// 이 사운드의 기본 볼륨.
  final double volume;

  /// 같은 사운드의 최소 재생 간격. 짧은 시간에 몰려 찢어지는 것을 막는다.
  final int throttleMs;

  /// 동시에 겹쳐 재생할 수 있는 최대 개수.
  final int maxPlayers;

  /// 반복 재생 시 기계적으로 들리지 않도록 볼륨을 흔드는 폭(0~1).
  final double volumeJitter;

  /// true 면 효과음이 아니라 음악 볼륨을 따른다.
  final bool music;
}

/// 사운드 에셋의 로딩과 재생을 담당하는 전역 오디오 매니저.
///
/// 게임 로직 어디에서든 `GameAudio.play(Sfx.meleeHit, at: grid)` 한 줄로
/// 소리를 낼 수 있도록 정적 API 로 구성했다. 재생 지연을 없애기 위해 모든
/// 사운드를 [AudioPool] 에 미리 올려 두고, [listener] 로부터의 거리에 따라
/// 볼륨을 감쇠시켜 화면 밖의 전투가 시끄럽지 않도록 한다.
///
/// 배경음악은 [playMusic] 으로 켜고 끈다. 효과음과 달리 한 번에 한 트랙만
/// 흐르며, 트랙을 바꾸면 이전 트랙은 자동으로 멈춘다. 게임이 스스로 트랙을
/// 트는 일은 없다 — 부르지 않으면 배경음악은 흐르지 않는다.
///
/// [init] 을 부르지 않았거나 플랫폼이 오디오를 지원하지 않으면 모든 재생
/// 요청은 조용히 무시된다. 소리 때문에 게임이 멈추는 일은 없다.
class GameAudio {
  GameAudio._();

  static const String _sfxDir = 'sfx/';
  static const String _musicDir = 'music/';

  /// 이 거리(타일)를 넘어선 곳의 소리는 들리지 않는다.
  static const double hearingRange = 20;

  /// 트랙별 파일과 상대 볼륨.
  ///
  /// 트랙마다 체감 음량이 달라 [musicVolume] 만으로는 균형이 맞지 않으므로
  /// 여기서 한 번 더 보정한다.
  static const Map<MusicTrack, ({String file, double gain})> _tracks = {
    MusicTrack.battle: (file: 'bgm_battle.mp3', gain: 1.0),
    MusicTrack.prowl: (file: 'bgm_prowl.mp3', gain: 1.0),
    MusicTrack.ambience: (file: 'ambience_factory.mp3', gain: 0.85),
  };

  static const Map<Sfx, _SfxSpec> _specs = {
    // ── 근접 전투 ────────────────────────────────────────────────
    Sfx.bladeSwing: _SfxSpec(
      ['blade_swing_0', 'blade_swing_1', 'blade_swing_2'],
      volume: 0.5,
      throttleMs: 60,
      maxPlayers: 3,
    ),
    Sfx.bladeSwingHeavy: _SfxSpec(
      ['blade_swing_heavy'],
      volume: 0.7,
      throttleMs: 60,
    ),
    Sfx.meleeHit: _SfxSpec(
      ['melee_hit_0', 'melee_hit_1', 'melee_hit_2'],
      volume: 0.7,
      throttleMs: 25,
      maxPlayers: 4,
    ),
    Sfx.meleeCrit: _SfxSpec(
      ['melee_crit'],
      volume: 0.9,
      throttleMs: 60,
    ),
    // ── 원거리 전투 ──────────────────────────────────────────────
    Sfx.plasmaShot: _SfxSpec(
      ['plasma_shot_0', 'plasma_shot_1', 'plasma_shot_2'],
      volume: 0.45,
      throttleMs: 40,
      maxPlayers: 4,
    ),
    Sfx.enemyShot: _SfxSpec(
      ['enemy_shot_0', 'enemy_shot_1'],
      volume: 0.4,
      throttleMs: 40,
      maxPlayers: 4,
    ),
    Sfx.bossShot: _SfxSpec(
      ['boss_shot'],
      volume: 0.55,
      throttleMs: 50,
      maxPlayers: 3,
    ),
    Sfx.boltImpact: _SfxSpec(
      ['bolt_impact_0', 'bolt_impact_1'],
      volume: 0.4,
      throttleMs: 25,
      maxPlayers: 4,
    ),
    // ── 이동 ─────────────────────────────────────────────────────
    Sfx.dash: _SfxSpec(
      ['dash_0', 'dash_1'],
      volume: 0.55,
      throttleMs: 80,
    ),
    Sfx.step: _SfxSpec(
      ['step_0', 'step_1', 'step_2', 'step_3'],
      volume: 0.25,
      throttleMs: 100,
      maxPlayers: 3,
      volumeJitter: 0.3,
    ),
    // ── 피격 / 파괴 ──────────────────────────────────────────────
    Sfx.playerHurt: _SfxSpec(
      ['player_hurt_0', 'player_hurt_1'],
      volume: 0.8,
      throttleMs: 150,
    ),
    Sfx.playerDeath: _SfxSpec(
      ['player_death'],
      volume: 1.0,
      maxPlayers: 1,
      volumeJitter: 0,
    ),
    Sfx.robotHit: _SfxSpec(
      ['robot_hit_0', 'robot_hit_1', 'robot_hit_2'],
      volume: 0.45,
      throttleMs: 25,
      maxPlayers: 4,
    ),
    Sfx.explosion: _SfxSpec(
      ['explosion_0', 'explosion_1', 'explosion_2'],
      volume: 0.7,
      throttleMs: 40,
      maxPlayers: 4,
    ),
    Sfx.explosionBoss: _SfxSpec(
      ['explosion_boss'],
      volume: 1.0,
      maxPlayers: 1,
      volumeJitter: 0,
    ),
    // ── 로봇 AI ──────────────────────────────────────────────────
    Sfx.robotAlert: _SfxSpec(
      ['robot_alert_0', 'robot_alert_1'],
      volume: 0.4,
      throttleMs: 350,
    ),
    Sfx.robotCharge: _SfxSpec(
      ['robot_charge'],
      volume: 0.35,
      throttleMs: 180,
      maxPlayers: 3,
    ),
    // ── 지형 / 구조물 ────────────────────────────────────────────
    Sfx.hazardBurn: _SfxSpec(
      ['hazard_burn'],
      volume: 0.45,
      throttleMs: 400,
      maxPlayers: 1,
    ),
    Sfx.crateHit: _SfxSpec(
      ['crate_hit_0', 'crate_hit_1'],
      volume: 0.5,
      throttleMs: 40,
      maxPlayers: 3,
    ),
    Sfx.crateBreak: _SfxSpec(
      ['crate_break'],
      volume: 0.75,
    ),
    // ── 아이템 / UI ──────────────────────────────────────────────
    Sfx.pickupHealth: _SfxSpec(['pickup_health'], volume: 0.55),
    Sfx.pickupEnergy: _SfxSpec(['pickup_energy'], volume: 0.5),
    Sfx.pickupChip: _SfxSpec(
      ['pickup_chip'],
      volume: 0.4,
      throttleMs: 40,
      maxPlayers: 3,
    ),
    Sfx.uiClick: _SfxSpec(['ui_click'], volume: 0.6, throttleMs: 40),
    Sfx.uiError: _SfxSpec(
      ['ui_error'],
      volume: 0.45,
      throttleMs: 250,
      maxPlayers: 1,
    ),
    // ── 징글(음악 볼륨을 따른다) ─────────────────────────────────
    Sfx.levelUp: _SfxSpec(
      ['levelup'],
      volume: 0.9,
      maxPlayers: 1,
      volumeJitter: 0,
      music: true,
    ),
    Sfx.gameOver: _SfxSpec(
      ['game_over'],
      volume: 0.9,
      maxPlayers: 1,
      volumeJitter: 0,
      music: true,
    ),
  };

  static final math.Random _rng = math.Random();
  static final Stopwatch _clock = Stopwatch()..start();
  static final Map<String, AudioPool> _pools = {};
  static final Map<Sfx, int> _lastPlayedMs = {};

  static bool _ready = false;
  static MusicTrack? _currentTrack;

  /// 효과음 전체 볼륨(0~1).
  static double sfxVolume = 0.85;

  /// 배경음·징글 전체 볼륨(0~1).
  static double musicVolume = 0.5;

  /// 오디오 시스템이 사용할 준비가 되었는지 여부.
  static bool get isReady => _ready;

  /// 지금 흐르고 있는 배경음악. 아무것도 재생 중이 아니면 null.
  static MusicTrack? get currentTrack => _currentTrack;

  /// 배경음악이 재생 중인지 여부.
  static bool get isMusicPlaying => _currentTrack != null;

  /// 거리 감쇠의 기준이 되는 청취 위치(보통 플레이어의 그리드 좌표).
  ///
  /// null 이면 감쇠 없이 전부 같은 볼륨으로 들린다.
  static Vector2? listener;

  static bool _muted = false;

  /// 음소거 여부. 켜면 재생 중인 배경음도 함께 멈춘다.
  static bool get muted => _muted;

  static set muted(bool value) {
    if (_muted == value) return;
    _muted = value;
    // 재생 중인 트랙이 없을 때 bgm 을 건드리면 플랫폼에 따라 예외가 난다.
    if (_currentTrack == null) return;
    unawaited(_guard(value ? FlameAudio.bgm.pause() : FlameAudio.bgm.resume()));
  }

  /// 오디오 실패가 게임 로직으로 번지지 않도록 삼킨다.
  static Future<void> _guard(Future<void> action) {
    return action.catchError((Object error) {
      debugPrint('GameAudio: 재생 중 오류 — $error');
    });
  }

  /// 모든 사운드를 메모리에 올리고 재생 준비를 마친다.
  ///
  /// 게임 로딩 단계에서 한 번만 부르면 된다. 실패해도 예외를 던지지 않고
  /// 무음 상태로 남는다.
  static Future<void> init() async {
    if (_ready) return;
    try {
      // 같은 파일을 여러 사운드가 공유할 수 있으므로 가장 큰 요구치로 맞춘다.
      final needed = <String, int>{};
      for (final spec in _specs.values) {
        for (final name in spec.files) {
          final path = '${spec.music ? _musicDir : _sfxDir}$name.wav';
          needed[path] = math.max(needed[path] ?? 1, spec.maxPlayers);
        }
      }

      // 배경음악도 함께 올려 두어야 트랙을 바꿀 때 끊기지 않는다.
      await FlameAudio.audioCache.loadAll([
        ...needed.keys,
        for (final track in _tracks.values) '$_musicDir${track.file}',
      ]);
      await Future.wait(
        needed.entries.map((entry) async {
          _pools[entry.key] = await FlameAudio.createPool(
            entry.key,
            maxPlayers: entry.value,
          );
        }),
      );
      await FlameAudio.bgm.initialize();
      _ready = true;
    } catch (error, stack) {
      // 오디오 장치가 없는 환경에서도 게임 자체는 계속 돌아가야 한다.
      _ready = false;
      debugPrint('GameAudio 초기화 실패 — 무음으로 진행합니다: $error');
      debugPrintStack(stackTrace: stack);
    }
  }

  /// 효과음 하나를 재생한다.
  ///
  /// [at] 을 넘기면 [listener] 로부터의 거리만큼 볼륨이 줄어들고, 청취
  /// 범위를 벗어나면 아예 재생하지 않는다. [volumeScale] 로 상황에 따라
  /// 세기를 조절할 수 있다(예: 약한 타격은 작게).
  static void play(Sfx sfx, {Vector2? at, double volumeScale = 1.0}) {
    if (!_ready || _muted) return;

    final spec = _specs[sfx];
    if (spec == null) return;

    // 같은 소리가 한꺼번에 몰려 찢어지는 것을 막는다.
    if (spec.throttleMs > 0) {
      final now = _clock.elapsedMilliseconds;
      final last = _lastPlayedMs[sfx];
      if (last != null && now - last < spec.throttleMs) return;
      _lastPlayedMs[sfx] = now;
    }

    final falloff = _falloffAt(at);
    if (falloff <= 0) return;

    final jitter = 1 - _rng.nextDouble() * spec.volumeJitter;
    final master = spec.music ? musicVolume : sfxVolume;
    final volume =
        (spec.volume * volumeScale * falloff * jitter * master).clamp(0.0, 1.0);
    if (volume < 0.01) return;

    final name = spec.files[_rng.nextInt(spec.files.length)];
    final pool = _pools['${spec.music ? _musicDir : _sfxDir}$name.wav'];
    if (pool == null) return;

    // 게임 루프를 막지 않도록 완료를 기다리지 않는다.
    unawaited(_guard(pool.start(volume: volume)));
  }

  /// 배경음악을 무한 반복으로 재생한다.
  ///
  /// 기본 트랙이라는 것은 없다. 어떤 곡을 틀지는 부르는 쪽이 반드시 정해야
  /// 하며, 아무도 부르지 않으면 게임은 배경음악 없이 굴러간다. 이미 같은
  /// 트랙이 흐르고 있으면 아무 일도 하지 않으므로 매 상태 전환마다 안심하고
  /// 불러도 된다.
  static Future<void> playMusic(MusicTrack track) async {
    if (!_ready || _currentTrack == track) return;
    _currentTrack = track;
    if (_muted) return;
    try {
      await FlameAudio.bgm.play(
        '$_musicDir${_tracks[track]!.file}',
        volume: _trackVolume(track),
      );
    } catch (error) {
      _currentTrack = null;
      debugPrint('배경음악 재생 실패($track): $error');
    }
  }

  /// 배경음악을 멈춘다.
  static Future<void> stopMusic() async {
    if (_currentTrack == null) return;
    _currentTrack = null;
    await _guard(FlameAudio.bgm.stop());
  }

  /// 배경음 볼륨을 바꾸고 재생 중인 트랙에도 즉시 반영한다.
  static Future<void> setMusicVolume(double value) async {
    musicVolume = value.clamp(0.0, 1.0);
    final track = _currentTrack;
    if (track != null && !_muted) {
      await _guard(
        FlameAudio.bgm.audioPlayer.setVolume(_trackVolume(track)),
      );
    }
  }

  /// 앱이 백그라운드로 갈 때처럼 전체 오디오를 잠시 멈춘다.
  static Future<void> pauseAll() async {
    if (_currentTrack != null) await _guard(FlameAudio.bgm.pause());
  }

  /// [pauseAll] 로 멈춘 오디오를 다시 재생한다.
  static Future<void> resumeAll() async {
    if (_currentTrack != null && !_muted) {
      await _guard(FlameAudio.bgm.resume());
    }
  }

  static double _trackVolume(MusicTrack track) =>
      (musicVolume * _tracks[track]!.gain).clamp(0.0, 1.0);

  /// [listener] 로부터의 거리에 따른 볼륨 배율(0~1)을 구한다.
  static double _falloffAt(Vector2? at) {
    final origin = listener;
    if (at == null || origin == null) return 1;
    final distance = (at - origin).length;
    if (distance >= hearingRange) return 0;
    final near = 1 - distance / hearingRange;
    // 제곱해서 가까운 소리는 또렷하게, 먼 소리는 빠르게 잦아들게 한다.
    return near * near;
  }
}
