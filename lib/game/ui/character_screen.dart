import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import '../action_rpg_game.dart';
import '../palette.dart';

/// 사이보그의 현재 상태를 한눈에 보는 캐릭터 화면.
///
/// 월드는 모두가 공유하는 하나의 실시간 공간이라 이 패널이 열려 있어도 게임은
/// 멈추지 않는다. 인벤토리 패널과 마찬가지로 항상 붙어 있고 [isOpen] 으로만
/// 열고 닫는다.
class CharacterScreen extends PositionComponent
    with TapCallbacks, HasGameReference<ActionRpgGame> {
  CharacterScreen() : super(priority: 140);

  /// 기준 해상도에서의 패널 크기. 화면이 좁으면 통째로 축소한다.
  static const double panelWidth = 440;
  static const double panelHeight = 446;

  bool _open = false;
  double _anim = 0;

  bool get isOpen => _open;

  void open() => _open = true;

  void close() => _open = false;

  void toggle() => _open ? close() : open();

  final TextPaint _title = TextPaint(
    style: const TextStyle(
      color: GamePalette.hudBorder,
      fontSize: 15,
      fontWeight: FontWeight.w900,
      letterSpacing: 2,
    ),
  );
  final TextPaint _name = TextPaint(
    style: const TextStyle(
      color: GamePalette.textPrimary,
      fontSize: 22,
      fontWeight: FontWeight.w900,
      letterSpacing: 0.5,
    ),
  );
  final TextPaint _section = TextPaint(
    style: const TextStyle(
      color: GamePalette.hudBorder,
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 2,
    ),
  );
  final TextPaint _label = TextPaint(
    style: const TextStyle(
      color: GamePalette.textDim,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 1,
    ),
  );
  final TextPaint _value = TextPaint(
    style: const TextStyle(
      color: GamePalette.textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w800,
    ),
  );
  final TextPaint _levelNumber = TextPaint(
    style: const TextStyle(
      color: GamePalette.textPrimary,
      fontSize: 30,
      fontWeight: FontWeight.w900,
    ),
  );
  final TextPaint _chip = TextPaint(
    style: const TextStyle(
      color: GamePalette.textPrimary,
      fontSize: 12,
      fontWeight: FontWeight.w800,
    ),
  );

  @override
  void onGameResize(Vector2 newSize) {
    super.onGameResize(newSize);
    size = newSize;
  }

  @override
  void update(double dt) {
    // 열고 닫을 때 살짝 미끄러지듯 움직인다.
    final target = _open ? 1.0 : 0.0;
    _anim += (target - _anim) * math.min(1, dt * 14);
    if ((_anim - target).abs() < 0.005) _anim = target;
  }

  // ── 좌표 변환 ───────────────────────────────────────────────────────

  /// 화면에 맞춘 패널 축소 비율. 작은 화면에서는 통째로 줄여 넣는다.
  ///
  /// 화면이 여백보다도 좁은 극단적인 경우에 배율이 0이나 음수가 되지 않도록
  /// 하한을 둔다.
  double get _scale => math.max(
        0.2,
        math.min(
          1.0,
          math.min((size.x - 32) / panelWidth, (size.y - 32) / panelHeight),
        ),
      );

  Offset get _origin => Offset(
        (size.x - panelWidth * _scale) / 2,
        (size.y - panelHeight * _scale) / 2,
      );

  /// 화면 좌표를 패널 내부 좌표로 옮긴다.
  Offset _toPanel(Vector2 point) {
    final scale = _scale;
    final origin = _origin;
    return Offset(
      (point.x - origin.dx) / scale,
      (point.y - origin.dy) / scale,
    );
  }

  static const Rect _closeRect = Rect.fromLTWH(panelWidth - 46, 14, 32, 32);

  // ── 입력 ────────────────────────────────────────────────────────────

  @override
  bool containsLocalPoint(Vector2 point) {
    // 열려 있을 때만 입력을 가로챈다.
    return _open;
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (!_open) return;
    // 화면 전체를 덮으므로 탭이 조이스틱이나 액션 버튼까지 새지 않게 한다.
    event.handled = true;

    final local = _toPanel(event.localPosition);
    const panel = Rect.fromLTWH(0, 0, panelWidth, panelHeight);
    // 닫기 버튼이나 패널 바깥을 누르면 닫는다.
    if (_closeRect.contains(local) || !panel.contains(local)) close();
  }

  // ── 렌더링 ──────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    if (_anim <= 0.004) return;
    final t = _anim.clamp(0.0, 1.0);

    // 월드를 어둡게 눌러 패널에 시선을 모은다.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y),
      Paint()..color = const Color(0xFF06202F).withValues(alpha: 0.5 * t),
    );

    // 히트 테스트(`_toPanel`)와 같은 배율·중심을 쓴다. 열리는 동안의 미세한
    // 확대는 연출일 뿐이라 판정에는 반영하지 않는다.
    canvas.save();
    canvas.translate(size.x / 2, size.y / 2);
    canvas.scale(_scale * (0.94 + t * 0.06));
    canvas.translate(-panelWidth / 2, -panelHeight / 2);
    canvas.saveLayer(
      const Rect.fromLTWH(-30, -30, panelWidth + 60, panelHeight + 60),
      Paint()..color = Colors.white.withValues(alpha: t),
    );

    _renderPanel(canvas);

    canvas.restore();
    canvas.restore();
  }

  void _renderPanel(Canvas canvas) {
    const rect = Rect.fromLTWH(0, 0, panelWidth, panelHeight);
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(16));

    canvas.drawRRect(
      shape,
      Paint()
        ..color = GamePalette.shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18),
    );
    canvas.drawRRect(shape, Paint()..color = GamePalette.hudBackground);
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = GamePalette.hudBorder.withValues(alpha: 0.5),
    );

    _renderHeader(canvas);
    _renderIdentity(canvas);
    _renderVitals(canvas);
    _renderColumns(canvas);
    _renderBuffs(canvas);
  }

  void _renderHeader(Canvas canvas) {
    _title.render(
      canvas,
      'CHARACTER',
      Vector2(24, 30),
      anchor: Anchor.centerLeft,
    );
    canvas.drawLine(
      const Offset(24, 54),
      const Offset(panelWidth - 24, 54),
      Paint()
        ..strokeWidth = 1
        ..color = GamePalette.hudBorder.withValues(alpha: 0.25),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(_closeRect, const Radius.circular(8)),
      Paint()..color = GamePalette.hudInset,
    );
    final center = _closeRect.center;
    final cross = Paint()
      ..color = GamePalette.textDim
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      center + const Offset(-6, -6),
      center + const Offset(6, 6),
      cross,
    );
    canvas.drawLine(
      center + const Offset(6, -6),
      center + const Offset(-6, 6),
      cross,
    );
  }

  /// 레벨 배지, 이름, 경험치 게이지.
  void _renderIdentity(Canvas canvas) {
    final player = game.player;
    const badgeCenter = Offset(62, 112);

    canvas.drawCircle(badgeCenter, 32, Paint()..color = GamePalette.hudInset);
    canvas.drawCircle(
      badgeCenter,
      32,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = GamePalette.hudBorder,
    );
    _levelNumber.render(
      canvas,
      '${player.level}',
      Vector2(badgeCenter.dx, badgeCenter.dy - 5),
      anchor: Anchor.center,
    );

    _label.render(
      canvas,
      'LEVEL',
      Vector2(badgeCenter.dx, badgeCenter.dy + 17),
      anchor: Anchor.center,
    );

    _name.render(canvas, game.characterName, Vector2(112, 88));

    _label.render(canvas, 'EXPERIENCE', Vector2(112, 118));
    _label.render(
      canvas,
      '${_grouped(player.xp)} / ${_grouped(player.xpToNextLevel)}',
      Vector2(panelWidth - 24, 118),
      anchor: Anchor.topRight,
    );
    _renderBar(
      canvas,
      const Rect.fromLTWH(112, 134, panelWidth - 112 - 24, 10),
      player.xp / player.xpToNextLevel,
      GamePalette.xpFill,
    );

    // 누적 경험치. 리더보드 순위를 정하는 값이므로 진행도와 함께 보여 준다 —
    // 게이지만 보면 "지금 레벨에서 얼마나 왔나" 는 알아도 "얼마나 쌓았나" 는
    // 알 수 없고, 순위가 왜 그런지도 설명되지 않는다.
    _label.render(canvas, 'TOTAL XP', Vector2(112, 150));
    _label.render(
      canvas,
      _grouped(player.totalXp),
      Vector2(panelWidth - 24, 150),
      anchor: Anchor.topRight,
    );
  }

  /// 천 단위마다 쉼표를 넣는다. 누적 경험치는 금세 여섯 자리를 넘는다.
  String _grouped(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  void _renderVitals(Canvas canvas) {
    final player = game.player;
    _section.render(canvas, 'VITALS', Vector2(24, 168));

    final hpRatio = player.hp / player.maxHp;
    _renderLabeledBar(
      canvas,
      top: 188,
      label: 'HP',
      ratio: hpRatio,
      color: hpRatio < 0.3 ? GamePalette.hpFillLow : GamePalette.hpFill,
      text: '${player.hp.ceil()} / ${player.maxHp.round()}',
    );
    _renderLabeledBar(
      canvas,
      top: 214,
      label: 'MANA',
      ratio: player.mp / player.maxMp,
      color: GamePalette.mpFill,
      text: '${player.mp.floor()} / ${player.maxMp.round()}',
    );
    _renderLabeledBar(
      canvas,
      top: 240,
      label: 'ENERGY',
      ratio: player.energy / player.maxEnergy,
      color: GamePalette.energyFill,
      text: '${player.energy.ceil()} / ${player.maxEnergy.round()}',
    );
  }

  void _renderLabeledBar(
    Canvas canvas, {
    required double top,
    required String label,
    required double ratio,
    required Color color,
    required String text,
  }) {
    _label.render(canvas, label, Vector2(24, top + 1));
    _renderBar(canvas, Rect.fromLTWH(88, top, 224, 12), ratio, color);
    _value.render(
      canvas,
      text,
      Vector2(panelWidth - 24, top - 1),
      anchor: Anchor.topRight,
    );
  }

  /// 전투 능력치와 이번 잠입의 전적을 두 단으로 보여준다.
  void _renderColumns(Canvas canvas) {
    final player = game.player;
    const top = 278.0;

    _section.render(canvas, 'COMBAT', Vector2(24, top));
    _renderStatRows(
      canvas,
      left: 24,
      top: top + 22,
      width: 176,
      rows: [
        ('MELEE', player.effectiveMeleeDamage.toStringAsFixed(1)),
        ('RANGED', player.effectiveRangedDamage.toStringAsFixed(1)),
        ('SPEED', player.effectiveMoveSpeed.toStringAsFixed(2)),
        ('LOOT R.', player.lootRadius.toStringAsFixed(1)),
      ],
    );

    _section.render(canvas, 'RECORD', Vector2(244, top));
    _renderStatRows(
      canvas,
      left: 244,
      top: top + 22,
      width: panelWidth - 244 - 24,
      rows: [
        ('KILLS', '${game.kills}'),
        ('SCORE', '${game.score}'),
        ('REBOOTS', '${game.deaths}'),
      ],
    );

    // 생존 시간은 두 단 아래에 가로로 길게 둔다.
    _label.render(canvas, 'UPTIME', Vector2(24, top + 112));
    _value.render(
      canvas,
      _formatTime(game.survivalTime),
      Vector2(200, top + 109),
      anchor: Anchor.topRight,
    );
  }

  void _renderStatRows(
    Canvas canvas, {
    required double left,
    required double top,
    required double width,
    required List<(String, String)> rows,
  }) {
    for (var i = 0; i < rows.length; i++) {
      final y = top + i * 21;
      _label.render(canvas, rows[i].$1, Vector2(left, y));
      _value.render(
        canvas,
        rows[i].$2,
        Vector2(left + width, y - 3),
        anchor: Anchor.topRight,
      );
    }
  }

  void _renderBuffs(Canvas canvas) {
    const top = 412.0;
    _section.render(canvas, 'BUFFS', Vector2(24, top));

    final buffs = game.player.buffs.active;
    if (buffs.isEmpty) {
      _label.render(canvas, 'NONE ACTIVE', Vector2(88, top));
      return;
    }

    var x = 88.0;
    for (final buff in buffs) {
      const chipWidth = 86.0;
      if (x + chipWidth > panelWidth - 24) break;
      final chip = Rect.fromLTWH(x, top - 6, chipWidth, 22);
      canvas.drawRRect(
        RRect.fromRectAndRadius(chip, const Radius.circular(11)),
        Paint()..color = buff.spec.color.withValues(alpha: 0.18),
      );
      // 남은 시간만큼 테두리를 진하게 해 잔여량을 알린다.
      canvas.drawRRect(
        RRect.fromRectAndRadius(chip, const Radius.circular(11)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = buff.spec.color.withValues(alpha: 0.3 + buff.ratio * 0.6),
      );
      _chip.render(
        canvas,
        '${buff.spec.label} ${buff.remaining.toStringAsFixed(1)}s',
        Vector2(chip.center.dx, chip.center.dy),
        anchor: Anchor.center,
      );
      x += chipWidth + 8;
    }
  }

  void _renderBar(Canvas canvas, Rect rect, double ratio, Color color) {
    final clamped = ratio.clamp(0.0, 1.0);
    final radius = Radius.circular(rect.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = GamePalette.hudInset,
    );
    if (clamped > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(rect.left, rect.top, rect.width * clamped, rect.height),
          radius,
        ),
        Paint()..color = color,
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = GamePalette.hudBorder.withValues(alpha: 0.25),
    );
  }

  String _formatTime(double seconds) {
    final total = seconds.floor();
    final minutes = (total ~/ 60).toString().padLeft(2, '0');
    final secs = (total % 60).toString().padLeft(2, '0');
    return '$minutes:$secs';
  }
}
