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
import 'entities/player.dart';
import 'entities/projectile.dart';
import 'fx/explosion.dart';
import 'fx/hit_spark.dart';
import 'iso.dart';
import 'level/ground_layer.dart';
import 'level/level_map.dart';
import 'level/safe_zone.dart';
import 'net/game_sync.dart';
import 'palette.dart';
import 'systems/drop_table.dart';
import 'systems/inventory.dart';
import 'systems/level_system.dart';
import 'systems/monster_population.dart';
import 'systems/wave_director.dart';
import 'ui/character_screen.dart';
import 'ui/hud.dart';
import 'ui/inventory_ui.dart';
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
  ActionRpgGame({this.sync});

  /// SpacetimeDB 연동(선택). null이면 완전 오프라인으로 동작한다.
  final GameSync? sync;

  late LevelMap map;
  late Player player;
  late WaveDirector _director;
  late Hud _hud;
  late InventoryPanel _inventoryPanel;
  late CharacterScreen _characterScreen;
  late WorldMenu _worldMenu;

  /// 이 접속에 쓰는 캐릭터 이름.
  ///
  /// 계정 시스템이 붙기 전까지는 기본 호출부호를 쓴다.
  String characterName = 'UNIT-01';

  /// 월드 전역에 상주하는 로봇 개체군의 장부.
  late MonsterPopulation population;

  /// 회수한 포션을 담아 두는 가방.
  final Inventory inventory = Inventory();

  final List<Enemy> enemies = [];
  final List<Pickup> pickups = [];

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
  final List<EnemyKind> _spawnQueue = [];
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
  double _hitStop = 0;

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

    player = Player(grid: map.respawnPoint());
    world.add(player);

    camera.backdrop = CyberBackdrop();
    camera.viewfinder.zoom = _zoomForSize(size);
    camera.viewfinder.position = _cameraTarget();

    _hud = Hud();
    camera.viewport.add(AtmosphereOverlay());
    camera.viewport.add(_hud);
    _addTouchControls();

    // 1 km² 월드는 통째로 들 수 없다. 주변 청크부터 채워 넣는다.
    _refreshBlockStreaming();
    _refreshMonsterStreaming();

    overlays.add(Overlays.mainMenu);
    pauseEngine();
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
        enabledCheck: () => player.energy >= 12,
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

    // 퀵슬롯과 버프 표시는 화면 크기에 맞춰 스스로 자리를 잡는다.
    _inventoryPanel = InventoryPanel();
    _characterScreen = CharacterScreen();
    _worldMenu = WorldMenu(
      entries: [
        WorldMenuEntry(
          label: '캐릭터 정보',
          icon: WorldMenuIcon.character,
          onSelected: openCharacterScreen,
        ),
      ],
    );
    camera.viewport.addAll([
      PotionQuickBar(),
      BuffBar(),
      _worldMenu,
      _inventoryPanel,
      _characterScreen,
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
    // 월드 메뉴는 우상단 미니맵 바로 아래에 붙인다.
    _worldMenu.position = Vector2(size.x - 18, 168);
    // 퀵슬롯과 버프 표시는 화면 크기에 맞춰 스스로 자리를 잡는다.
  }

  // ── 게임 루프 ───────────────────────────────────────────────────────

  @override
  void update(double dt) {
    if (status != GameStatus.playing) {
      super.update(dt);
      return;
    }

    // 타격감을 위한 짧은 히트스톱.
    if (_hitStop > 0) {
      _hitStop -= dt;
      dt *= 0.25;
    }

    survivalTime += dt;
    if (comboDisplayTimer > 0) comboDisplayTimer -= dt;

    _applyInput();
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
    enemies.removeWhere((enemy) => enemy.isRemoved);
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
        kind: seed.kind,
        grid: map.nearestWalkable(seed.position),
        hpMultiplier: seed.hpMultiplier,
        damageMultiplier: seed.damageMultiplier,
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

    // 남은 적이 없으면 웨이브 종료.
    if (enemies.every((enemy) => !enemy.isAlive)) {
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
    final kind = _spawnQueue.removeAt(0);
    final plan = currentPlan;
    final spawnGrid = _director.pickSpawnPoint(
      player.grid,
      minDistance: kind == EnemyKind.commander ? 11 : 9,
    );
    final enemy = Enemy(
      kind: kind,
      grid: spawnGrid,
      hpMultiplier: plan?.hpMultiplier ?? 1,
      damageMultiplier: plan?.damageMultiplier ?? 1,
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
  Iterable<Damageable> meleeTargets() sync* {
    yield* enemies.where((enemy) => enemy.isAlive);
    yield* _destructibles.where((block) => block.isAlive);
  }

  /// 플레이어 발사체가 명중할 수 있는 대상 목록.
  Iterable<Damageable> projectileTargetsForPlayer() sync* {
    yield* enemies.where((enemy) => enemy.isAlive);
    yield* _destructibles.where((block) => block.isAlive);
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
  bool usePotion(PickupKind kind) {
    if (status != GameStatus.playing) return false;

    final result = inventory.use(kind, player);
    if (result == null) {
      GameAudio.play(Sfx.uiError);
      return false;
    }

    // 무엇이 얼마나 회복됐는지 한 줄로 알려 준다.
    final parts = <String>[];
    if (result.healed > 0) parts.add('+${result.healed.round()} HP');
    if (result.energized > 0) parts.add('+${result.energized.round()} EN');
    if (result.buffed) parts.add(result.spec.name);
    if (parts.isNotEmpty) _showBanner(parts.join('  '));

    GameAudio.play(_lootSfx(kind), volumeScale: 1.2);
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
    _inventoryPanel.toggle();
    GameAudio.play(Sfx.uiClick);
  }

  /// 캐릭터 정보 화면이 떠 있는지 여부.
  bool get isCharacterScreenOpen => _characterScreen.isOpen;

  /// 캐릭터 정보 화면을 연다. 인벤토리와는 동시에 뜨지 않는다.
  void openCharacterScreen() {
    if (status != GameStatus.playing) return;
    _inventoryPanel.close();
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

  // ── 이벤트 콜백 ─────────────────────────────────────────────────────

  /// 적이 파괴되었을 때 호출된다.
  void onEnemyKilled(Enemy enemy) {
    enemies.remove(enemy);

    // 월드에 상주하던 개체라면 장부에 파괴를 기록한다. 시간이 지나면
    // AI가 같은 자리에 새 유닛을 배치하므로 월드가 텅 비지 않는다.
    final seed = enemy.seed;
    if (seed != null) {
      population.markDestroyed(seed);
      _activeMonsters.remove(seed.id);
    }

    kills++;
    score += switch (enemy.kind) {
      EnemyKind.scout => 15,
      EnemyKind.sentry => 30,
      EnemyKind.heavy => 70,
      EnemyKind.commander => 400,
    };
    player.gainXp(
      LevelSystem.killXp(enemy.xpValue, playerLevel: player.level),
    );
    _hitStop = enemy.isBoss ? 0.16 : 0.05;

    // 잔해에서 전리품이 튀어나온다. 후반 웨이브일수록 조금 더 후하다.
    _spawnDrops(
      enemy.grid,
      DropTables.forEnemy(enemy.kind),
      luck: math.min(0.15, waveNumber * 0.01),
      amountMultiplier: 1 + math.min(0.5, waveNumber * 0.02),
    );

    sync?.reportKill(enemy.kind.name, score);
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
        PickupKind.nanoVial || PickupKind.nanoCanister => Sfx.pickupHealth,
        PickupKind.energyCell ||
        PickupKind.overchargeCell ||
        PickupKind.combatStim =>
          Sfx.pickupEnergy,
        PickupKind.dataChip || PickupKind.scrapCore => Sfx.pickupChip,
      };

  /// 플레이어가 피해를 입었을 때 호출된다.
  void onPlayerDamaged() {
    _hitStop = 0.06;
  }

  /// 레벨업 시 호출된다. [milestone]은 5레벨 단위의 강화 구간인지 여부다.
  void onLevelUp(int level, {bool milestone = false}) {
    _showBanner(milestone ? 'LEVEL UP  $level  ▲BOOST' : 'LEVEL UP  $level');
    shakeCamera(milestone ? 10 : 4, milestone ? 0.3 : 0.2);
    sync?.reportLevel(level);
  }

  /// 플레이어가 사망했을 때 호출된다.
  ///
  /// 모두가 하나의 월드를 공유하므로 이 게임에는 게임 오버가 없다. 파괴된
  /// 몸체는 그 자리에 잔해로 남고, 백업된 의식은 안전지대의 접속 지점에서
  /// 곧바로 새 몸체로 재가동된다.
  void onPlayerDied() {
    deaths++;

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
    _showBanner('SYSTEM REBOOT — 안전지대 재가동');

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
    GameAudio.startAmbience();
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

    // 월드를 비우고 새 지형을 만든다.
    world.removeAll(world.children.toList());
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
    player = Player(grid: map.respawnPoint());
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
        case LogicalKeyboardKey.escape:
          // 인벤토리가 열려 있으면 먼저 닫는다.
          if (_inventoryPanel.isOpen) {
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
