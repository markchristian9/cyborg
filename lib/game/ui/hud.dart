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
    const left = 18.0;
    const top = 18.0;
    const panelWidth = 268.0;

    final panel = RRect.fromRectAndRadius(
      const Rect.fromLTWH(left - 8, top - 8, panelWidth, 112),
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
    final centerX = size.x / 2;
    final zone = TeleportDestination.at(game.player.grid, game.map);

    final rect = Rect.fromCenter(
      center: Offset(centerX, 32),
      width: 236,
      height: 46,
    );
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

    _headline.render(
      canvas,
      zone.label,
      Vector2(centerX, 20),
      anchor: Anchor.topCenter,
    );
    _label.render(
      canvas,
      _presenceText(),
      Vector2(centerX, 40),
      anchor: Anchor.topCenter,
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

  /// 플레이어를 중심으로 한 근접 레이더.
  ///
  /// 월드가 1 km²라 전체를 132픽셀에 담으면 아무것도 분간할 수 없다.
  /// 그래서 주변 [_radarRangeTiles]미터만 잘라 보여 주고, 실제 위치는
  /// 아래쪽 좌표 표시로 알린다.
  void _renderMinimap(Canvas canvas) {
    final map = game.map;
    final player = game.player;
    final origin = Offset(size.x - _minimapSize - 18, 18);
    final center = Offset(_minimapSize / 2, _minimapSize / 2);

    // 레이더 한 픽셀이 담는 거리(미터).
    final scale = _minimapSize / (_radarRangeTiles * 2);

    /// 그리드 좌표를 레이더 안의 위치로 옮긴다.
    Offset toRadar(Vector2 grid) => center +
        Offset(
          (grid.x - player.grid.x) * scale,
          (grid.y - player.grid.y) * scale,
        );

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

    // 지형은 여러 칸을 한 점으로 묶어 훑는다. 매 프레임 100만 칸을 볼 수는 없다.
    const step = 3;
    final cellSize = step * scale + 0.6;
    final minX = (player.grid.x - _radarRangeTiles).floor();
    final maxX = (player.grid.x + _radarRangeTiles).ceil();
    final minY = (player.grid.y - _radarRangeTiles).floor();
    final maxY = (player.grid.y + _radarRangeTiles).ceil();

    final plate = Paint()..color = const Color(0xFFDCEFF8);
    final conduit = Paint()..color = const Color(0xFF9DE8F5);
    final firewall = Paint()..color = const Color(0xFFFFAFC8);
    final tower = Paint()..color = const Color(0xFF6E9DB8);

    for (var y = minY; y <= maxY; y += step) {
      for (var x = minX; x <= maxX; x += step) {
        final tile = map.tileAt(x, y);
        if (tile == TileType.none) continue;
        final point = toRadar(Vector2(x.toDouble(), y.toDouble()));
        canvas.drawRect(
          Rect.fromLTWH(point.dx, point.dy, cellSize, cellSize),
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

    // 안전지대
    final zone = map.safeZone;
    final zoneTopLeft = toRadar(Vector2(zone.minX, zone.minY));
    final zoneBottomRight = toRadar(Vector2(zone.maxX, zone.maxY));
    final zoneRect = Rect.fromPoints(zoneTopLeft, zoneBottomRight);
    canvas.drawRect(
      zoneRect,
      Paint()..color = GamePalette.safeZoneFill.withValues(alpha: 0.3),
    );
    canvas.drawRect(
      zoneRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = GamePalette.safeZoneEdge.withValues(alpha: 0.9),
    );

    // 전리품. 무엇이 떨어졌는지 색으로 구분하고 희귀품은 크게 찍는다.
    for (final pickup in game.pickups) {
      canvas.drawCircle(
        toRadar(pickup.grid),
        pickup.spec.rarity == LootRarity.rare ? 2.6 : 1.8,
        Paint()..color = pickup.spec.color.withValues(alpha: 0.85),
      );
    }

    // 적. 지휘 유닛은 크게 찍어 멀리서도 알아보게 한다.
    for (final enemy in game.enemies) {
      if (!enemy.isAlive) continue;
      final isBoss = enemy.isBoss;
      canvas.drawCircle(
        toRadar(enemy.grid),
        isBoss ? 4 : 2.2,
        Paint()..color = GamePalette.robotEye,
      );
    }

    // 같은 월드의 다른 요원. 내 몸(청록)과 갈리는 호박색으로 찍는다.
    //
    // 적(마젠타)보다 조금 크게 그려 "저건 사람이다" 가 먼저 읽히게 한다 —
    // 몹은 지나치면 그만이지만 사람은 함께 사냥할 수도, PK 로 붙을 수도 있어
    // 판단이 필요하다.
    for (final other in game.presence.others) {
      final at = toRadar(other.grid);
      canvas.drawCircle(
        at,
        4.5,
        Paint()..color = GamePalette.remotePlayer.withValues(alpha: 0.3),
      );
      canvas.drawCircle(
        at,
        2.6,
        Paint()
          ..color = other.alive
              ? GamePalette.remotePlayer
              : GamePalette.remotePlayer.withValues(alpha: 0.45),
      );
    }

    // 플레이어(맥동하는 링)
    final pulse = 3 + math.sin(_time * 4) * 1.5;
    canvas.drawCircle(
      center,
      pulse + 3,
      Paint()..color = GamePalette.playerAccent.withValues(alpha: 0.25),
    );
    canvas.drawCircle(
      center,
      2.8,
      Paint()..color = GamePalette.playerAccent,
    );

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
