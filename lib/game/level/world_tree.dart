import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../entities/iso_entity.dart';
import '../palette.dart';

/// 월드 정중앙 안전지대에 서 있는 큰 나무.
///
/// 이미지를 쓰지 않고 매 프레임 [Canvas]로 그린다. 그래서 크기·가지 배치·
/// 흔들림이 전부 수치로 정해지고, 값 하나만 바꿔도 다른 나무가 된다.
///
/// 무대가 전산망 내부이므로 자연 그대로의 나무가 아니라 **데이터가 자라
/// 굳은 나무**로 그린다 — 줄기는 배경에서 떨어지도록 짙게, 잎은 안전지대와
/// 같은 민트-그린 발광으로 둔다. 열매 자리에는 데이터 노드가 맺힌다.
///
/// 지면에 뿌리내린 장식이라 충돌 판정은 갖지 않는다. 통행을 막으려면
/// [LevelMap]의 타일을 바꿔야 하는데, 그러면 안전지대 한복판의 스폰·귀환
/// 로직까지 함께 손봐야 한다.
class WorldTree extends IsoEntity {
  WorldTree({required Vector2 grid, this.treeHeight = 236})
      : super(grid: grid, bodyRadius: 0.9);

  /// 밑동에서 우듬지까지의 높이(화면 픽셀).
  ///
  /// 사이보그의 키가 102~108이므로 기본값은 사람 두 배가 조금 넘는다.
  final double treeHeight;

  /// 바람 위상. 가지마다 어긋나게 흔들려야 통짜로 움직이지 않는다.
  double _time = 0;

  /// 잎 덩어리와 가지는 한 번 정하면 변하지 않는다. 매 프레임 난수를 뽑으면
  /// 나무가 부글거린다.
  late final List<_Branch> _branches = _buildBranches();
  late final List<_Leaf> _leaves = _buildLeaves();
  late final List<_Node> _nodes = _buildNodes();

  static final math.Random _rng = math.Random(20260804);

  @override
  void update(double dt) {
    advance(dt);
    super.update(dt);
  }

  /// 바람 시각만 [dt]만큼 흘린다.
  ///
  /// [update]는 컴포넌트가 마운트돼 있어야 하지만(좌표 갱신이 게임을 참조한다),
  /// 스냅샷 테스트는 캔버스에 바로 그린다. 흔들리는 순간을 검수하려면
  /// 시각만 따로 밀 수 있어야 한다.
  void advance(double dt) => _time += dt;

  @override
  void render(Canvas canvas) {
    // 아이소메트릭 지면에 눕는 그림자. 수관이 넓으니 크게 드리운다.
    renderShadow(canvas, treeHeight * 0.30, radiusY: treeHeight * 0.13);

    _drawRoots(canvas);
    _drawTrunk(canvas);
    for (final branch in _branches) {
      _drawBranch(canvas, branch);
    }
    for (final leaf in _leaves) {
      _drawLeaf(canvas, leaf);
    }
    for (final node in _nodes) {
      _drawNode(canvas, node);
    }
  }

  // ── 형태 만들기 ─────────────────────────────────────────────────────

  List<_Branch> _buildBranches() {
    // 좌우로 번갈아 뻗되 높이와 길이를 조금씩 달리해 대칭을 깬다.
    //
    // 길이는 수관 반지름(잎 덩어리 최대 0.30)보다 길게 잡는다. 그보다 짧으면
    // 가지가 잎 안에 통째로 갇혀, 그리는 비용만 들고 실루엣에는 아무것도
    // 보태지 못한다.
    const specs = <(double, double, double)>[
      // (밑동에서의 높이 비율, 방향(-1 왼쪽/1 오른쪽), 길이 비율)
      (0.44, -1, 0.40),
      (0.54, 1, 0.44),
      (0.66, -1, 0.34),
      (0.76, 1, 0.28),
    ];
    return [
      for (final (at, dir, len) in specs)
        _Branch(
          startY: -treeHeight * at,
          direction: dir,
          length: treeHeight * len,
          rise: treeHeight * (0.10 + _rng.nextDouble() * 0.05),
          phase: _rng.nextDouble() * math.pi * 2,
        ),
    ];
  }

  List<_Leaf> _buildLeaves() {
    // 수관을 덩어리 여러 개로 쌓아 실루엣에 굴곡을 만든다. 하나의 큰 원은
    // 축소했을 때 공처럼 보인다.
    const specs = <(double, double, double)>[
      // (중심 x 비율, 중심 y 비율(위가 음수), 반지름 비율)
      (0.00, 0.86, 0.30),
      (-0.24, 0.74, 0.25),
      (0.25, 0.76, 0.24),
      (-0.14, 0.94, 0.20),
      (0.16, 0.95, 0.19),
      (0.00, 0.66, 0.22),
    ];
    return [
      for (final (dx, dy, r) in specs)
        _Leaf(
          center: Offset(treeHeight * dx, -treeHeight * dy),
          radius: treeHeight * r,
          phase: _rng.nextDouble() * math.pi * 2,
          // 위쪽 덩어리일수록 바람을 더 받는다.
          sway: 0.5 + dy * 0.9,
        ),
    ];
  }

  List<_Node> _buildNodes() {
    // 잎 사이에 맺히는 데이터 열매. 맥동 위상을 흩어 놓아야 함께 깜빡이지 않는다.
    return [
      for (var i = 0; i < 7; i++)
        _Node(
          center: Offset(
            treeHeight * (_rng.nextDouble() * 0.52 - 0.26),
            -treeHeight * (0.66 + _rng.nextDouble() * 0.28),
          ),
          radius: 2.0 + _rng.nextDouble() * 1.6,
          phase: _rng.nextDouble() * math.pi * 2,
        ),
    ];
  }

  // ── 그리기 ──────────────────────────────────────────────────────────

  /// 밑동에서 지면으로 퍼지는 뿌리. 나무가 땅에 얹힌 것처럼 보이지 않게 한다.
  void _drawRoots(Canvas canvas) {
    final w = treeHeight * 0.13;
    final paint = Paint()..color = GamePalette.textPrimary;
    for (var i = -2; i <= 2; i++) {
      if (i == 0) continue;
      final dx = i * w * 0.42;
      final path = Path()
        ..moveTo(0, -treeHeight * 0.06)
        ..quadraticBezierTo(dx * 0.6, -treeHeight * 0.02, dx, 0)
        ..quadraticBezierTo(dx * 0.5, treeHeight * 0.012, 0, 0)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  void _drawTrunk(Canvas canvas) {
    final bottom = treeHeight * 0.085;
    final top = treeHeight * 0.030;
    final trunkTop = -treeHeight * 0.62;
    // 우듬지 쪽이 바람에 조금 밀린다.
    final lean = math.sin(_time * 0.8) * treeHeight * 0.010;

    final path = Path()
      ..moveTo(-bottom, 0)
      ..quadraticBezierTo(-bottom * 0.72, trunkTop * 0.5, -top + lean, trunkTop)
      ..lineTo(top + lean, trunkTop)
      ..quadraticBezierTo(bottom * 0.72, trunkTop * 0.5, bottom, 0)
      ..close();
    canvas.drawPath(path, Paint()..color = GamePalette.textPrimary);

    // 빛을 받는 왼쪽 면. 2톤으로 나눠야 원통처럼 읽힌다.
    final litPath = Path()
      ..moveTo(-bottom, 0)
      ..quadraticBezierTo(
        -bottom * 0.72,
        trunkTop * 0.5,
        -top + lean,
        trunkTop,
      )
      ..lineTo(-top * 0.1 + lean, trunkTop)
      ..quadraticBezierTo(-bottom * 0.2, trunkTop * 0.5, -bottom * 0.28, 0)
      ..close();
    canvas.drawPath(
      litPath,
      Paint()..color = GamePalette.playerArmorLight.withValues(alpha: 0.55),
    );

    // 줄기를 타고 오르는 수액 회로.
    final vein = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..color = GamePalette.safeZoneGlow.withValues(alpha: 0.5);
    canvas.drawPath(
      Path()
        ..moveTo(-bottom * 0.3, -treeHeight * 0.03)
        ..quadraticBezierTo(
          bottom * 0.15,
          trunkTop * 0.45,
          -top * 0.3 + lean,
          trunkTop * 0.95,
        ),
      vein,
    );
  }

  void _drawBranch(Canvas canvas, _Branch branch) {
    // 가지마다 위상이 달라 통짜로 흔들리지 않는다.
    final sway = math.sin(_time * 1.1 + branch.phase) * branch.length * 0.045;
    final endX = branch.direction * branch.length + sway;
    final endY = branch.startY - branch.rise;

    canvas.drawPath(
      Path()
        ..moveTo(0, branch.startY)
        ..quadraticBezierTo(
          branch.direction * branch.length * 0.55,
          branch.startY - branch.rise * 0.35,
          endX,
          endY,
        ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = treeHeight * 0.020
        ..strokeCap = StrokeCap.round
        ..color = GamePalette.textPrimary,
    );
  }

  void _drawLeaf(Canvas canvas, _Leaf leaf) {
    final sway = math.sin(_time * 0.9 + leaf.phase) * 2.4 * leaf.sway;
    final center = leaf.center.translate(sway, math.sin(_time * 1.3 + leaf.phase) * 1.1);

    // 바깥 후광 → 본체 → 밝은 윗면. 세 겹이라야 발광하는 잎으로 읽힌다.
    canvas.drawCircle(
      center,
      leaf.radius * 1.06,
      Paint()
        ..color = GamePalette.safeZoneGlow.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawCircle(
      center,
      leaf.radius,
      Paint()..color = GamePalette.safeZoneEdge,
    );
    // 위에서 빛을 받는 면.
    canvas.drawCircle(
      center.translate(-leaf.radius * 0.22, -leaf.radius * 0.26),
      leaf.radius * 0.68,
      Paint()..color = GamePalette.safeZoneFill.withValues(alpha: 0.85),
    );
  }

  void _drawNode(Canvas canvas, _Node node) {
    final pulse = 0.55 + 0.45 * math.sin(_time * 2.4 + node.phase);
    final sway = math.sin(_time * 0.9 + node.phase) * 2.0;
    final center = node.center.translate(sway, 0);

    canvas.drawCircle(
      center,
      node.radius * 2.4,
      Paint()
        ..color = GamePalette.playerAccent.withValues(alpha: 0.30 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );
    canvas.drawCircle(
      center,
      node.radius,
      Paint()..color = GamePalette.bladeCore.withValues(alpha: 0.65 + 0.35 * pulse),
    );
  }
}

/// 줄기에서 뻗어 나온 가지 하나.
class _Branch {
  const _Branch({
    required this.startY,
    required this.direction,
    required this.length,
    required this.rise,
    required this.phase,
  });

  /// 줄기에서 갈라지는 높이(위가 음수).
  final double startY;

  /// -1이면 왼쪽, 1이면 오른쪽.
  final double direction;

  final double length;

  /// 끝이 시작보다 얼마나 위로 올라가는지.
  final double rise;

  /// 바람 위상.
  final double phase;
}

/// 수관을 이루는 잎 덩어리 하나.
class _Leaf {
  const _Leaf({
    required this.center,
    required this.radius,
    required this.phase,
    required this.sway,
  });

  final Offset center;
  final double radius;
  final double phase;

  /// 바람에 흔들리는 정도. 위쪽 덩어리일수록 크다.
  final double sway;
}

/// 잎 사이에 맺힌 데이터 열매.
class _Node {
  const _Node({
    required this.center,
    required this.radius,
    required this.phase,
  });

  final Offset center;
  final double radius;
  final double phase;
}
