import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/camera.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spacetimedb_sdk/spacetimedb_sdk.dart';

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
import 'level/world_tree.dart';
import 'level/teleport_destinations.dart';
import 'entities/remote_player.dart';
import 'net/game_sync.dart';
import 'net/leaderboard_source.dart';
import 'net/party_session.dart';
import 'net/world_presence.dart';
import 'palette.dart';
import 'systems/auto_hunt.dart';
import 'systems/party_follow.dart';
import 'systems/drop_table.dart';
import 'systems/hit_stop.dart';
import 'systems/inventory.dart';
import 'systems/level_system.dart';
import 'systems/monster_codex.dart';
import '../spacetime/reducer_error.dart';
import 'ui/auto_hunt_control.dart';
import 'ui/character_screen.dart';
import 'ui/context_action_bar.dart';
import 'ui/party_panel.dart';
import 'ui/hud.dart';
import 'ui/inventory_ui.dart';
import 'ui/leaderboard_screen.dart';
import 'ui/mute_button.dart';
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
    WorldPresence? presence,
    PartySession? party,
    int startTotalXp = 0,
    this.design = CyborgDesign.assault,
    this.autoStart = false,
  })  : leaderboard = leaderboard ?? const EmptyLeaderboardSource(),
        presence = presence ?? const OfflineWorldPresence(),
        party = party ?? const OfflinePartySession(),
        _carriedTotalXp = startTotalXp;

  /// 시작 메뉴를 건너뛰고 곧바로 월드에 들어갈지.
  ///
  /// 여러 클라이언트를 한꺼번에 띄울 때는 "접속하기" 를 눌러 줄 사람이 없다.
  /// 그 판단은 게임 밖(`GameScreen`)에서 내리고, 여기서는 결과만 따른다.
  final bool autoStart;

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

  /// 같은 월드에 있는 다른 요원들. 서버가 없으면 빈 목록이다.
  ///
  /// 이것이 "여럿이 하나의 월드를 공유한다" 는 전제를 실제로 만드는 통로다.
  /// 없으면 게임은 혼자 플레이하는 모습으로 그대로 돌아간다.
  final WorldPresence presence;

  /// 파티 — 누구와 함께 다니는지. 서버가 없으면 파티가 없는 것과 같다.
  ///
  /// 파티는 **보상을 나누지 않는다.** 함께 다니고 따라다니게 할 뿐이며,
  /// 경험치는 몹을 선점한 사람에게만 간다(`CLAUDE.md` Multiplayer).
  final PartySession party;

  /// 월드 메뉴에서 로그아웃을 선택했을 때 호출된다.
  ///
  /// 계정과 세션은 게임 바깥(앱 셸)의 몫이라 실제 처리는 넘겨받는 쪽이 한다.
  /// null이면 메뉴에 로그아웃 항목이 생기지 않는다.
  final VoidCallback? onLogout;

  late LevelMap map;
  late Player player;
  late Hud _hud;
  late InventoryPanel _inventoryPanel;
  late CharacterScreen _characterScreen;
  late LeaderboardScreen _leaderboardScreen;
  late TeleportSheet _teleportSheet;
  late WorldMenu _worldMenu;

  /// 소리를 끄고 켜는 버튼. 월드 메뉴 버튼 옆에 선다.
  late MuteButton _muteButton;

  /// 파티를 보고 다루는 패널. 월드 메뉴에서 연다.
  late PartyPanel _partyPanel;

  /// 받은 초대를 알리는 카드. 열어 보지 않아도 스스로 뜬다.
  late PartyInviteCard _partyInviteCard;

  /// 고른 요원에게 무엇을 할지 고르는 하단 막대.
  late ContextActionBar _contextActionBar;
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

  /// 화면에 올라와 있는 다른 요원. 캐릭터 번호로 찾는다.
  final Map<int, RemotePlayerEntity> _remotePlayers = {};

  /// 지금 월드에 함께 있는 다른 요원의 수. HUD 가 읽는다.
  int get remotePlayerCount => _remotePlayers.length;

  /// 앵커 주변만 도는 자동 사냥의 상태와 판단을 맡는다.
  ///
  /// 판단만 하고 실행은 [_updateAutoHunt] 가 한다. 좌표와 생사만 콜백으로
  /// 넘기므로 컨트롤러 쪽은 Flame 을 전혀 모른다.
  final AutoHuntController<Enemy> autoHunt = AutoHuntController<Enemy>(
    gridOf: (enemy) => enemy.grid,
    aliveOf: (enemy) => enemy.isAlive,
  );

  /// 파티장을 따라다니는 판단을 맡는다.
  ///
  /// [autoHunt] 와 같은 방식이다 — 판단만 하고 실행은 [_updatePartyFollow] 가
  /// 한다. 추종은 결국 **자동 사냥의 중심을 파티장에게 옮기는 일**이므로 따로
  /// 걷는 코드를 두지 않는다.
  final PartyFollowController partyFollow = PartyFollowController();

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


  /// 이 거리보다 멀어지면 다시 잠재운다. 경계에서 깜빡이지 않도록 활성
  /// 반경보다 넓게 둔다.
  ///
  /// **화면보다 조금만 넓게 잡는다.** 예전에는 60 이었는데, 그 반경이 화면
  /// 반폭(약 22 타일)의 세 배에 가까워 눈에 보이지도 않는 몹이 마릿수 상한을
  /// 먼저 채웠다. 조밀한 저레벨 사냥터에서는 그 결과 **눈앞의 몹이 그려지지
  /// 않아 화면이 비어 보였다**(실측: 화면 반폭 안에만 66 기).
  static const double _monsterReleaseRadius = 34;

  /// 동시에 살아 움직일 수 있는 상주 로봇의 상한.
  ///
  /// **관심 영역의 "몬스터 50" 은 여기서 만들어진다.** 구독 청크는 면적만 자를 뿐
  /// 마릿수를 자르지 못한다 — 구독 SQL 에 `LIMIT` 이 없고, 몹은 레벨 띠를 따라
  /// 군집 배치되어 저레벨 구역이 외곽보다 열 배 넘게 조밀하다. 그래서 마릿수
  /// 상한은 그리는 쪽에서만 강제할 수 있다([_refreshMonsterStreaming] 이
  /// **화면 안을 먼저**, 그다음 가까운 순으로 정렬한 뒤 이 수만큼만 만든다).
  ///
  /// **50 으로는 화면을 덮지 못한다.** 실측하면 가장 조밀한 저레벨 사냥터는
  /// 화면 반폭(약 22 타일) 안에만 66 기가 있다. 50 에서 잘리면 그중 열여섯
  /// 기가 사라지는데, 어떤 몹은 보이고 어떤 몹은 안 보이니 화면이 성기게
  /// 비어 보인다 — "몬스터가 투명하다" 로 읽히던 증상이다.
  static const int _maxActiveMonsters = 120;

  /// 동시에 그리는 다른 요원의 상한.
  ///
  /// [_maxActiveMonsters] 와 같은 이유로 필요하다. 안전지대(50×50 타일)는 플레이어
  /// 구독 청크 3×3(222×222) 안에 통째로 들어가므로, 거기 사람이 몰리면 그 수만큼
  /// 행이 온다. 그리는 것은 가까운 이 수만큼이다.
  static const int _maxRemotePlayers = 50;

  GameStatus status = GameStatus.ready;

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

  /// 월드 전역에 남아 있는 로봇 수(멀리 있어 잠들어 있는 개체 포함).
  int get worldMonsterCount =>
      presence.monsters.where((m) => m.alive).length;

  @override
  Color backgroundColor() => GamePalette.skyLow;

  @override
  Future<void> onLoad() async {
    // 첫 타격에서 소리가 밀리지 않도록 효과음을 미리 올려 둔다.
    await GameAudio.init();

    map = LevelMap.generate();

    world.add(GroundLayer(map));
    world.add(SafeZoneField(map.safeZone));
    // 월드 정중앙에 선 나무. 안전지대 한복판의 이정표다.
    world.add(WorldTree(grid: map.worldCenter));
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

    if (autoStart) {
      // 메뉴를 띄웠다 지우지 않고 곧장 들어간다. 한 프레임이라도 메뉴가 보이면
      // 그 사이 엔진이 멈춰 있어, 여러 클라이언트가 서로 다른 시점에 출발한다.
      startGame();
    } else {
      overlays.add(Overlays.mainMenu);
      pauseEngine();
    }
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

  // ── 화면 배율 ───────────────────────────────────────────────────────

  /// 사용자가 고른 배율 배수. 1 이면 화면 크기에 맞춘 기본값이다.
  ///
  /// 화면 크기에 따른 기본 배율([_zoomForSize])에 이 값을 곱한다. 절대 배율을
  /// 직접 들고 있으면 창 크기가 바뀔 때마다 사용자가 고른 값이 뒤집힌다.
  double _zoomScale = 1;

  /// 배율 배수의 한계.
  ///
  /// 넓게 보는 쪽(0.5)은 멀리 있는 다른 요원까지 화면에 담기 위한 것이고,
  /// 당겨 보는 쪽(2.0)은 몸의 생김새와 이름표를 확인하기 위한 것이다.
  static const double _minZoomScale = 0.5;
  static const double _maxZoomScale = 2.0;

  /// 버튼 한 번에 움직이는 폭.
  static const double _zoomStep = 0.2;

  /// 지금 배율 배수(0.5 ~ 2.0). 버튼이 눌림 여부를 판단하는 데 쓴다.
  double get zoomScale => _zoomScale;

  bool get canZoomIn => _zoomScale < _maxZoomScale - 0.001;
  bool get canZoomOut => _zoomScale > _minZoomScale + 0.001;

  /// 화면을 당겨 본다.
  void zoomIn() => _applyZoomScale(_zoomScale + _zoomStep);

  /// 화면을 넓게 본다. 멀리 있는 다른 요원을 찾을 때 쓴다.
  void zoomOut() => _applyZoomScale(_zoomScale - _zoomStep);

  /// 기본 배율로 되돌린다.
  void resetZoom() => _applyZoomScale(1);

  void _applyZoomScale(double next) {
    final clamped = next.clamp(_minZoomScale, _maxZoomScale).toDouble();
    if ((clamped - _zoomScale).abs() < 0.001) return;
    _zoomScale = clamped;
    camera.viewfinder.zoom = _zoomForSize(size);
    GameAudio.play(Sfx.uiClick);
  }

  double _zoomForSize(Vector2 screenSize) {
    // 세로 기준 약 760px 분량의 월드가 보이도록 맞춘다.
    final zoom = screenSize.y / 760;
    return zoom.clamp(0.55, 1.6) * _zoomScale;
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
        icon: ActionIcon.zoomIn,
        id: 'zoomIn',
        color: GamePalette.hudBorder,
        radius: 22,
        onPressed: zoomIn,
        enabledCheck: () => canZoomIn,
        position: Vector2.zero(),
        priority: 90,
      ),
      ActionButton(
        icon: ActionIcon.zoomOut,
        id: 'zoomOut',
        color: GamePalette.hudBorder,
        radius: 22,
        onPressed: zoomOut,
        enabledCheck: () => canZoomOut,
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
    _partyPanel = PartyPanel();
    _partyInviteCard = PartyInviteCard();
    _contextActionBar = ContextActionBar();
    _worldMenu = WorldMenu(
      entries: [
        WorldMenuEntry(
          label: '캐릭터 정보',
          icon: WorldMenuIcon.character,
          onSelected: openCharacterScreen,
        ),
        WorldMenuEntry(
          label: '파티',
          icon: WorldMenuIcon.character,
          onSelected: togglePartyPanel,
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
    _muteButton = MuteButton();
    camera.viewport.addAll([
      PotionQuickBar(),
      BuffBar(),
      _worldMenu,
      _muteButton,
      _partyPanel,
      _partyInviteCard,
      _contextActionBar,
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
        // 배율 버튼은 왼쪽 아래, 조이스틱 위에 세로로 세운다. 오른손 액션
        // 버튼과 멀리 떼어 놓아야 전투 중에 잘못 누르지 않는다.
        case 'zoomIn':
          child.position = Vector2(52, size.y - 176);
        case 'zoomOut':
          child.position = Vector2(52, size.y - 124);
      }
    }
    // 자동 사냥은 대시 버튼 위로 이어 세운다. 위가 늘리기, 아래가 줄이기다.
    // 세로가 짧은 창에서 화면 밖으로 밀리지 않도록 위쪽에 하한을 둔다.
    // 하한은 반경 증가 버튼(중심이 52 위, 반경 15)이 화면 위로 잘리지 않는
    // 선이다. 52 로 두면 세로가 짧은 창에서 그 버튼의 위쪽 절반이 사라진다.
    final autoHuntY = math.max(72.0, size.y - 298);
    _autoHuntButton.position = Vector2(size.x - 92, autoHuntY);
    _autoHuntRadiusUp.position = Vector2(size.x - 92, autoHuntY - 52);
    _autoHuntRadiusDown.position = Vector2(size.x - 92, autoHuntY + 52);

    // 월드 메뉴와 음소거 버튼은 우상단 미니맵 아래에 나란히 세운다.
    //
    // 미니맵 아래 좌표 표시는 우측 정렬이라 미니맵 폭을 훨씬 넘어 왼쪽으로
    // 300픽셀 넘게 뻗는다(`Hud._renderMinimap`). 그 글줄 아래(y 173)를 확실히
    // 비켜야 버튼이 좌표를 덮어 가리지 않는다.
    const menuRowY = 180.0;
    _worldMenu.position = Vector2(size.x - 18, menuRowY);
    // 음소거는 메뉴 버튼 왼쪽에 붙인다. 메뉴는 아래로 펼쳐지므로 같은 줄에
    // 두어야 패널이 열려도 가려지지 않는다.
    _muteButton.position = Vector2(
      size.x - 18 - WorldMenu.buttonSize - 10,
      menuRowY,
    );
    // 퀵슬롯과 버프 표시는 화면 크기에 맞춰 스스로 자리를 잡는다.

    // 파티 패널은 좌상단 생존 정보 패널 아래에 둔다. 전투 시야를 가리지 않는
    // 자리이면서, 파티원이 늘어 아래로 자라도 조이스틱과 겹치지 않는다.
    _partyPanel.position = Vector2(10, 132);
    // 초대는 화면 한가운데 위쪽에 띄운다 — 20 초 만에 사라지므로 눈에 걸려야 한다.
    _partyInviteCard.position = Vector2(size.x / 2, 16);

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
    // 자동 사냥보다 먼저 판단한다. 추종은 사냥의 중심을 옮기는 일이므로,
    // 옮기기 전에 사냥이 한 번 돌면 그 프레임은 옛 중심으로 움직인다.
    _updatePartyFollow(dt);
    _updateAutoHunt(dt);
    super.update(dt);
    _pruneRemoved();
    _updateCamera(dt);
    _updateStreaming(dt);
    sync?.tick(dt, this);

    // 내 위치를 알리고, 남들이 어디 있는지 받아 온다. 이 두 줄이 "같은 월드에
    // 있다" 를 실제로 만드는 지점이다.
    // 방향도 함께 보낸다. 멈춰 서서 몸만 돌리는 동작은 좌표에 남지 않아,
    // 이것이 없으면 남의 화면에서 나는 마지막으로 걸었던 쪽만 계속 바라본다.
    presence.report(player.grid, player.facing);
    _syncRemotePlayers();
    // 서버가 확정한 내 상태를 몸에 옮겨 담는다. 보고 **뒤에** 두는 이유는,
    // 방금 보낸 좌표에 대한 답이 아직 오지 않았기 때문이다 — 먼저 두면 한 프레임
    // 낡은 좌표로 자신을 되돌리게 된다.
    _adoptServerState(dt);
  }

  /// 마지막으로 본 서버 사망 누계. 이 수가 오르면 쓰러진 것이다.
  int? _lastServerDeaths;

  /// 마지막으로 **연출한** 피격의 서버 시각(마이크로초).
  ///
  /// 첫 갱신에서는 재생하지 않는다 — 접속하자마자 옛 피격이 되살아나는 것을
  /// 막기 위해서다(사망 누계를 다루는 방식과 같다).
  int? _lastServerHurtAt;

  /// 서버가 확정한 내 체력·마력·좌표를 화면에 반영한다.
  ///
  /// **이 게임의 판정은 서버에 있다.** 클라이언트가 하는 일은 그 결과를 그리고,
  /// 다음 갱신이 올 때까지의 사이를 예측으로 메우는 것뿐이다. 예측은 화면을
  /// 부드럽게 하려는 것이지 판정이 아니므로, 서버 값이 오면 언제나 그쪽이 이긴다.
  void _adoptServerState(double dt) {
    final state = presence.me;
    if (state == null) return;

    // 맞았는지는 **시각으로** 안다. 체력 숫자의 감소만 보면 회복과 구별되지
    // 않고, 사망 재가동의 체력 리셋까지 피격으로 오인한다.
    final hurtAt = state.lastDamagedAtMicros;
    final wasHurt = _lastServerHurtAt != null && hurtAt > _lastServerHurtAt!;
    final beforeHp = player.hp;
    _lastServerHurtAt = hurtAt;

    player.adoptServerVitals(
      hp: state.hp,
      maxHp: state.maxHp,
      mp: state.mp,
      maxMp: state.maxMp,
    );

    // 체력 대입 **뒤에** 낸다. 깎인 폭을 알아야 숫자를 띄울 수 있고, 그 폭은
    // 서버 값이 들어온 뒤라야 나온다. 재가동으로 체력이 차오른 경우는 음수가
    // 되므로 숫자 없이 흔들림만 남는다.
    if (wasHurt) player.playHurtReaction(beforeHp - player.hp);

    // 사망은 상태가 아니라 사건이다 — 쓰러지면 서버가 곧바로 안전지대에서
    // 다시 일으켜 세우므로 `alive` 가 내려가 있는 순간을 구독으로 보지 못한다.
    // 누계가 오르는 것을 보고 연출을 시작한다.
    final deaths = state.deaths;
    if (_lastServerDeaths != null && deaths > _lastServerDeaths!) {
      _onServerDeath();
    }
    _lastServerDeaths = deaths;

    // 좌표는 즉시 대입하지 않고 당긴다. 즉시 대입하면 서버가 보내는 간격마다
    // 화면이 끊겨 보이고, 내 입력이 매번 뒤로 밀린다.
    player.reconcileServerGrid(state.grid, dt);

    _adoptServerGrowth();
  }

  /// 서버가 올려 준 성장을 화면에 옮긴다.
  ///
  /// **서버 몹의 경험치는 서버에서만 오른다.** 클라이언트가 같은 킬에 또 주면
  /// 두 배가 되고, 크레딧이 선점자에게 가므로 가로챈 쪽까지 받게 된다. 그래서
  /// 로컬 지급을 막아 두었는데, 그 결과 **화면의 레벨과 경험치 바가 출격 시점에
  /// 멈춰 있었다** — 리더보드만 오르고 내 화면은 그대로인 상태다.
  ///
  /// 서버 쪽이 앞설 때만 그 차이를 채운다. 뒤처져 있으면 두지 않는다 —
  /// 오프라인에서 번 몫이 아직 서버에 닿지 않은 것이고, 그것은 진행 보고가
  /// 따로 올린다.
  void _adoptServerGrowth() {
    final serverXp = presence.serverTotalXp;
    if (serverXp == null) return;
    final gap = serverXp - player.totalXp;
    if (gap <= 0) return;
    player.gainXp(gap);
  }

  /// 서버가 "쓰러졌다" 고 알려 왔을 때의 연출.
  ///
  /// 체력을 깎거나 되살리지 않는다 — 그건 이미 서버가 했고 [_adoptServerState]
  /// 가 받아 왔다. 여기서 하는 일은 화면에서 일어나야 하는 것들뿐이다.
  void _onServerDeath() {
    deaths++;

    // 자동 사냥을 끊는다. 앵커는 쓰러진 자리 근처이므로 그대로 두면 재가동
    // 직후 자기를 죽인 무리 한가운데로 혼자 걸어 들어가 다시 죽는다.
    if (autoHunt.enabled) autoHunt.disable();
    // 안전지대에서 되살아나면 리더와의 거리가 통째로 달라진다. 다가가던 기록을
    // 지우지 않으면 그 거리가 "진전 없음" 으로 읽혀 추종이 곧 끊긴다.
    partyFollow.noteSelfMoved();

    spawnEffect(
      Explosion(
        grid: player.grid.clone(),
        z: 0.35,
        tint: GamePalette.playerAccent,
      ),
    );
    GameAudio.play(Sfx.playerDeath);

    // 재가동 지점은 서버가 정한다. 예측 위치를 거기로 즉시 옮기지 않으면
    // 안전지대로 되돌아가는 동안 몸이 사냥터를 가로질러 걸어간다.
    final state = presence.me;
    if (state != null) {
      player.teleportTo(state.grid);
      player.clearMoveTarget();
    }

    // 월드를 가로지르는 이동이라 카메라를 보간하면 한참을 날아간다.
    camera.viewfinder.position = _cameraTarget();
    _refreshBlockStreaming();
    _refreshMonsterStreaming();

    sync?.reportDeath(deaths: deaths, score: score);
  }

  /// 서버가 알려 준 다른 요원 목록을 화면의 몸과 맞춘다.
  ///
  /// 매 프레임 전부 새로 만들지 않는다. 그러면 보간 상태가 사라져 남들이
  /// 초당 60번 제자리에서 다시 태어나고, 걸어오는 모습이 나오지 않는다.
  void _syncRemotePlayers() {
    final seen = <int>{};

    // 가까운 [_maxRemotePlayers] 명만 그린다. 구독이 면적만 자르므로 안전지대처럼
    // 사람이 몰리는 곳에서는 수백 명이 올 수 있고, 그대로 다 만들면 저사양 기기가
    // 먼저 무너진다. 화면에 보이지도 않는 사람을 위해 컴포넌트를 만들 이유가 없다.
    final all = presence.others.toList()
      ..sort((a, b) => (a.grid - player.grid)
          .length2
          .compareTo((b.grid - player.grid).length2));
    final visible =
        all.length > _maxRemotePlayers ? all.take(_maxRemotePlayers) : all;

    for (final other in visible) {
      seen.add(other.characterId);
      final existing = _remotePlayers[other.characterId];
      if (existing != null) {
        existing.applySnapshot(other);
      } else {
        final entity = RemotePlayerEntity(snapshot: other);
        _remotePlayers[other.characterId] = entity;
        world.add(entity);
      }
    }

    // 나간 사람의 몸을 걷어낸다.
    if (_remotePlayers.length != seen.length) {
      _remotePlayers.removeWhere((id, entity) {
        if (seen.contains(id)) return false;
        entity.removeFromParent();
        return true;
      });
    }
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

  /// 자동 사냥의 중심을 다시 잡는 최소 이동 거리(타일).
  ///
  /// 드래그 한 번에 수십 번 들어오는 클릭을 그대로 받지 않기 위한 문턱이다.
  static const double _autoHuntAnchorStep = 1.0;

  /// 자동 사냥의 판단을 받아 실제 조작으로 옮긴다.
  void _updateAutoHunt(double dt) {
    if (!autoHunt.enabled) return;

    // 쓰러져 있는 동안에는 판단하지 않는다. 재가동 처리는 [onPlayerDied] 가
    // 하고, 그때 자동 사냥도 함께 끊는다.
    if (!player.isAlive) return;

    // 조이스틱이나 키보드가 들어오면 사람이 이긴다. 상태는 그대로 두므로
    // 손을 떼면 하던 사냥을 그대로 잇는다.
    // 대시도 사람이 낸 조작이다. 이동 입력 없이 제자리에서 대시하면
    // `moveInput` 이 비어 있어 이 판정을 빠져나가는데, 그러면 자동 사냥이
    // `faceTowards` 로 몸을 돌리고 대시는 매 프레임 그 방향을 속도로 쓰기
    // 때문에 피하려던 대시가 사냥감 쪽으로 휜다.
    final manual = player.moveInput.length2 > 0.001 || player.isDashing;

    // 파티장에게 따라붙는 중에도 사냥은 쉰다. 여기서 판단을 내리면 중심 쪽으로
    // 걸으라는 지시가 [_updatePartyFollow] 가 방금 준 "파티장에게 가라" 를 매
    // 프레임 덮어써, 둘 사이 어딘가에서 제자리걸음을 한다.
    final decision = autoHunt.update(
      dt,
      playerGrid: player.grid,
      candidates: enemies,
      attackRangeTiles: _autoHuntAttackRange,
      suspended: manual || partyFollow.isRejoining,
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
        // 노리는 몹을 그대로 넘긴다. 넘기지 않으면 스윙마다 부채꼴 안 몹
        // 수만큼 서버 공격 요청이 나가고, 서버는 공격 쿨다운으로 첫 건 말고
        // 전부 거절한다 — 자동 사냥은 쉬지 않으므로 그 낭비가 계속 쌓인다.
        player.tryMelee(target: decision.target);
    }
  }

  /// 자동 사냥의 목적지를 플레이어에게 전달한다.
  ///
  /// 목적지가 거의 그대로면 [Player.moveTo] 를 다시 부르지 않는다. 그 메서드는
  /// 부를 때마다 벽 끼임 감지용 누적 시간을 0 으로 되돌리기 때문이다.
  ///
  /// 다만 이것으로 [Player] 쪽 끼임 감지가 살아나지는 **않는다**. 벽에 막힌
  /// 플레이어가 스스로 목표를 버리면 다음 프레임에 여기서 같은 자리를 다시
  /// 지시하므로, 그 안전망은 자동 사냥 중에는 사실상 돌지 않는다. 닿지 못하는
  /// 대상에서 빠져나오는 일은 전적으로 [AutoHuntController.pursuitTimeout] 이
  /// 맡는다 — 그쪽을 늘리거나 없애면 벽 앞에서 멈추는 회귀가 생긴다.
  void _steerAutoHunt(Vector2 destination) {
    final current = player.moveTarget;
    if (current != null && (current - destination).length2 < 0.09) return;
    player.moveTo(destination);
  }

  // ── 파티 추종 ───────────────────────────────────────────────────────

  /// 추종을 끊고 서버가 그 사실을 받아들이기를 기다리는 중인가.
  ///
  /// 끊겠다는 요청은 서버를 한 번 다녀오므로, 그 사이에도 파티 상태는 여전히
  /// "따라가는 중" 이다. 이 표시가 없으면 그동안 매 프레임 다시 끊으려 들고
  /// 배너가 쏟아진다.
  bool _followStopping = false;

  /// 직전 프레임에 따라가고 있었는가.
  ///
  /// 서버가 추종을 푼 순간을 알아채려고 둔다 — 내가 끊은 것과 남이 끊은 것을
  /// 구별해야 알림을 한 번만, 그리고 맞는 경우에만 띄울 수 있다.
  bool _wasFollowing = false;

  /// 지금 파티장을 따라가는 중인가. HUD 가 읽는다.
  bool get isFollowingLeader => party.isFollowing && !_followStopping;

  /// 파티 추종의 판단을 받아 실제 조작으로 옮긴다.
  ///
  /// 추종이 하는 일은 결국 **자동 사냥의 중심을 파티장에게 옮기는 것**이다.
  /// 중심만 따라 움직이면 나머지(다가가기·때리기·사냥감이 없을 때 되돌아오기)는
  /// 기존 자동 사냥이 그대로 해 준다.
  void _updatePartyFollow(double dt) {
    if (!party.isFollowing) {
      // 내가 끊은 것이 아니라 **서버 쪽에서** 풀린 경우가 있다 — 이끌던 사람이
      // 그만두거나, 파티가 해산되거나, 내가 추방됐을 때다. 그때는 조용히 멈추는
      // 대신 사냥터를 지금 자리로 되돌리고 왜 멈췄는지 알린다. 앵커를 그대로 두면
      // 자동 사냥이 옛 리더의 마지막 좌표를 향해 계속 돈다.
      if (_wasFollowing && !_followStopping) {
        if (autoHunt.enabled) autoHunt.moveAnchor(player.grid);
        _showBanner('추종이 끝났다');
      }
      _wasFollowing = false;
      _followStopping = false;
      partyFollow.reset();
      return;
    }
    _wasFollowing = true;
    if (_followStopping) return;

    // 쓰러져 있는 동안에는 판단하지 않는다. 되살아난 뒤 거리를 보고 이어갈지
    // 정하며, 너무 멀면 그때 스스로 끊는다.
    if (!player.isAlive) return;

    final decision = partyFollow.update(
      dt,
      following: true,
      leader: _followTarget(),
      selfGrid: player.grid,
    );

    switch (decision.action) {
      case PartyFollowAction.none:
        break;
      case PartyFollowAction.lost:
        _stopFollowing(decision.message);
      case PartyFollowAction.hold:
        // 파티장이 쓰러져 있다. 중심을 옮기지 않고 하던 사냥을 잇는다.
        break;
      case PartyFollowAction.rejoin:
        // 사냥보다 따라붙는 것이 먼저다. 자동 사냥은 이번 프레임을 쉰다
        // ([_updateAutoHunt] 가 `partyFollow.isRejoining` 을 보고 판단을 미룬다).
        _steerAutoHunt(decision.destination!);
      case PartyFollowAction.anchor:
        if (autoHunt.enabled) {
          autoHunt.moveAnchor(decision.destination!);
        } else {
          // 따라다니는 것과 그 주변을 사냥하는 것은 한 몸이다. 사냥이 꺼져
          // 있으면 파티장 자리에서 켠다.
          autoHunt.enable(decision.destination!);
        }
    }
  }

  /// 내가 따라가기로 한 사람. 아무도 따라가지 않으면 null.
  int? get _followingCharacterId {
    final self = party.selfCharacterId;
    if (self == null) return null;
    for (final member in party.members) {
      if (member.characterId == self) return member.followingCharacterId;
    }
    return null;
  }

  /// 따라가는 사람이 지금 월드 어디에 있는지. 보이지 않으면 null.
  FollowTarget? _followTarget() {
    // **파티장이 아니라 "내가 따라가기로 한 사람"** 을 본다. 이끄는 사람은 파티를
    // 만든 사람과 다를 수 있고, 그때 파티장을 따라가면 누른 것과 다른 결과가 된다.
    final leaderId = _followingCharacterId;
    if (leaderId == null) return null;

    for (final other in presence.others) {
      if (other.characterId != leaderId) continue;
      return FollowTarget(
        characterId: other.characterId,
        grid: other.grid,
        alive: other.alive,
      );
    }
    return null;
  }

  /// 추종을 끊는다. 사냥까지 멈추지는 않는다.
  ///
  /// 파티장을 놓쳤다고 그 자리에 멈춰 서면, 눈을 떼고 있던 사람에게는 그저
  /// 캐릭터가 굳은 것으로 보인다. 하던 사냥은 지금 서 있는 자리를 중심으로
  /// 이어 간다.
  void _stopFollowing([String? message]) {
    _followStopping = true;
    partyFollow.reset();
    if (autoHunt.enabled) autoHunt.moveAnchor(player.grid);
    if (message != null) _showBanner(message);
    unawaited(_pushFollowing(false));
  }

  /// 추종 여부를 서버에 알린다. 닿지 못하면 그 사실을 숨기지 않는다.
  ///
  /// 화면은 이미 그렇게 움직이고 있는데 서버가 모르면, 다른 파티원 눈에는 내가
  /// 아직 따라다니는 것으로 보인다. 조용히 넘어가면 그 어긋남을 아무도 눈치채지
  /// 못한 채 남는다.
  Future<void> _pushFollowing(bool following) async {
    try {
      await party.setFollowing(following);
    } catch (_) {
      _showBanner('추종 상태를 서버에 알리지 못했다');
    }
  }

  // ── 원격 요원 선택 ──────────────────────────────────────────────────

  /// 지금 골라 둔 다른 요원. 없으면 null.
  ///
  /// 이 값이 곧 하단 행동 막대가 누구를 향하는지를 정한다.
  int? _selectedRemoteCharacterId;

  int? get selectedRemoteCharacterId => _selectedRemoteCharacterId;

  /// 고른 요원의 지금 모습. 월드에서 사라졌으면 null.
  RemotePlayer? get selectedRemotePlayer {
    final id = _selectedRemoteCharacterId;
    if (id == null) return null;
    for (final other in presence.others) {
      if (other.characterId == id) return other;
    }
    return null;
  }

  /// 다른 요원을 고른다. 몸을 눌렀을 때 [RemotePlayerEntity] 가 부른다.
  void selectRemotePlayer(int characterId) {
    if (_selectedRemoteCharacterId == characterId) return;
    _selectedRemoteCharacterId = characterId;
    GameAudio.play(Sfx.uiClick);
  }

  /// 골라 둔 요원을 놓는다. 빈 땅을 누르면 불린다.
  void clearRemotePlayerSelection() {
    _selectedRemoteCharacterId = null;
  }

  /// 화면 가운데에 한 줄을 띄운다.
  ///
  /// HUD 컴포넌트가 사용자에게 알릴 일이 있을 때 쓴다 — 배너를 그리는 자리는
  /// 하나여야 여러 알림이 서로를 덮어쓰지 않는다.
  void showBanner(String message) => _showBanner(message);

  /// 파티 패널을 열고 닫는다. 월드 메뉴가 부른다.
  void togglePartyPanel() {
    _partyPanel.toggle();
    GameAudio.play(Sfx.uiClick);
  }

  /// 근처 요원을 파티로 부른다.
  void invitePlayerToParty(int characterId, String name) {
    GameAudio.play(Sfx.uiClick);
    _showBanner('$name 님을 초대했다');
    unawaited(_runPartyAction(() => party.invite(characterId)));
  }

  /// 주변에 있는 요원을 한 번에 부른다.
  void inviteNearbyToParty() {
    GameAudio.play(Sfx.uiClick);
    _showBanner('주변 요원을 부른다');
    unawaited(_runPartyAction(party.inviteNearby));
  }

  /// 받은 초대를 수락한다.
  void acceptPartyInvite(PartyInviteInfo invite) {
    GameAudio.play(Sfx.uiClick);
    unawaited(_runPartyAction(() => party.accept(invite.id)));
  }

  /// 받은 초대를 거절한다.
  void declinePartyInvite(PartyInviteInfo invite) {
    GameAudio.play(Sfx.uiClick);
    unawaited(_runPartyAction(() => party.decline(invite.id)));
  }

  /// 파티장 자리를 넘긴다.
  void promotePartyMember(int characterId, String name) {
    GameAudio.play(Sfx.uiClick);
    _showBanner('$name 님에게 파티장을 넘긴다');
    unawaited(_runPartyAction(() => party.promote(characterId)));
  }

  /// 파티에서 나간다.
  void leavePartyFromPanel() {
    GameAudio.play(Sfx.uiClick);
    if (isFollowingLeader) _stopFollowing();
    _showBanner('파티에서 나왔다');
    unawaited(_runPartyAction(party.leave));
  }

  /// 파티를 해산한다.
  void disbandPartyFromPanel() {
    GameAudio.play(Sfx.uiClick);
    _showBanner('파티를 해산했다');
    unawaited(_runPartyAction(party.disband));
  }

  /// 파티 요청을 보내고, 서버가 거절하면 그 사유를 화면에 띄운다.
  ///
  /// 삼키지 않는 이유는 파티의 실패가 **사람에게 설명되어야 하는 실패**이기
  /// 때문이다. "상대가 이미 다른 파티에 있다" 처럼 서버가 문장으로 주는 사유를
  /// 지워 버리면, 눌렀는데 아무 일도 일어나지 않는 화면이 된다.
  Future<void> _runPartyAction(Future<void> Function() action) async {
    try {
      await action();
    } on SpacetimeDbReducerException catch (error) {
      // 서버가 한국어 문장으로 사유를 준다. 전송 과정에서 앞에 붙는 찌꺼기만
      // 벗겨서 그대로 보여준다.
      _showBanner(cleanReducerError(error.message));
    } on Object {
      _showBanner('서버에 닿지 못했다');
    }
  }

  /// 사냥을 이끌기 시작하거나 그만둔다. 파티원이면 누구나 할 수 있다.
  ///
  /// 파티장(파티를 만든 사람)과는 다른 축이다 — 길을 아는 사람이 앞장서면 된다.
  void togglePartyHuntLead() {
    if (status != GameStatus.playing) return;
    if (!party.inParty) {
      _showBanner('파티가 없다');
      return;
    }

    GameAudio.play(Sfx.uiClick);
    if (party.isHuntLeading) {
      _showBanner('이끌기를 그만뒀다');
      unawaited(_runPartyAction(party.stopHuntLead));
      return;
    }

    if (party.hasHuntLead) {
      _showBanner('다른 요원이 이끌고 있다');
      return;
    }

    _showBanner('사냥을 이끈다 — 파티원이 따라올 수 있다');
    unawaited(_runPartyAction(party.startHuntLead));
  }

  /// 진행 중인 이끌기에 참여한다. 따라가는 중이면 그만둔다.
  void togglePartyFollow() {
    if (status != GameStatus.playing) return;
    if (!party.inParty) {
      _showBanner('파티가 없다');
      return;
    }
    if (isFollowingLeader) {
      GameAudio.play(Sfx.uiClick);
      _stopFollowing('추종 해제');
      return;
    }

    if (!party.hasHuntLead) {
      _showBanner('이끄는 요원이 없다');
      return;
    }
    if (party.isHuntLeading) {
      _showBanner('이끄는 중에는 따라갈 수 없다');
      return;
    }

    GameAudio.play(Sfx.uiClick);
    _followStopping = false;
    partyFollow.reset();
    _showBanner('추종을 시작한다 — 경험치는 각자 몫이다');
    // 어느 이끌기인지 함께 보낸다. 그 사이 이끄는 사람이 바뀌었으면 서버가
    // 거절하고, 누른 것과 다른 사람을 따라가는 일이 생기지 않는다.
    unawaited(_runPartyAction(() => party.acceptHuntLead(party.huntLeadSeq)));
  }

  /// 자동 사냥을 켜고 끈다. 켤 때는 지금 서 있는 자리가 중심이 된다.
  void toggleAutoHunt() {
    if (status != GameStatus.playing || !player.isAlive) return;

    // 추종 중에 사냥을 끄겠다는 것은 "혼자 하겠다" 는 뜻이다. 추종만 남겨 두면
    // 다음 프레임에 사냥이 다시 켜져 버튼이 듣지 않는 것처럼 보인다.
    if (isFollowingLeader) {
      _stopFollowing('추종 해제');
    }

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

  /// 지금 소리가 꺼져 있는지. 음소거 버튼이 매 프레임 이 값을 보고 그린다.
  bool get isAudioMuted => GameAudio.muted;

  /// 효과음과 배경음을 통째로 끄고 켠다. 고른 상태는 다음 실행까지 남는다.
  void toggleMute() {
    final muted = GameAudio.toggleMuted();
    // 켜는 쪽으로 뒤집었을 때만 소리로 답한다. 끄는 순간의 클릭음은 이미
    // 음소거에 걸려 울리지 않는다 — 침묵 자체가 그 답이다.
    if (!muted) GameAudio.play(Sfx.uiClick);
    _showBanner(muted ? '소리 꺼짐' : '소리 켜짐');
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
      // 전리품도 서버가 쥐고 있으므로 같은 주기로 맞춘다. 몹이 쓰러지는 자리와
      // 떨어지는 자리가 같으니 따로 돌 이유가 없다.
      _syncServerLoot();
    }
  }

  /// 서버가 놓아 둔 전리품을 화면의 몸과 맞춘다.
  ///
  /// **무엇이 떨어졌는지는 서버가 정한다.** 각자 굴리면 같은 몹을 잡고도 서로
  /// 다른 것을 보게 되어, 누가 무엇을 가져갔는지를 두고 이야기할 수조차 없다.
  void _syncServerLoot() {
    if (!presence.isAvailable) return;

    final seen = <int>{};
    for (final loot in presence.loots) {
      final kind = _lootKindByName[loot.kind];
      // 서버에 새 종류가 생겼는데 이 클라이언트가 낡았다. 그리지 않고 넘긴다 —
      // 알 수 없는 것을 억지로 그리면 엉뚱한 아이콘이 뜬다.
      if (kind == null) continue;
      seen.add(loot.id);
      if (_serverLoot.containsKey(loot.id)) continue;

      final pickup = Pickup(
        grid: loot.grid.clone(),
        kind: kind,
        amount: loot.amount.toDouble(),
        serverId: loot.id,
      );
      _serverLoot[loot.id] = pickup;
      pickups.add(pickup);
      world.add(pickup);
    }

    // 표에서 사라진 것은 누군가 주웠거나 수명이 다한 것이다.
    if (_serverLoot.length == seen.length) return;
    final gone = [
      for (final id in _serverLoot.keys)
        if (!seen.contains(id)) id,
    ];
    for (final id in gone) {
      _serverLoot.remove(id)?.removeFromParent();
    }
  }

  /// 화면에 올라와 있는 서버 전리품. 번호로 같은 것을 다시 찾는다.
  final Map<int, Pickup> _serverLoot = {};

  /// 서버가 보내는 이름을 전리품 종류로 옮긴다.
  ///
  /// 서버 `world.rs` 의 `LOOT_KINDS` 와 같은 이름이어야 한다.
  static final Map<String, PickupKind> _lootKindByName = {
    for (final kind in PickupKind.values) kind.name: kind,
  };

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
  /// 서버가 알려 준 몬스터를 화면의 몸과 맞춘다.
  ///
  /// **몬스터의 진실은 전부 서버에 있다.** 여기서 만들어 내거나 없애는 판단을
  /// 하지 않고, 서버 표에 있는 것을 그대로 비춘다. 로컬에서 따로 굴리면 A 가
  /// 잡은 몹이 B 화면에 살아 있게 되어 같은 대상을 함께 때리는 일이 성립하지
  /// 않는다.
  ///
  /// 화면 밖 몹까지 컴포넌트로 들고 있지는 않는다. 서버에는 7 천 기가 있고
  /// 그 전부를 그릴 이유가 없다 — 멀어지면 컴포넌트만 걷어내고, 다시 다가가면
  /// 서버가 준 최신 상태로 되살린다.
  void _refreshMonsterStreaming() {
    final visible = _monsterReleaseRadius * _monsterReleaseRadius;
    final seen = <int>{};

    // **화면 안을 먼저, 그다음 가까운 순.** 구독은 면적만 자르므로(청크 3×3)
    // 저레벨 사냥터처럼 몹이 조밀한 곳에서는 [_maxActiveMonsters] 를 훌쩍 넘는
    // 수가 온다. 거리만으로 자르면 화면 모서리 밖의 몹이 화면 한복판의 몹보다
    // 가까울 수 있어, 정작 눈에 보여야 할 자리가 빈다.
    //
    // 화면 경계는 아이소메트릭에서 마름모라 이 사각형이 실제 시야보다 넉넉하다.
    // 넉넉한 쪽이 맞다 — 가장자리에서 몹이 갑자기 튀어나오는 것보다 낫다.
    final bounds = visibleGridBounds(margin: 4);
    final byPriority = presence.monsters.toList()
      ..sort((a, b) {
        final aInView = bounds.contains(Offset(a.grid.x, a.grid.y));
        final bInView = bounds.contains(Offset(b.grid.x, b.grid.y));
        if (aInView != bInView) return aInView ? -1 : 1;
        return (a.grid - player.grid)
            .length2
            .compareTo((b.grid - player.grid).length2);
      });

    for (final snapshot in byPriority) {
      // 멀리 있는 것은 아직 그리지 않는다.
      if ((snapshot.grid - player.grid).length2 > visible) continue;
      seen.add(snapshot.id);

      final existing = _activeMonsters[snapshot.id];
      if (existing != null) {
        existing.applyServerState(
          grid: snapshot.grid,
          hpRatio: snapshot.hpRatio,
          alive: snapshot.alive,
          tagged: snapshot.taggedByMe,
          facing: snapshot.facing,
          lastAttackAtMicros: snapshot.lastAttackAtMicros,
        );
        continue;
      }

      // 쓰러져 있는 몹은 새로 만들지 않는다. 되살아나면 그때 나타난다.
      if (!snapshot.alive) continue;
      if (_activeMonsters.length >= _maxActiveMonsters) continue;

      final enemy = Enemy(
        species: MonsterCodex.byLevel(snapshot.level),
        grid: snapshot.grid.clone(),
      )..serverId = snapshot.id;
      enemy.applyServerState(
        grid: snapshot.grid,
        hpRatio: snapshot.hpRatio,
        alive: snapshot.alive,
        tagged: snapshot.taggedByMe,
        facing: snapshot.facing,
        lastAttackAtMicros: snapshot.lastAttackAtMicros,
      );
      _activeMonsters[snapshot.id] = enemy;
      enemies.add(enemy);
      world.add(enemy);
    }

    // 멀어졌거나 서버에서 사라진 몹의 몸을 걷어낸다.
    if (_activeMonsters.length == seen.length) return;
    final stale = <int>[];
    _activeMonsters.forEach((id, enemy) {
      if (!seen.contains(id)) stale.add(id);
    });
    for (final id in stale) {
      final enemy = _activeMonsters.remove(id);
      if (enemy == null) continue;
      enemies.remove(enemy);
      // 자동 사냥이 쥐고 있으면 사라진 좌표를 향해 계속 걷는다.
      autoHunt.forget(enemy);
      enemy.removeFromParent();
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
    // 추종 중에는 사냥터를 따로 정할 수 없다. 중심은 파티장이 쥐고 있고, 여기서
    // 옮겨 봐야 다음 프레임에 파티장 자리로 되돌아간다 — 버튼이 고장 난 것처럼
    // 보이므로 왜 안 되는지 알린다.
    if (isFollowingLeader) {
      _showBanner('추종 중에는 사냥터를 옮길 수 없다');
      return;
    }

    if (autoHunt.enabled) {
      // 드래그는 포인터가 움직일 때마다 이 함수를 부른다(ClickMoveLayer).
      // 그대로 받으면 앵커가 손가락을 따라다니면서 타깃과 추격 시계를 매
      // 이벤트 초기화해, 끄는 내내 사냥이 재시작만 반복하고 목적지 표식도
      // 프레임마다 쌓인다. 사냥터를 옮겼다고 할 만큼 움직였을 때만 받는다.
      final anchor = autoHunt.anchor;
      if (anchor != null && (anchor - target).length < _autoHuntAnchorStep) {
        return;
      }
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
  ///
  /// **다른 요원은 여기 들어오지 않는다.** PK 는 허용되지만, 남의 몸을 로컬에서
  /// 깎으면 그 순간 두 화면이 갈라진다 — 서버가 안전지대나 사거리로 거절해도
  /// 내 화면에서는 이미 피가 깎여 있다. 사람을 치는 것은 [remoteTargetInArc] 로
  /// 골라 **의도만 서버에 보낸다.**
  List<Damageable> _damageableTargets() => <Damageable>[
        ...enemies.where((enemy) => enemy.isAlive),
        ..._destructibles.where((block) => block.isAlive),
      ];

  /// 근접 사거리와 부채꼴 안에 있는, 가장 가까운 다른 요원의 캐릭터 번호.
  ///
  /// 없으면 `null`. 여럿이면 하나만 고른다 — 서버 쿨다운이 어차피 한 번만
  /// 받아들이므로, 여러 요청을 보내면 누가 맞을지가 도착 순서에 좌우된다.
  int? remoteTargetInArc(Vector2 origin, Vector2 direction, double range) {
    int? best;
    var bestDistance = double.infinity;
    for (final entry in _remotePlayers.entries) {
      final other = entry.value;
      if (!other.alive) continue;
      final toTarget = other.grid - origin;
      final distance = toTarget.length;
      if (distance > range + other.bodyRadius) continue;
      if (distance > 0.001) {
        // 근접 판정과 같은 전방 120도 부채꼴을 쓴다. 규칙이 갈라지면 몹은
        // 맞는데 사람은 안 맞는 각도가 생긴다.
        if (toTarget.normalized().dot(direction) < 0.35) continue;
      }
      if (distance < bestDistance) {
        bestDistance = distance;
        best = entry.key;
      }
    }
    return best;
  }

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
    // 월드에서 먼저 빠진다. 남겨 두면 조종하는 사람이 없는 몸이 사냥터
    // 한복판에 서 있게 된다.
    presence.leave();
    // 파티 구독만 닫는다. 탈퇴는 하지 않는다 — 잠깐 자리를 비운 것과 파티를
    // 떠난 것은 다르다.
    party.detach();

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

    // 서버가 모는 개체는 서버 표에서 사라지거나 되살아난다. 여기서는 화면의
    // 몸만 걷어내고, 리스폰은 서버 정비 틱이 맡는다.
    final serverId = enemy.serverId;
    if (serverId != null) _activeMonsters.remove(serverId);

    kills++;
    // 점수는 골격 등급과 몬스터 레벨을 함께 반영한다.
    final baseScore = switch (enemy.build) {
      MonsterBuild.drone => 15,
      MonsterBuild.walker => 30,
      MonsterBuild.siege => 70,
      MonsterBuild.sovereign => 400,
    };
    score += (baseScore * (1 + enemy.level * 0.05)).round();

    // **경험치는 서버가 준다.** 서버가 모는 몹은 `award_kill` 이 선점자에게
    // 크레딧을 주므로, 여기서 또 주면 두 배가 된다. 게다가 크레딧은 막타가
    // 아니라 **처음 때린 사람**에게 가므로, 로컬에서 주면 가로챈 쪽도 받는다.
    if (!enemy.isServerDriven) {
      player.gainXp(
        LevelSystem.killXp(enemy.xpValue, playerLevel: player.level),
      );
    }
    hitStop.trigger(enemy.isBoss ? 0.16 : 0.05);

    // 잔해에서 전리품이 튀어나온다. 강한 개체일수록 조금 더 후하다.
    //
    // 예전에는 웨이브 번호가 이 기울기를 정했다. 판 구분이 없는 월드에서는
    // 그런 진행 축이 없으므로, 쓰러뜨린 개체의 레벨이 그 자리를 대신한다.
    // 더 위험한 곳으로 나갈수록 벌이가 나아진다는 뜻이 되어, 사냥터를 골라
    // 다니는 것 자체가 선택이 된다. 20 레벨 언저리에서 상한에 닿던 곡선은
    // 그대로 두었다.
    //
    // **서버가 모는 몹의 전리품은 서버가 떨군다**(`spawn_loot`). 여기서 또 내면
    // 같은 몹을 잡고도 사람마다 다른 것을 줍게 되어 "하나의 월드" 가 깨진다.
    // 아래 굴림은 연습 모드처럼 서버가 없을 때만 도는 길이다.
    if (!enemy.isServerDriven) {
      _spawnDrops(
        enemy.grid,
        DropTables.forEnemy(enemy.build),
        luck: math.min(0.15, enemy.level * 0.0075),
        amountMultiplier: 1 + math.min(0.5, enemy.level * 0.025),
      );
    }

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
    // 서버가 쥔 것이면 목록에서도 뺀다. 서버 표에서도 곧 사라지지만, 그
    // 왕복을 기다리는 동안 같은 번호로 몸이 다시 붙는 것을 막는다.
    final id = pickup.serverId;
    if (id != null) _serverLoot.remove(id);
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
    partyFollow.noteSelfMoved();

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

    // 배경음악은 자동으로 켜지 않는다. 트랙이 필요한 연출이 스스로
    // [GameAudio.playMusic] 을 부른다.

    // 월드에 들어간다. **내 몸이 실제로 선 자리**를 함께 넘겨야 남의 화면에
    // 곧바로 제자리에 나타난다. 실패해도 게임은 그대로 굴러가고, 다른 요원만
    // 보이지 않는다.
    presence.enter(player.grid);
    unawaited(party.attach());
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

    map = LevelMap.generate();
    kills = 0;
    score = 0;
    survivalTime = 0;
    comboDisplayTimer = 0;
    _blockStreamTimer = 0;
    _monsterStreamTimer = 0;

    world.add(GroundLayer(map));
    world.add(SafeZoneField(map.safeZone));
    // 월드 정중앙에 선 나무. 안전지대 한복판의 이정표다.
    world.add(WorldTree(grid: map.worldCenter));
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
