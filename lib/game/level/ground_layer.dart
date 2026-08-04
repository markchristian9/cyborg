import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../action_rpg_game.dart';
import '../iso.dart';
import '../palette.dart';
import 'level_map.dart';

/// 청크 하나의 래스터화 결과.
class _GroundChunk {
  _GroundChunk(this.picture, this.hazardPath, this.bounds);

  final ui.Picture picture;

  /// 청크 안 방화벽 구역 전체를 합친 경로. 없으면 null.
  final Path? hazardPath;

  /// 청크가 화면에서 차지하는 영역(월드 좌표).
  final Rect bounds;

  /// 마지막으로 화면에 쓰인 시각. 캐시 방출 판단에 쓴다.
  double lastUsed = 0;

  void dispose() => picture.dispose();
}

/// 1 km × 1 km 데이터 공간의 바닥을 그리는 레이어.
///
/// 100만 칸을 한 장으로 래스터화할 수 없으므로 월드를 [kChunkTiles] 격자로
/// 나누고, 카메라에 들어온 청크만 [ui.Picture]로 구워 캐시한다.
/// 맥동하는 방화벽 발광만 매 프레임 덧그린다.
class GroundLayer extends PositionComponent
    with HasGameReference<ActionRpgGame> {
  GroundLayer(this.map) : super(priority: -100000);

  final LevelMap map;

  final Map<int, _GroundChunk> _cache = {};
  final List<int> _visibleKeys = [];

  double _time = 0;

  /// 캐시에 유지할 최대 청크 수. 화면에 필요한 양의 몇 배로 넉넉히 잡는다.
  static const int _maxCachedChunks = 96;

  /// 프레임당 새로 구울 수 있는 청크 수. 이동 중 프레임 스파이크를 막는다.
  static const int _chunkBudgetPerFrame = 3;

  @override
  void onRemove() {
    for (final chunk in _cache.values) {
      chunk.dispose();
    }
    _cache.clear();
    super.onRemove();
  }

  @override
  void update(double dt) {
    _time += dt;
    _refreshVisibleChunks();
  }

  /// 카메라가 보는 영역을 청크 목록으로 바꾸고 필요한 만큼 새로 굽는다.
  void _refreshVisibleChunks() {
    _visibleKeys.clear();

    final view = game.visibleGridBounds(margin: 2);
    final minCx = (view.left / kChunkTiles).floor().clamp(0, map.chunksX - 1);
    final maxCx = (view.right / kChunkTiles).ceil().clamp(0, map.chunksX - 1);
    final minCy = (view.top / kChunkTiles).floor().clamp(0, map.chunksY - 1);
    final maxCy = (view.bottom / kChunkTiles).ceil().clamp(0, map.chunksY - 1);

    var budget = _chunkBudgetPerFrame;
    for (var cy = minCy; cy <= maxCy; cy++) {
      for (var cx = minCx; cx <= maxCx; cx++) {
        final key = cy * map.chunksX + cx;
        var chunk = _cache[key];
        if (chunk == null) {
          if (budget <= 0) continue;
          budget--;
          chunk = _bakeChunk(cx, cy);
          _cache[key] = chunk;
        }
        chunk.lastUsed = _time;
        _visibleKeys.add(key);
      }
    }

    _evictStaleChunks();
  }

  /// 오래 쓰이지 않은 청크부터 캐시에서 버린다.
  void _evictStaleChunks() {
    if (_cache.length <= _maxCachedChunks) return;
    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.lastUsed.compareTo(b.value.lastUsed));
    final excess = _cache.length - _maxCachedChunks;
    for (var i = 0; i < excess; i++) {
      final entry = entries[i];
      if (entry.value.lastUsed == _time) break; // 이번 프레임에 쓰이는 건 남긴다.
      entry.value.dispose();
      _cache.remove(entry.key);
    }
  }

  // ── 청크 래스터화 ────────────────────────────────────────────────────

  /// 타일 하나의 다이아몬드 외곽 경로 좌표.
  static List<Offset> _diamond(int gx, int gy, [double inset = 0]) {
    final x = gx.toDouble();
    final y = gy.toDouble();
    final top = gridToScreen(x + inset, y + inset);
    final right = gridToScreen(x + 1 - inset, y + inset);
    final bottom = gridToScreen(x + 1 - inset, y + 1 - inset);
    final left = gridToScreen(x + inset, y + 1 - inset);
    return [
      top.toOffset(),
      right.toOffset(),
      bottom.toOffset(),
      left.toOffset(),
    ];
  }

  /// 청크가 화면에서 차지하는 사각 영역을 구한다.
  Rect _chunkBounds(int cx, int cy) {
    final x0 = cx * kChunkTiles;
    final y0 = cy * kChunkTiles;
    final x1 = x0 + kChunkTiles;
    final y1 = y0 + kChunkTiles;
    final corners = [
      gridToScreen(x0.toDouble(), y0.toDouble()),
      gridToScreen(x1.toDouble(), y0.toDouble()),
      gridToScreen(x1.toDouble(), y1.toDouble()),
      gridToScreen(x0.toDouble(), y1.toDouble()),
    ];
    var left = corners.first.x;
    var right = corners.first.x;
    var top = corners.first.y;
    var bottom = corners.first.y;
    for (final c in corners) {
      left = math.min(left, c.x);
      right = math.max(right, c.x);
      top = math.min(top, c.y);
      bottom = math.max(bottom, c.y);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  _GroundChunk _bakeChunk(int cx, int cy) {
    final bounds = _chunkBounds(cx, cy);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, bounds.inflate(4));

    final startX = cx * kChunkTiles;
    final startY = cy * kChunkTiles;
    final endX = math.min(startX + kChunkTiles, map.width);
    final endY = math.min(startY + kChunkTiles, map.height);

    // 같은 색끼리 경로를 합쳐 그리기 호출 수를 타입 수준으로 줄인다.
    final plateEven = Path();
    final plateOdd = Path();
    final conduit = Path();
    final stream = Path();
    final hazard = Path();
    var hasHazard = false;

    for (var y = startY; y < endY; y++) {
      for (var x = startX; x < endX; x++) {
        final type = map.tileAt(x, y);
        if (type == TileType.none) continue;
        final poly = _diamond(x, y);
        switch (type) {
          case TileType.floor:
            ((x + y).isEven ? plateEven : plateOdd).addPolygon(poly, true);
          case TileType.circuit:
            conduit.addPolygon(poly, true);
          case TileType.stream:
            stream.addPolygon(poly, true);
          case TileType.hazard:
            hazard.addPolygon(poly, true);
            hasHazard = true;
          case TileType.none:
            break;
        }
      }
    }

    final fill = Paint()..style = PaintingStyle.fill;
    canvas.drawPath(plateEven, fill..color = GamePalette.floorBase);
    canvas.drawPath(plateOdd, fill..color = GamePalette.floorAlt);
    canvas.drawPath(conduit, fill..color = GamePalette.floorCircuit);
    canvas.drawPath(stream, fill..color = GamePalette.floorStream);
    canvas.drawPath(hazard, fill..color = GamePalette.floorHazard);

    _drawTileGrid(canvas, startX, startY, endX, endY);
    _drawConduitTraces(canvas, startX, startY, endX, endY);
    _drawPlatformRim(canvas, startX, startY, endX, endY);

    return _GroundChunk(
      recorder.endRecording(),
      hasHazard ? hazard : null,
      bounds,
    );
  }

  /// 데이터 플레이트의 이음새 격자.
  ///
  /// 칸마다 마름모를 그리는 대신 청크를 가로지르는 대각선 두 벌로 처리한다.
  void _drawTileGrid(Canvas canvas, int startX, int startY, int endX, int endY) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = GamePalette.floorGrid.withValues(alpha: 0.55);

    for (var x = startX; x <= endX; x++) {
      final a = gridToScreen(x.toDouble(), startY.toDouble());
      final b = gridToScreen(x.toDouble(), endY.toDouble());
      canvas.drawLine(a.toOffset(), b.toOffset(), line);
    }
    for (var y = startY; y <= endY; y++) {
      final a = gridToScreen(startX.toDouble(), y.toDouble());
      final b = gridToScreen(endX.toDouble(), y.toDouble());
      canvas.drawLine(a.toOffset(), b.toOffset(), line);
    }
  }

  /// 도관·스트림 위를 흐르는 발광 배선.
  void _drawConduitTraces(
    Canvas canvas,
    int startX,
    int startY,
    int endX,
    int endY,
  ) {
    final conduitTrace = Path();
    final streamTrace = Path();
    final node = Path();

    for (var y = startY; y < endY; y++) {
      for (var x = startX; x < endX; x++) {
        final type = map.tileAt(x, y);
        if (type != TileType.circuit && type != TileType.stream) continue;

        // 배선은 통로가 이어지는 방향을 따라간다.
        final alongX = map.tileAt(x - 1, y) == type ||
            map.tileAt(x + 1, y) == type;
        final alongY = map.tileAt(x, y - 1) == type ||
            map.tileAt(x, y + 1) == type;
        final target = type == TileType.circuit ? conduitTrace : streamTrace;

        if (alongX) {
          final a = gridToScreen(x.toDouble(), y + 0.5);
          final b = gridToScreen(x + 1.0, y + 0.5);
          target
            ..moveTo(a.x, a.y)
            ..lineTo(b.x, b.y);
        }
        if (alongY) {
          final a = gridToScreen(x + 0.5, y.toDouble());
          final b = gridToScreen(x + 0.5, y + 1.0);
          target
            ..moveTo(a.x, a.y)
            ..lineTo(b.x, b.y);
        }
        // 교차점에는 접속 노드를 찍는다.
        if (alongX && alongY && (x + y) % 8 == 0) {
          final c = gridToScreen(x + 0.5, y + 0.5);
          node.addOval(Rect.fromCircle(center: c.toOffset(), radius: 3));
        }
      }
    }

    final trace = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(
      conduitTrace,
      trace..color = GamePalette.floorCircuitGlow.withValues(alpha: 0.55),
    );
    canvas.drawPath(
      streamTrace,
      trace
        ..strokeWidth = 2.6
        ..color = GamePalette.floorStreamGlow.withValues(alpha: 0.5),
    );
    canvas.drawPath(
      node,
      Paint()..color = GamePalette.floorCircuitGlow.withValues(alpha: 0.85),
    );
  }

  /// 데이터 공백과 맞닿은 가장자리에 발광 테두리를 둘러 부유감을 만든다.
  void _drawPlatformRim(
    Canvas canvas,
    int startX,
    int startY,
    int endX,
    int endY,
  ) {
    final rim = Path();
    for (var y = startY; y < endY; y++) {
      for (var x = startX; x < endX; x++) {
        if (map.tileAt(x, y) == TileType.none) continue;
        final poly = _diamond(x, y);
        // 마름모 꼭짓점: 0=북(-x-y), 1=동(+x), 2=남(+x+y), 3=서(+y)
        if (map.tileAt(x, y - 1) == TileType.none) {
          rim
            ..moveTo(poly[0].dx, poly[0].dy)
            ..lineTo(poly[1].dx, poly[1].dy);
        }
        if (map.tileAt(x + 1, y) == TileType.none) {
          rim
            ..moveTo(poly[1].dx, poly[1].dy)
            ..lineTo(poly[2].dx, poly[2].dy);
        }
        if (map.tileAt(x, y + 1) == TileType.none) {
          rim
            ..moveTo(poly[2].dx, poly[2].dy)
            ..lineTo(poly[3].dx, poly[3].dy);
        }
        if (map.tileAt(x - 1, y) == TileType.none) {
          rim
            ..moveTo(poly[3].dx, poly[3].dy)
            ..lineTo(poly[0].dx, poly[0].dy);
        }
      }
    }

    canvas.drawPath(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..color = GamePalette.horizonGlow.withValues(alpha: 0.5)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = GamePalette.floorCircuitGlow.withValues(alpha: 0.9),
    );
  }

  // ── 렌더 ────────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    for (final key in _visibleKeys) {
      final chunk = _cache[key];
      if (chunk != null) canvas.drawPicture(chunk.picture);
    }

    // 방화벽 구역의 맥동 발광.
    final pulse = 0.35 + 0.25 * math.sin(_time * 2.4);
    final glow = Paint()
      ..color = GamePalette.floorHazardGlow.withValues(alpha: pulse * 0.45)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    final rim = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = GamePalette.floorHazardGlow.withValues(alpha: pulse);

    for (final key in _visibleKeys) {
      final path = _cache[key]?.hazardPath;
      if (path == null) continue;
      canvas.drawPath(path, glow);
      canvas.drawPath(path, rim);
    }
  }
}
