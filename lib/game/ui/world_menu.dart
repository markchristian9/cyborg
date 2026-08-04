import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import '../palette.dart';

/// 서브메뉴 한 줄에 그릴 아이콘.
enum WorldMenuIcon { character, leaderboard, teleport, logout }

/// 월드 메뉴에서 펼쳐지는 서브메뉴 항목 하나.
class WorldMenuEntry {
  const WorldMenuEntry({
    required this.label,
    required this.icon,
    required this.onSelected,
    this.danger = false,
  });

  /// 항목에 표시할 이름.
  final String label;

  final WorldMenuIcon icon;

  /// 항목을 눌렀을 때 실행할 동작.
  final VoidCallback onSelected;

  /// 로그아웃처럼 되돌리기 어려운 동작이면 true. 경고색으로 그린다.
  final bool danger;
}

/// 화면 우상단에 고정되는 메뉴 버튼과 그 아래로 펼쳐지는 서브메뉴.
///
/// 조이스틱·액션 버튼과 마찬가지로 `camera.viewport` 에 붙는 HUD 컴포넌트라
/// 카메라가 움직여도 항상 같은 자리에 남는다.
class WorldMenu extends PositionComponent with TapCallbacks {
  WorldMenu({
    required List<WorldMenuEntry> entries,
    int priority = 130,
  })  : entries = List.unmodifiable(entries),
        super(
          anchor: Anchor.topRight,
          priority: priority,
          size: Vector2(
            panelWidth,
            buttonSize +
                panelGap +
                panelPadding * 2 +
                itemHeight * entries.length,
          ),
        );

  final List<WorldMenuEntry> entries;

  /// 메뉴 버튼 한 변의 길이.
  static const double buttonSize = 44;

  /// 펼쳐지는 패널의 너비.
  static const double panelWidth = 190;

  /// 서브메뉴 한 줄의 높이.
  static const double itemHeight = 44;

  /// 패널 안쪽 여백.
  static const double panelPadding = 6;

  /// 버튼과 패널 사이의 간격.
  static const double panelGap = 8;

  bool _open = false;

  /// 0(닫힘) ~ 1(열림) 사이의 펼침 진행도.
  double _anim = 0;

  /// 눌린 항목의 인덱스. 없으면 -1.
  int _pressedIndex = -1;

  /// 메뉴가 열려 있는 동안 화면 나머지를 덮는 투명 레이어.
  _MenuScrim? _scrim;

  bool get isOpen => _open;

  double get _panelHeight => panelPadding * 2 + itemHeight * entries.length;

  Rect get _buttonRect =>
      Rect.fromLTWH(size.x - buttonSize, 0, buttonSize, buttonSize);

  Rect get _panelRect =>
      Rect.fromLTWH(0, buttonSize + panelGap, panelWidth, _panelHeight);

  final TextPaint _itemLabel = TextPaint(
    style: const TextStyle(
      color: GamePalette.textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
    ),
  );
  final TextPaint _dangerLabel = TextPaint(
    style: const TextStyle(
      color: GamePalette.hpFillLow,
      fontSize: 14,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.3,
    ),
  );

  // ── 열기 / 닫기 ─────────────────────────────────────────────────────

  void open() {
    if (_open) return;
    _open = true;
    // 바깥을 누르면 닫히도록 화면 전체를 덮는다. 메뉴보다 우선순위가 낮아
    // 메뉴 자체의 탭은 그대로 통과한다.
    final scrim = _MenuScrim(onDismiss: close, priority: priority - 1);
    _scrim = scrim;
    parent?.add(scrim);
  }

  void close() {
    if (!_open) return;
    _open = false;
    _pressedIndex = -1;
    _scrim?.removeFromParent();
    _scrim = null;
  }

  void toggle() => _open ? close() : open();

  @override
  void onRemove() {
    _scrim?.removeFromParent();
    _scrim = null;
    super.onRemove();
  }

  // ── 입력 ────────────────────────────────────────────────────────────

  @override
  bool containsLocalPoint(Vector2 point) {
    final offset = Offset(point.x, point.y);
    if (_buttonRect.contains(offset)) return true;
    return _open && _panelRect.contains(offset);
  }

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    final point = Offset(event.localPosition.x, event.localPosition.y);

    if (_buttonRect.contains(point)) {
      toggle();
      return;
    }
    if (!_open) return;

    _pressedIndex = _entryIndexAt(point);
  }

  @override
  void onTapUp(TapUpEvent event) {
    final index = _pressedIndex;
    _pressedIndex = -1;
    if (index < 0) return;
    // 누른 항목 위에서 손을 뗐을 때만 실행한다.
    final point = Offset(event.localPosition.x, event.localPosition.y);
    if (_entryIndexAt(point) != index) return;
    close();
    entries[index].onSelected();
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    _pressedIndex = -1;
  }

  /// [point]가 가리키는 서브메뉴 항목의 인덱스. 항목 밖이면 -1.
  int _entryIndexAt(Offset point) {
    final panel = _panelRect;
    if (!panel.contains(point)) return -1;
    final index = ((point.dy - panel.top - panelPadding) / itemHeight).floor();
    if (index < 0 || index >= entries.length) return -1;
    return index;
  }

  // ── 갱신 ────────────────────────────────────────────────────────────

  @override
  void update(double dt) {
    final target = _open ? 1.0 : 0.0;
    final step = dt * 9;
    if (_anim < target) {
      _anim = math.min(target, _anim + step);
    } else if (_anim > target) {
      _anim = math.max(target, _anim - step);
    }
  }

  // ── 렌더링 ──────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    if (_anim > 0.001) _renderPanel(canvas);
    _renderButton(canvas);
  }

  void _renderButton(Canvas canvas) {
    final rect = RRect.fromRectAndRadius(
      _buttonRect,
      const Radius.circular(10),
    );

    canvas.drawRRect(
      rect,
      Paint()
        ..color = GamePalette.hudBorder.withValues(alpha: 0.14 + _anim * 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawRRect(rect, Paint()..color = GamePalette.hudBackground);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = GamePalette.hudBorder.withValues(alpha: 0.35 + _anim * 0.5),
    );

    _drawMenuGlyph(canvas, _buttonRect.center, _anim);
  }

  /// 햄버거(≡)에서 닫기(×)로 변형되는 아이콘.
  void _drawMenuGlyph(Canvas canvas, Offset center, double t) {
    final paint = Paint()
      ..color = GamePalette.hudBorder
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    const half = 9.0;

    // 가운데 줄은 열릴수록 사라진다.
    canvas.drawLine(
      center + const Offset(-half, 0),
      center + const Offset(half, 0),
      Paint()
        ..color = GamePalette.hudBorder
            .withValues(alpha: (1 - t * 1.8).clamp(0.0, 1.0))
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    // 위아래 줄이 모여 ×를 만든다.
    for (final side in const [-1, 1]) {
      canvas.save();
      canvas.translate(center.dx, center.dy + side * 6.0 * (1 - t));
      canvas.rotate(-side * (math.pi / 4) * t);
      canvas.drawLine(
        const Offset(-half, 0),
        const Offset(half, 0),
        paint,
      );
      canvas.restore();
    }
  }

  void _renderPanel(Canvas canvas) {
    final t = Curves.easeOutCubic.transform(_anim.clamp(0.0, 1.0));
    final panel = _panelRect;

    canvas.save();
    // 버튼 쪽(패널 위쪽)에서 아래로 펼쳐지는 느낌을 준다.
    canvas.translate(panel.center.dx, panel.top);
    canvas.scale(0.92 + t * 0.08, t);
    canvas.translate(-panel.center.dx, -panel.top);
    canvas.saveLayer(
      panel.inflate(24),
      Paint()..color = Colors.white.withValues(alpha: t),
    );

    final shape = RRect.fromRectAndRadius(panel, const Radius.circular(12));
    canvas.drawRRect(
      shape,
      Paint()
        ..color = GamePalette.shadow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawRRect(shape, Paint()..color = GamePalette.hudBackground);
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = GamePalette.hudBorder.withValues(alpha: 0.45),
    );

    for (var i = 0; i < entries.length; i++) {
      _renderEntry(canvas, i, panel);
    }

    canvas.restore();
    canvas.restore();
  }

  void _renderEntry(Canvas canvas, int index, Rect panel) {
    final entry = entries[index];
    final rect = Rect.fromLTWH(
      panel.left + panelPadding,
      panel.top + panelPadding + itemHeight * index,
      panel.width - panelPadding * 2,
      itemHeight,
    );
    final accent =
        entry.danger ? GamePalette.hpFillLow : GamePalette.hudBorder;

    // 누르고 있는 동안 항목을 밝힌다.
    if (_pressedIndex == index) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(1), const Radius.circular(8)),
        Paint()..color = accent.withValues(alpha: 0.16),
      );
    }

    _drawEntryIcon(
      canvas,
      entry.icon,
      Offset(rect.left + 20, rect.center.dy),
      accent,
    );
    (entry.danger ? _dangerLabel : _itemLabel).render(
      canvas,
      entry.label,
      Vector2(rect.left + 40, rect.center.dy),
      anchor: Anchor.centerLeft,
    );

    // 마지막 줄을 제외하고 얇은 구분선을 둔다.
    if (index < entries.length - 1) {
      canvas.drawLine(
        Offset(rect.left + 10, rect.bottom),
        Offset(rect.right - 10, rect.bottom),
        Paint()
          ..strokeWidth = 1
          ..color = GamePalette.hudBorder.withValues(alpha: 0.16),
      );
    }
  }

  void _drawEntryIcon(
    Canvas canvas,
    WorldMenuIcon icon,
    Offset center,
    Color color,
  ) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    switch (icon) {
      case WorldMenuIcon.character:
        // 머리와 어깨로 이루어진 인물 실루엣.
        canvas.drawCircle(center + const Offset(0, -5), 3.8, stroke);
        canvas.drawArc(
          Rect.fromCenter(
            center: center + const Offset(0, 8),
            width: 15,
            height: 14,
          ),
          math.pi,
          math.pi,
          false,
          stroke,
        );
      case WorldMenuIcon.leaderboard:
        // 순위를 나타내는 세 개의 시상대. 가운데가 1위로 가장 높다.
        final fill = Paint()..color = color.withValues(alpha: 0.22);
        const podium = [
          // (좌측 x, 높이) — 2위 · 1위 · 3위 순으로 그린다.
          (-8.0, 8.0),
          (-2.5, 13.0),
          (3.0, 5.0),
        ];
        for (final (left, height) in podium) {
          final bar = Rect.fromLTWH(
            center.dx + left,
            center.dy + 8 - height,
            5.0,
            height,
          );
          canvas.drawRect(bar, fill);
          canvas.drawRect(bar, stroke);
        }
      case WorldMenuIcon.teleport:
        // 아이소메트릭 지면에 열린 마름모 포털과 그리로 빨려 드는 화살표.
        canvas.drawPath(
          Path()
            ..moveTo(center.dx, center.dy + 1)
            ..lineTo(center.dx + 9, center.dy + 5.5)
            ..lineTo(center.dx, center.dy + 10)
            ..lineTo(center.dx - 9, center.dy + 5.5)
            ..close(),
          stroke,
        );
        canvas.drawLine(
          center + const Offset(0, -9),
          center + const Offset(0, 2),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(center.dx - 4, center.dy - 2)
            ..lineTo(center.dx, center.dy + 2.5)
            ..lineTo(center.dx + 4, center.dy - 2),
          stroke,
        );
      case WorldMenuIcon.logout:
        // 열린 문에서 밖으로 향하는 화살표.
        canvas.drawPath(
          Path()
            ..moveTo(center.dx + 0.5, center.dy - 8)
            ..lineTo(center.dx - 7, center.dy - 8)
            ..lineTo(center.dx - 7, center.dy + 8)
            ..lineTo(center.dx + 0.5, center.dy + 8),
          stroke,
        );
        canvas.drawLine(
          center + const Offset(-1, 0),
          center + const Offset(7.5, 0),
          stroke,
        );
        canvas.drawPath(
          Path()
            ..moveTo(center.dx + 3.5, center.dy - 4)
            ..lineTo(center.dx + 7.5, center.dy)
            ..lineTo(center.dx + 3.5, center.dy + 4),
          stroke,
        );
    }
  }
}

/// 메뉴가 열려 있는 동안 화면 전체를 덮는 보이지 않는 레이어.
///
/// 메뉴 바깥을 누르면 닫히게 하고, 그 탭이 조이스틱이나 액션 버튼까지
/// 흘러가지 않도록 막는다.
class _MenuScrim extends PositionComponent with TapCallbacks {
  _MenuScrim({required this.onDismiss, required int priority})
      : super(priority: priority);

  final VoidCallback onDismiss;

  @override
  void onGameResize(Vector2 newSize) {
    super.onGameResize(newSize);
    size = newSize;
  }

  @override
  bool containsLocalPoint(Vector2 point) => true;

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    onDismiss();
  }
}
