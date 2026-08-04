import '../entities/pickup.dart';
import '../entities/player.dart';

/// 인벤토리 한 칸. 같은 종류의 포션이 [count]개 쌓여 있다.
class InventorySlot {
  InventorySlot(this.kind, this.count);

  final PickupKind kind;
  int count;

  PickupSpec get spec => PickupSpec.table[kind]!;
}

/// 포션을 사용했을 때 실제로 적용된 결과.
class PotionUseResult {
  const PotionUseResult({
    required this.kind,
    required this.healed,
    required this.energized,
    required this.buffed,
  });

  final PickupKind kind;

  /// 실제로 회복된 체력(이미 만피면 0).
  final double healed;

  /// 실제로 회복된 에너지.
  final double energized;

  /// 강화 효과가 걸렸는지 여부.
  final bool buffed;

  PickupSpec get spec => PickupSpec.table[kind]!;
}

/// 회수한 포션을 보관하는 가방.
///
/// 같은 종류는 한 칸에 [maxStack]개까지 쌓이고, 칸은 [slotCount]개까지
/// 늘어난다. 포션이 아닌 전리품(데이터 칩·스크랩 코어)은 회수 즉시
/// 환산되므로 여기 들어오지 않는다.
class Inventory {
  Inventory({this.slotCount = 6, this.maxStack = 9});

  /// 서로 다른 종류를 몇 칸까지 담을 수 있는지.
  final int slotCount;

  /// 한 칸에 몇 개까지 쌓이는지.
  final int maxStack;

  final List<InventorySlot> _slots = [];

  /// 획득한 순서대로 정렬된 칸 목록(읽기 전용).
  List<InventorySlot> get slots => List.unmodifiable(_slots);

  bool get isEmpty => _slots.isEmpty;

  /// 담긴 포션의 총 개수.
  int get totalCount =>
      _slots.fold(0, (sum, slot) => sum + slot.count);

  /// [kind]를 몇 개 갖고 있는지.
  int countOf(PickupKind kind) {
    for (final slot in _slots) {
      if (slot.kind == kind) return slot.count;
    }
    return 0;
  }

  /// [kind]를 더 받을 자리가 있는지.
  ///
  /// 자리가 없으면 전리품이 바닥에 남으므로 자동 회수도 멈춘다.
  bool canAccept(PickupKind kind) {
    for (final slot in _slots) {
      if (slot.kind == kind) return slot.count < maxStack;
    }
    return _slots.length < slotCount;
  }

  /// 포션을 [count]개 담는다. 자리가 없으면 아무것도 담지 않고 false.
  bool add(PickupKind kind, {int count = 1}) {
    if (!PickupSpec.table[kind]!.isPotion) return false;

    for (final slot in _slots) {
      if (slot.kind != kind) continue;
      if (slot.count >= maxStack) return false;
      slot.count = (slot.count + count).clamp(0, maxStack);
      return true;
    }

    if (_slots.length >= slotCount) return false;
    _slots.add(InventorySlot(kind, count.clamp(1, maxStack)));
    return true;
  }

  /// [kind] 포션을 한 개 마신다.
  ///
  /// 보유하지 않았거나 [player]가 죽었으면 null을 돌려준다.
  PotionUseResult? use(PickupKind kind, Player player) {
    if (!player.isAlive) return null;

    final index = _slots.indexWhere((slot) => slot.kind == kind);
    if (index < 0) return null;

    final effect = PickupSpec.table[kind]!.potion;
    if (effect == null) return null;

    final slot = _slots[index];
    slot.count--;
    if (slot.count <= 0) _slots.removeAt(index);

    return player.drinkPotion(kind, effect);
  }

  /// 첫 번째 칸부터 세어 [index]번째 칸의 포션을 마신다(퀵슬롯용).
  PotionUseResult? useSlot(int index, Player player) {
    if (index < 0 || index >= _slots.length) return null;
    return use(_slots[index].kind, player);
  }

  /// 자동·수동 회복에 쓸 체력 포션을 고른다. 없으면 null.
  ///
  /// 소형부터 비워 대형을 위급한 순간까지 아껴 둔다. 전투 강화제는
  /// 회복이 곁다리라 여기서 고르지 않는다.
  PickupKind? bestHealingPotion() {
    for (final kind in const [
      PickupKind.nanoVial,
      PickupKind.nanoCanister,
      PickupKind.repairCell,
      PickupKind.regenAmpoule,
      PickupKind.overhaulKit,
    ]) {
      if (countOf(kind) > 0) return kind;
    }
    return null;
  }

  void clear() => _slots.clear();
}
