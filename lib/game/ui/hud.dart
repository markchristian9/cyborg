import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../action_rpg_game.dart';
import '../entities/pickup.dart';
import '../level/level_map.dart';
import '../level/teleport_destinations.dart';
import '../palette.dart';

/// 화면에 고정되어 표시되는 게임 정보 패널.
class Hud extends PositionComponent with HasGameReference<ActionRpgGame> {
  Hud() : super(priority: 100);

  double _time = 0;
  double _damageFlash = 0;
  double _lastHp = -1;

  static const double _minimapSize = 132;

  /// 레이더가 보여 주는 반경(미터). 월드가 1 km²라 전체가 아니라 주변만 본다.
  static const double _radarRangeTiles = 70;

  // ── 상단 패널의 자리 ────────────────────────────────────────────────
  //
  // 세 패널(생존 정보·월드 배너·미니맵)이 같은 띠를 나눠 쓰므로 자리를 한곳에
  // 모아 둔다. 각자 자기 자리를 따로 계산하면 **좁은 화면에서 겹치는 것을
  // 아무도 알아채지 못한다** — 오류가 나지 않고 그저 나중에 그린 패널이 앞의
  // 것을 덮어, 체력 숫자가 잘린 채로 남는다.

  /// 좌상단 생존 정보 패널의 바깥 사각형(왼쪽·위·너비·높이).
  static const double _vitalsLeft = 10;
  static const double _vitalsTop = 10;
  static const double _vitalsWidth = 268;
  static const double _vitalsHeight = 112;

  /// 패널 사이에 두는 최소 간격.
  static const double _panelGap = 8;

  /// 미니맵 바깥 여백. 오른쪽 끝에서 이만큼 띄운다.
  static const double _minimapMargin = 18;

  final TextPaint _label = TextPaint(
    style: const TextStyle(
      color: GamePalette.textDim,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    ),
  );
  final TextPaint _value = TextPaint(
    style: const TextStyle(
      color: GamePalette.textPrimary,
      fontSize: 15,
      fontWeight: FontWeight.w800,
    ),
  );
  final TextPaint _big = TextPaint(
    style: TextStyle(
      color: GamePalette.textPrimary,
      fontSize: 22,
      fontWeight: FontWeight.w900,
      shadows: [
        Shadow(
          color: GamePalette.hudBorder.withValues(alpha: 0.6),
          blurRadius: 10,
        ),
      ],
    ),
  );
  final TextPaint _headline = TextPaint(
    style: const TextStyle(
      color: GamePalette.hudBorder,
      fontSize: 13,
      fontWeight: FontWeight.w800,
      letterSpacing: 2,
    ),
  );

  @override
  void onGameResize(Vector2 newSize) {
    super.onGameResize(newSize);
    size = newSize;
  }

  @override
  Future<void> onLoad() async {
    size = game.size;
  }

  @override
  void update(double dt) {
    _time += dt;
    if (_damageFlash > 0) _damageFlash -= dt * 2.4;

    final hp = game.player.hp;
    if (_lastHp >= 0 && hp < _lastHp) {
      _damageFlash = 1;
    }
    _lastHp = hp;
  }


  @override
  void render(Canvas canvas) {
    _renderVitals(canvas);
    _renderWorldBanner(canvas);
    _renderMinimap(canvas);
    _renderDamageVignette(canvas);
    if (game.comboDisplayTimer > 0) _renderComboBadge(canvas);
  }

  // ── 좌상단: 생존 정보 ───────────────────────────────────────────────

  void _renderVitals(Canvas canvas) {
    final player = game.player;
    const left = _vitalsLeft + 8;
    const top = _vitalsTop + 8;

    final panel = RRect.fromRectAndRadius(
      vitalsRect,
      const Radius.circular(10),
    );
    canvas.drawRRect(panel, Paint()..color = GamePalette.hudBackground);
    canvas.drawRRect(
      panel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = GamePalette.hudBorder.withValues(alpha: 0.35),
    );

    // 레벨 배지
    canvas.drawCircle(
      const Offset(left + 22, top + 24),
      21,
      Paint()..color = const Color(0xFF14202B),
    );
    canvas.drawCircle(
      const Offset(left + 22, top + 24),
      21,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = GamePalette.hudBorder,
    );
    _big.render(
      canvas,
      '${player.level}',
      Vector2(left + 22, top + 24),
      anchor: Anchor.center,
    );
    // 만렙이 없으므로 'MAX' 표시도 없다. 레벨은 언제나 더 오를 수 있다.
    _label.render(
      canvas,
      'LV',
      Vector2(left + 22, top + 48),
      anchor: Anchor.topCenter,
    );

    const barLeft = left + 54;
    const barWidth = 186.0;

    _renderBar(
      canvas,
      Rect.fromLTWH(barLeft, top + 2, barWidth, 13),
      player.hp / player.maxHp,
      player.hp / player.maxHp < 0.3
          ? GamePalette.hpFillLow
          : GamePalette.hpFill,
      label: 'HP',
      valueText: '${player.hp.ceil()} / ${player.maxHp.round()}',
    );
    // 마력. 스킬을 굴리는 자원이라 남은 양을 숫자까지 보여 준다.
    _renderBar(
      canvas,
      Rect.fromLTWH(barLeft, top + 20, barWidth, 12),
      player.mp / player.maxMp,
      GamePalette.mpFill,
      label: 'MP',
      valueText: '${player.mp.floor()} / ${player.maxMp.round()}',
    );
    _renderBar(
      canvas,
      Rect.fromLTWH(barLeft, top + 38, barWidth, 8),
      player.energy / player.maxEnergy,
      GamePalette.energyFill,
      label: 'EN',
    );
    _renderBar(
      canvas,
      Rect.fromLTWH(barLeft, top + 52, barWidth, 6),
      player.xp / player.xpToNextLevel,
      GamePalette.xpFill,
    );

    if (player.rest.isSheltered) {
      _renderRestBadge(canvas, Rect.fromLTWH(barLeft, top + 2, barWidth, 13));
    }

    // 대시 쿨다운 표시
    final dashReady = game.player.dashCooldownRatio <= 0;
    final dashRect = Rect.fromLTWH(barLeft, top + 66, 58, 14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(dashRect, const Radius.circular(4)),
      Paint()..color = const Color(0xFF14202B),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          dashRect.left,
          dashRect.top,
          dashRect.width * (1 - game.player.dashCooldownRatio),
          dashRect.height,
        ),
        const Radius.circular(4),
      ),
      Paint()
        ..color = dashReady
            ? GamePalette.hudBorder.withValues(alpha: 0.75)
            : GamePalette.hudBorder.withValues(alpha: 0.3),
    );
    _label.render(
      canvas,
      'DASH',
      Vector2(dashRect.center.dx, dashRect.center.dy),
      anchor: Anchor.center,
    );

    // 처치 수
    _label.render(canvas, 'KILLS', Vector2(barLeft + 74, top + 66));
    _value.render(canvas, '${game.kills}', Vector2(barLeft + 74, top + 76));

    _label.render(canvas, 'SCORE', Vector2(barLeft + 126, top + 66));
    _value.render(canvas, '${game.score}', Vector2(barLeft + 126, top + 76));
  }

  /// 안전지대 안일 때 체력 바 오른쪽 위에 붙는 휴식 배지.
  ///
  /// 회복이 이미 돌고 있으면 초록으로 맥동하고, 얻어맞은 직후라 아직
  /// 기다려야 하면 남은 시간을 흐린 글씨로 알려 준다.
  void _renderRestBadge(Canvas canvas, Rect hpRect) {
    final rest = game.player.rest;
    final recovering = rest.isRecovering;
    final color = recovering ? GamePalette.healGlow : GamePalette.textDim;
    final pulse = recovering ? 0.7 + math.sin(_time * 5) * 0.3 : 1.0;

    final text = recovering
        ? 'RESTING'
        : 'REST IN ${rest.warmupRemaining.ceil()}s';
    final badge = Rect.fromLTWH(hpRect.right - 84, hpRect.top - 15, 84, 14);
    final rrect = RRect.fromRectAndRadius(badge, const Radius.circular(7));

    canvas.drawRRect(rrect, Paint()..color = GamePalette.hudBackground);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = color.withValues(alpha: 0.75 * pulse),
    );
    TextPaint(
      style: TextStyle(
        color: color.withValues(alpha: pulse),
        fontSize: 9,
        fontWeight: FontWeight.w900,
        letterSpacing: 1,
      ),
    ).render(
      canvas,
      text,
      Vector2(badge.center.dx, badge.center.dy),
      anchor: Anchor.center,
    );
  }

  void _renderBar(
    Canvas canvas,
    Rect rect,
    double ratio,
    Color color, {
    String? label,
    String? valueText,
  }) {
    final clamped = ratio.clamp(0.0, 1.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
      Paint()..color = const Color(0xFF10161E),
    );
    if (clamped > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.left, rect.top, rect.width * clamped, rect.height),
          Radius.circular(rect.height / 2),
        ),
        Paint()..color = color,
      );
      // 상단 광택
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            rect.left + 1,
            rect.top + 1,
            math.max(0, rect.width * clamped - 2),
            rect.height * 0.36,
          ),
          Radius.circular(rect.height / 3),
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.22),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.5),
    );

    if (label != null && rect.height >= 12) {
      _label.render(
        canvas,
        label,
        Vector2(rect.left + 6, rect.center.dy),
        anchor: Anchor.centerLeft,
      );
    }
    if (valueText != null) {
      _label.render(
        canvas,
        valueText,
        Vector2(rect.right - 6, rect.center.dy),
        anchor: Anchor.centerRight,
      );
    }
  }

  // ── 상단 중앙: 월드 ─────────────────────────────────────────────────

  /// 지금 어디에 있고, 이 월드에 몇 명이 함께 있는지.
  ///
  /// 웨이브 번호가 있던 자리다. 판 구분도 초기화도 없는 하나의 월드에는
  /// "몇 번째" 라고 할 진행도가 없으므로, 그 대신 위치와 동료 수를 알린다.
  void _renderWorldBanner(Canvas canvas) {
    final rect = worldBannerRect;
    final centerX = rect.center.dx;
    final zone = TeleportDestination.at(game.player.grid, game.map);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()..color = GamePalette.hudBackground,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        // 안전지대에서만 테두리가 살아난다. 로봇이 들어오지 못하는 곳이라는
        // 사실은 화면 어디서든 한눈에 보여야 한다.
        ..color = zone.isSafe
            ? GamePalette.hudBorder.withValues(alpha: 0.8)
            : GamePalette.hudBorder.withValues(alpha: 0.35),
    );

    // 글씨는 **상자를 따라간다.** 화면 위쪽에 고정해 두면 좁은 창에서 상자만
    // 한 줄 아래로 내려가고 글씨는 제자리에 남는다.
    _headline.render(
      canvas,
      zone.label,
      Vector2(centerX, rect.top + 11),
      anchor: Anchor.topCenter,
    );
    _label.render(
      canvas,
      _presenceText(),
      Vector2(centerX, rect.top + 31),
      anchor: Anchor.topCenter,
    );
  }

  /// 좌상단 생존 정보 패널이 차지하는 자리.
  @visibleForTesting
  Rect get vitalsRect => const Rect.fromLTWH(
        _vitalsLeft,
        _vitalsTop,
        _vitalsWidth,
        _vitalsHeight,
      );

  /// 우상단 미니맵이 차지하는 자리.
  @visibleForTesting
  Rect get minimapRect => Rect.fromLTWH(
        size.x - _minimapSize - _minimapMargin,
        18,
        _minimapSize,
        _minimapSize,
      );

  /// 상단 중앙 배너가 차지하는 자리. **화면 한복판이 늘 비어 있는 것은 아니다.**
  ///
  /// 좌상단 생존 정보와 우상단 미니맵이 같은 띠를 쓰므로, 창이 좁으면 화면
  /// 중앙에 둔 배너가 그 둘과 겹친다. 배너는 셋 중 마지막에 그려져 앞의 것을
  /// 덮으므로, 겹치는 순간 **체력·마력 숫자가 잘린 채로 남는다** — 오류가 나지
  /// 않아 눈으로 보기 전까지 드러나지 않는다. 720 픽셀 창에서 실제로 그랬다.
  ///
  /// 그래서 **들어갈 자리가 있으면 화면 중앙**을 그대로 쓰고, 없을 때만 빈
  /// 구간 안으로 밀어 넣는다. 넓은 화면에서는 아무것도 달라지지 않는다.
  ///
  /// 사이가 배너보다 좁으면 **한 줄 아래로 내린다.** 세로로 좁히거나 글씨를
  /// 줄이는 길도 있지만, 이 배너는 지금 어디에 있는지를 알리는 줄이라 읽히지
  /// 않으면 있으나 마나다. 한 줄 아래는 어느 너비에서든 비어 있다.
  @visibleForTesting
  Rect get worldBannerRect {
    const width = 236.0;
    const height = 46.0;
    const half = width / 2;

    final minCenter = vitalsRect.right + _panelGap + half;
    final maxCenter = minimapRect.left - _panelGap - half;
    if (maxCenter >= minCenter) {
      return Rect.fromCenter(
        center: Offset((size.x / 2).clamp(minCenter, maxCenter), 32),
        width: width,
        height: height,
      );
    }

    // 🛑 **둘 다의 아래**여야 한다. 생존 정보만 피하면 세로로 더 긴 미니맵과
    // 겹친다 — 좁은 화면일수록 미니맵이 화면 중앙 쪽으로 다가오므로 그 실수가
    // 정확히 여기서 드러난다.
    final top = math.max(vitalsRect.bottom, minimapRect.bottom) + _panelGap;
    return Rect.fromCenter(
      center: Offset(size.x / 2, top + height / 2),
      width: width,
      height: height,
    );
  }

  /// 아래 줄에 적을 접속 상태 문구.
  ///
  /// [WorldPresence.others] 는 나를 뺀 목록이라 하나를 더한다. 서버에 붙지
  /// 않았으면 "1 명" 이라고 적는 대신 오프라인임을 밝힌다 — 아무도 없는 월드와
  /// 연결이 끊긴 상태는 전혀 다른 사정인데 숫자로는 구별되지 않는다.
  String _presenceText() {
    if (!game.presence.isAvailable) return 'OFFLINE';
    return 'AGENTS  ${game.presence.others.length + 1}';
  }

  // ── 우상단: 미니맵 ──────────────────────────────────────────────────

  // 레이더가 돌려 쓰는 붓들.
  //
  // 레이더는 매 프레임 점 수백 개를 찍는다 — 몹 360 기, 사람 50 명, 전리품까지.
  // 점 하나에 [Paint] 를 새로 지으면 그것만으로 초당 수만 개가 태어난다.
  //
  // 🛑 **색이 바뀌는 붓([_radarDot])은 쓰기 직전에 반드시 색을 지정할 것.**
  // 앞선 loop 가 남긴 색이 그대로 묻어 온다.
  final Paint _radarDot = Paint();
  final Paint _radarAgentHalo = Paint()
    ..color = GamePalette.remotePlayer.withValues(alpha: 0.3);
  final Paint _radarSelfHalo = Paint()
    ..color = GamePalette.playerAccent.withValues(alpha: 0.25);
  final Paint _radarSelf = Paint()..color = GamePalette.playerAccent;
  final Paint _radarZoneFill = Paint()
    ..color = GamePalette.safeZoneFill.withValues(alpha: 0.3);
  final Paint _radarZoneEdge = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4
    ..color = GamePalette.safeZoneEdge.withValues(alpha: 0.9);

  // ── 레이더 지형 그림 ────────────────────────────────────────────────
  //
  // 지형은 **월드에 붙박여 있다.** 레이더가 플레이어를 따라 흐를 뿐, 어느 칸이
  // 무슨 지형인지는 변하지 않는다. 그런데도 한때 매 프레임 2,200 칸을 새로
  // 그렸다 — 실측하면 HUD 렌더 시간의 4 분의 3 이 여기였다(약 600 µs).
  //
  // 그래서 한 번 그려 [Picture] 로 굳혀 두고, 그 뒤로는 밀어서 쓴다. 플레이어가
  // 움직여도 그림을 옮기기만 하면 되므로 프레임당 그리기 명령이 2,200 개에서
  // 하나로 준다.

  /// 굳혀 둔 지형 그림. 아직 한 번도 그리지 않았으면 null.
  ui.Picture? _terrainPicture;

  /// 지금 쥐고 있는 지형 그림. 다시 굳혔는지를 회귀 시험이 이것으로 가린다.
  @visibleForTesting
  ui.Picture? get terrainPicture => _terrainPicture;

  /// 레이더 한 픽셀이 담는 거리(타일). 시험이 밀린 거리를 되짚는 데 쓴다.
  @visibleForTesting
  static double get radarScale => _minimapSize / (_radarRangeTiles * 2);

  /// [_terrainPicture] 를 그릴 때 플레이어가 서 있던 자리.
  ///
  /// 지금 자리와의 차이가 곧 그림을 밀어야 할 거리다.
  double _terrainRefX = 0;
  double _terrainRefY = 0;

  /// 그림에 여유로 더 담아 두는 반경(타일).
  ///
  /// 이만큼은 플레이어가 움직여도 그림을 다시 그리지 않는다. 가장자리가 비지
  /// 않으려면 담아 둔 여유보다 적게 움직여야 하므로 두 값이 같다.
  ///
  /// 크게 잡을수록 다시 그리는 일이 드물어지지만 한 번에 그리는 칸이 늘어난다.
  /// 12 타일이면 걸어서 3 초쯤(3.6 타일/초)이고, 그때 그리는 칸은 반경 82 타일
  /// 어치라 매 프레임 그리던 시절의 한 판보다 4 할쯤 많을 뿐이다.
  static const double _terrainMargin = 12;

  /// 굳혀 둔 지형을 그린다. 필요하면 다시 굳힌다.
  void _drawTerrain(
    Canvas canvas,
    LevelMap map,
    Vector2 grid,
    double scale,
    Offset center,
  ) {
    final dx = grid.x - _terrainRefX;
    final dy = grid.y - _terrainRefY;
    if (_terrainPicture == null ||
        dx.abs() > _terrainMargin ||
        dy.abs() > _terrainMargin) {
      _terrainPicture?.dispose();
      _terrainPicture = _recordTerrain(map, grid, scale, center);
      _terrainRefX = grid.x;
      _terrainRefY = grid.y;
    }

    // 그림은 기준 자리에서 그려졌다. 그동안 움직인 만큼 거꾸로 민다.
    canvas.save();
    canvas.translate(
      -(grid.x - _terrainRefX) * scale,
      -(grid.y - _terrainRefY) * scale,
    );
    canvas.drawPicture(_terrainPicture!);
    canvas.restore();
  }

  /// 기준 자리 [grid] 를 중심으로 지형을 한 번 그려 [Picture] 로 굳힌다.
  ui.Picture _recordTerrain(
    LevelMap map,
    Vector2 grid,
    double scale,
    Offset center,
  ) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // 여러 칸을 한 점으로 묶어 훑는다. 매 프레임 100만 칸을 볼 수는 없다.
    const step = 3;
    final cellSize = step * scale + 0.6;
    const reach = _radarRangeTiles + _terrainMargin;
    final minX = (grid.x - reach).floor();
    final maxX = (grid.x + reach).ceil();
    final minY = (grid.y - reach).floor();
    final maxY = (grid.y + reach).ceil();

    final plate = Paint()..color = const Color(0xFFDCEFF8);
    final conduit = Paint()..color = const Color(0xFF9DE8F5);
    final firewall = Paint()..color = const Color(0xFFFFAFC8);
    final tower = Paint()..color = const Color(0xFF6E9DB8);

    final originX = center.dx - grid.x * scale;
    final originY = center.dy - grid.y * scale;

    for (var y = minY; y <= maxY; y += step) {
      final top = originY + y * scale;
      for (var x = minX; x <= maxX; x += step) {
        final tile = map.tileAt(x, y);
        if (tile == TileType.none) continue;
        canvas.drawRect(
          Rect.fromLTWH(originX + x * scale, top, cellSize, cellSize),
          map.isBlocked(x, y)
              ? tower
              : switch (tile) {
                  TileType.circuit || TileType.stream => conduit,
                  TileType.hazard => firewall,
                  _ => plate,
                },
        );
      }
    }
    return recorder.endRecording();
  }

  @override
  void onRemove() {
    // [Picture] 는 네이티브 자원을 쥔다. 놓지 않으면 화면을 오갈 때마다 샌다.
    _terrainPicture?.dispose();
    _terrainPicture = null;
    super.onRemove();
  }

  /// 플레이어를 중심으로 한 근접 레이더.
  ///
  /// 월드가 1 km²라 전체를 132픽셀에 담으면 아무것도 분간할 수 없다.
  /// 그래서 주변 [_radarRangeTiles]미터만 잘라 보여 주고, 실제 위치는
  /// 아래쪽 좌표 표시로 알린다.
  void _renderMinimap(Canvas canvas) {
    final map = game.map;
    final player = game.player;
    final origin = minimapRect.topLeft;
    final center = Offset(_minimapSize / 2, _minimapSize / 2);

    // 레이더 한 픽셀이 담는 거리(미터).
    final scale = _minimapSize / (_radarRangeTiles * 2);

    /// 그리드 좌표를 레이더 안의 위치로 옮긴다.
    ///
    /// 🛑 **[Vector2] 를 받는 판을 새로 만들지 말 것.** 부르는 쪽이 좌표를 담을
    /// [Vector2] 를 하나 더 짓게 되는데, 이 함수는 한 프레임에 수천 번 불린다.
    /// 이미 [Vector2] 를 손에 쥐고 있으면 `.x` · `.y` 를 그대로 넘기면 된다.
    ///
    /// 레이더 원점을 미리 접어 두어 `center + Offset(...)` 두 번 대신 [Offset]
    /// 하나만 짓는다.
    final radarOriginX = center.dx - player.grid.x * scale;
    final radarOriginY = center.dy - player.grid.y * scale;
    Offset toRadar(double gridX, double gridY) =>
        Offset(radarOriginX + gridX * scale, radarOriginY + gridY * scale);

    final frame = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        origin.dx - 6,
        origin.dy - 6,
        _minimapSize + 12,
        _minimapSize + 12,
      ),
      const Radius.circular(8),
    );
    canvas.drawRRect(frame, Paint()..color = GamePalette.hudBackground);
    canvas.drawRRect(
      frame,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = GamePalette.hudBorder.withValues(alpha: 0.35),
    );

    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(origin.dx, origin.dy, _minimapSize, _minimapSize),
        const Radius.circular(4),
      ),
    );
    canvas.translate(origin.dx, origin.dy);

    _drawTerrain(canvas, map, player.grid, scale, center);

    // 안전지대
    final zone = map.safeZone;
    final zoneRect = Rect.fromPoints(
      toRadar(zone.minX, zone.minY),
      toRadar(zone.maxX, zone.maxY),
    );
    canvas.drawRect(zoneRect, _radarZoneFill);
    canvas.drawRect(zoneRect, _radarZoneEdge);

    // 전리품. 무엇이 떨어졌는지 색으로 구분하고 희귀품은 크게 찍는다.
    //
    // 붓은 아래 loop 마다 하나씩 돌려 쓴다. 점 하나에 [Paint] 를 새로 지으면
    // 몹 360 기 · 사람 50 명이 그대로 초당 수만 개가 된다. `canvas.drawX` 는
    // 넘겨받은 붓을 그 자리에서 디스플레이 리스트로 옮겨 적으므로, 다음 점을
    // 그리기 전에 색만 바꿔 주면 된다.
    for (final pickup in game.pickups) {
      _radarDot.color = pickup.spec.color.withValues(alpha: 0.85);
      canvas.drawCircle(
        toRadar(pickup.grid.x, pickup.grid.y),
        pickup.spec.rarity == LootRarity.rare ? 2.6 : 1.8,
        _radarDot,
      );
    }

    // 적. 지휘 유닛은 크게 찍어 멀리서도 알아보게 한다.
    _radarDot.color = GamePalette.robotEye;
    for (final enemy in game.enemies) {
      if (!enemy.isAlive) continue;
      canvas.drawCircle(
        toRadar(enemy.grid.x, enemy.grid.y),
        enemy.isBoss ? 4 : 2.2,
        _radarDot,
      );
    }

    // 같은 월드의 다른 요원. 내 몸(청록)과 갈리는 호박색으로 찍는다.
    //
    // 적(마젠타)보다 조금 크게 그려 "저건 사람이다" 가 먼저 읽히게 한다 —
    // 몹은 지나치면 그만이지만 사람은 함께 사냥할 수도, PK 로 붙을 수도 있어
    // 판단이 필요하다.
    for (final other in game.presence.others) {
      final at = toRadar(other.grid.x, other.grid.y);
      canvas.drawCircle(at, 4.5, _radarAgentHalo);
      _radarDot.color = other.alive
          ? GamePalette.remotePlayer
          : GamePalette.remotePlayer.withValues(alpha: 0.45);
      canvas.drawCircle(at, 2.6, _radarDot);
    }

    // 플레이어(맥동하는 링)
    final pulse = 3 + math.sin(_time * 4) * 1.5;
    canvas.drawCircle(center, pulse + 3, _radarSelfHalo);
    canvas.drawCircle(center, 2.8, _radarSelf);

    canvas.restore();

    // 레이더 아래에 현재 좌표와 사거리를 적어 1 km 월드에서 길을 잃지 않게 한다.
    _label.render(
      canvas,
      '${player.grid.x.round()} , ${player.grid.y.round()} m'
      '   ·   R ${_radarRangeTiles.round()} m',
      Vector2(origin.dx + _minimapSize, origin.dy + _minimapSize + 12),
      anchor: Anchor.topRight,
    );
  }

  // ── 오버레이 ────────────────────────────────────────────────────────

  void _renderDamageVignette(Canvas canvas) {
    final player = game.player;
    final lowHp = player.isAlive && player.hp / player.maxHp < 0.3;
    final intensity = math.max(
      _damageFlash.clamp(0.0, 1.0) * 0.55,
      lowHp ? (0.18 + math.sin(_time * 5) * 0.08) : 0.0,
    );
    if (intensity <= 0.01) return;

    final rect = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          rect.center,
          math.max(size.x, size.y) * 0.62,
          [
            Colors.transparent,
            GamePalette.hpFillLow.withValues(alpha: intensity),
          ],
          [0.55, 1.0],
        ),
    );
  }

  void _renderComboBadge(Canvas canvas) {
    final t = (game.comboDisplayTimer / 1.2).clamp(0.0, 1.0);
    final scale = 1 + (1 - t) * 0.0 + math.sin(t * math.pi) * 0.08;
    canvas.save();
    canvas.translate(size.x / 2, size.y * 0.24);
    canvas.scale(scale);
    TextPaint(
      style: TextStyle(
        color: GamePalette.hitSpark.withValues(alpha: t.clamp(0.0, 1.0)),
        fontSize: 28,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
        shadows: const [
          Shadow(color: Colors.black, blurRadius: 8),
        ],
      ),
    ).render(canvas, game.comboDisplayText, Vector2.zero(),
        anchor: Anchor.center);
    canvas.restore();
  }
}
