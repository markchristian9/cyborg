import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio/game_audio.dart';
import 'entities/block.dart';
import 'entities/enemy.dart';
import 'entities/iso_entity.dart';
import 'entities/pickup.dart';
import 'entities/cyborg_design.dart';
import 'entities/player.dart';
import 'entities/projectile.dart';
import 'fx/explosion.dart';
import 'fx/hit_spark.dart';
import 'input/click_move.dart';
import 'iso.dart';
import 'level/ground_layer.dart';
import 'level/level_map.dart';
import 'level/safe_zone.dart';
import 'level/teleport_destinations.dart';
import 'net/game_sync.dart';
import 'net/leaderboard_source.dart';
import 'palette.dart';
import 'systems/auto_hunt.dart';
import 'systems/drop_table.dart';
import 'systems/hit_stop.dart';
import 'systems/inventory.dart';
import 'systems/level_system.dart';
import 'systems/monster_codex.dart';
import 'systems/monster_population.dart';
import 'systems/wave_director.dart';
import 'ui/auto_hunt_control.dart';
import 'ui/character_screen.dart';
import 'ui/hud.dart';
import 'ui/inventory_ui.dart';
import 'ui/leaderboard_screen.dart';
import 'ui/teleport_sheet.dart';
import 'ui/touch_controls.dart';
import 'ui/world_menu.dart';

/// 게임의 진행 상태.
enum GameStatus { ready, playing, paused, gameOver }

/// 오버레이 식별자.
abstract final class Overlays {
  static const mainMenu = 'mainMenu';
  static const pauseMenu = 'pauseMenu';
  static const gameOver = 'gameOver';
  static const levelUp = 'levelUp';
}

/// 2.5D 아이소메트릭 액션 RPG 본체.
class ActionRpgGame extends FlameGame with HasKeyboardHandlerComponents {
  ActionRpgGame({
    this.sync,
    this.onLogout,
    LeaderboardSource? leaderboard,
    int startTotalXp = 0,
    this.design = CyborgDesign.assault,
  })  : leaderboard = leaderboard ?? const EmptyLeaderboardSource(),
        _carriedTotalXp = startTotalXp;

  /// 이번 출격에 쓰는 신체 프레임.
  ///
  /// 캐릭터 선택 화면에서 고른 몸이 여기로 들어와 [Player]까지 전달된다.
  /// 이 값을 넘기지 않으면 선택 화면에서 여성형을 골라도 게임 안에서는
  /// 기본값인 남성형이 나온다 — 실제로 그런 상태였다.
  final CyborgDesign design;

  /// SpacetimeDB 연동(선택). null이면 완전 오프라인으로 동작한다.
  final GameSync? sync;

  /// 월드 순위표의 출처.
  ///
  /// 서버가 없으면 [EmptyLeaderboardSource]가 들어와 메뉴 항목은 그대로 있고
  /// 화면만 "연결되지 않았다"고 알린다. 순위를 못 본다고 게임을 막지는 않는다.
  final LeaderboardSource leaderboard;

  /// 월드 메뉴에서 로그아웃을 선택했을 때 호출된다.
  ///
  /// 계정과 세션은 게임 바깥(앱 셸)의 몫이라 실제 처리는 넘겨받는 쪽이 한다.
  /// null이면 메뉴에 로그아웃 항목이 생기지 않는다.
  final VoidCallback? onLogout;

  late LevelMap map;
  late Player player;
  late WaveDirector _director;
  late Hud _hud;
  late InventoryPanel _inventoryPanel;
  late CharacterScreen _characterScreen;
  late LeaderboardScreen _leaderboardScreen;
  late TeleportSheet _teleportSheet;
  late WorldMenu _worldMenu;
  late AutoHuntButton _autoHuntButton;
  late AutoHuntRadiusButton _autoHuntRadiusUp;
  late AutoHuntRadiusButton _autoHuntRadiusDown;

  /// 이 접속에 쓰는 캐릭터 이름.
  ///
  /// 계정 시스템이 붙기 전까지는 기본 호출부호를 쓴다.
  String characterName = 'UNIT-01';

  /// 새로 만드는 [Player] 에게 물려줄 누적 경험치.
  ///
  /// 처음에는 서버에 저장된 값이고, 그 뒤로는 **직전 몸체가 쌓은 값**이다.
  /// 재시작([restart])은 월드를 새로 짜는 것이지 캐릭터를 초기화하는 것이 아니다 —
  /// 여기에 현재 값을 옮겨 담지 않으면 재시작할 때마다 출격 시점으로 후퇴하고,
  /// 그러면 서버가 뒤로 가는 보고를 버려 순위가 다시 멈춘다.
  int _carriedTotalXp;

  /// 월드 전역에 상주하는 로봇 개체군의 장부.
  late MonsterPopulation population;

  /// 회수한 포션을 담아 두는 가방.
  final Inventory inventory = Inventory();

  /// 지금 월드에 살아 있는 로봇들.
  ///
  /// 🛑 **피해를 줄 수 있는 코드는 이 목록을 직접 `for-in` 하지 말 것.**
  /// [Damageable.applyDamage] 는 대상을 죽일 수 있고, 죽음은 [onEnemyKilled]
  /// 를 타고 여기서 `remove` 로 돌아온다. 순회 도중 그 일이 벌어지면
  /// `ConcurrentModificationError` 가 게임 루프의 `update` 안에서 터져 화면이
  /// 통째로 멈춘다 — 실제로 그렇게 멈췄었다.
  /// 광역 공격처럼 여러 대상을 때려야 하면 [meleeTargets] 가 주는 **스냅샷**을
  /// 쓰거나, 직접 `toList()` 로 복사한 뒤 순회한다.
  final List<Enemy> enemies = [];
  final List<Pickup> pickups = [];

  /// 앵커 주변만 도는 자동 사냥의 상태와 판단을 맡는다.
  ///
  /// 판단만 하고 실행은 [_updateAutoHunt] 가 한다. 좌표와 생사만 콜백으로
  /// 넘기므로 컨트롤러 쪽은 Flame 을 전혀 모른다.
  final AutoHuntController<Enemy> autoHunt = AutoHuntController<Enemy>(
    gridOf: (enemy) => enemy.grid,
    aliveOf: (enemy) => enemy.isAlive,
  );

  /// 청크 키(cy * chunksX + cx) → 그 청크에서 마운트한 구조물들.
  final Map<int, List<BlockComponent>> _loadedBlocks = {};

  /// 지금 살아 움직이는 상주 로봇. 개체 번호로 찾는다.
  final Map<int, Enemy> _activeMonsters = {};

  double _blockStreamTimer = 0;
  double _monsterStreamTimer = 0;

  /// 구조물을 컴포넌트로 유지할 화면 밖 여유(타일 = 미터).
  ///
  /// 높은 데이터 타워는 화면 아래 경계 밖에서도 위로 솟아 보이므로
  /// 시야보다 넉넉히 잡아 둔다.
  static const double _blockStreamMargin = 16;

  /// 상주 로봇을 깨울 반경(미터).
  static const double _monsterActivationRadius = 46;

  /// 이 거리보다 멀어지면 다시 잠재운다. 경계에서 깜빡이지 않도록 활성
  /// 반경보다 넓게 둔다.
  static const double _monsterReleaseRadius = 60;

  /// 동시에 살아 움직일 수 있는 상주 로봇의 상한.
  static const int _maxActiveMonsters = 140;

  GameStatus status = GameStatus.ready;

  // 웨이브 진행
  int waveNumber = 0;
  WavePlan? currentPlan;
  final List<MonsterSpecies> _spawnQueue = [];
  double _spawnTimer = 0;
  bool isIntermission = false;
  double intermissionRemaining = 0;

  // 점수/기록
  int kills = 0;
  int score = 0;
  double survivalTime = 0;

  /// 지금까지 몸체가 파괴되어 안전지대에서 재가동한 횟수.
  int deaths = 0;

  // 연출
  String comboDisplayText = '';
  double comboDisplayTimer = 0;
  double _shakeIntensity = 0;
  double _shakeTimer = 0;
  /// 타격감을 위한 짧은 슬로우모션. 재발동 잠금까지 [HitStop] 이 관리한다.
  final HitStop hitStop = HitStop();

  // 입력
  final Set<LogicalKeyboardKey> _pressedKeys = {};
  JoystickComponent? _joystick;
  final Vector2 _keyboardInput = Vector2.zero();

  /// 다음 웨이브까지의 대기 시간(초).
  static const double intermissionDuration = 5;

  /// 아직 스폰되지 않고 대기 중인 적의 수.
  int get pendingSpawnCount => _spawnQueue.length;

  /// 월드 전역에 남아 있는 로봇 수(멀리 있어 잠들어 있는 개체 포함).
  int get worldMonsterCount => population.aliveCount;

  @override
  Color backgroundColor() => GamePalette.skyLow;

  @override
  Future<void> onLoad() async {
    // 첫 타격에서 소리가 밀리지 않도록 효과음을 미리 올려 둔다.
    await GameAudio.init();

    map = LevelMap.generate();
    population = MonsterPopulation.generate(map);
    _director = WaveDirector(map: map);

    world.add(GroundLayer(map));
    world.add(SafeZoneField(map.safeZone));
    // 빈 땅 클릭을 받아 내는 레이어. 월드 맨 아래에 깔려 UI 가 잡지 않은
    // 탭만 받는다.
    world.add(ClickMoveLayer());
    world.add(MovePathHint());
    world.add(AutoHuntRangeField());

    player = _spawnPlayer();
    world.add(player);

    camera.backdrop = CyberBackdrop();
    camera.viewfinder.zoom = _zoomForSize(size);
    camera.viewfinder.position = _cameraTarget();

    _hud = Hud();
    camera.viewport.add(AtmosphereOverlay());
    camera.viewport.add(_hud);
    _addTouchControls();
    _addTapShields();

    // 1 km² 월드는 통째로 들 수 없다. 주변 청크부터 채워 넣는다.
    _refreshBlockStreaming();
    _refreshMonsterStreaming();

    overlays.add(Overlays.mainMenu);
    pauseEngine();
  }

  /// 물려받은 성장 상태를 채운 새 몸체를 만든다.
  ///
  /// 최초 출격에서는 서버에 저장된 값이고, 재시작에서는 직전 몸체의 값이다.
  Player _spawnPlayer() {
    // 재시작도 이 함수를 거치므로, 여기서 프레임을 넘기면 다시 태어날 때도
    // 고른 몸이 유지된다.
    return Player(grid: map.respawnPoint(), design: design)
      ..restoreProgress(totalXp: _carriedTotalXp);
  }

  double _zoomForSize(Vector2 screenSize) {
    // 세로 기준 약 760px 분량의 월드가 보이도록 맞춘다.
    final zoom = screenSize.y / 760;
    return zoom.clamp(0.55, 1.6);
  }

  @override
  void onGameResize(Vector2 newSize) {
    super.onGameResize(newSize);
    if (isLoaded) {
      camera.viewfinder.zoom = _zoomForSize(newSize);
      _layoutTouchControls();
    }
  }

  // ── 터치 컨트롤 ─────────────────────────────────────────────────────

  void _addTouchControls() {
    final joystick = JoystickComponent(
      knob: JoystickKnob(radius: 26),
      background: JoystickBase(radius: 62),
      margin: const EdgeInsets.only(left: 40, bottom: 40),
      priority: 90,
    );
    _joystick = joystick;
    camera.viewport.add(joystick);

    camera.viewport.addAll([
      ActionButton(
        icon: ActionIcon.blade,
        id: 'melee',
        color: GamePalette.bladeGlow,
        radius: 40,
        onPressed: () => player.tryMelee(),
        position: Vector2.zero(),
        priority: 90,
      ),
      ActionButton(
        icon: ActionIcon.plasma,
        id: 'shoot',
        color: GamePalette.energyFill,
        radius: 32,
        onPressed: () => player.tryShoot(),
        enabledCheck: () => player.mp >= Player.plasmaMpCost,
        position: Vector2.zero(),
        priority: 90,
      ),
      ActionButton(
        icon: ActionIcon.dash,
        id: 'dash',
        color: GamePalette.playerAccent,
        radius: 28,
        onPressed: () => player.tryDash(),
        cooldownRatio: () => player.dashCooldownRatio,
        enabledCheck: () => player.energy >= 20,
        position: Vector2.zero(),
        priority: 90,
      ),
    ]);

    // 자동 사냥 토글과 반경 조절. 세 개를 세로로 세워 액션 버튼 열에 잇는다.
    _autoHuntButton = AutoHuntButton(radius: 32, position: Vector2.zero());
    _autoHuntRadiusUp = AutoHuntRadiusButton(
      deltaMeters: 1,
      position: Vector2.zero(),
    );
    _autoHuntRadiusDown = AutoHuntRadiusButton(
      deltaMeters: -1,
      position: Vector2.zero(),
    );
    camera.viewport.addAll([
      _autoHuntButton,
      _autoHuntRadiusUp,
      _autoHuntRadiusDown,
    ]);

    // 퀵슬롯과 버프 표시는 화면 크기에 맞춰 스스로 자리를 잡는다.
    _inventoryPanel = InventoryPanel();
    _characterScreen = CharacterScreen();
    _leaderboardScreen = LeaderboardScreen(source: leaderboard);
    _teleportSheet = TeleportSheet();
    _worldMenu = WorldMenu(
      entries: [
        WorldMenuEntry(
          label: '캐릭터 정보',
          icon: WorldMenuIcon.character,
          onSelected: openCharacterScreen,
        ),
        WorldMenuEntry(
          label: '리더보드',
          icon: WorldMenuIcon.leaderboard,
          onSelected: openLeaderboard,
        ),
        WorldMenuEntry(
          label: '텔레포트',
          icon: WorldMenuIcon.teleport,
          onSelected: openTeleportSheet,
        ),
        // 계정을 붙이지 않은 오프라인 실행에서는 로그아웃할 것이 없다.
        if (onLogout != null)
          WorldMenuEntry(
            label: '로그아웃',
            icon: WorldMenuIcon.logout,
            danger: true,
            onSelected: requestLogout,
          ),
      ],
    );
    camera.viewport.addAll([
      PotionQuickBar(),
      BuffBar(),
      _worldMenu,
      _inventoryPanel,
      _characterScreen,
      _leaderboardScreen,
      _teleportSheet,
    ]);

    _layoutTouchControls();
  }

  void _layoutTouchControls() {
    for (final child in camera.viewport.children.whereType<ActionButton>()) {
      switch (child.id) {
        case 'melee':
          child.position = Vector2(size.x - 92, size.y - 92);
        case 'shoot':
          child.position = Vector2(size.x - 176, size.y - 74);
        case 'dash':
          child.position = Vector2(size.x - 92, size.y - 188);
      }
    }
    // 자동 사냥은 대시 버튼 위로 이어 세운다. 위가 늘리기, 아래가 줄이기다.
    // 세로가 짧은 창에서 화면 밖으로 밀리지 않도록 위쪽에 하한을 둔다.
    final autoHuntY = math.max(52.0, size.y - 298);
    _autoHuntButton.position = Vector2(size.x - 92, autoHuntY);
    _autoHuntRadiusUp.position = Vector2(size.x - 92, autoHuntY - 52);
    _autoHuntRadiusDown.position = Vector2(size.x - 92, autoHuntY + 52);

    // 월드 메뉴는 우상단 미니맵 바로 아래에 붙인다.
    _worldMenu.position = Vector2(size.x - 18, 168);
    // 퀵슬롯과 버프 표시는 화면 크기에 맞춰 스스로 자리를 잡는다.

    // 탭 차폐막을 조이스틱·HUD 패널 위에 다시 맞춘다.
    for (final shield in camera.viewport.children.whereType<TapShield>()) {
      if (shield.anchor == Anchor.center) {
        // 조이스틱: 좌하단 여백 40 + 배경 반경 62.
        shield.position = Vector2(_joystickRadius + 40, size.y - _joystickRadius - 40);
      }
    }
  }

  /// 가상 조이스틱 배경의 반경. 탭 차폐막 크기를 맞추는 데 쓴다.
  static const double _joystickRadius = 62;

  /// 조이스틱·HUD 위의 탭이 월드로 새지 않도록 차폐막을 덮는다.
  ///
  /// Flame 의 `JoystickComponent` 는 `DragCallbacks` 만 갖고 `Hud` 는 표시
  /// 전용이라, 둘 다 탭을 소비하지 않는다. 그대로 두면 조이스틱을 잡으려다
  /// 놓치거나 체력바를 건드릴 때마다 캐릭터가 그 화면 지점으로 걸어간다.
  void _addTapShields() {
    camera.viewport.addAll([
      // 조이스틱
      TapShield(
        position: Vector2(_joystickRadius + 40, size.y - _joystickRadius - 40),
        size: Vector2.all(_joystickRadius * 2),
        anchor: Anchor.center,
      ),
      // 좌상단 생존 정보 패널(`Hud._renderVitals`의 사각형과 같은 자리).
      TapShield(
        position: Vector2(10, 10),
        size: Vector2(268, 112),
      ),
    ]);
  }

  // ── 게임 루프 ───────────────────────────────────────────────────────

  @override
  void update(double dt) {
    if (status != GameStatus.playing) {
      super.update(dt);
      return;
    }

    // 타격감을 위한 짧은 히트스톱.
    dt = hitStop.advance(dt);

    survivalTime += dt;
    if (comboDisplayTimer > 0) comboDisplayTimer -= dt;

    _applyInput();
    _updateAutoHunt(dt);
    super.update(dt);
    _pruneRemoved();
    _updateWaves(dt);
    _updateCamera(dt);
    _updateStreaming(dt);
    population.tick(dt);
    sync?.tick(dt, this);
  }

  /// 스스로 사라진 컴포넌트를 목록에서 걷어낸다.
  ///
  /// 보급품은 수명이 다하면 콜백 없이 사라지므로 여기서 정리해 주지 않으면
  /// 목록이 계속 불어난다.
  void _pruneRemoved() {
    enemies.removeWhere((enemy) {
      if (!enemy.isRemoved) return false;
      // 사라진 개체를 자동 사냥이 계속 참조하면, 없는 대상을 향해 걷거나
      // 차단 목록이 자라기만 한다.
      autoHunt.forget(enemy);
      return true;
    });
    pickups.removeWhere((pickup) => pickup.isRemoved);
    _activeMonsters.removeWhere((_, enemy) => enemy.isRemoved);
  }

  void _applyInput() {
    final input = Vector2.zero();

    // 키보드: 화면 기준 방향을 그리드 방향으로 변환한다.
    if (_keyboardInput.length2 > 0.001) {
      input.add(screenDirToGridDir(_keyboardInput));
    }

    // 조이스틱
    final joystick = _joystick;
    if (joystick != null && joystick.intensity > 0.06) {
      input.add(screenDirToGridDir(joystick.relativeDelta.clone()));
    }

    if (input.length2 > 0.001) {
      input.normalize();
    }
    player.moveInput.setFrom(input);
  }

  // ── 자동 사냥 ───────────────────────────────────────────────────────

  /// 자동 사냥이 접근을 멈추는 거리(타일).
  ///
  /// 실제 타격 판정은 `사거리 + 대상의 몸 반경`이라 이보다 넓다. 좁은 쪽에
  /// 맞춰 붙기 때문에 대상의 덩치와 무관하게 반드시 닿는다 — 넓은 쪽에
  /// 맞추면 몸집이 작은 몬스터에게 닿지 않는 자리에서 헛스윙한다.
  static const double _autoHuntAttackRange = Player.meleeRange;

  /// 자동 사냥의 판단을 받아 실제 조작으로 옮긴다.
  void _updateAutoHunt(double dt) {
    if (!autoHunt.enabled) return;

    // 쓰러져 있는 동안에는 판단하지 않는다. 재가동 처리는 [onPlayerDied] 가
    // 하고, 그때 자동 사냥도 함께 끊는다.
    if (!player.isAlive) return;

    // 조이스틱이나 키보드가 들어오면 사람이 이긴다. 상태는 그대로 두므로
    // 손을 떼면 하던 사냥을 그대로 잇는다.
    final manual = player.moveInput.length2 > 0.001;

    final decision = autoHunt.update(
      dt,
      playerGrid: player.grid,
      candidates: enemies,
      attackRangeTiles: _autoHuntAttackRange,
      suspended: manual,
    );

    switch (decision.action) {
      case AutoHuntAction.none:
        break;
      case AutoHuntAction.idle:
        player.clearMoveTarget();
      case AutoHuntAction.approach:
      case AutoHuntAction.returnToAnchor:
        _steerAutoHunt(decision.destination!);
      case AutoHuntAction.attack:
        player.clearMoveTarget();
        // 멈춰 서면 [Player.facing] 이 갱신되지 않는다. 근접 판정은 전방
        // 부채꼴이므로, 돌려 세우지 않으면 옆에 붙은 대상을 계속 헛친다.
        player.faceTowards(autoHunt.gridOf(decision.target!));
        player.tryMelee();
    }
  }

  /// 자동 사냥의 목적지를 플레이어에게 전달한다.
  ///
  /// 매 프레임 [Player.moveTo] 를 부르지 않는다. 그 메서드는 부를 때마다 벽
  /// 끼임 감지용 누적 시간을 0 으로 되돌리므로, 프레임마다 부르면 캐릭터가
  /// 벽에 붙어 한 발도 못 나가는데도 영영 목표를 포기하지 않는다.
  void _steerAutoHunt(Vector2 destination) {
    final current = player.moveTarget;
    if (current != null && (current - destination).length2 < 0.09) return;
    player.moveTo(destination);
  }

  /// 자동 사냥을 켜고 끈다. 켤 때는 지금 서 있는 자리가 중심이 된다.
  void toggleAutoHunt() {
    if (status != GameStatus.playing || !player.isAlive) return;

    final on = autoHunt.toggle(player.grid);
    GameAudio.play(Sfx.uiClick);
    if (on) {
      _showBanner(
        '자동 사냥 시작 — 반경 ${autoHunt.radiusMeters.toStringAsFixed(0)}m',
      );
    } else {
      // 끄는 순간 걷던 것을 멈춘다. 남겨 두면 마지막 목표까지 혼자 걸어간다.
      player.clearMoveTarget();
      _showBanner('자동 사냥 해제');
    }
  }

  /// 자동 사냥 반경을 [deltaMeters] 만큼 조절한다. 1~10 m 를 벗어나지 않는다.
  void adjustAutoHuntRadius(double deltaMeters) {
    final before = autoHunt.radiusMeters;
    autoHunt.radiusMeters = before + deltaMeters;

    if (autoHunt.radiusMeters == before) {
      // 상한·하한에 닿았다. 눌렸는데 아무 변화가 없으면 고장으로 보이므로
      // 소리로 알린다.
      GameAudio.play(Sfx.uiError);
      return;
    }
    GameAudio.play(Sfx.uiClick);
  }

  void _updateCamera(double dt) {
    final target = _cameraTarget();
    final current = camera.viewfinder.position;
    // 부드럽게 따라간다.
    final smoothing = 1 - math.pow(0.0016, dt).toDouble();
    final next = current + (target - current) * smoothing;

    if (_shakeTimer > 0) {
      _shakeTimer -= dt;
      final decay = (_shakeTimer / 0.35).clamp(0.0, 1.0);
      final amount = _shakeIntensity * decay;
      next.add(
        Vector2(
          (_random.nextDouble() * 2 - 1) * amount,
          (_random.nextDouble() * 2 - 1) * amount * 0.6,
        ),
      );
    }

    camera.viewfinder.position = _clampToWorld(next);
  }

  Vector2 _cameraTarget() {
    final screen = gridToScreen(player.grid.x, player.grid.y, 0);
    // 캐릭터가 화면 중앙보다 살짝 아래에 오도록 위로 당긴다.
    return Vector2(screen.x, screen.y - 40);
  }

  /// 카메라가 데이터 공간 바깥의 허공을 비추지 않도록 가둔다.
  ///
  /// 아이소메트릭이라 월드는 화면에서 마름모가 되지만, 여기서는 그 마름모를
  /// 감싸는 사각형으로 충분하다. 1 km 월드라 가장자리에 닿는 일 자체가 드물다.
  Vector2 _clampToWorld(Vector2 target) {
    final half = size / (2 * camera.viewfinder.zoom);
    final left = -map.height * kHalfTileWidth + half.x;
    final right = map.width * kHalfTileWidth - half.x;
    // 위쪽은 높은 타워가 솟을 여유를 조금 둔다.
    final top = -kHeightUnit * 8 + half.y;
    final bottom = (map.width + map.height) * kHalfTileHeight - half.y;
    return Vector2(
      left <= right ? target.x.clamp(left, right) : 0,
      top <= bottom ? target.y.clamp(top, bottom) : (top + bottom) / 2,
    );
  }

  final math.Random _random = math.Random();

  // ── 월드 스트리밍 ───────────────────────────────────────────────────
  //
  // 월드는 1 km × 1 km(100만 칸)이고 로봇 수천 기가 상주한다. 전부 컴포넌트로
  // 들고 있으면 어떤 기기도 버티지 못하므로, 지형·구조물·적 모두 플레이어
  // 주변에서만 실체를 갖고 멀어지면 장부(=데이터)로 되돌아간다.

  void _updateStreaming(double dt) {
    _blockStreamTimer -= dt;
    if (_blockStreamTimer <= 0) {
      _blockStreamTimer = 0.25;
      _refreshBlockStreaming();
    }
    _monsterStreamTimer -= dt;
    if (_monsterStreamTimer <= 0) {
      _monsterStreamTimer = 0.3;
      _refreshMonsterStreaming();
    }
  }

  /// 지금 카메라가 비추는 영역을 그리드 좌표 AABB로 돌려준다.
  ///
  /// 아이소메트릭에서 화면 사각형은 그리드 위의 마름모가 된다. 네 모서리를
  /// 역변환해 감싸는 사각형을 취하므로 실제 시야보다 넉넉하게 나온다.
  Rect visibleGridBounds({double margin = 0}) {
    if (!camera.isMounted) {
      return Rect.fromCircle(
        center: Offset(player.grid.x, player.grid.y),
        radius: 36 + margin,
      );
    }
    final rect = camera.visibleWorldRect;
    final corners = [
      screenToGrid(Vector2(rect.left, rect.top)),
      screenToGrid(Vector2(rect.right, rect.top)),
      screenToGrid(Vector2(rect.right, rect.bottom)),
      screenToGrid(Vector2(rect.left, rect.bottom)),
    ];
    var minX = corners.first.x;
    var maxX = corners.first.x;
    var minY = corners.first.y;
    var maxY = corners.first.y;
    for (final corner in corners) {
      minX = math.min(minX, corner.x);
      maxX = math.max(maxX, corner.x);
      minY = math.min(minY, corner.y);
      maxY = math.max(maxY, corner.y);
    }
    return Rect.fromLTRB(
      minX - margin,
      minY - margin,
      maxX + margin,
      maxY + margin,
    );
  }

  /// 시야에 들어온 청크의 구조물을 마운트하고, 벗어난 청크는 회수한다.
  void _refreshBlockStreaming() {
    final view = visibleGridBounds(margin: _blockStreamMargin);
    final minCx = (view.left / kChunkTiles).floor().clamp(0, map.chunksX - 1);
    final maxCx = (view.right / kChunkTiles).ceil().clamp(0, map.chunksX - 1);
    final minCy = (view.top / kChunkTiles).floor().clamp(0, map.chunksY - 1);
    final maxCy = (view.bottom / kChunkTiles).ceil().clamp(0, map.chunksY - 1);

    final needed = <int>{};
    for (var cy = minCy; cy <= maxCy; cy++) {
      for (var cx = minCx; cx <= maxCx; cx++) {
        needed.add(cy * map.chunksX + cx);
      }
    }

    _loadedBlocks.removeWhere((key, components) {
      if (needed.contains(key)) return false;
      for (final component in components) {
        component.removeFromParent();
      }
      return true;
    });

    for (final key in needed) {
      if (_loadedBlocks.containsKey(key)) continue;
      final cx = key % map.chunksX;
      final cy = key ~/ map.chunksX;
      final components = [
        for (final spec in map.blocksInChunk(cx, cy)) BlockComponent(spec),
      ];
      _loadedBlocks[key] = components;
      if (components.isNotEmpty) world.addAll(components);
    }
  }

  /// 가까워진 상주 로봇을 깨우고, 멀어진 로봇은 다시 잠재운다.
  void _refreshMonsterStreaming() {
    // 1. 멀어진 개체 회수. 있던 자리를 장부에 적어 두고 사라진다.
    final releaseSquared = _monsterReleaseRadius * _monsterReleaseRadius;
    final toRelease = <int>[];
    _activeMonsters.forEach((id, enemy) {
      if (!enemy.isAlive) return;
      if ((enemy.grid - player.grid).length2 > releaseSquared) {
        toRelease.add(id);
      }
    });
    for (final id in toRelease) {
      final enemy = _activeMonsters.remove(id);
      if (enemy == null) continue;
      final seed = enemy.seed;
      if (seed != null) {
        seed.position.setFrom(enemy.grid);
        seed.active = false;
      }
      enemies.remove(enemy);
      // 회수된 개체는 더 이상 월드에 없다. 자동 사냥이 쥐고 있으면 사라진
      // 좌표를 향해 계속 걷는다.
      autoHunt.forget(enemy);
      enemy.removeFromParent();
    }

    // 2. 활성 반경에 들어온 개체를 깨운다.
    if (_activeMonsters.length >= _maxActiveMonsters) return;
    final activationSquared =
        _monsterActivationRadius * _monsterActivationRadius;

    for (final seed in population.seedsNear(
      player.grid,
      _monsterActivationRadius,
    )) {
      if (_activeMonsters.length >= _maxActiveMonsters) break;
      if (seed.active) continue;
      if ((seed.position - player.grid).length2 > activationSquared) continue;
      // 안전지대 안으로는 한 발도 들이지 않는다.
      if (map.safeZone.contains(seed.position.x, seed.position.y)) continue;

      final enemy = Enemy(
        species: seed.species,
        grid: map.nearestWalkable(seed.position),
        hpMultiplier: seed.hpMultiplier,
      )..seed = seed;
      seed.active = true;
      _activeMonsters[seed.id] = enemy;
      enemies.add(enemy);
      world.add(enemy);
    }
  }

  /// 마운트되어 있는 구조물 중 파괴 가능한 것들.
  Iterable<BlockComponent> get _destructibles sync* {
    for (final chunk in _loadedBlocks.values) {
      for (final block in chunk) {
        if (block.isDestructible) yield block;
      }
    }
  }

  // ── 웨이브 관리 ─────────────────────────────────────────────────────

  void _updateWaves(double dt) {
    if (isIntermission) {
      intermissionRemaining -= dt;
      if (intermissionRemaining <= 0) {
        isIntermission = false;
        _startWave(waveNumber + 1);
      }
      return;
    }

    // 대기열에서 순차적으로 스폰한다.
    if (_spawnQueue.isNotEmpty) {
      _spawnTimer -= dt;
      if (_spawnTimer <= 0) {
        _spawnTimer = 0.35;
        _spawnNextEnemy();
      }
      return;
    }

    // 웨이브 종료는 이번 웨이브가 투입한 추적대만 보고 판정한다.
    //
    // `enemies` 에는 스트리밍으로 깨운 상주 몹도 함께 들어 있다(`seed != null`).
    // 1 km 월드에는 상주 몹이 흩뿌려져 있어 플레이어 주변에 늘 깨어 있는 개체가
    // 있고, 그것까지 세면 추적대를 전멸시켜도 웨이브가 끝나지 않는다.
    if (!enemies.any((enemy) => enemy.seed == null && enemy.isAlive)) {
      _completeWave();
    }
  }

  void _startWave(int wave) {
    waveNumber = wave;
    final plan = _director.planFor(wave);
    currentPlan = plan;
    _spawnQueue
      ..clear()
      ..addAll(plan.units);
    _spawnTimer = 0.4;
    _showBanner(plan.isBossWave ? '⚠ BOSS WAVE $wave' : 'WAVE $wave');
    sync?.reportWaveStarted(wave);
  }

  void _spawnNextEnemy() {
    if (_spawnQueue.isEmpty) return;
    final species = _spawnQueue.removeAt(0);
    final plan = currentPlan;
    final spawnGrid = _director.pickSpawnPoint(
      player.grid,
      minDistance: species.isSovereign ? 11 : 9,
    );
    final enemy = Enemy(
      species: species,
      grid: spawnGrid,
      hpMultiplier: plan?.hpMultiplier ?? 1,
    );
    enemies.add(enemy);
    world.add(enemy);
  }

  void _completeWave() {
    isIntermission = true;
    intermissionRemaining = intermissionDuration;
    score += 100 * waveNumber;
    _showBanner('WAVE $waveNumber CLEAR');

    // 보상 보급품을 플레이어 주변에 떨어뜨린다.
    _spawnDrops(player.grid, DropTables.waveClear);

    sync?.reportWaveCleared(waveNumber, score);
  }

  void _showBanner(String text) {
    comboDisplayText = text;
    comboDisplayTimer = 1.6;
  }

  // ── 월드 조작 API ───────────────────────────────────────────────────

  /// 월드 좌표 [worldPoint]를 찍었을 때 플레이어를 그쪽으로 걸어가게 한다.
  ///
  /// 찍은 지점이 벽이거나 맵 밖이면 가장 가까운 걸을 수 있는 칸으로 보정한다.
  /// 경로 탐색은 하지 않는다 — 직선으로 향하되 벽에는 미끄러지고, 막히면
  /// [Player]가 스스로 목표를 버린다.
  void movePlayerToWorldPoint(Vector2 worldPoint) {
    if (status != GameStatus.playing || !player.isAlive) return;

    final rawGrid = screenToGrid(worldPoint);
    final target = map.nearestWalkable(rawGrid);

    // 주변에 걸을 곳이 없으면 `nearestWalkable`이 월드 중앙 스폰을 돌려준다.
    // 그대로 목표로 삼으면 허공을 찍었는데 캐릭터가 안전지대까지 걸어가므로
    // 탭을 없던 일로 한다. 찍은 자리가 원래 걸을 수 있었다면 정상이다.
    if (map.isWalkableFallback(target) && !map.isWalkableAt(rawGrid.x, rawGrid.y)) {
      return;
    }

    // 자동 사냥 중의 클릭은 "저기로 걸어가라"가 아니라 "저기를 중심으로
    // 사냥하라"는 뜻이다. 걷는 것은 자동 사냥이 이어서 지시하므로 여기서
    // 직접 목표를 주지 않는다 — 주면 다음 프레임에 곧바로 덮어써진다.
    if (autoHunt.enabled) {
      autoHunt.moveAnchor(target);
      world.add(MoveMarker(grid: target));
      return;
    }

    player.moveTo(target);
    world.add(MoveMarker(grid: target));
  }

  /// 발사체를 월드에 추가한다.
  void spawnProjectile(Projectile projectile) => world.add(projectile);

  /// 이펙트를 월드에 추가한다.
  void spawnEffect(IsoEntity effect) => world.add(effect);

  /// 카메라를 [intensity]만큼 [duration]초 동안 흔든다.
  void shakeCamera(double intensity, double duration) {
    _shakeIntensity = math.max(_shakeIntensity, intensity);
    _shakeTimer = math.max(_shakeTimer, duration);
  }

  /// 근접 공격이 판정할 수 있는 대상 목록.
  ///
  /// **반드시 스냅샷을 돌려준다.** 지연 순회(`sync*`)로 [enemies] 를 그대로
  /// 흘려보내면, 호출부가 순회 도중 [Damageable.applyDamage] 로 적을 죽이는
  /// 순간 [onEnemyKilled] 가 원본 목록에서 그 적을 지워 다음 걸음에서
  /// `ConcurrentModificationError` 가 터진다. 그 예외는 게임 루프의 `update`
  /// 안에서 터지므로 프레임이 통째로 멈춘다 — 전투 중 적을 때리거나 죽는
  /// 순간 게임이 얼어붙던 원인이 이것이었다.
  List<Damageable> meleeTargets() => _damageableTargets();

  /// 플레이어 발사체가 명중할 수 있는 대상 목록.
  ///
  /// [meleeTargets] 와 같은 이유로 스냅샷이다.
  List<Damageable> projectileTargetsForPlayer() => _damageableTargets();

  /// 지금 살아 있는 피격 대상 전부를 복사해 담는다.
  List<Damageable> _damageableTargets() => <Damageable>[
        ...enemies.where((enemy) => enemy.isAlive),
        ..._destructibles.where((block) => block.isAlive),
      ];

  // ── 전리품 드롭 ─────────────────────────────────────────────────────

  /// 드롭 표를 굴려 [origin] 자리에 전리품을 뿌린다.
  ///
  /// 여러 개가 나오면 사방으로 조금씩 튀어나가 서로 겹치지 않는다.
  void _spawnDrops(
    Vector2 origin,
    DropTable table, {
    double luck = 0,
    double amountMultiplier = 1.0,
  }) {
    final results = table.roll(
      _random,
      luck: luck,
      amountMultiplier: amountMultiplier,
    );
    if (results.isEmpty) return;

    final baseAngle = _random.nextDouble() * math.pi * 2;
    for (var i = 0; i < results.length; i++) {
      // 부채꼴로 고르게 흩어 놓는다.
      final angle = baseAngle + i * (math.pi * 2 / results.length);
      final speed = 1.6 + _random.nextDouble() * 1.1;
      _dropPickup(
        origin,
        results[i],
        velocity: Vector2(math.cos(angle), math.sin(angle)) * speed,
        lift: 2.4 + _random.nextDouble() * 1.2,
      );
    }
  }

  void _dropPickup(
    Vector2 grid,
    DropResult result, {
    Vector2? velocity,
    double lift = 2.6,
  }) {
    final safeGrid = map.nearestWalkable(grid);
    final pickup = Pickup(
      grid: safeGrid,
      kind: result.kind,
      amount: result.amount,
      launchVelocity: velocity,
      launchLift: lift,
    );
    pickups.add(pickup);
    world.add(pickup);
  }

  /// 인벤토리의 [kind] 포션을 마신다. 실제로 마셨으면 true.
  ///
  /// [announce]가 false면 배너와 실패음을 내지 않는다. 자동 회복처럼
  /// 짧은 간격으로 반복 호출되는 쪽에서 화면과 소리를 어지럽히지
  /// 않도록 쓴다.
  bool usePotion(PickupKind kind, {bool announce = true}) {
    if (status != GameStatus.playing) return false;

    final result = inventory.use(kind, player);
    if (result == null) {
      if (announce) GameAudio.play(Sfx.uiError);
      return false;
    }

    // 무엇이 얼마나 회복됐는지 한 줄로 알려 준다.
    if (announce) {
      final parts = <String>[];
      if (result.healed > 0) parts.add('+${result.healed.round()} HP');
      if (result.energized > 0) parts.add('+${result.energized.round()} EN');
      if (result.buffed) parts.add(result.spec.name);
      if (parts.isNotEmpty) _showBanner(parts.join('  '));
    }

    GameAudio.play(_lootSfx(kind), volumeScale: announce ? 1.2 : 0.7);
    // 강화 효과가 붙는 포션은 징글을 살짝 겹쳐 확실히 알린다.
    if (result.buffed) GameAudio.play(Sfx.levelUp, volumeScale: 0.45);
    return true;
  }

  /// 퀵슬롯 [index]번 포션을 마신다.
  bool usePotionSlot(int index) {
    final slots = inventory.slots;
    if (index < 0 || index >= slots.length) return false;
    return usePotion(slots[index].kind);
  }

  /// 인벤토리 패널을 열거나 닫는다.
  void toggleInventory() {
    if (status != GameStatus.playing && !_inventoryPanel.isOpen) return;
    // 인벤토리는 다른 패널과 함께 떠 있어도 되지만, 텔레포트 시트는 화면
    // 아래를 덮고 입력을 가로채므로 겹쳐 두면 서로 눌리지 않는다.
    _teleportSheet.close();
    _inventoryPanel.toggle();
    GameAudio.play(Sfx.uiClick);
  }

  /// 캐릭터 정보 화면이 떠 있는지 여부.
  bool get isCharacterScreenOpen => _characterScreen.isOpen;

  /// 캐릭터 정보 화면을 연다. 다른 전체 화면 패널과는 동시에 뜨지 않는다.
  void openCharacterScreen() {
    if (status != GameStatus.playing) return;
    _inventoryPanel.close();
    _leaderboardScreen.close();
    _teleportSheet.close();
    _characterScreen.open();
    GameAudio.play(Sfx.uiClick);
  }

  /// 캐릭터 정보 화면을 닫는다.
  void closeCharacterScreen() {
    if (!_characterScreen.isOpen) return;
    _characterScreen.close();
    GameAudio.play(Sfx.uiClick);
  }

  /// 캐릭터 정보 화면을 열거나 닫는다.
  void toggleCharacterScreen() {
    if (_characterScreen.isOpen) {
      closeCharacterScreen();
    } else {
      openCharacterScreen();
    }
  }

  /// 리더보드가 떠 있는지 여부.
  bool get isLeaderboardOpen => _leaderboardScreen.isOpen;

  /// 리더보드를 연다. 다른 전체 화면 패널과는 동시에 뜨지 않는다.
  void openLeaderboard() {
    if (status != GameStatus.playing) return;
    _inventoryPanel.close();
    _characterScreen.close();
    _teleportSheet.close();
    _leaderboardScreen.open();
    GameAudio.play(Sfx.uiClick);
  }

  /// 리더보드를 닫는다.
  void closeLeaderboard() {
    if (!_leaderboardScreen.isOpen) return;
    _leaderboardScreen.close();
    GameAudio.play(Sfx.uiClick);
  }

  /// 리더보드를 열거나 닫는다.
  void toggleLeaderboard() {
    if (_leaderboardScreen.isOpen) {
      closeLeaderboard();
    } else {
      openLeaderboard();
    }
  }

  /// 텔레포트 목적지 목록이 떠 있는지 여부.
  bool get isTeleportSheetOpen => _teleportSheet.isOpen;

  /// 텔레포트 목적지 목록을 연다. 다른 패널과는 동시에 뜨지 않는다.
  void openTeleportSheet() {
    if (status != GameStatus.playing) return;
    _inventoryPanel.close();
    _characterScreen.close();
    _leaderboardScreen.close();
    _teleportSheet.open();
    GameAudio.play(Sfx.uiClick);
  }

  /// 텔레포트 목적지 목록을 닫는다.
  void closeTeleportSheet() {
    if (!_teleportSheet.isOpen) return;
    _teleportSheet.close();
    GameAudio.play(Sfx.uiClick);
  }

  /// 텔레포트 목적지 목록을 열거나 닫는다.
  void toggleTeleportSheet() {
    if (_teleportSheet.isOpen) {
      closeTeleportSheet();
    } else {
      openTeleportSheet();
    }
  }

  /// [destination]으로 순간이동한다.
  ///
  /// 사망 처리와 같은 후처리가 필요하다. 월드를 가로지르는 이동이라 카메라와
  /// 스트리밍을 이번 프레임에 바로 맞춰 주지 않으면, 카메라가 한참을 날아가고
  /// 도착지는 지형도 로봇도 없이 텅 빈 채로 나타난다.
  void teleportPlayerTo(TeleportDestination destination) {
    if (status != GameStatus.playing || !player.isAlive) return;

    final point = destination.resolve(map, _random);
    player.teleportTo(point);

    // 사냥터를 통째로 옮긴 것이므로 중심도 함께 옮긴다. 그대로 두면 도착
    // 하자마자 월드 반대편의 옛 사냥터를 향해 되돌아 걷는다.
    if (autoHunt.enabled) autoHunt.moveAnchor(player.grid);

    camera.viewfinder.position = _cameraTarget();
    _refreshBlockStreaming();
    _refreshMonsterStreaming();

    _teleportSheet.close();

    spawnEffect(
      HitSpark(
        grid: player.grid.clone(),
        z: 0.6,
        color: destination.isSafe
            ? GamePalette.safeZoneGlow
            : GamePalette.playerAccent,
        count: 14,
        spread: 38,
      ),
    );
    GameAudio.play(Sfx.dash);
    _showBanner('${destination.label} 도착');
  }

  /// 월드 메뉴에서 로그아웃을 선택했을 때 실행된다.
  ///
  /// 세션을 어디까지 정리할지는 앱 셸이 정한다. 게임은 열려 있던 화면을 접고
  /// 지금까지의 기록을 넘긴 뒤 [onLogout] 을 부르는 데서 손을 뗀다.
  Future<void> requestLogout() async {
    closeCharacterScreen();
    _inventoryPanel.close();
    _worldMenu.close();
    reportRunFinished();

    // 로그아웃하면 이 게임 인스턴스가 통째로 사라진다 — 주기 전송이 따라잡을
    // 기회가 더는 없으므로, 마지막 진행 상황이 서버에 닿을 때까지 기다린 뒤에
    // 넘긴다. 기다리지 않으면 방금 오른 레벨이 순위에 반영되지 않은 채 나간다.
    //
    // 서버가 응답하지 않는다고 로그아웃까지 막지는 않는다. 기록보다 사용자가
    // 나가려는 의사가 우선이다.
    final sync = this.sync;
    if (sync != null) {
      try {
        await sync.flushProgress().timeout(const Duration(seconds: 3));
      } on TimeoutException {
        // 못 보냈다. 다음 접속에서 더 높은 값을 보내면 그때 반영된다.
      }
    }

    onLogout?.call();
  }

  // ── 이벤트 콜백 ─────────────────────────────────────────────────────

  /// 적이 파괴되었을 때 호출된다.
  void onEnemyKilled(Enemy enemy) {
    enemies.remove(enemy);
    // 쓰러진 대상을 붙들고 있으면 시체 앞에서 다음 사냥감을 찾지 않는다.
    autoHunt.forget(enemy);

    // 월드에 상주하던 개체라면 장부에 파괴를 기록한다. 시간이 지나면
    // AI가 같은 자리에 새 유닛을 배치하므로 월드가 텅 비지 않는다.
    final seed = enemy.seed;
    if (seed != null) {
      population.markDestroyed(seed);
      _activeMonsters.remove(seed.id);
    }

    kills++;
    // 점수는 골격 등급과 몬스터 레벨을 함께 반영한다.
    final baseScore = switch (enemy.build) {
      MonsterBuild.drone => 15,
      MonsterBuild.walker => 30,
      MonsterBuild.siege => 70,
      MonsterBuild.sovereign => 400,
    };
    score += (baseScore * (1 + enemy.level * 0.05)).round();
    player.gainXp(
      LevelSystem.killXp(enemy.xpValue, playerLevel: player.level),
    );
    hitStop.trigger(enemy.isBoss ? 0.16 : 0.05);

    // 잔해에서 전리품이 튀어나온다. 후반 웨이브일수록 조금 더 후하다.
    _spawnDrops(
      enemy.grid,
      DropTables.forEnemy(enemy.build),
      luck: math.min(0.15, waveNumber * 0.01),
      amountMultiplier: 1 + math.min(0.5, waveNumber * 0.02),
    );

    sync?.reportKill(enemy.species.codeName, score);
  }

  /// 데이터 캐시가 파괴되었을 때 호출된다.
  void onBlockDestroyed(BlockComponent block) {
    // 지형 장부에서 지워 두면 청크가 다시 로드돼도 되살아나지 않는다.
    map.clearBlock(block.spec.gx, block.spec.gy);
    for (final chunk in _loadedBlocks.values) {
      if (chunk.remove(block)) break;
    }
    _spawnDrops(block.grid, DropTables.crate);
  }

  /// 전리품을 회수했을 때 호출된다.
  void onPickupCollected(Pickup pickup) {
    pickups.remove(pickup);
    // 스크랩 코어는 그 자체가 점수다.
    score += pickup.kind == PickupKind.scrapCore
        ? pickup.amount.round()
        : 5;
    GameAudio.play(_lootSfx(pickup.kind));
  }

  /// 전리품 종류에 어울리는 회수음.
  Sfx _lootSfx(PickupKind kind) => switch (kind) {
        PickupKind.nanoVial ||
        PickupKind.nanoCanister ||
        PickupKind.repairCell ||
        PickupKind.regenAmpoule ||
        PickupKind.overhaulKit =>
          Sfx.pickupHealth,
        PickupKind.energyCell ||
        PickupKind.overchargeCell ||
        PickupKind.combatStim =>
          Sfx.pickupEnergy,
        PickupKind.dataChip || PickupKind.scrapCore => Sfx.pickupChip,
      };

  /// 플레이어가 피해를 입었을 때 호출된다.
  void onPlayerDamaged() {
    hitStop.trigger(0.06);
  }

  /// 레벨업 시 호출된다. [milestone]은 5레벨 단위의 강화 구간인지 여부다.
  void onLevelUp(int level, {bool milestone = false}) {
    _showBanner(milestone ? 'LEVEL UP  $level  ▲BOOST' : 'LEVEL UP  $level');
    shakeCamera(milestone ? 10 : 4, milestone ? 0.3 : 0.2);
    // 서버에 올리는 것은 누적 하나다. 레벨은 서버가 거기서 다시 계산한다.
    sync?.reportLevel(level, player.totalXp);
  }

  /// 플레이어가 사망했을 때 호출된다.
  ///
  /// 모두가 하나의 월드를 공유하므로 이 게임에는 게임 오버가 없다. 파괴된
  /// 몸체는 그 자리에 잔해로 남고, 백업된 의식은 안전지대의 접속 지점에서
  /// 곧바로 새 몸체로 재가동된다.
  void onPlayerDied() {
    deaths++;

    // 자동 사냥을 끊는다. 앵커는 쓰러진 자리 근처이므로 그대로 두면 재가동
    // 직후 자기를 죽인 무리 한가운데로 혼자 걸어 들어가 다시 죽는다.
    final wasAutoHunting = autoHunt.enabled;
    if (wasAutoHunting) autoHunt.disable();

    // 쓰러진 자리에 잔해를 남긴다.
    spawnEffect(
      Explosion(
        grid: player.grid.clone(),
        z: 0.35,
        tint: GamePalette.playerAccent,
      ),
    );

    player.respawnAt(map.respawnPoint(_random));

    // 월드를 가로지르는 순간이동이라 카메라를 보간하면 한참을 날아간다.
    // 새 몸체 위에 즉시 붙인다.
    camera.viewfinder.position = _cameraTarget();

    // 스트리밍 주기를 기다리면 안전지대가 텅 빈 채로 한 박자 늦게 채워진다.
    _refreshBlockStreaming();
    _refreshMonsterStreaming();

    spawnEffect(
      HitSpark(
        grid: player.grid.clone(),
        z: 0.6,
        color: GamePalette.safeZoneGlow,
        count: 16,
        spread: 44,
      ),
    );
    shakeCamera(10, 0.25);
    _showBanner(
      wasAutoHunting
          ? 'SYSTEM REBOOT — 자동 사냥 해제됨'
          : 'SYSTEM REBOOT — 안전지대 재가동',
    );

    sync?.reportDeath(deaths: deaths, score: score);
  }

  /// 지금까지의 기록을 백엔드에 넘긴다.
  ///
  /// 사망이 더 이상 런의 끝이 아니므로, 세션을 접는 쪽(로비 복귀·재시작 등)이
  /// 이 시점을 정한다.
  void reportRunFinished() {
    sync?.reportRunFinished(
      wave: waveNumber,
      kills: kills,
      score: score,
      survivalTime: survivalTime,
    );
  }

  // ── 상태 전환 ───────────────────────────────────────────────────────

  /// 새 게임을 시작한다.
  void startGame() {
    overlays.remove(Overlays.mainMenu);
    status = GameStatus.playing;
    resumeEngine();
    GameAudio.play(Sfx.uiClick);
    GameAudio.playMusic();
    if (waveNumber == 0) _startWave(1);
  }

  /// 게임을 일시정지한다.
  void pauseGame() {
    if (status != GameStatus.playing) return;
    status = GameStatus.paused;
    overlays.add(Overlays.pauseMenu);
    pauseEngine();
    GameAudio.pauseAll();
  }

  /// 일시정지를 해제한다.
  void resumeGame() {
    if (status != GameStatus.paused) return;
    overlays.remove(Overlays.pauseMenu);
    status = GameStatus.playing;
    resumeEngine();
    GameAudio.resumeAll();
  }

  /// 처음부터 다시 시작한다.
  Future<void> restart() async {
    overlays
      ..remove(Overlays.gameOver)
      ..remove(Overlays.pauseMenu);
    GameAudio.play(Sfx.uiClick);

    // 새 월드로 옮겨 가는 것이지 캐릭터를 갈아 끼우는 것이 아니다. 지금까지의
    // 성장을 다음 몸체에 그대로 물려준다 — 여기서 놓치면 재시작할 때마다 레벨이
    // 출격 시점으로 돌아가고, 서버는 그 후퇴를 무시해 순위가 멈춘다.
    _carriedTotalXp = player.totalXp;

    // 월드를 비우고 새 지형을 만든다.
    world.removeAll(world.children.toList());
    // 새 월드로 옮겨 가므로 옛 월드의 앵커와 타깃은 모두 무효다.
    autoHunt.disable();
    enemies.clear();
    pickups.clear();
    inventory.clear();
    _inventoryPanel.close();
    _loadedBlocks.clear();
    _activeMonsters.clear();
    _spawnQueue.clear();

    map = LevelMap.generate();
    population = MonsterPopulation.generate(map);
    _director = WaveDirector(map: map);
    waveNumber = 0;
    currentPlan = null;
    kills = 0;
    score = 0;
    survivalTime = 0;
    isIntermission = false;
    intermissionRemaining = 0;
    comboDisplayTimer = 0;
    _blockStreamTimer = 0;
    _monsterStreamTimer = 0;

    world.add(GroundLayer(map));
    world.add(SafeZoneField(map.safeZone));
    world.add(ClickMoveLayer());
    world.add(MovePathHint());
    world.add(AutoHuntRangeField());
    player = _spawnPlayer();
    world.add(player);
    camera.viewfinder.position = _cameraTarget();

    _refreshBlockStreaming();
    _refreshMonsterStreaming();

    status = GameStatus.playing;
    resumeEngine();
    _startWave(1);
  }

  // ── 키보드 ──────────────────────────────────────────────────────────

  @override
  KeyEventResult onKeyEvent(
    KeyEvent event,
    Set<LogicalKeyboardKey> keysPressed,
  ) {
    super.onKeyEvent(event, keysPressed);
    _pressedKeys
      ..clear()
      ..addAll(keysPressed);
    _recomputeKeyboardInput();

    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.space:
        case LogicalKeyboardKey.keyJ:
          player.tryMelee();
        case LogicalKeyboardKey.keyK:
        case LogicalKeyboardKey.keyF:
          player.tryShoot();
        case LogicalKeyboardKey.shiftLeft:
        case LogicalKeyboardKey.shiftRight:
        case LogicalKeyboardKey.keyL:
          player.tryDash();
        case LogicalKeyboardKey.keyC:
          toggleCharacterScreen();
        case LogicalKeyboardKey.keyB:
          toggleLeaderboard();
        case LogicalKeyboardKey.escape:
          // 떠 있는 창이 있으면 먼저 닫는다.
          if (_teleportSheet.isOpen) {
            closeTeleportSheet();
          } else if (_leaderboardScreen.isOpen) {
            closeLeaderboard();
          } else if (_characterScreen.isOpen) {
            closeCharacterScreen();
          } else if (_worldMenu.isOpen) {
            _worldMenu.close();
          } else if (_inventoryPanel.isOpen) {
            _inventoryPanel.close();
          } else if (status == GameStatus.playing) {
            pauseGame();
          } else if (status == GameStatus.paused) {
            resumeGame();
          }
        case LogicalKeyboardKey.keyP:
          if (status == GameStatus.playing) {
            pauseGame();
          } else if (status == GameStatus.paused) {
            resumeGame();
          }
        case LogicalKeyboardKey.keyI:
        case LogicalKeyboardKey.tab:
          toggleInventory();
        case LogicalKeyboardKey.keyQ:
          // 가장 아깝지 않은 회복 포션을 즉시 마신다.
          final kind = inventory.bestHealingPotion();
          if (kind != null) usePotion(kind);
        case LogicalKeyboardKey.digit1:
          usePotionSlot(0);
        case LogicalKeyboardKey.digit2:
          usePotionSlot(1);
        case LogicalKeyboardKey.digit3:
          usePotionSlot(2);
        case LogicalKeyboardKey.digit4:
          usePotionSlot(3);
        case LogicalKeyboardKey.digit5:
          usePotionSlot(4);
        case LogicalKeyboardKey.digit6:
          usePotionSlot(5);
        case LogicalKeyboardKey.enter:
          if (status == GameStatus.ready) startGame();
      }
    }

    return KeyEventResult.handled;
  }

  void _recomputeKeyboardInput() {
    // 화면 기준 방향(위/아래/좌/우)을 누적한다.
    var x = 0.0;
    var y = 0.0;
    if (_isDown(LogicalKeyboardKey.keyW) ||
        _isDown(LogicalKeyboardKey.arrowUp)) {
      y -= 1;
    }
    if (_isDown(LogicalKeyboardKey.keyS) ||
        _isDown(LogicalKeyboardKey.arrowDown)) {
      y += 1;
    }
    if (_isDown(LogicalKeyboardKey.keyA) ||
        _isDown(LogicalKeyboardKey.arrowLeft)) {
      x -= 1;
    }
    if (_isDown(LogicalKeyboardKey.keyD) ||
        _isDown(LogicalKeyboardKey.arrowRight)) {
      x += 1;
    }
    _keyboardInput.setValues(x, y);
  }

  bool _isDown(LogicalKeyboardKey key) => _pressedKeys.contains(key);
}

/// 월드 뒤에 깔리는 데이터 공간의 하늘.
///
/// 위쪽은 흰빛, 아래로 갈수록 옅은 청록이고 그 경계에서 빛이 번진다.
/// 이 게임의 사이버 스페이스는 어두운 심연이 아니라 밝게 빛나는 연산 공간이다.
class CyberBackdrop extends Component with HasGameReference<ActionRpgGame> {
  double _time = 0;

  /// 공간을 천천히 떠오르는 데이터 입자.
  late final List<_DataMote> _motes = List.generate(
    72,
    (i) => _DataMote(
      x: (i * 97 % 101) / 101,
      y: (i * 61 % 103) / 103,
      size: 1 + (i % 5) * 0.6,
      speed: 0.012 + (i % 7) * 0.004,
    ),
  );

  @override
  void update(double dt) {
    _time += dt;
    for (final mote in _motes) {
      mote.y -= mote.speed * dt;
      if (mote.y < 0) mote.y += 1;
    }
  }

  @override
  void render(Canvas canvas) {
    final screen = game.size;
    final rect = Rect.fromLTWH(0, 0, screen.x, screen.y);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, rect.top),
          Offset(0, rect.bottom),
          [
            GamePalette.skyHigh,
            GamePalette.skyHigh,
            GamePalette.horizonGlow.withValues(alpha: 0.5),
            GamePalette.skyLow,
          ],
          [0.0, 0.32, 0.52, 1.0],
        ),
    );

    // 화면 한가운데에서 부풀어 오르는 빛. 공간 전체를 환하게 띄운다.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(screen.x * 0.5, screen.y * 0.46),
          screen.x * 0.75,
          [
            Colors.white.withValues(alpha: 0.5),
            Colors.white.withValues(alpha: 0.0),
          ],
        ),
    );

    // 원경으로 물러나는 격자. 아래로 갈수록 촘촘해져 깊이를 만든다.
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = GamePalette.horizonGlow.withValues(alpha: 0.2);
    const lines = 15;
    for (var i = 1; i < lines; i++) {
      final t = i / lines;
      final y = screen.y * (0.5 + t * t * 0.5);
      canvas.drawLine(Offset(0, y), Offset(screen.x, y), grid);
    }

    final motePaint = Paint();
    for (final mote in _motes) {
      final twinkle = 0.35 + 0.35 * math.sin(_time * 2 + mote.x * 12);
      motePaint.color = GamePalette.dataMote.withValues(alpha: twinkle * 0.5);
      canvas.drawCircle(
        Offset(mote.x * screen.x, mote.y * screen.y),
        mote.size,
        motePaint,
      );
    }
  }
}

class _DataMote {
  _DataMote({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
  });

  final double x;
  double y;
  final double size;
  final double speed;
}

/// 월드 위에 얹는 대기 효과.
///
/// 화면 위쪽(아이소메트릭에서 먼 곳)을 흰빛으로 날려 거리감을 주고,
/// 전체에 옅은 청록 블룸을 더해 발광이 번지게 한다.
class AtmosphereOverlay extends Component with HasGameReference<ActionRpgGame> {
  AtmosphereOverlay() : super(priority: 50);

  @override
  void render(Canvas canvas) {
    final screen = game.size;

    canvas.drawRect(
      Rect.fromLTWH(0, 0, screen.x, screen.y * 0.4),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, screen.y * 0.4),
          [
            GamePalette.skyHigh.withValues(alpha: 0.62),
            GamePalette.skyHigh.withValues(alpha: 0.0),
          ],
        ),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, screen.x, screen.y),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(
          Offset(screen.x * 0.5, screen.y * 0.45),
          math.max(screen.x, screen.y) * 0.7,
          [
            GamePalette.horizonGlow.withValues(alpha: 0.05),
            GamePalette.horizonGlow.withValues(alpha: 0.0),
          ],
        ),
    );
  }
}
