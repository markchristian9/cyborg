import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import '../action_rpg_game.dart';
import '../palette.dart';
import 'inventory_ui.dart';

/// 고른 요원에게 무엇을 할지 고르는 하단 막대.
///
/// 원격 요원의 몸을 누르면 나타나고, 빈 땅을 누르면 사라진다. 자리는 퀵슬롯
/// **바로 위 가운데**다 — 좌하단은 조이스틱, 우하단은 액션 버튼이 차지하고 있어
/// 그 사이 통로가 겹치지 않는 유일한 곳이다.
///
/// 선택이 없을 때는 [containsLocalPoint] 가 거짓이라 탭이 그대로 월드로
/// 내려간다. 별도의 탭 차폐막이 필요 없는 이유다.
class ContextActionBar extends PositionComponent
    with TapCallbacks, HasGameReference<ActionRpgGame> {
  ContextActionBar({int priority = 138})
      : super(anchor: Anchor.bottomCenter, priority: priority);

  /// 막대의 높이.
  static const double barHeight = 46;

  /// 퀵슬롯과의 간격.
  static const double gapAboveQuickBar = 8;

  /// 최대 너비. 넓은 화면에서 끝없이 늘어나지 않게 한다.
  static const double maxWidth = 380;

  /// 눌린 버튼. 0=파티, 1=교환. 없으면 -1.
  int _pressed = -1;

  final TextPaint _name = TextPaint(
    style: const TextStyle(
      color: GamePalette.textPrimary,
      fontSize: 13,
      fontWeight: FontWeight.w800,
    ),
  );
  final TextPaint _button = TextPaint(
    style: const TextStyle(
      color: GamePalette.textPrimary,
      fontSize: 13,
      fontWeight: FontWeight.w700,
    ),
  );
  final TextPaint _disabled = TextPaint(
    style: TextStyle(
      color: GamePalette.textPrimary.withValues(alpha: 0.4),
      fontSize: 13,
      fontWeight: FontWeight.w700,
    ),
  );

  @override
  void onMount() {
    super.onMount();
    _applyLayout(game.size);
  }

  @override
  void onGameResize(Vector2 newSize) {
    super.onGameResize(newSize);
    if (isLoaded) _applyLayout(newSize);
  }

  void _applyLayout(Vector2 screenSize) {
    final available = math.max(
      200.0,
      screenSize.x - PotionQuickBar.joystickReserve - PotionQuickBar.actionReserve,
    );
    size = Vector2(math.min(maxWidth, available), barHeight);

    // 퀵슬롯이 화면 폭에 따라 커지므로 그 높이를 읽어 그만큼 띄운다.
    final quickBarHeight = _quickBarHeight();
    position = Vector2(
      (PotionQuickBar.joystickReserve +
              (screenSize.x - PotionQuickBar.actionReserve)) /
          2,
      screenSize.y - 10 - quickBarHeight - gapAboveQuickBar,
    );
  }

  /// 퀵슬롯이 차지하는 높이. 슬롯 크기가 화면 폭에 따라 변하므로 직접 읽는다.
  double _quickBarHeight() {
    final bar = game.camera.viewport.children.whereType<PotionQuickBar>();
    if (bar.isNotEmpty) return bar.first.size.y;
    return 60;
  }

  // ── 상태 ────────────────────────────────────────────────────────────

  bool get _visible => game.selectedRemotePlayer != null;

  /// 파티 버튼에 쓸 문구와 누를 수 있는지.
  ///
  /// 서버가 최종 판정하므로 여기서는 **확실히 안 되는 것만** 미리 막는다.
  /// 상대가 다른 파티에 있는지 등은 내 화면에서 알 수 없어 눌러 보고 사유를 받는다.
  (String, bool) get _partyAction {
    final party = game.party;
    final target = game.selectedRemotePlayer;
    if (target == null) return ('파티 초대', false);

    if (party.members.any((m) => m.characterId == target.characterId)) {
      return ('파티원', false);
    }
    if (party.inParty && party.isFull) {
      return ('정원이 찼다', false);
    }
    return ('파티 초대', true);
  }

  // ── 렌더링 ──────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    final target = game.selectedRemotePlayer;
    if (target == null) return;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.x, size.y),
      const Radius.circular(12),
    );
    canvas.drawRRect(rect, Paint()..color = GamePalette.hudBackground);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = GamePalette.hudBorder.withValues(alpha: 0.6),
    );

    _name.render(
      canvas,
      target.name.isEmpty ? '요원' : target.name,
      Vector2(12, size.y / 2),
      anchor: Anchor.centerLeft,
    );

    final (partyLabel, partyEnabled) = _partyAction;
    _renderButton(canvas, 0, partyLabel, enabled: partyEnabled);
    _renderButton(canvas, 1, '교환 · 준비 중', enabled: false);
  }

  /// 버튼 두 개는 오른쪽에 나란히 둔다. 왼쪽은 이름 자리다.
  Rect _buttonRect(int index) {
    const width = 104.0;
    const gap = 6.0;
    final right = size.x - 10;
    final left = right - width * 2 - gap;
    return Rect.fromLTWH(
      left + index * (width + gap),
      8,
      width,
      size.y - 16,
    );
  }

  void _renderButton(
    Canvas canvas,
    int index,
    String label, {
    required bool enabled,
  }) {
    final rect = _buttonRect(index);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(8)),
      Paint()
        ..color = !enabled
            ? GamePalette.hudBorder.withValues(alpha: 0.07)
            : (_pressed == index
                ? GamePalette.hudBorder.withValues(alpha: 0.3)
                : GamePalette.hudBorder.withValues(alpha: 0.16)),
    );
    (enabled ? _button : _disabled).render(
      canvas,
      label,
      Vector2(rect.center.dx, rect.center.dy),
      anchor: Anchor.center,
    );
  }

  // ── 입력 ────────────────────────────────────────────────────────────

  @override
  bool containsLocalPoint(Vector2 point) =>
      _visible && super.containsLocalPoint(point);

  @override
  void onTapDown(TapDownEvent event) {
    final local = Offset(event.localPosition.x, event.localPosition.y);
    for (var i = 0; i < 2; i++) {
      if (_buttonRect(i).contains(local)) {
        _pressed = i;
        return;
      }
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    final pressed = _pressed;
    _pressed = -1;
    final target = game.selectedRemotePlayer;
    if (pressed < 0 || target == null) return;

    if (pressed == 0) {
      final (_, enabled) = _partyAction;
      if (!enabled) return;
      game.invitePlayerToParty(target.characterId, target.name);
      return;
    }

    // 교환은 아직 없다. 서버에 인벤토리 표가 없어 소유권을 검증할 자료 자체가
    // 없으므로, 있는 척하는 화면을 만들지 않고 사실대로 알린다.
    game.showBanner('교환은 아직 준비 중이다');
  }

  @override
  void onTapCancel(TapCancelEvent event) => _pressed = -1;
}
