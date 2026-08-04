import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../audio/game_audio.dart';
import '../iso.dart';
import '../level/level_map.dart';
import '../palette.dart';
import 'iso_entity.dart';

/// 맵 위의 한 칸을 차지하는 입체 구조물(벽 또는 보급 상자).
class BlockComponent extends IsoEntity with Damageable, HasVisibility {
  BlockComponent(this.spec)
      : _hp = spec.type == BlockType.crate ? 30 : double.infinity,
        _maxHp = spec.type == BlockType.crate ? 30 : double.infinity,
        super(
          grid: Vector2(spec.gx + 0.5, spec.gy + 0.5),
          bodyRadius: 0.5,
          depthBias: -0.05,
        );

  final BlockSpec spec;

  double _hp;
  final double _maxHp;
  double _hitFlash = 0;

  @override
  double get hp => _hp;

  @override
  double get maxHp => _maxHp;

  bool get isDestructible => spec.type == BlockType.crate;

  double get blockHeight => spec.height.toDouble();

  static final _rng = math.Random(1337);
  late final bool _hasGlowStrip =
      spec.type == BlockType.wall && _rng.nextDouble() < 0.22;
  late final double _panelSeed = _rng.nextDouble();

  @override
  void update(double dt) {
    super.update(dt);
    if (_hitFlash > 0) _hitFlash = math.max(0, _hitFlash - dt * 4);
  }

  @override
  void applyDamage(double amount, {Vector2? knockback, bool critical = false}) {
    if (!isDestructible || !isAlive) return;
    _hp -= amount;
    _hitFlash = 1;
    if (_hp <= 0) {
      _destroy();
    } else {
      GameAudio.play(Sfx.crateHit, at: grid);
    }
  }

  void _destroy() {
    GameAudio.play(Sfx.crateBreak, at: grid);
    game.onBlockDestroyed(this);
    removeFromParent();
  }

  // 타일 중심을 원점으로 한 지면 마름모의 네 꼭짓점.
  static const Offset _north = Offset(0, -kHalfTileHeight);
  static const Offset _east = Offset(kHalfTileWidth, 0);
  static const Offset _south = Offset(0, kHalfTileHeight);
  static const Offset _west = Offset(-kHalfTileWidth, 0);

  Path _topFace(double lift) {
    return Path()
      ..moveTo(_north.dx, _north.dy - lift)
      ..lineTo(_east.dx, _east.dy - lift)
      ..lineTo(_south.dx, _south.dy - lift)
      ..lineTo(_west.dx, _west.dy - lift)
      ..close();
  }

  Path _leftFace(double lift) {
    return Path()
      ..moveTo(_west.dx, _west.dy - lift)
      ..lineTo(_south.dx, _south.dy - lift)
      ..lineTo(_south.dx, _south.dy)
      ..lineTo(_west.dx, _west.dy)
      ..close();
  }

  Path _rightFace(double lift) {
    return Path()
      ..moveTo(_south.dx, _south.dy - lift)
      ..lineTo(_east.dx, _east.dy - lift)
      ..lineTo(_east.dx, _east.dy)
      ..lineTo(_south.dx, _south.dy)
      ..close();
  }

  @override
  void render(Canvas canvas) {
    final lift = blockHeight * kHeightUnit;
    final isCrate = spec.type == BlockType.crate;

    final leftColor = isCrate ? GamePalette.crateLeft : GamePalette.wallLeft;
    final rightColor = isCrate ? GamePalette.crateRight : GamePalette.wallRight;
    final topColor = isCrate ? GamePalette.crateTop : GamePalette.wallTop;

    final paint = Paint()..style = PaintingStyle.fill;

    paint.color = leftColor;
    canvas.drawPath(_leftFace(lift), paint);
    paint.color = rightColor;
    canvas.drawPath(_rightFace(lift), paint);
    paint.color = topColor;
    canvas.drawPath(_topFace(lift), paint);

    if (isCrate) {
      _renderCrateDetails(canvas, lift);
    } else {
      _renderWallDetails(canvas, lift);
    }

    // 상단 모서리 하이라이트.
    canvas.drawPath(
      _topFace(lift),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = isCrate
            ? GamePalette.crateTop.withValues(alpha: 0.9)
            : GamePalette.wallEdge,
    );

    if (_hitFlash > 0) {
      final flash = Paint()
        ..color = Colors.white.withValues(alpha: _hitFlash * 0.5)
        ..blendMode = BlendMode.plus;
      canvas.drawPath(_topFace(lift), flash);
      canvas.drawPath(_leftFace(lift), flash);
      canvas.drawPath(_rightFace(lift), flash);
    }
  }

  void _renderWallDetails(Canvas canvas, double lift) {
    // 층을 나누는 패널 이음선.
    final seam = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = Colors.black.withValues(alpha: 0.35);
    for (var level = 1; level < spec.height; level++) {
      final y = kHeightUnit * level;
      canvas.drawLine(
        Offset(_west.dx, _west.dy - y),
        Offset(_south.dx, _south.dy - y),
        seam,
      );
      canvas.drawLine(
        Offset(_south.dx, _south.dy - y),
        Offset(_east.dx, _east.dy - y),
        seam,
      );
    }

    // 리벳.
    final rivet = Paint()..color = Colors.black.withValues(alpha: 0.28);
    final rivetY = -lift + kHeightUnit * 0.45;
    canvas.drawCircle(Offset(-kHalfTileWidth * 0.45, rivetY + 16), 2, rivet);
    canvas.drawCircle(Offset(kHalfTileWidth * 0.45, rivetY + 16), 2, rivet);

    if (_hasGlowStrip) {
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..color = GamePalette.robotEye.withValues(alpha: 0.75)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      final y = -lift + kHeightUnit * (0.35 + _panelSeed * 0.3);
      canvas.drawLine(
        Offset(_west.dx * 0.55, y + kHalfTileHeight * 0.55),
        Offset(_south.dx, y + kHalfTileHeight),
        glow,
      );
    }
  }

  void _renderCrateDetails(Canvas canvas, double lift) {
    final strap = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.black.withValues(alpha: 0.35);
    canvas.drawLine(
      Offset(_west.dx * 0.5, _west.dy - lift * 0.5),
      Offset(_south.dx * 0.5, _south.dy - lift * 0.5),
      strap,
    );
    canvas.drawLine(
      Offset(_east.dx * 0.5, _east.dy - lift * 0.5),
      Offset(_south.dx * 0.5, _south.dy - lift * 0.5),
      strap,
    );

    // 저항군 보급 마크.
    final mark = Paint()
      ..color = GamePalette.playerAccent.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawCircle(Offset(0, -lift), 9, mark);
    canvas.drawLine(
      Offset(-5, -lift),
      Offset(5, -lift),
      mark,
    );
    canvas.drawLine(
      Offset(0, -lift - 5),
      Offset(0, -lift + 5),
      mark,
    );
  }
}
