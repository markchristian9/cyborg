import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import '../action_rpg_game.dart';
import '../net/leaderboard_source.dart';
import '../palette.dart';
import '../systems/level_system.dart';

/// 월드 전체의 레벨 순위를 보여주는 화면.
///
/// 캐릭터 화면·인벤토리와 같은 방식으로 항상 붙어 있고 [isOpen] 으로만 열고
/// 닫는다. 월드는 모두가 공유하는 실시간 공간이므로 이 패널이 떠 있어도 게임은
/// 멈추지 않는다.
///
/// 순위는 [LeaderboardSource] 가 준다. 서버가 없으면 그 사실을 화면에 적을 뿐
/// 게임은 그대로 굴러간다.
class LeaderboardScreen extends PositionComponent
    with TapCallbacks, DragCallbacks, HasGameReference<ActionRpgGame> {
  LeaderboardScreen({required this.source}) : super(priority: 141);

  final LeaderboardSource source;

  /// 기준 해상도에서의 패널 크기. 화면이 좁으면 통째로 축소한다.
  static const double panelWidth = 460;
  static const double panelHeight = 520;

  /// 목록 한 줄의 높이.
  static const double rowHeight = 42;

  /// 목록이 그려지는 영역.
  static const Rect _listRect = Rect.fromLTWH(
    16,
    108,
    panelWidth - 32,
    panelHeight - 108 - 78,
  );

  /// 내 순위를 붙박이로 보여주는 띠.
  static const Rect _myRankRect = Rect.fromLTWH(
    16,
    panelHeight - 68,
    panelWidth - 32,
    52,
  );

  static const Rect _closeRect = Rect.fromLTWH(panelWidth - 46, 14, 32, 32);

  bool _open = false;
  double _anim = 0;

  /// 화면에 그릴 순위표. [LeaderboardSource.changes] 가 울릴 때만 다시 만든다.
  ///
  /// 매 프레임 만들면 100 줄짜리 리스트를 초당 60번 정렬하게 된다.
  List<LeaderboardRow> _rows = const [];
  LeaderboardRow? _myRank;

  /// 목록을 위로 밀어 올린 양(픽셀).
  double _scroll = 0;

  /// 순위표가 아직 한 번도 도착하지 않았는지.
  ///
  /// "아무도 없다" 와 "아직 안 왔다" 는 다른 상태이고, 사용자에게도 다르게
  /// 보여야 한다.
  bool _loading = false;

  /// 순위표를 받아오지 못했는지. 서버가 응답하지 않거나 구독이 거절된 경우다.
  bool _failed = false;

  /// 열고 닫을 때마다 오르는 번호. 늦게 도착한 [LeaderboardSource.attach] 완료가
  /// 이미 닫힌 화면의 상태를 되돌리지 못하게 막는다.
  int _generation = 0;

  /// 구독이 이 시간 안에 자리 잡지 않으면 실패로 본다.
  static const Duration _attachTimeout = Duration(seconds: 8);

  bool get isOpen => _open;

  final TextPaint _title = TextPaint(
    style: const TextStyle(
      color: GamePalette.hudBorder,
      fontSize: 15,
      fontWeight: FontWeight.w900,
      letterSpacing: 2,
    ),
  );
  final TextPaint _column = TextPaint(
    style: const TextStyle(
      color: GamePalette.textDim,
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.6,
    ),
  );
  final TextPaint _name = TextPaint(
    style: const TextStyle(
      color: GamePalette.textPrimary,
      fontSize: 15,
      fontWeight: FontWeight.w800,
    ),
  );
  final TextPaint _nameMine = TextPaint(
    style: const TextStyle(
      color: GamePalette.hudBorder,
      fontSize: 15,
      fontWeight: FontWeight.w900,
    ),
  );
  final TextPaint _rankNumber = TextPaint(
    style: const TextStyle(
      color: GamePalette.textPrimary,
      fontSize: 15,
      fontWeight: FontWeight.w900,
    ),
  );
  final TextPaint _level = TextPaint(
    style: const TextStyle(
      color: GamePalette.textPrimary,
      fontSize: 19,
      fontWeight: FontWeight.w900,
    ),
  );
  final TextPaint _hint = TextPaint(
    style: const TextStyle(
      color: GamePalette.textDim,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
    ),
  );

  // ── 열기 / 닫기 ─────────────────────────────────────────────────────

  /// 화면을 열고 순위표를 받기 시작한다.
  void open() {
    if (_open) return;
    _open = true;
    _scroll = 0;
    _failed = false;
    _loading = source.isAvailable && _rows.isEmpty;
    _pull();

    final generation = ++_generation;
    // 첫 행이 오면 [_onChanged] 가 풀어 주지만, 순위표가 비어 있으면 알림이
    // 아예 오지 않는다. 구독이 자리 잡는 것 자체를 완료 신호로 삼아야 "불러오는
    // 중" 이 영원히 남지 않는다.
    source.attach().timeout(_attachTimeout).then(
      (_) {
        if (generation != _generation) return;
        _loading = false;
      },
      onError: (_) {
        if (generation != _generation) return;
        _loading = false;
        _failed = true;
      },
    );
  }

  /// 화면을 닫고 순위표 구독을 푼다.
  void close() {
    if (!_open) return;
    _open = false;
    _loading = false;
    // 번호를 올려 아직 오지 않은 attach 완료가 상태를 되돌리지 못하게 한다.
    _generation++;
    source.detach();
  }

  void toggle() => _open ? close() : open();

  @override
  void onMount() {
    super.onMount();
    source.changes.addListener(_onChanged);
  }

  @override
  void onRemove() {
    source.changes.removeListener(_onChanged);
    // 열려 있지 않아도 푼다. 구독이 걸리는 도중에 닫혔다면 `_open` 은 false 인데
    // 구독은 살아 있을 수 있다.
    _generation++;
    source.detach();
    super.onRemove();
  }

  void _onChanged() {
    _loading = false;
    _failed = false;
    _pull();
  }

  /// 공급자가 가진 최신 순위를 받아 온다.
  void _pull() {
    _rows = source.rows;
    _myRank = source.myRank;
    _clampScroll();
  }

  // ── 좌표 변환 ───────────────────────────────────────────────────────

  @override
  void onGameResize(Vector2 newSize) {
    super.onGameResize(newSize);
    size = newSize;
  }

  /// 화면에 맞춘 패널 축소 비율. 작은 화면에서는 통째로 줄여 넣는다.
  double get _scale => math.min(
    1.0,
    math.min((size.x - 32) / panelWidth, (size.y - 32) / panelHeight),
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

  // ── 입력 ────────────────────────────────────────────────────────────

  @override
  bool containsLocalPoint(Vector2 point) => _open;

  @override
  void onTapDown(TapDownEvent event) {
    if (!_open) return;
    // 화면 전체를 덮으므로 탭이 조이스틱이나 액션 버튼까지 새지 않게 한다.
    event.handled = true;

    final local = _toPanel(event.localPosition);
    const panel = Rect.fromLTWH(0, 0, panelWidth, panelHeight);
    if (_closeRect.contains(local) || !panel.contains(local)) close();
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    if (!_open) return;
    // 목록이 화면보다 길 때만 밀린다. 배율을 반영해야 손가락과 목록이 같이 움직인다.
    _scroll -= event.localDelta.y / _scale;
    _clampScroll();
  }

  double get _contentHeight => _rows.length * rowHeight;

  double get _maxScroll => math.max(0, _contentHeight - _listRect.height);

  void _clampScroll() => _scroll = _scroll.clamp(0.0, _maxScroll);

  // ── 갱신 ────────────────────────────────────────────────────────────

  @override
  void update(double dt) {
    final target = _open ? 1.0 : 0.0;
    _anim += (target - _anim) * math.min(1, dt * 14);
    if ((_anim - target).abs() < 0.005) _anim = target;
  }

  // ── 렌더링 ──────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    if (_anim <= 0.004) return;
    final t = _anim.clamp(0.0, 1.0);

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

    if (!source.isAvailable) {
      _renderNotice(canvas, '서버에 연결되지 않아 순위를 볼 수 없다');
      return;
    }
    if (_loading) {
      _renderNotice(canvas, '순위를 불러오는 중');
      return;
    }
    if (_failed && _rows.isEmpty) {
      _renderNotice(canvas, '순위를 받아오지 못했다 · 창을 닫았다 다시 열어라');
      return;
    }
    if (_rows.isEmpty) {
      _renderNotice(canvas, '아직 순위에 오른 요원이 없다');
      return;
    }

    _renderList(canvas);
    _renderMyRank(canvas);
  }

  void _renderHeader(Canvas canvas) {
    _title.render(
      canvas,
      'LEADERBOARD',
      Vector2(24, 30),
      anchor: Anchor.centerLeft,
    );
    _hint.render(
      canvas,
      '레벨 순위',
      Vector2(154, 31),
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

    // 열 이름.
    _column.render(canvas, 'RANK', Vector2(30, 84));
    _column.render(canvas, 'OPERATIVE', Vector2(84, 84));
    _column.render(
      canvas,
      'LEVEL',
      Vector2(panelWidth - 30, 84),
      anchor: Anchor.topRight,
    );
  }

  /// 목록 대신 한 줄 안내를 보여준다.
  void _renderNotice(Canvas canvas, String message) {
    _hint.render(
      canvas,
      message,
      Vector2(panelWidth / 2, panelHeight / 2),
      anchor: Anchor.center,
    );
  }

  void _renderList(Canvas canvas) {
    canvas.save();
    canvas.clipRRect(
      RRect.fromRectAndRadius(_listRect, const Radius.circular(10)),
    );
    canvas.translate(0, -_scroll);

    // 보이는 줄만 그린다. 100 줄이라도 그리는 것은 여남은 줄이다.
    final first = math.max(0, (_scroll / rowHeight).floor());
    final last = math.min(
      _rows.length,
      ((_scroll + _listRect.height) / rowHeight).ceil() + 1,
    );

    for (var i = first; i < last; i++) {
      _renderRow(
        canvas,
        _rows[i],
        Rect.fromLTWH(
          _listRect.left,
          _listRect.top + i * rowHeight,
          _listRect.width,
          rowHeight,
        ),
      );
    }

    canvas.restore();

    if (_maxScroll > 0) _renderScrollbar(canvas);
  }

  void _renderRow(Canvas canvas, LeaderboardRow row, Rect rect) {
    final inner = rect.deflate(2);

    if (row.isMine) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(inner, const Radius.circular(8)),
        Paint()..color = GamePalette.hudBorder.withValues(alpha: 0.14),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(inner, const Radius.circular(8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = GamePalette.hudBorder.withValues(alpha: 0.55),
      );
    } else if (row.rank.isEven) {
      // 줄이 길어지면 눈이 행을 놓친다. 한 줄 걸러 옅게 깔아 준다.
      canvas.drawRRect(
        RRect.fromRectAndRadius(inner, const Radius.circular(8)),
        Paint()..color = GamePalette.hudInset.withValues(alpha: 0.5),
      );
    }

    _renderRankBadge(canvas, row.rank, Offset(rect.left + 24, rect.center.dy));

    (row.isMine ? _nameMine : _name).render(
      canvas,
      row.name,
      Vector2(rect.left + 52, rect.center.dy),
      anchor: Anchor.centerLeft,
    );
    _renderKindDot(
      canvas,
      row.kind,
      Offset(rect.right - 108, rect.center.dy),
    );

    _level.render(
      canvas,
      '${row.level}',
      Vector2(rect.right - 14, rect.center.dy),
      anchor: Anchor.centerRight,
    );
    // 같은 레벨끼리는 경험치가 순위를 가른다. 얼마나 앞섰는지 얇게 표시한다.
    _renderXpTick(canvas, row, rect);
  }

  /// 1~3 위는 색으로 구별한다. 그 아래는 숫자만 둔다.
  void _renderRankBadge(Canvas canvas, int rank, Offset center) {
    final medal = switch (rank) {
      1 => const Color(0xFFE0B658),
      2 => const Color(0xFF9FB4C4),
      3 => const Color(0xFFCE8B5C),
      _ => null,
    };

    if (medal != null) {
      canvas.drawCircle(center, 13, Paint()..color = medal.withValues(alpha: 0.22));
      canvas.drawCircle(
        center,
        13,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = medal,
      );
    }

    _rankNumber.render(
      canvas,
      '$rank',
      Vector2(center.dx, center.dy),
      anchor: Anchor.center,
    );
  }

  /// 남성형·여성형을 작은 점 색으로 구별한다.
  void _renderKindDot(Canvas canvas, String kind, Offset center) {
    final color = kind == 'female_cyborg'
        ? GamePalette.robotEnergy
        : GamePalette.playerAccent;
    canvas.drawCircle(center, 4, Paint()..color = color.withValues(alpha: 0.85));
  }

  /// 현재 레벨 안에서 얼마나 나아갔는지를 오른쪽 끝에 얇은 막대로 둔다.
  ///
  /// 분모는 그 레벨의 실제 요구 경험치([LevelSystem.xpToNext])다. 예전에는
  /// 목록 안 같은 레벨의 최댓값을 기준으로 삼았는데, 목록은 상위 100 명뿐이라
  /// 내 레벨 그룹이 목록에 없으면 분모가 1 이 되어 **막대가 늘 가득 찼다** —
  /// 순위는 바닥인데 진행도는 최대치로 보이는, 정확히 거꾸로 된 표시였다.
  void _renderXpTick(Canvas canvas, LeaderboardRow row, Rect rect) {
    final track = Rect.fromLTWH(rect.right - 96, rect.center.dy - 2, 56, 4);

    // 만렙이 없으므로 언제나 "다음 레벨까지" 가 있다.
    final ratio = (row.xp / LevelSystem.xpToNext(row.level)).clamp(0.0, 1.0);

    canvas.drawRRect(
      RRect.fromRectAndRadius(track, const Radius.circular(2)),
      Paint()..color = GamePalette.hudInset,
    );
    if (ratio > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(track.left, track.top, track.width * ratio, track.height),
          const Radius.circular(2),
        ),
        Paint()..color = GamePalette.xpFill.withValues(alpha: 0.8),
      );
    }
  }

  void _renderScrollbar(Canvas canvas) {
    final trackHeight = _listRect.height;
    final thumbHeight = math.max(
      28.0,
      trackHeight * (trackHeight / _contentHeight),
    );
    final travel = trackHeight - thumbHeight;
    final top = _listRect.top + travel * (_scroll / _maxScroll);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(_listRect.right - 3, top, 3, thumbHeight),
        const Radius.circular(2),
      ),
      Paint()..color = GamePalette.hudBorder.withValues(alpha: 0.35),
    );
  }

  /// 목록 아래에 내 순위를 붙박이로 둔다.
  ///
  /// 상위권 밖이면 목록을 아무리 내려도 내 줄이 나오지 않는다. 자기 순위는
  /// 리더보드를 여는 가장 큰 이유이므로 항상 보이는 자리에 따로 둔다.
  void _renderMyRank(Canvas canvas) {
    canvas.drawLine(
      Offset(_myRankRect.left, _myRankRect.top - 8),
      Offset(_myRankRect.right, _myRankRect.top - 8),
      Paint()
        ..strokeWidth = 1
        ..color = GamePalette.hudBorder.withValues(alpha: 0.2),
    );

    final mine = _myRank;
    if (mine == null) {
      _hint.render(
        canvas,
        '캐릭터를 골라야 순위에 오른다',
        Vector2(panelWidth / 2, _myRankRect.center.dy),
        anchor: Anchor.center,
      );
      return;
    }

    canvas.drawRRect(
      RRect.fromRectAndRadius(_myRankRect, const Radius.circular(10)),
      Paint()..color = GamePalette.hudBorder.withValues(alpha: 0.12),
    );
    _column.render(
      canvas,
      'YOU',
      Vector2(_myRankRect.left + 14, _myRankRect.top + 10),
    );
    _renderRow(
      canvas,
      mine,
      Rect.fromLTWH(
        _myRankRect.left + 34,
        _myRankRect.top + 5,
        _myRankRect.width - 34,
        rowHeight,
      ),
    );
  }
}
