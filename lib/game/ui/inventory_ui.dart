import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import '../action_rpg_game.dart';
import '../entities/pickup.dart';
import '../palette.dart';
import '../systems/buff.dart';
import '../systems/inventory.dart';

/// 화면 하단 중앙의 포션 퀵슬롯 줄.
///
/// 회수한 포션이 순서대로 채워지고, 슬롯을 누르거나 숫자키를 누르면
/// 그 자리에서 마신다.
class PotionQuickBar extends PositionComponent
    with HasGameReference<ActionRpgGame> {
  PotionQuickBar() : super(priority: 95, anchor: Anchor.bottomCenter);

  static const double maxSlotSize = 52;
  static const double minSlotSize = 34;
  static const double slotGap = 8;

  /// 좌하단 조이스틱이 차지하는 폭.
  static const double joystickReserve = 172;

  /// 우하단 액션 버튼들이 차지하는 폭.
  static const double actionReserve = 216;

  /// 마운트 순서와 무관하게 배치할 수 있도록 슬롯을 직접 들고 있는다.
  final List<PotionSlotButton> _buttons = [];

  @override
  Future<void> onLoad() async {
    for (var i = 0; i < game.inventory.slotCount; i++) {
      final button = PotionSlotButton(index: i);
      _buttons.add(button);
      add(button);
    }
    _applyLayout(game.size);
  }

  @override
  void onGameResize(Vector2 newSize) {
    super.onGameResize(newSize);
    if (isLoaded) _applyLayout(newSize);
  }

  /// 조이스틱과 액션 버튼 사이 공간에 맞춰 슬롯 크기와 위치를 잡는다.
  void _applyLayout(Vector2 screenSize) {
    if (_buttons.isEmpty) return;

    final available =
        math.max(160.0, screenSize.x - joystickReserve - actionReserve);
    final gaps = (_buttons.length - 1) * slotGap;
    final slotSize = ((available - gaps) / _buttons.length)
        .clamp(minSlotSize, maxSlotSize);

    size = Vector2(_buttons.length * slotSize + gaps, slotSize + 14);

    for (var i = 0; i < _buttons.length; i++) {
      _buttons[i]
        ..size = Vector2.all(slotSize)
        ..position = Vector2(i * (slotSize + slotGap), 14);
    }

    position = Vector2(
      (joystickReserve + (screenSize.x - actionReserve)) / 2,
      screenSize.y - 10,
    );
  }
}

/// 퀵슬롯 한 칸. 비어 있으면 흐릿한 테두리만 남는다.
class PotionSlotButton extends PositionComponent
    with TapCallbacks, HasGameReference<ActionRpgGame> {
  PotionSlotButton({required this.index})
      : super(size: Vector2.all(PotionQuickBar.maxSlotSize));

  /// 인벤토리에서 몇 번째 칸을 보여 주는지.
  final int index;

  double _useFlash = 0;

  InventorySlot? get _slot {
    final slots = game.inventory.slots;
    return index < slots.length ? slots[index] : null;
  }

  final TextPaint _hotkey = TextPaint(
    style: const TextStyle(
      color: GamePalette.textDim,
      fontSize: 10,
      fontWeight: FontWeight.w700,
    ),
  );
  final TextPaint _count = TextPaint(
    style: const TextStyle(
      color: GamePalette.textPrimary,
      fontSize: 13,
      fontWeight: FontWeight.w900,
      shadows: [Shadow(color: Colors.black, blurRadius: 3)],
    ),
  );

  @override
  void onTapDown(TapDownEvent event) {
    event.handled = true;
    final slot = _slot;
    if (slot == null) return;
    if (game.usePotion(slot.kind)) _useFlash = 1;
  }

  @override
  void update(double dt) {
    if (_useFlash > 0) _useFlash = math.max(0, _useFlash - dt * 3);
  }

  @override
  void render(Canvas canvas) {
    final slot = _slot;
    final rect = Rect.fromLTWH(0, 0, width, height);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    final color = slot?.spec.color ?? GamePalette.textDim;

    // 사용 직후 잠깐 밝게 빛난다.
    if (_useFlash > 0) {
      canvas.drawRRect(
        rrect.inflate(4),
        Paint()
          ..color = color.withValues(alpha: 0.5 * _useFlash)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
    }

    canvas.drawRRect(rrect, Paint()..color = GamePalette.hudBackground);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = slot == null ? 1.2 : 2
        ..color = color.withValues(alpha: slot == null ? 0.22 : 0.85),
    );

    // 단축키 번호는 항상 보인다.
    _hotkey.render(canvas, '${index + 1}', Vector2(5, 3));

    if (slot == null) return;

    canvas.save();
    canvas.translate(width / 2, height / 2 + 2);
    // 슬롯이 줄어들면 아이콘도 같은 비율로 작아진다.
    canvas.scale(0.82 * width / PotionQuickBar.maxSlotSize);
    Pickup.drawIcon(canvas, slot.kind, slot.spec.color);
    canvas.restore();

    // 보유 개수
    final text = 'x${slot.count}';
    _count.render(
      canvas,
      text,
      Vector2(width - 5, height - 4),
      anchor: Anchor.bottomRight,
    );
  }
}

/// 지금 걸려 있는 강화 효과를 남은 시간과 함께 보여 주는 줄.
class BuffBar extends PositionComponent with HasGameReference<ActionRpgGame> {
  BuffBar() : super(priority: 96, anchor: Anchor.topCenter);

  static const double pillWidth = 74;
  static const double pillHeight = 22;
  static const double gap = 6;

  @override
  void onGameResize(Vector2 newSize) {
    super.onGameResize(newSize);
    // 웨이브 배너 바로 아래에 자리 잡는다.
    position = Vector2(newSize.x / 2, 96);
  }

  final TextPaint _label = TextPaint(
    style: const TextStyle(
      color: GamePalette.textPrimary,
      fontSize: 11,
      fontWeight: FontWeight.w900,
      letterSpacing: 1,
    ),
  );

  @override
  void render(Canvas canvas) {
    final buffs = game.player.buffs.active;
    if (buffs.isEmpty) return;

    final totalWidth = buffs.length * pillWidth + (buffs.length - 1) * gap;
    var x = -totalWidth / 2;

    for (final buff in buffs) {
      _renderPill(canvas, buff, x);
      x += pillWidth + gap;
    }
  }

  void _renderPill(Canvas canvas, ActiveBuff buff, double x) {
    final rect = Rect.fromLTWH(x, 0, pillWidth, pillHeight);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(11));
    final color = buff.spec.color;

    // 곧 끝나면 깜빡여 알려 준다.
    final expiring = buff.remaining < 3;
    final blink = expiring ? 0.55 + math.sin(buff.remaining * 12) * 0.45 : 1.0;

    canvas.drawRRect(rrect, Paint()..color = GamePalette.hudBackground);

    // 남은 시간만큼 안쪽을 채운다.
    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      Rect.fromLTWH(x, 0, pillWidth * buff.ratio, pillHeight),
      Paint()..color = color.withValues(alpha: 0.28 * blink),
    );
    canvas.restore();

    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = color.withValues(alpha: 0.8 * blink),
    );

    _label.render(
      canvas,
      '${buff.spec.label} ${buff.remaining.ceil()}s',
      Vector2(x + pillWidth / 2, pillHeight / 2),
      anchor: Anchor.center,
    );
  }
}

/// 회수한 포션을 한눈에 보는 인벤토리 패널.
///
/// `I` 키나 HUD 버튼으로 열고 닫으며, 항목을 누르면 바로 마신다.
class InventoryPanel extends PositionComponent
    with TapCallbacks, HasGameReference<ActionRpgGame> {
  InventoryPanel() : super(priority: 120);

  static const double rowHeight = 54;
  static const double panelWidth = 340;
  static const double headerHeight = 46;
  static const double footerHeight = 30;

  bool _open = false;
  double _anim = 0;

  bool get isOpen => _open;

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
      fontSize: 13,
      fontWeight: FontWeight.w800,
    ),
  );
  final TextPaint _detail = TextPaint(
    style: const TextStyle(
      color: GamePalette.textDim,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    ),
  );
  final TextPaint _stack = TextPaint(
    style: const TextStyle(
      color: GamePalette.textPrimary,
      fontSize: 15,
      fontWeight: FontWeight.w900,
    ),
  );
  final TextPaint _hint = TextPaint(
    style: const TextStyle(
      color: GamePalette.textDim,
      fontSize: 10,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    ),
  );
  final TextPaint _empty = TextPaint(
    style: const TextStyle(
      color: GamePalette.textDim,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
  );

  @override
  void onGameResize(Vector2 newSize) {
    super.onGameResize(newSize);
    size = newSize;
  }

  void toggle() => _open ? close() : open();

  void open() => _open = true;

  void close() => _open = false;

  @override
  void update(double dt) {
    // 열고 닫을 때 살짝 미끄러지듯 움직인다.
    final target = _open ? 1.0 : 0.0;
    _anim += (target - _anim) * math.min(1, dt * 14);
    if ((_anim - target).abs() < 0.005) _anim = target;
  }

  /// 패널 본체가 차지하는 사각형.
  Rect get _panelRect {
    final slots = game.inventory.slots;
    final rows = math.max(1, slots.length);
    final height = headerHeight + rows * rowHeight + footerHeight;
    return Rect.fromCenter(
      center: Offset(size.x / 2, size.y / 2),
      width: panelWidth,
      height: height,
    );
  }

  @override
  bool containsLocalPoint(Vector2 point) {
    // 열려 있을 때만 입력을 가로챈다.
    return _open;
  }

  @override
  void onTapDown(TapDownEvent event) {
    if (!_open) return;
    event.handled = true;

    final local = event.localPosition;
    final panel = _panelRect;
    if (!panel.contains(Offset(local.x, local.y))) {
      // 바깥을 누르면 닫는다.
      close();
      return;
    }

    final index =
        ((local.y - panel.top - headerHeight) / rowHeight).floor();
    final slots = game.inventory.slots;
    if (index < 0 || index >= slots.length) return;
    game.usePotion(slots[index].kind);
  }

  @override
  void render(Canvas canvas) {
    if (_anim <= 0.005) return;

    // 뒤쪽 게임 화면을 어둡게 깔아 준다.
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.x, size.y),
      Paint()..color = Colors.black.withValues(alpha: 0.55 * _anim),
    );

    final panel = _panelRect;
    canvas.save();
    // 아래에서 살짝 올라오며 나타난다.
    canvas.translate(0, (1 - _anim) * 24);

    final rrect =
        RRect.fromRectAndRadius(panel, const Radius.circular(12));
    canvas.drawRRect(rrect, Paint()..color = GamePalette.hudBackground);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = GamePalette.hudBorder.withValues(alpha: 0.7),
    );

    final inventory = game.inventory;
    _title.render(
      canvas,
      'INVENTORY',
      Vector2(panel.left + 16, panel.top + 16),
    );
    _hint.render(
      canvas,
      '${inventory.totalCount} / ${inventory.slotCount * inventory.maxStack}',
      Vector2(panel.right - 16, panel.top + 18),
      anchor: Anchor.topRight,
    );
    canvas.drawLine(
      Offset(panel.left + 12, panel.top + headerHeight - 6),
      Offset(panel.right - 12, panel.top + headerHeight - 6),
      Paint()
        ..strokeWidth = 1
        ..color = GamePalette.hudBorder.withValues(alpha: 0.25),
    );

    final slots = inventory.slots;
    if (slots.isEmpty) {
      _empty.render(
        canvas,
        'NO POTIONS — DESTROY ROBOTS TO LOOT',
        Vector2(panel.center.dx, panel.top + headerHeight + rowHeight / 2),
        anchor: Anchor.center,
      );
    } else {
      for (var i = 0; i < slots.length; i++) {
        _renderRow(canvas, slots[i], i, panel);
      }
    }

    _hint.render(
      canvas,
      'TAP TO DRINK   ·   1~${inventory.slotCount} QUICK USE   ·   I TO CLOSE',
      Vector2(panel.center.dx, panel.bottom - 14),
      anchor: Anchor.center,
    );

    canvas.restore();
  }

  void _renderRow(Canvas canvas, InventorySlot slot, int index, Rect panel) {
    final top = panel.top + headerHeight + index * rowHeight;
    final rowRect = Rect.fromLTWH(
      panel.left + 8,
      top + 3,
      panel.width - 16,
      rowHeight - 6,
    );
    final color = slot.spec.color;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rowRect, const Radius.circular(8)),
      Paint()..color = color.withValues(alpha: 0.08),
    );

    // 아이콘
    canvas.save();
    canvas.translate(rowRect.left + 28, rowRect.center.dy);
    canvas.scale(0.72);
    Pickup.drawIcon(canvas, slot.kind, color);
    canvas.restore();

    _name.render(
      canvas,
      slot.spec.name,
      Vector2(rowRect.left + 56, rowRect.top + 9),
    );
    _detail.render(
      canvas,
      _describe(slot.kind),
      Vector2(rowRect.left + 56, rowRect.top + 27),
    );
    _stack.render(
      canvas,
      'x${slot.count}',
      Vector2(rowRect.right - 12, rowRect.center.dy),
      anchor: Anchor.centerRight,
    );
  }

  /// 포션 한 줄 설명. 회복량과 강화 효과를 함께 적는다.
  String _describe(PickupKind kind) {
    final effect = PickupSpec.table[kind]!.potion;
    if (effect == null) return '';

    final parts = <String>[];
    if (effect.heal > 0) parts.add('+${effect.heal.round()} HP');
    if (effect.energy > 0) parts.add('+${effect.energy.round()} EN');

    final buff = effect.buff;
    if (buff != null) {
      final spec = BuffSpec.table[buff]!;
      final gains = <String>[];
      if (spec.damageMultiplier != 1.0) {
        gains.add('DMG +${((spec.damageMultiplier - 1) * 100).round()}%');
      }
      if (spec.speedMultiplier != 1.0) {
        gains.add('SPD +${((spec.speedMultiplier - 1) * 100).round()}%');
      }
      if (spec.damageTakenMultiplier != 1.0) {
        // 수치 스탯인 방어력(DEF)과 헷갈리지 않도록 다른 이름을 쓴다.
        // 이쪽은 "받는 피해를 몇 % 깎는다"는 별개의 축이다.
        gains.add(
          '피해감소 ${((1 - spec.damageTakenMultiplier) * 100).round()}%',
        );
      }
      if (spec.energyRegenMultiplier != 1.0) {
        gains.add('EN REGEN x${spec.energyRegenMultiplier.toStringAsFixed(1)}');
      }
      parts.add('${gains.join(' ')} (${spec.duration.round()}s)');
    }

    return parts.join('   ');
  }
}
