import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import '../action_rpg_game.dart';
import '../net/party_session.dart';
import '../palette.dart';

/// 파티 패널에 그릴 한 줄.
///
/// 파티가 있으면 파티원, 없으면 초대할 만한 근처 요원이다. 두 경우가 같은 모양의
/// 줄이라 한 타입으로 다룬다 — 화면에서 하는 일이 "사람 하나를 보여 주고 누르게
/// 하는 것" 으로 같기 때문이다.
class _Row {
  const _Row({
    required this.characterId,
    required this.name,
    required this.level,
    required this.isLeader,
    required this.isFollowing,
    required this.isSelf,
    this.isHuntLead = false,
    this.hpRatio,
  });

  final int characterId;
  final String name;
  final int level;
  final bool isLeader;
  final bool isFollowing;
  final bool isSelf;

  /// 이 사람이 지금 사냥을 이끌고 있는가. 파티장 여부와는 별개다.
  final bool isHuntLead;

  /// 체력 비율. 월드에서 보이지 않는 파티원은 알 수 없어 null 이다.
  final double? hpRatio;
}

/// 파티를 보고 다루는 화면.
///
/// 파티가 없을 때는 **근처 요원 목록**이 되어 초대의 진입점 노릇을 한다. 원격
/// 요원을 직접 눌러 초대하는 길이 이 게임에는 아직 없기 때문이다(탭은 땅으로만
/// 간다). 목록에서 고르게 하면 그 길을 새로 뚫지 않아도 파티를 맺을 수 있다.
///
/// `camera.viewport` 에 붙는 HUD 라 카메라가 움직여도 자리를 지킨다.
class PartyPanel extends PositionComponent
    with TapCallbacks, HasGameReference<ActionRpgGame> {
  PartyPanel({int priority = 135})
      : super(anchor: Anchor.topLeft, priority: priority, size: Vector2(276, 0));

  /// 패널 너비.
  static const double panelWidth = 276;

  /// 한 줄의 높이.
  static const double rowHeight = 38;

  /// 안쪽 여백.
  static const double padding = 10;

  /// 제목 줄의 높이.
  static const double headerHeight = 30;

  /// 아래쪽 버튼 줄의 높이.
  static const double footerHeight = 40;

  /// 파티원 아래에 이어 붙일 초대 후보의 최대 줄 수.
  ///
  /// 파티원 목록을 밀어내지 않을 만큼만 보여 준다. 더 부르려면 "주변 모두
  /// 부르기" 가 있다.
  static const int maxInviteRows = 4;

  /// 목록에 한 번에 보여 줄 최대 줄 수.
  ///
  /// 정원은 12 명이지만 화면을 다 덮으면 사냥을 볼 수 없다. 넘치는 만큼은
  /// "+N" 으로 접는다.
  static const int maxVisibleRows = 8;

  /// 초대 후보로 보여 줄 최대 거리(타일).
  ///
  /// 월드 전체의 접속자가 목록에 쏟아지면 고를 수가 없다. 눈에 보이는 범위에
  /// 있는 사람만 후보로 둔다.
  static const double inviteRangeTiles = 40;

  bool _open = false;
  bool get isOpen => _open;

  /// 눌린 줄. 없으면 -1.
  int _pressedRow = -1;

  /// 눌린 아래쪽 버튼. 0=추종, 1=나가기. 없으면 -1.
  int _pressedButton = -1;

  /// 닫기 버튼을 누르고 있는가.
  bool _pressedClose = false;

  /// "주변 모두 부르기" 를 누르고 있는가.
  bool _pressedInviteAll = false;

  final TextPaint _title = TextPaint(
    style: const TextStyle(
      color: GamePalette.textPrimary,
      fontSize: 14,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.4,
    ),
  );
  final TextPaint _label = TextPaint(
    style: const TextStyle(
      color: GamePalette.textPrimary,
      fontSize: 13,
      fontWeight: FontWeight.w700,
    ),
  );
  final TextPaint _muted = TextPaint(
    style: TextStyle(
      color: GamePalette.textPrimary.withValues(alpha: 0.55),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    ),
  );

  void open() {
    _open = true;
    _resize();
  }

  void close() {
    _open = false;
    _pressedRow = -1;
    _pressedButton = -1;
    _pressedClose = false;
    _pressedInviteAll = false;
    size.y = 0;
  }

  void toggle() => _open ? close() : open();

  // ── 데이터 ──────────────────────────────────────────────────────────

  PartySession get _party => game.party;

  /// 파티가 있으면 파티원, 없으면 초대할 만한 근처 요원.
  List<_Row> get _rows {
    final party = _party;
    if (party.inParty) return _memberRows(party);
    return _nearbyRows();
  }

  /// 파티원 아래에 이어 붙일 초대 후보.
  ///
  /// 파티가 없을 때는 [_rows] 자체가 후보 목록이므로 여기서는 비운다. 파티가
  /// 있을 때만 "누구를 더 부를까" 라는 물음이 따로 생긴다.
  ///
  /// 이미 파티에 있는 사람은 뺀다 — 부를 수 없는 사람을 목록에 두면 누를 때마다
  /// 거절만 돌아온다.
  List<_Row> get _inviteCandidates {
    final party = _party;
    if (!party.inParty || party.isFull) return const [];

    final mine = {for (final m in party.members) m.characterId};
    return _nearbyRows().where((r) => !mine.contains(r.characterId)).toList();
  }

  List<_Row> _memberRows(PartySession party) {
    final others = {
      for (final other in game.presence.others) other.characterId: other,
    };
    final self = party.selfCharacterId;

    final rows = <_Row>[];
    for (final member in party.members) {
      final isSelf = member.characterId == self;
      final other = others[member.characterId];

      // 이름과 레벨은 월드에서 온다. 파티 목록에 그것까지 실었다면 누가 한 걸음
      // 옮길 때마다 목록 전체가 다시 밀려왔을 것이다.
      // 본인 이름은 굳이 찾지 않는다. 목록에서 자기를 알아보는 데 이름은 필요
      // 없고, 캐릭터 이름을 게임 쪽에서 꺼내려면 없는 경로를 새로 뚫어야 한다.
      rows.add(_Row(
        characterId: member.characterId,
        name: isSelf ? '나' : (other?.name ?? '접속 중이 아님'),
        level: isSelf ? game.player.level : (other?.level ?? 0),
        isLeader: member.isLeader,
        isFollowing: member.isFollowing,
        isSelf: isSelf,
        isHuntLead: member.characterId == party.huntLeadCharacterId,
        hpRatio: isSelf
            ? (game.player.maxHp <= 0
                ? null
                : (game.player.hp / game.player.maxHp).clamp(0.0, 1.0))
            : (other == null || other.maxHp <= 0
                ? null
                : (other.hp / other.maxHp).clamp(0.0, 1.0)),
      ));
    }

    // 파티장을 맨 위에, 나머지는 이름 순. 매번 순서가 달라지면 누르려던 줄이
    // 손가락 아래에서 바뀐다.
    rows.sort((a, b) {
      if (a.isLeader != b.isLeader) return a.isLeader ? -1 : 1;
      return a.name.compareTo(b.name);
    });
    return rows;
  }

  List<_Row> _nearbyRows() {
    final me = game.player.grid;
    final rows = <_Row>[];
    for (final other in game.presence.others) {
      if ((other.grid - me).length > inviteRangeTiles) continue;
      rows.add(_Row(
        characterId: other.characterId,
        name: other.name,
        level: other.level,
        isLeader: false,
        isFollowing: false,
        isSelf: false,
        hpRatio: other.maxHp <= 0
            ? null
            : (other.hp / other.maxHp).clamp(0.0, 1.0),
      ));
    }
    rows.sort((a, b) => a.name.compareTo(b.name));
    return rows;
  }

  bool get _showsFooter => _party.inParty;

  void _resize() {
    final count = _rows.length.clamp(0, maxVisibleRows);
    final overflow = _rows.length > maxVisibleRows ? 16.0 : 0.0;
    final invites = _inviteCandidates.length.clamp(0, maxInviteRows);
    // 초대 구역은 안내 한 줄(18)을 머리에 두고 시작한다.
    final inviteHeight = invites == 0 ? 0.0 : 18 + rowHeight * invites;
    size.y = headerHeight +
        padding * 2 +
        rowHeight * count +
        overflow +
        inviteHeight +
        (_showsFooter ? footerHeight : 0) +
        (count == 0 ? 24 : 0);
  }

  @override
  void update(double dt) {
    super.update(dt);
    // 파티원이 들고 나면 패널 높이가 달라진다. 눌리는 자리와 그려지는 자리가
    // 어긋나지 않도록 매 프레임 맞춘다.
    if (_open) _resize();
  }

  // ── 렌더링 ──────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    if (!_open) return;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, panelWidth, size.y),
      const Radius.circular(12),
    );
    canvas.drawRRect(rect, Paint()..color = GamePalette.hudBackground);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = GamePalette.hudBorder.withValues(alpha: 0.55),
    );

    final party = _party;
    final rows = _rows;

    _title.render(
      canvas,
      party.inParty ? '파티 ${party.members.length}/$kMaxPartySize' : '근처 요원',
      Vector2(padding, 9),
    );

    if (_showsInviteAll) {
      final rect = _inviteAllRect;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(7)),
        Paint()
          ..color = _pressedInviteAll
              ? GamePalette.hudBorder.withValues(alpha: 0.3)
              : GamePalette.hudBorder.withValues(alpha: 0.16),
      );
      _muted.render(
        canvas,
        '주변 모두 부르기',
        Vector2(rect.center.dx, rect.center.dy),
        anchor: Anchor.center,
      );
    }

    _renderCloseButton(canvas);

    var y = headerHeight + padding;

    if (rows.isEmpty) {
      _muted.render(
        canvas,
        party.inParty ? '파티원이 없다' : '근처에 다른 요원이 없다',
        Vector2(padding, y + 4),
      );
      return;
    }

    final visible = rows.take(maxVisibleRows).toList();
    for (var i = 0; i < visible.length; i++) {
      _renderRow(canvas, visible[i], y, pressed: _pressedRow == i);
      y += rowHeight;
    }

    if (rows.length > visible.length) {
      _muted.render(
        canvas,
        '+${rows.length - visible.length}명 더',
        Vector2(padding, y),
      );
      y += 16;
    }

    // 파티 중이라면 그 아래에 "더 부를 수 있는 사람" 을 잇는다. 파티가 찼거나
    // 주변에 아무도 없으면 구역 자체가 나타나지 않는다.
    final candidates = _inviteCandidates;
    if (candidates.isNotEmpty) {
      _muted.render(canvas, '주변 요원 — 눌러서 초대', Vector2(padding, y + 2));
      y += 18;
      for (var i = 0; i < candidates.length && i < maxInviteRows; i++) {
        _renderRow(
          canvas,
          candidates[i],
          y,
          pressed: _pressedRow == visible.length + i,
        );
        y += rowHeight;
      }
    }

    if (_showsFooter) _renderFooter(canvas, y);
  }

  /// 제목 줄 오른쪽의 닫기(×) 버튼.
  ///
  /// 이 패널은 월드 메뉴로 열지만 **거기로 다시 가서 닫으라고 하면 닫는 길이
  /// 있다는 것을 알 수 없다.** 열린 창에는 닫는 자리가 보여야 한다.
  void _renderCloseButton(Canvas canvas) {
    final rect = _closeRect;
    if (_pressedClose) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(7)),
        Paint()..color = GamePalette.hudBorder.withValues(alpha: 0.2),
      );
    }

    final center = rect.center;
    final paint = Paint()
      ..color = GamePalette.textPrimary.withValues(alpha: 0.6)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    const arm = 5.0;
    canvas.drawLine(
      center + const Offset(-arm, -arm),
      center + const Offset(arm, arm),
      paint,
    );
    canvas.drawLine(
      center + const Offset(arm, -arm),
      center + const Offset(-arm, arm),
      paint,
    );
  }

  /// 닫기 버튼의 자리. 손가락으로 누를 수 있도록 그리는 ×보다 넉넉하다.
  Rect get _closeRect =>
      Rect.fromLTWH(panelWidth - padding - 26, 4, 26, headerHeight - 6);

  /// 한 번에 부르기는 자리가 남아 있으면 **누구에게나** 보여 준다.
  ///
  /// 파티장만 부를 수 있게 하면 아는 사람을 만났을 때 파티장을 찾아 부탁해야
  /// 하고, 그러느니 대개 그냥 지나간다. 파티장이 쥐는 것은 내보내는 일이지
  /// 불러들이는 일이 아니다.
  bool get _showsInviteAll => !_party.inParty || !_party.isFull;

  Rect get _inviteAllRect =>
      Rect.fromLTWH(panelWidth - padding - 26 - 108, 5, 104, headerHeight - 8);

  void _renderRow(Canvas canvas, _Row row, double y, {required bool pressed}) {
    if (pressed) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(padding * 0.5, y, panelWidth - padding, rowHeight - 4),
          const Radius.circular(8),
        ),
        Paint()..color = GamePalette.hudBorder.withValues(alpha: 0.16),
      );
    }

    var x = padding;

    // 파티장 표식. 글자로 두는 이유는 이 프로젝트에 아이콘 자산이 없어서다.
    if (row.isLeader) {
      _label.render(canvas, '★', Vector2(x, y + 8));
      x += 16;
    }

    _label.render(canvas, row.name, Vector2(x, y + 6));

    _muted.render(
      canvas,
      row.level > 0 ? 'Lv.${row.level}' : '—',
      Vector2(panelWidth - padding, y + 8),
      anchor: Anchor.topRight,
    );

    // 지금 무엇을 하고 있는지 한 줄 아래에 작게 표시한다. 파티장 표식(★)과
    // 따로 두는 이유는 축이 다르기 때문이다 — 파티장이 남을 따라갈 수도 있다.
    if (row.isHuntLead) {
      _muted.render(canvas, '이끄는 중', Vector2(x, y + 21));
    } else if (row.isFollowing) {
      _muted.render(canvas, '추종 중', Vector2(x, y + 21));
    }

    final ratio = row.hpRatio;
    if (ratio != null) {
      const barWidth = 64.0;
      final barX = panelWidth - padding - barWidth;
      final barY = y + 24;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barX, barY, barWidth, 4),
          const Radius.circular(2),
        ),
        Paint()..color = GamePalette.textPrimary.withValues(alpha: 0.12),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barX, barY, barWidth * ratio, 4),
          const Radius.circular(2),
        ),
        Paint()
          ..color = ratio > 0.3 ? GamePalette.hpFill : GamePalette.hpFillLow,
      );
    }
  }

  void _renderFooter(Canvas canvas, double y) {
    final party = _party;
    final buttons = _footerLabels(party);

    final width = (panelWidth - padding * 2 - 8) / 2;
    for (var i = 0; i < 2; i++) {
      final rect = Rect.fromLTWH(
        padding + i * (width + 8),
        y,
        width,
        footerHeight - 10,
      );
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));

      canvas.drawRRect(
        rrect,
        Paint()
          ..color = _pressedButton == i
              ? GamePalette.hudBorder.withValues(alpha: 0.28)
              : GamePalette.hudBorder.withValues(alpha: 0.12),
      );
      _label.render(
        canvas,
        buttons[i],
        Vector2(rect.center.dx, rect.center.dy),
        anchor: Anchor.center,
      );
    }
  }

  /// 아래쪽 두 버튼의 이름.
  ///
  /// 파티장에게는 추종 버튼이 의미가 없다(자기를 따라갈 수 없다). 대신 해산을 준다.
  /// 아래쪽 두 버튼의 이름.
  ///
  /// 왼쪽은 **사냥을 이끄는 일**, 오른쪽은 **파티를 떠나는 일**이다. 둘은 다른
  /// 축이라 — 파티장이면서 남을 따라갈 수도, 파티장이 아니면서 이끌 수도 있다 —
  /// 한 버튼에 섞지 않는다.
  List<String> _footerLabels(PartySession party) {
    final right = party.isLeader ? '해산' : '나가기';
    if (game.isFollowingLeader) return ['추종 중단', right];
    if (party.isHuntLeading) return ['이끌기 중지', right];
    if (party.hasHuntLead) return ['추종', right];
    return ['파티 이끌기', right];
  }

  // ── 입력 ────────────────────────────────────────────────────────────

  @override
  bool containsLocalPoint(Vector2 point) =>
      _open && super.containsLocalPoint(point);

  @override
  void onTapDown(TapDownEvent event) {
    if (!_open) return;
    final local = event.localPosition;

    if (_closeRect.contains(Offset(local.x, local.y))) {
      _pressedClose = true;
      return;
    }

    if (_showsInviteAll && _inviteAllRect.contains(Offset(local.x, local.y))) {
      _pressedInviteAll = true;
      return;
    }

    final listTop = headerHeight + padding;
    final rows = _rows.take(maxVisibleRows).toList();
    final listBottom = listTop + rowHeight * rows.length;

    if (local.y >= listTop && local.y < listBottom) {
      _pressedRow = ((local.y - listTop) / rowHeight).floor();
      return;
    }

    final overflow = _rows.length > maxVisibleRows ? 16.0 : 0.0;
    final candidates = _inviteCandidates;
    final shownCandidates =
        candidates.length > maxInviteRows ? maxInviteRows : candidates.length;

    if (shownCandidates > 0) {
      // 안내 한 줄만큼 내려간 자리에서 시작한다.
      final inviteTop = listBottom + overflow + 18;
      final inviteBottom = inviteTop + rowHeight * shownCandidates;
      if (local.y >= inviteTop && local.y < inviteBottom) {
        final index = ((local.y - inviteTop) / rowHeight).floor();
        _pressedRow = rows.length + index;
        return;
      }
    }

    if (_showsFooter) {
      final inviteHeight =
          shownCandidates == 0 ? 0.0 : 18 + rowHeight * shownCandidates;
      final footerTop = listBottom + overflow + inviteHeight;
      if (local.y >= footerTop && local.y < footerTop + footerHeight) {
        final width = (panelWidth - padding * 2 - 8) / 2;
        _pressedButton = local.x < padding + width ? 0 : 1;
      }
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    final row = _pressedRow;
    final button = _pressedButton;
    final closing = _pressedClose;
    final invitingAll = _pressedInviteAll;
    _pressedRow = -1;
    _pressedButton = -1;
    _pressedClose = false;
    _pressedInviteAll = false;

    if (closing) {
      close();
      return;
    }
    if (invitingAll) {
      game.inviteNearbyToParty();
      return;
    }

    if (row >= 0) {
      final rows = _rows.take(maxVisibleRows).toList();
      if (row < rows.length) {
        _onRowSelected(rows[row]);
        return;
      }
      // 파티원 다음 줄부터는 초대 후보다.
      final candidates = _inviteCandidates;
      final index = row - rows.length;
      if (index < candidates.length) {
        final target = candidates[index];
        game.invitePlayerToParty(target.characterId, target.name);
      }
      return;
    }
    if (button >= 0) _onButtonSelected(button);
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    _pressedRow = -1;
    _pressedButton = -1;
    _pressedClose = false;
    _pressedInviteAll = false;
  }

  void _onRowSelected(_Row row) {
    // 파티가 없을 때의 목록은 초대 후보다.
    if (!_party.inParty) {
      game.invitePlayerToParty(row.characterId, row.name);
      return;
    }
    // 파티 안에서는 파티장이 자리를 넘길 수 있다. 그 밖의 줄은 누를 것이 없다.
    if (_party.isLeader && !row.isSelf) {
      game.promotePartyMember(row.characterId, row.name);
    }
  }

  void _onButtonSelected(int index) {
    final party = _party;

    if (index == 1) {
      if (party.isLeader) {
        game.disbandPartyFromPanel();
      } else {
        game.leavePartyFromPanel();
      }
      close();
      return;
    }

    // 따라가는 중이거나 따라갈 사람이 있으면 그쪽을, 아니면 내가 이끈다.
    if (game.isFollowingLeader || party.hasHuntLead) {
      game.togglePartyFollow();
      return;
    }
    game.togglePartyHuntLead();
  }
}

/// 받은 파티 초대를 알리는 카드.
///
/// 패널과 따로 있는 이유는 **사람이 열어 보지 않아도 떠야 하기** 때문이다.
/// 초대는 20 초 만에 사라지므로, 메뉴를 열어야 보이는 자리에 두면 대부분 놓친다.
class PartyInviteCard extends PositionComponent
    with TapCallbacks, HasGameReference<ActionRpgGame> {
  PartyInviteCard({int priority = 140})
      : super(
          anchor: Anchor.topCenter,
          priority: priority,
          size: Vector2(300, 78),
        );

  int _pressed = -1;

  final TextPaint _title = TextPaint(
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
  final TextPaint _muted = TextPaint(
    style: TextStyle(
      color: GamePalette.textPrimary.withValues(alpha: 0.55),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    ),
  );

  /// 지금 보여 줄 초대. 없으면 카드를 그리지 않는다.
  ///
  /// 만료된 것은 거른다. 서버는 view 에서 시각을 읽을 수 없어 만료된 행도 함께
  /// 보내며, 판정은 수락할 때 서버가 다시 한다.
  PartyInviteInfo? get _invite {
    final now = DateTime.now().toUtc();
    for (final invite in game.party.invites) {
      if (!invite.isExpiredAt(now)) return invite;
    }
    return null;
  }

  @override
  void render(Canvas canvas) {
    final invite = _invite;
    if (invite == null) return;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.x, size.y),
      const Radius.circular(12),
    );
    canvas.drawRRect(rect, Paint()..color = GamePalette.hudBackground);
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = GamePalette.hudBorder.withValues(alpha: 0.7),
    );

    final name = invite.fromName.isEmpty ? '어느 요원' : invite.fromName;
    _title.render(canvas, '$name 님의 파티 초대', Vector2(12, 12));
    // 초대를 받은 사람이 가장 알고 싶은 것은 "들어가면 무엇이 달라지나" 다.
    // 파티의 값어치가 곧 이 한 줄이므로 여기에 둔다.
    _muted.render(canvas, '30m 안에서 함께 잡으면 경험치를 나눈다', Vector2(12, 30));

    const labels = ['수락', '거절'];
    final width = (size.x - 24 - 8) / 2;
    for (var i = 0; i < 2; i++) {
      final r = Rect.fromLTWH(12 + i * (width + 8), 46, width, 22);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(7)),
        Paint()
          ..color = _pressed == i
              ? GamePalette.hudBorder.withValues(alpha: 0.3)
              : GamePalette.hudBorder.withValues(alpha: 0.14),
      );
      _button.render(
        canvas,
        labels[i],
        Vector2(r.center.dx, r.center.dy),
        anchor: Anchor.center,
      );
    }
  }

  @override
  bool containsLocalPoint(Vector2 point) =>
      _invite != null && super.containsLocalPoint(point);

  @override
  void onTapDown(TapDownEvent event) {
    if (event.localPosition.y < 46) return;
    final width = (size.x - 24 - 8) / 2;
    _pressed = event.localPosition.x < 12 + width ? 0 : 1;
  }

  @override
  void onTapUp(TapUpEvent event) {
    final pressed = _pressed;
    _pressed = -1;
    final invite = _invite;
    if (pressed < 0 || invite == null) return;

    if (pressed == 0) {
      game.acceptPartyInvite(invite);
    } else {
      game.declinePartyInvite(invite);
    }
  }

  @override
  void onTapCancel(TapCancelEvent event) => _pressed = -1;
}
