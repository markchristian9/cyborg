import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flame/components.dart';

import '../iso.dart';
import 'safe_zone.dart';

/// 데이터 공간 바닥 한 칸의 종류.
enum TileType {
  /// 데이터 공백. 발판이 없어 통행 불가.
  none,

  /// 기본 데이터 플레이트.
  floor,

  /// 에너지 도관이 흐르는 바닥. 대로 역할을 한다.
  circuit,

  /// 방화벽 구역. 밟으면 지속 피해를 입는다.
  hazard,

  /// 고속 데이터 스트림 대역. 시각적 연출 전용.
  stream,
}

/// 바닥 위에 솟은 구조물의 종류.
enum BlockType {
  /// 파괴 불가능한 데이터 타워.
  wall,

  /// 파괴 가능한 데이터 캐시. 부수면 보급품이 나온다.
  crate,
}

/// 맵 위 한 칸을 차지하는 구조물 정보.
class BlockSpec {
  BlockSpec({
    required this.gx,
    required this.gy,
    required this.height,
    required this.type,
  });

  final int gx;
  final int gy;

  /// 그리드 z 단위의 높이(1 = 타일 한 칸 높이).
  final int height;
  final BlockType type;
}

/// 절차적으로 생성된 1 km × 1 km 사이버 스페이스 지형.
///
/// 100만 칸을 객체로 들고 있을 수 없으므로 바닥/구조물은 모두
/// [Uint8List] 평면 배열에 저장하고, 구조물 객체([BlockSpec])는
/// 카메라 근처 청크를 조회할 때만 [blocksInChunk]로 만들어 준다.
class LevelMap {
  LevelMap._({
    required this.width,
    required this.height,
    required Uint8List tiles,
    required Uint8List blockHeights,
    required Uint8List blockKinds,
    required this.spawn,
  })  : _tiles = tiles,
        _blockHeights = blockHeights,
        _blockKinds = blockKinds,
        safeZone = SafeZone.centeredOn(Vector2(width / 2, height / 2));

  final int width;
  final int height;

  /// 월드 한가운데의 안전지대. 적은 이 구역에 들어올 수 없다.
  final SafeZone safeZone;

  /// 월드의 한가운데(그리드 좌표).
  Vector2 get worldCenter => Vector2(width / 2, height / 2);

  /// 안전지대(접속 지점 광장)의 중심. 곧 월드의 한가운데다.
  Vector2 get safeZoneCenter => safeZone.center;

  /// [gx], [gy]가 안전지대 안인지 판정한다.
  ///
  /// [margin]을 주면 그만큼 넓힌 경계로 판정한다. 적의 몸통 반경처럼
  /// 경계에 걸치는 것까지 막고 싶을 때 쓴다.
  bool isInSafeZone(double gx, double gy, {double margin = 0}) =>
      safeZone.overlapsBody(gx, gy, margin);

  /// 안전지대 안에서 접속(재접속) 지점을 하나 고른다.
  ///
  /// 여러 플레이어가 같은 칸에 겹치지 않도록 광장 안에 흩뿌린다.
  Vector2 respawnPoint([math.Random? random]) {
    final rng = random ?? math.Random();
    // 경계에 붙어 스폰하면 곧바로 밖으로 밀려날 수 있어 안쪽만 쓴다.
    final usable = safeZone.halfExtent - 1.5;
    for (var attempt = 0; attempt < 48; attempt++) {
      final x = safeZoneCenter.x + (rng.nextDouble() * 2 - 1) * usable;
      final y = safeZoneCenter.y + (rng.nextDouble() * 2 - 1) * usable;
      if (isWalkableAt(x, y)) return Vector2(x, y);
    }
    return nearestWalkable(safeZoneCenter);
  }

  /// 칸별 [TileType]의 인덱스.
  final Uint8List _tiles;

  /// 칸별 구조물 높이. 0이면 구조물이 없다.
  final Uint8List _blockHeights;

  /// 칸별 [BlockType]의 인덱스.
  final Uint8List _blockKinds;

  /// 플레이어가 시작하는 그리드 좌표.
  final Vector2 spawn;

  /// 격자 한 변의 길이(미터). 통행 불가 테두리를 포함한다.
  double get widthInMeters => tilesToMeters(width.toDouble());

  /// 격자 세로 길이(미터). 통행 불가 테두리를 포함한다.
  double get heightInMeters => tilesToMeters(height.toDouble());

  /// 걸을 수 있는 영역의 첫 칸(포함).
  int get playableMin => kWorldEdgeMarginTiles;

  /// 걸을 수 있는 영역의 마지막 칸 다음(배타적).
  int get playableMaxX => width - kWorldEdgeMarginTiles;

  /// 걸을 수 있는 영역의 마지막 칸 다음(배타적).
  int get playableMaxY => height - kWorldEdgeMarginTiles;

  /// 플레이어가 실제로 걸을 수 있는 가로 길이(미터).
  ///
  /// 이 값이 규격에서 말하는 "월드의 크기"다. 격자 크기([widthInMeters])는
  /// 여기에 허공 테두리를 더한 것이라 조금 더 크다.
  double get playableWidthInMeters =>
      tilesToMeters((playableMaxX - playableMin).toDouble());

  /// 플레이어가 실제로 걸을 수 있는 세로 길이(미터).
  double get playableHeightInMeters =>
      tilesToMeters((playableMaxY - playableMin).toDouble());

  int get chunksX => (width + kChunkTiles - 1) ~/ kChunkTiles;
  int get chunksY => (height + kChunkTiles - 1) ~/ kChunkTiles;

  int _index(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return -1;
    return y * width + x;
  }

  TileType tileAt(int x, int y) {
    final index = _index(x, y);
    return index < 0 ? TileType.none : TileType.values[_tiles[index]];
  }

  /// 해당 칸의 구조물 높이(없으면 0).
  int blockHeightAt(int x, int y) {
    final index = _index(x, y);
    return index < 0 ? 0 : _blockHeights[index];
  }

  /// 해당 칸이 구조물로 막혀 있는지 여부.
  bool isBlocked(int x, int y) {
    final index = _index(x, y);
    if (index < 0) return true;
    return _blockHeights[index] > 0;
  }

  /// 해당 칸을 캐릭터가 지나갈 수 있는지 여부.
  bool isWalkable(int x, int y) {
    final index = _index(x, y);
    if (index < 0) return false;
    if (_blockHeights[index] > 0) return false;
    return _tiles[index] != _tNone;
  }

  /// 실수 좌표 기준으로 통행 가능 여부를 판정한다.
  bool isWalkableAt(double gx, double gy) => isWalkable(gx.floor(), gy.floor());

  /// 데이터 캐시가 파괴되었을 때 통행 가능 상태로 되돌린다.
  void clearBlock(int x, int y) {
    final index = _index(x, y);
    if (index >= 0) _blockHeights[index] = 0;
  }

  /// 청크 (cx, cy) 안에 있는 구조물 목록을 만든다.
  ///
  /// 매 프레임이 아니라 청크가 새로 시야에 들어올 때만 호출한다.
  List<BlockSpec> blocksInChunk(int cx, int cy) {
    final result = <BlockSpec>[];
    final startX = cx * kChunkTiles;
    final startY = cy * kChunkTiles;
    final endX = math.min(startX + kChunkTiles, width);
    final endY = math.min(startY + kChunkTiles, height);
    if (startX >= endX || startY >= endY) return result;

    for (var y = startY; y < endY; y++) {
      final row = y * width;
      for (var x = startX; x < endX; x++) {
        final blockHeight = _blockHeights[row + x];
        if (blockHeight == 0) continue;
        result.add(
          BlockSpec(
            gx: x,
            gy: y,
            height: blockHeight,
            type: BlockType.values[_blockKinds[row + x]],
          ),
        );
      }
    }
    return result;
  }

  /// 지정한 지점에서 가장 가까운 통행 가능한 칸의 중심 좌표를 찾는다.
  Vector2 nearestWalkable(Vector2 from) {
    final startX = from.x.floor();
    final startY = from.y.floor();
    if (isWalkable(startX, startY)) return from.clone();
    for (var radius = 1; radius < 24; radius++) {
      for (var dy = -radius; dy <= radius; dy++) {
        for (var dx = -radius; dx <= radius; dx++) {
          if (dx.abs() != radius && dy.abs() != radius) continue;
          final x = startX + dx;
          final y = startY + dy;
          if (isWalkable(x, y)) {
            return Vector2(x + 0.5, y + 0.5);
          }
        }
      }
    }
    return spawn.clone();
  }

  /// [point]가 [nearestWalkable]의 **실패 반환값**(월드 중앙 스폰)인지 여부.
  ///
  /// `nearestWalkable`은 반경 안에서 걸을 수 있는 칸을 못 찾으면 예외 대신
  /// 스폰 지점을 돌려준다. 그 값을 그대로 이동 목표로 삼으면 허공을 찍었는데
  /// 캐릭터가 안전지대까지 걸어가 버리므로, 호출한 쪽이 실패를 알아볼 수
  /// 있어야 한다.
  bool isWalkableFallback(Vector2 point) =>
      point.distanceToSquared(spawn) < 0.001;

  // TileType 인덱스 캐시. 매 칸 검사에서 enum 조회를 피한다.
  static final int _tNone = TileType.none.index;
  static final int _tFloor = TileType.floor.index;
  static final int _tCircuit = TileType.circuit.index;
  static final int _tHazard = TileType.hazard.index;
  static final int _tStream = TileType.stream.index;

  /// 회로 기판을 닮은 1 km × 1 km 데이터 공간 하나를 생성한다.
  ///
  /// 구조는 세 층으로 쌓인다.
  /// 1. 저주파 노이즈로 데이터 공백(허공)을 뚫어 부유하는 플랫폼을 만든다.
  /// 2. 일정 간격의 도관 대로가 격자로 지나가 어디서든 통행이 이어지게 한다.
  /// 3. 대로가 나눈 구획 안에 데이터 타워 군집과 캐시, 방화벽을 배치한다.
  factory LevelMap.generate({
    int width = kWorldTiles,
    int height = kWorldTiles,
    int? seed,
  }) {
    final random = math.Random(seed ?? 20260804);
    final cells = width * height;
    final tiles = Uint8List(cells)..fillRange(0, cells, _tFloor);
    final blockHeights = Uint8List(cells);
    final blockKinds = Uint8List(cells);

    int index(int x, int y) => y * width + x;

    // ── 1. 데이터 공백 ────────────────────────────────────────────────
    // 저해상도 노이즈를 보간해 100만 칸을 훑는다. 값이 낮은 골짜기가 허공이 된다.
    final voidNoise = _ValueNoise(24, random);
    final edgeNoise = _ValueNoise(72, random);
    // 걸을 수 있는 1 km 바깥을 두르는 허공 테두리. 통행 가능 영역은
    // 이 테두리를 뺀 [kWorldPlayableTiles] × [kWorldPlayableTiles]다.
    const margin = kWorldEdgeMarginTiles;

    for (var y = 0; y < height; y++) {
      final v = y / height;
      final row = y * width;
      for (var x = 0; x < width; x++) {
        if (x < margin || y < margin || x >= width - margin ||
            y >= height - margin) {
          tiles[row + x] = _tNone;
          continue;
        }
        final u = x / width;
        // 큰 덩어리 + 잔결. 잔결이 가장자리를 너덜너덜하게 만든다.
        final n = voidNoise.sample(u * 6, v * 6) * 0.78 +
            edgeNoise.sample(u * 18, v * 18) * 0.22;
        if (n < 0.30) tiles[row + x] = _tNone;
      }
    }

    // ── 2. 도관 대로 격자 ─────────────────────────────────────────────
    // 회로 기판의 배선처럼 일정 간격으로 대로를 깔아 통행을 보장한다.
    const avenueSpacing = 40;
    const avenueHalf = 2; // 대로 폭 = 5칸

    void carveHorizontal(int cy, int halfWidth, int type) {
      for (var dy = -halfWidth; dy <= halfWidth; dy++) {
        final y = cy + dy;
        if (y < margin || y >= height - margin) continue;
        final row = y * width;
        for (var x = margin; x < width - margin; x++) {
          tiles[row + x] = type;
          blockHeights[row + x] = 0;
        }
      }
    }

    void carveVertical(int cx, int halfWidth, int type) {
      for (var dx = -halfWidth; dx <= halfWidth; dx++) {
        final x = cx + dx;
        if (x < margin || x >= width - margin) continue;
        for (var y = margin; y < height - margin; y++) {
          tiles[y * width + x] = type;
          blockHeights[y * width + x] = 0;
        }
      }
    }

    final avenueRows = <int>[];
    final avenueCols = <int>[];
    for (var c = avenueSpacing; c < width - margin; c += avenueSpacing) {
      avenueCols.add(c);
    }
    for (var r = avenueSpacing; r < height - margin; r += avenueSpacing) {
      avenueRows.add(r);
    }

    // 다섯 줄에 하나는 넓은 고속 스트림 대역으로 승격한다.
    for (var i = 0; i < avenueRows.length; i++) {
      final trunk = i % 5 == 2;
      carveHorizontal(
        avenueRows[i],
        trunk ? avenueHalf + 2 : avenueHalf,
        trunk ? _tStream : _tCircuit,
      );
    }
    for (var i = 0; i < avenueCols.length; i++) {
      final trunk = i % 5 == 2;
      carveVertical(
        avenueCols[i],
        trunk ? avenueHalf + 2 : avenueHalf,
        trunk ? _tStream : _tCircuit,
      );
    }

    // ── 3. 구획 내부 ──────────────────────────────────────────────────
    final spawn = Vector2(width / 2, height / 2);
    final spawnX = spawn.x.floor();
    final spawnY = spawn.y.floor();

    bool nearSpawn(int x, int y, [int radius = 10]) =>
        (x - spawnX).abs() <= radius && (y - spawnY).abs() <= radius;

    /// 구획 안에 데이터 타워 하나를 세운다. 속을 비운 껍데기라 엄폐물이 된다.
    void placeTower(int bx, int by, int bw, int bh, int towerHeight) {
      for (var y = by; y < by + bh; y++) {
        if (y < margin || y >= height - margin) continue;
        for (var x = bx; x < bx + bw; x++) {
          if (x < margin || x >= width - margin) continue;
          if (nearSpawn(x, y)) continue;
          final i = index(x, y);
          if (tiles[i] == _tNone) continue;
          if (tiles[i] == _tCircuit || tiles[i] == _tStream) continue;
          final isShell =
              x == bx || y == by || x == bx + bw - 1 || y == by + bh - 1;
          if (!isShell && random.nextDouble() < 0.72) continue;
          blockHeights[i] = towerHeight;
          blockKinds[i] = BlockType.wall.index;
        }
      }
    }

    // 대로가 만든 구획을 하나씩 돌며 타워 군집을 세운다.
    for (var by = 0; by <= avenueRows.length; by++) {
      final top = by == 0 ? margin : avenueRows[by - 1] + avenueHalf + 2;
      final bottom = by == avenueRows.length
          ? height - margin
          : avenueRows[by] - avenueHalf - 2;
      if (bottom - top < 6) continue;

      for (var bxi = 0; bxi <= avenueCols.length; bxi++) {
        final left = bxi == 0 ? margin : avenueCols[bxi - 1] + avenueHalf + 2;
        final right = bxi == avenueCols.length
            ? width - margin
            : avenueCols[bxi] - avenueHalf - 2;
        if (right - left < 6) continue;

        // 중심에서 멀수록 고층 밀집 지구가 된다.
        final dxCenter = ((left + right) / 2 - spawnX) / (width / 2);
        final dyCenter = ((top + bottom) / 2 - spawnY) / (height / 2);
        final rim = math.sqrt(dxCenter * dxCenter + dyCenter * dyCenter);
        final density = 2 + (rim * 3).round() + random.nextInt(2);

        for (var t = 0; t < density; t++) {
          final bw = 3 + random.nextInt(6);
          final bh = 3 + random.nextInt(6);
          if (right - left <= bw + 1 || bottom - top <= bh + 1) continue;
          final bx = left + random.nextInt(right - left - bw);
          final byy = top + random.nextInt(bottom - top - bh);
          final towerHeight = 1 + random.nextInt(2) + (rim * 3).round();
          placeTower(bx, byy, bw, bh, towerHeight.clamp(1, 6));
        }
      }
    }

    // ── 4. 방화벽 구역 ────────────────────────────────────────────────
    final hazardPatches = 320 + random.nextInt(120);
    for (var i = 0; i < hazardPatches; i++) {
      final cx = margin + random.nextInt(width - margin * 2);
      final cy = margin + random.nextInt(height - margin * 2);
      if (nearSpawn(cx, cy, 14)) continue;
      final radius = 2 + random.nextInt(4);
      for (var y = cy - radius; y <= cy + radius; y++) {
        if (y < margin || y >= height - margin) continue;
        for (var x = cx - radius; x <= cx + radius; x++) {
          if (x < margin || x >= width - margin) continue;
          final dx = x - cx;
          final dy = y - cy;
          if (dx * dx + dy * dy > radius * radius) continue;
          final i2 = index(x, y);
          if (blockHeights[i2] > 0) continue;
          if (tiles[i2] == _tNone) continue;
          tiles[i2] = _tHazard;
        }
      }
    }

    // ── 5. 데이터 캐시 ────────────────────────────────────────────────
    var crateBudget = 2600;
    var attempts = 0;
    while (crateBudget > 0 && attempts < 40000) {
      attempts++;
      final x = margin + random.nextInt(width - margin * 2);
      final y = margin + random.nextInt(height - margin * 2);
      final i = index(x, y);
      if (blockHeights[i] != 0) continue;
      if (tiles[i] != _tFloor) continue;
      if (nearSpawn(x, y, 5)) continue;
      blockHeights[i] = 1;
      blockKinds[i] = BlockType.crate.index;
      crateBudget--;
    }

    // ── 6. 안전지대 ───────────────────────────────────────────────────
    // 월드 한가운데 50 m × 50 m는 적이 들어올 수 없는 접속 거점이다.
    // 데이터 공백·구조물·방화벽을 모두 걷어내 항상 온전한 광장으로 남긴다.
    // 경계 바깥 [apron]칸은 완충 구역으로, 출입구가 구조물에 막히지 않게 한다.
    final safeHalf = (metersToTiles(kSafeZoneSizeMeters) / 2).ceil();
    const apron = 2;
    for (var y = spawnY - safeHalf - apron; y <= spawnY + safeHalf + apron; y++) {
      if (y < margin || y >= height - margin) continue;
      for (var x = spawnX - safeHalf - apron; x <= spawnX + safeHalf + apron; x++) {
        if (x < margin || x >= width - margin) continue;
        final i = index(x, y);
        blockHeights[i] = 0;

        final inside =
            (x - spawnX).abs() <= safeHalf && (y - spawnY).abs() <= safeHalf;
        if (!inside) {
          // 완충 구역은 통행만 보장하고 방화벽만 걷어낸다.
          if (tiles[i] == _tNone || tiles[i] == _tHazard) tiles[i] = _tFloor;
          continue;
        }

        final dx = x - spawnX;
        final dy = y - spawnY;
        tiles[i] = dx * dx + dy * dy <= 81 ? _tCircuit : _tFloor;
      }
    }

    return LevelMap._(
      width: width,
      height: height,
      tiles: tiles,
      blockHeights: blockHeights,
      blockKinds: blockKinds,
      spawn: spawn,
    );
  }
}

/// 격자 값에 스무스스텝 보간을 적용한 간단한 value noise.
///
/// 100만 칸마다 난수를 뽑는 대신 저해상도 격자를 보간해 지형 덩어리를 만든다.
class _ValueNoise {
  _ValueNoise(this.size, math.Random random) : _values = Float32List(size * size) {
    for (var i = 0; i < _values.length; i++) {
      _values[i] = random.nextDouble();
    }
  }

  final int size;
  final Float32List _values;

  double _at(int gx, int gy) {
    final x = gx % size;
    final y = gy % size;
    return _values[(y < 0 ? y + size : y) * size + (x < 0 ? x + size : x)];
  }

  /// [u], [v]는 격자 칸 단위의 실수 좌표이며 경계에서 순환한다.
  double sample(double u, double v) {
    final x0 = u.floor();
    final y0 = v.floor();
    final fx = u - x0;
    final fy = v - y0;
    final sx = fx * fx * (3 - 2 * fx);
    final sy = fy * fy * (3 - 2 * fy);

    final a = _at(x0, y0);
    final b = _at(x0 + 1, y0);
    final c = _at(x0, y0 + 1);
    final d = _at(x0 + 1, y0 + 1);

    final top = a + (b - a) * sx;
    final bottom = c + (d - c) * sx;
    return top + (bottom - top) * sy;
  }
}
