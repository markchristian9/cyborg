import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import '../action_rpg_game.dart';
import '../level/teleport_destinations.dart';
import '../palette.dart';

/// 화면 아래에서 올라오는 텔레포트 목적지 목록.
///
/// 캐릭터 화면·리더보드와 마찬가지로 항상 붙어 있고 [isOpen] 으로만 열고
/// 닫는다. 월드는 모두가 공유하는 실시간 공간이라 이 시트가 열려 있어도 게임은
/// 멈추지 않는다.
class TeleportSheet extends PositionComponent
    with TapCallbacks, HasGameReference<ActionRpgGame> {
  TeleportSheet() : super(priority: 142);

  /// 기준 해상도에서의 시트 너비. 화면이 좁으면 화면에 맞춘다.
  static const double sheetWidth = 460;

  /// 목적지 한 줄의 높이.
  static const double rowHeight = 62;

  /// 제목이 놓이는 머리 부분의 높이.
  static const double headerHeight = 58;

  /// 시트 안쪽 여백.
  static const double padding = 14;

  static const List<TeleportDestination> destinations =
      TeleportDestination.values;

  bool _open = false;

  /// 0(닫힘) ~ 1(열림) 사이의 펼침 진행도.
  double _anim = 0;

  /// 눌린 항목의 인덱스. 없으면 -1.
  int _pressedIndex = -1;

  bool get isOpen => _open;

  void open() {
    _open = true;
    _pressedIndex = -1;
  }

  void close() {
    _open = false;
    _pressedIndex = -1;
  }

  void toggle() => _open ? close() : open();

  final TextPaint _title = TextPaint(
    style: const TextStyle(
      color: GamePalette.hudBorder,
      fontSize: 13,
      fontWeight: FontWeight.w900,
      letterSpacing: 2.5,
    ),
  );
  final TextPaint _hint = TextPaint(
    style: const TextStyle(
      color: GamePalette.textDim,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.6,
    ),
  );
  final TextPaint _label = TextPaint(
    style: const TextStyle(
      color: GamePalette.textPrimary,
      fontSize: 16,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.4,
    ),
  );
  final TextPaint _safeLabel = TextPaint(
    style: const TextStyle(
      color: GamePalette.safeZoneGlow,
      fontSize: 16,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.4,
    ),
  );
  final TextPaint _desc = TextPaint(
    style: const TextStyle(
      color: GamePalette.textDim,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    ),
  );
  final TextPaint _coord = TextPaint(
    style: const TextStyle(
      color: GamePalette.textDim,
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
    ),
  );

  @override
  void onGameResize(Vector2 newSize) {
    super.onGameResize(newSize);
    size = newSize;
  }

  @override
  void update(double dt) {
    final target = _open ? 1.0 : 0.0;
    _anim += (target - _anim) * math.min(1, dt * 14);
    if ((_anim - target).abs() < 0.005) _anim = target;
  }

  // ── 좌표 ────────────────────────────────────────────────────────────

  double get _sheetHeight =>
      headerHeight + padding + rowHeight * destinations.length + padding;

  double get _sheetWidth => math.min(sheetWidth, size.x - 24);

  /// 완전히 열렸을 때 시트의 왼쪽 위 모서리.
  Offset get _restOrigin => Offset(
        (size.x - _sheetWidth) / 2,
        size.y - _sheetHeight - 12,
      );

  /// 지금 그려질 자리. 닫힐수록 화면 밖으로 내려간다.
  Offset get _origin {
    final t = Curves.easeOutCubic.transform(_anim.clamp(0.0, 1.0));
    final rest = _restOrigin;
    return Offset(rest.dx, rest.dy + (1 - t) * (_sheetHeight + 24));
  }

  Rect get _sheetRect =>
      Rect.fromLTWH(_origin.dx, _origin.dy, _sheetWidth, _sheetHeight);

  Rect get _closeRect =>
      Rect.fromLTWH(_sheetRect.right - 44, _sheetRect.top + 12, 32, 32);

  Rect _rowRect(int index) => Rect.fromLTWH(
        _sheetRect.left + padding,
        _sheetRect.top + headerHeight + padding + rowHeight * index,
        _sheetWidth - padding * 2,
        rowHeight,
      );

  /// [point]가 가리키는 목적지 인덱스. 항목 밖이면 -1.
  int _rowIndexAt(Offset point) {
    for (var i = 0; i < destinations.length; i++) {
      if (_rowRect(i).contains(point)) return i;
    }
    return -1;
  }

  // ── 입력 ────────────────────────────────────────────────────────────

  @override
  bool containsLocalPoint(Vector2 point) => _open;

  @override
  void onTapDown(TapDownEvent event) {
    if (!_open) return;
    // 화면 전체를 덮으므로 탭이 조이스틱이나 액션 버튼까지 새지 않게 한다.
    event.handled = true;

    final point = Offset(event.localPosition.x, event.localPosition.y);
    if (_closeRect.contains(point) || !_sheetRect.contains(point)) {
      game.closeTeleportSheet();
      return;
    }
    _pressedIndex = _rowIndexAt(point);
  }

  @override
  void onTapUp(TapUpEvent event) {
    final index = _pressedIndex;
    _pressedIndex = -1;
    if (!_open || index < 0) return;

    // 누른 항목 위에서 손을 뗐을 때만 실행한다.
    final point = Offset(event.localPosition.x, event.localPosition.y);
    if (_rowIndexAt(point) != index) return;

    game.teleportPlayerTo(destinations[index]);
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    _pressedIndex = -1;
  }

  // ── 렌더링 ──────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    if (_anim <= 0.001) return;

    // 뒤쪽을 살짝 어둡게 덮어 시트에 시선을 모은다.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y),
      Paint()..color = GamePalette.shadow.withValues(alpha: _anim * 0.45),
    );

    final rect = _sheetRect;
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(18));

    canvas.drawRRect(
      shape,
      Paint()
        ..color = GamePalette.shadow.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
    );
    canvas.drawRRect(shape, Paint()..color = GamePalette.hudBackground);
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = GamePalette.hudBorder.withValues(alpha: 0.45),
    );

    _renderHeader(canvas, rect);
    for (var i = 0; i < destinations.length; i++) {
      _renderRow(canvas, i);
    }
  }

  void _renderHeader(Canvas canvas, Rect rect) {
    // 손잡이 모양의 짧은 막대.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(rect.center.dx, rect.top + 10),
          width: 44,
          height: 4,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = GamePalette.hudBorder.withValues(alpha: 0.35),
    );

    _title.render(
      canvas,
      'TELEPORT',
      Vector2(rect.left + padding + 4, rect.top + 26),
      anchor: Anchor.topLeft,
    );
    _hint.render(
      canvas,
      '이동할 구역을 고른다',
      Vector2(rect.left + padding + 4, rect.top + 43),
      anchor: Anchor.topLeft,
    );

    // 닫기 버튼.
    final close = _closeRect;
    final stroke = Paint()
      ..color = GamePalette.hudBorder
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      close.center + const Offset(-6, -6),
      close.center + const Offset(6, 6),
      stroke,
    );
    canvas.drawLine(
      close.center + const Offset(6, -6),
      close.center + const Offset(-6, 6),
      stroke,
    );

    canvas.drawLine(
      Offset(rect.left + padding, rect.top + headerHeight),
      Offset(rect.right - padding, rect.top + headerHeight),
      Paint()
        ..strokeWidth = 1
        ..color = GamePalette.hudBorder.withValues(alpha: 0.16),
    );
  }

  void _renderRow(Canvas canvas, int index) {
    final dest = destinations[index];
    final rect = _rowRect(index);
    final accent =
        dest.isSafe ? GamePalette.safeZoneGlow : GamePalette.hudBorder;

    if (_pressedIndex == index) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(2), const Radius.circular(10)),
        Paint()..color = accent.withValues(alpha: 0.18),
      );
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(2), const Radius.circular(10)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = accent.withValues(alpha: 0.30),
    );

    _drawDestinationGlyph(
      canvas,
      dest,
      Offset(rect.left + 30, rect.center.dy),
      accent,
    );

    (dest.isSafe ? _safeLabel : _label).render(
      canvas,
      dest.label,
      Vector2(rect.left + 60, rect.center.dy - 10),
      anchor: Anchor.centerLeft,
    );
    _desc.render(
      canvas,
      dest.description,
      Vector2(rect.left + 60, rect.center.dy + 10),
      anchor: Anchor.centerLeft,
    );

    // 어느 방향인지 헷갈리지 않도록 대표 좌표를 함께 보여 준다.
    final anchor = dest.anchorOn(game.map);
    _coord.render(
      canvas,
      '${anchor.x.round()}, ${anchor.y.round()}',
      Vector2(rect.right - 14, rect.center.dy),
      anchor: Anchor.centerRight,
    );
  }

  /// 목적지를 나타내는 작은 표식.
  ///
  /// 안전지대는 보호막, 나머지는 그 방위를 가리키는 화살표다. 화살표 방향은
  /// 미니맵과 같은 그리드 축을 따른다.
  void _drawDestinationGlyph(
    Canvas canvas,
    TeleportDestination dest,
    Offset center,
    Color color,
  ) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawCircle(center, 13, stroke..color = color.withValues(alpha: 0.4));
    stroke.color = color;

    if (dest.isSafe) {
      // 방패 모양의 보호막.
      canvas.drawPath(
        Path()
          ..moveTo(center.dx, center.dy - 7)
          ..lineTo(center.dx + 6, center.dy - 4)
          ..lineTo(center.dx + 6, center.dy + 2)
          ..quadraticBezierTo(
            center.dx + 6,
            center.dy + 6,
            center.dx,
            center.dy + 8,
          )
          ..quadraticBezierTo(
            center.dx - 6,
            center.dy + 6,
            center.dx - 6,
            center.dy + 2,
          )
          ..lineTo(center.dx - 6, center.dy - 4)
          ..close(),
        stroke,
      );
      return;
    }

    // 방위 화살표. 북이 위, 동이 오른쪽이다.
    final angle = switch (dest) {
      TeleportDestination.north => -math.pi / 2,
      TeleportDestination.east => 0.0,
      TeleportDestination.south => math.pi / 2,
      TeleportDestination.west => math.pi,
      TeleportDestination.safeZone => 0.0,
    };

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.drawLine(const Offset(-7, 0), const Offset(6, 0), stroke);
    canvas.drawPath(
      Path()
        ..moveTo(2, -4)
        ..lineTo(7, 0)
        ..lineTo(2, 4),
      stroke,
    );
    canvas.restore();
  }
}
