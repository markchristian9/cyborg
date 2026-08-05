import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../audio/game_audio.dart';
import '../iso.dart';
import '../net/world_presence.dart';
import '../palette.dart';
import 'cyborg_design.dart';
import 'cyborg_renderer.dart';
import 'iso_entity.dart';
import 'projectile.dart';

/// 같은 월드에 있는 **다른 요원**의 몸.
///
/// 조종하지 않는 몸이므로 입력도 전투 판정도 없다. 서버가 알려 준 좌표를 향해
/// 미끄러지듯 따라가며 그려질 뿐이다.
///
/// 좌표를 그대로 순간이동시키지 않는 이유가 있다. 위치 보고는 1/24 초마다(24 Hz)
/// 오는데, 받은 값을 즉시 반영하면 다른 사람이 초당 스물네 번 계단을 밟듯 튄다.
/// 목표를 향해 보간하면 같은 데이터로도 걸어오는 것처럼 보인다 — 화면은 60fps 로
/// 그리므로 갱신 하나를 두세 프레임에 나누어 지나간다.
class RemotePlayerEntity extends IsoEntity with TapCallbacks {
  RemotePlayerEntity({required RemotePlayer snapshot})
      : characterId = snapshot.characterId,
        name = snapshot.name,
        level = snapshot.level,
        design = _designFor(snapshot.kind),
        _segFrom = snapshot.grid.clone(),
        _segTo = snapshot.grid.clone(),
        alive = snapshot.alive,
        // **지금 값을 기준으로 삼는다.** 이 사람이 시야에 들어오기 전에 휘두른
        // 공격까지 되살려 등장하자마자 허공을 치는 것을 막는다. 기준을 0 으로
        // 두고 "0 이면 재생하지 않는다" 로 처리하면 **한 번도 공격한 적 없는
        // 사람의 첫 공격**까지 함께 버려진다 — 두 사람이 마주 서서 시험할 때
        // 가장 먼저 보는 바로 그 한 번이다.
        _playedAttackAt = snapshot.lastAttackAtMicros,
        super(grid: snapshot.grid.clone(), bodyRadius: 0.28, depthBias: 0.02);

  /// 서버가 부여한 캐릭터 식별자. 같은 사람을 다시 찾는 열쇠다.
  final int characterId;

  /// 눌러서 고를 수 있는 영역의 반너비(화면 픽셀).
  ///
  /// **좁게 잡는다.** 형제 게임 라리엔은 넓은 원형 판정을 썼다가 몸 옆의 빈 땅
  /// 클릭까지 삼켜 이동이 막히는 회귀를 겪었다. 여기서도 이 값을 키우면 그만큼
  /// 월드를 클릭할 수 없어진다.
  static const double _tapHalfWidth = 26;

  /// 발밑(원점)에서 머리끝까지의 높이(화면 픽셀).
  ///
  /// 몸은 원점 **위쪽**으로 그려진다([CyborgDesign.totalHeight] 가 102~108).
  /// 이름표(`y = -78` 부근)까지 넓히지 않는 이유는, 이름표가 몸보다 넓어 옆
  /// 사람과 겹치면 엉뚱한 요원이 골라지기 때문이다.
  static const double _tapHeight = 104;

  /// 발밑에서 아래로 조금 더 잡는 여유.
  ///
  /// 발끝을 정확히 눌러야만 골라지면 손가락으로는 거의 못 고른다.
  static const double _tapFootMargin = 6;

  String name;
  int level;
  bool alive;

  /// 이 몸이 쓰는 신체 프레임. 내 캐릭터와 같은 렌더러로 그린다.
  final CyborgDesign design;

  /// 이번 보간 구간의 시작점 — 갱신이 올 때의 **화면 위치**다.
  ///
  /// 서버가 준 이전 좌표가 아니라 지금 그려지는 자리에서 출발해야 한다. 아니면
  /// 갱신마다 몸이 뒤로 튕겼다 다시 나아간다.
  final Vector2 _segFrom;

  /// 이번 구간의 도착점. 서버가 마지막으로 알려 준 좌표다.
  Vector2 _segTo;

  double _segElapsed = 0;
  double _segDuration = _defaultSegment;

  /// 서버 갱신 간격의 이동 평균(초).
  ///
  /// 보고 주기를 상수로 박아 두면 그 값을 바꿀 때 양쪽을 함께 고쳐야 하고,
  /// 한쪽만 고치면 아무도 눈치채지 못한 채 움직임이 어색해진다. 실측한다.
  double _tickEstimate = _defaultSegment;

  DateTime? _lastServerAt;

  /// 위치 보고 주기(1/24 초 = 24 Hz)를 기본값으로 삼는다.
  ///
  /// 첫 갱신 한 번을 받기 전까지만 쓰이는 값이다. 그 뒤로는 [_tickEstimate] 가
  /// 실측으로 덮으므로, 서버 주기가 바뀌어도 여기를 고치지 않아 어긋날 일은 없다.
  static const double _defaultSegment = 1 / 24;

  /// 구간 길이에 곱하는 여유. [Enemy] 와 같은 이유로 1 보다 커야 한다 —
  /// 배정 시간이 실측 간격과 같으면 갱신이 늦을 때마다 도착해 **멈춘다.**
  static const double _segmentSlack = 1.25;

  /// 서버가 알려 준 바라보는 방향.
  ///
  /// **멈춰 있을 때가 이 값이 쓰이는 자리다.** 좌표가 그대로면 움직임에서
  /// 방향을 뽑을 수 없어, 마지막으로 걸었던 쪽을 계속 바라보게 된다.
  Vector2? _serverFacing;

  double _animTime = 0;

  /// 마지막으로 나아간 방향. 멈춰 있으면 직전 방향을 유지한다.
  double _renderYaw = 0;

  /// 지금 그려지는 몸의 방향(화면 기준 라디안).
  ///
  /// 회귀 테스트가 "제자리에서 몸만 돌린 것" 을 확인하는 데 쓴다 — 좌표가
  /// 그대로라 위치로는 검사할 수 없는 값이다.
  @visibleForTesting
  double get renderYaw => _renderYaw;

  /// 실제로 움직이고 있는지. 다리 애니메이션을 켤지 정한다.
  bool _moving = false;

  // ── 공격 동작 ───────────────────────────────────────────────────────

  /// 마지막으로 **재생한** 공격의 서버 시각(마이크로초).
  ///
  /// 서버 시각을 지금 시각과 견주지 않는다. 기기 시계는 서버와 몇 초씩 어긋나
  /// 있어서, 절대 비교로 거르면 모든 공격이 "너무 오래된 것" 이 되거나 매
  /// 프레임 다시 재생된다. **값이 바뀌었는가**만 본다.
  ///
  /// 생성자가 첫 스냅샷 값으로 채운다. 그래야 "아직 기준이 없다" 와 "이 사람은
  /// 한 번도 공격한 적이 없다" 를 구별할 수 있다.
  int _playedAttackAt;

  /// 남은 공격 동작 시간(초). 0 보다 크면 휘두르는 중이다.
  double _swingTimer = 0;

  /// 이번 공격이 무엇이었는지. 스킬마다 다르게 그린다.
  int _swingSkill = AttackSkill.none;

  /// 공격 동작 한 번의 길이(초).
  ///
  /// 서버 기본 공격 쿨다운(0.35초)보다 짧게 잡는다. 길면 연타할 때 동작이
  /// 끊기지 않고 이어져, 언제 한 대가 들어갔는지 눈으로 셀 수 없다.
  static const double _swingDuration = 0.26;

  /// 지금 휘두르는 중인지. 무기를 꺼내 보일지 정한다.
  bool get isSwinging => _swingTimer > 0;

  /// 서버 외형 문자열을 신체 프레임으로 옮긴다.
  ///
  /// 모르는 값이 와도 칸이 비지 않도록 기본 프레임으로 떨어뜨린다 — 서버에
  /// 새 외형이 생겼는데 이 클라이언트가 낡았을 때를 위한 것이다.
  static CyborgDesign _designFor(String kind) {
    return kind == 'female_cyborg'
        ? CyborgDesign.infiltrator
        : CyborgDesign.assault;
  }

  /// 서버가 알려 준 체력 비율(0~1).
  ///
  /// **PK 가 허용되므로 이것이 보여야 한다.** 상대가 얼마나 버티는지 모르면
  /// 덤빌지 물러설지 판단할 수 없고, 몹에게 쫓기는 동료를 알아볼 수도 없다.
  double hpRatio = 1;

  /// 체력 바를 더 보여 줄 시간(초).
  ///
  /// 멀쩡한 사람 머리 위에까지 바를 띄우면 사냥터가 막대로 뒤덮인다. 다치거나
  /// 회복하는 동안만 잠깐 띄우고, 조용해지면 이름표만 남긴다.
  double _healthBarTimer = 0;

  /// 지금 체력 바를 그려야 하는지.
  ///
  /// 만신창이인 사람은 계속 보여 준다 — 곧 쓰러질 상대를 놓치면 PK 든 구조든
  /// 판단할 기회가 사라진다.
  bool get _showHealthBar => _healthBarTimer > 0 || hpRatio < 0.999;

  /// 서버가 보낸 새 상태를 반영한다.
  void applySnapshot(RemotePlayer snapshot) {
    _beginSegment(snapshot.grid);
    if (snapshot.facing.length2 > 0.0001) {
      _serverFacing = (_serverFacing ?? Vector2.zero())..setFrom(snapshot.facing);
    }
    name = snapshot.name;
    level = snapshot.level;
    alive = snapshot.alive;

    // 공격은 **사건**이다. 시각이 바뀐 것을 보고 한 번만 재생한다.
    //
    // 등장 직후의 헛스윙은 생성자가 기준값을 채워 막는다(위 `_playedAttackAt`).
    // 여기서 다시 "0 이면 거른다" 를 걸면 한 번도 공격한 적 없는 사람의 첫
    // 공격까지 버려진다.
    final attackAt = snapshot.lastAttackAtMicros;
    if (attackAt != _playedAttackAt) {
      if (attackAt != 0) {
        _swingTimer = _swingDuration;
        _swingSkill = snapshot.attackSkill;
        // 휘두른 방향으로 몸을 돌린다. 등 뒤를 보고 치는 모습이 되면 누구를
        // 노렸는지 알 수 없다.
        final dir = snapshot.attackDir;
        if (dir.length2 > 0.0001) _renderYaw = _yawFor(dir);

        // **원거리 스킬은 탄이 날아가는 것이 보여야 한다.** 아크만 그리면 옆
        // 사람이 무엇을 하는지 알 수 없고, 먼 곳의 몹이 이유 없이 죽는다.
        //
        // 피해는 넣지 않는다 — 판정은 서버가 이미 끝냈고 이것은 결과를 그리는
        // 연출이다. 서버 몹은 `isServerJudged` 로 걸러지지만, 그에 기대지 않고
        // 피해를 0 으로 둔다. 남의 탄이 내 화면에서 무언가를 깎으면 그 순간
        // 두 화면이 갈라진다.
        if (snapshot.attackSkill == AttackSkill.plasma &&
            dir.length2 > 0.0001) {
          _spawnRemoteBolt(dir);
        } else {
          // 근접 스윙 소리. **PK 가 허용되는 월드**라 등 뒤에서 누가 칼을
          // 휘두르는지는 화면 밖에서도 알아야 한다. 거리로 잦아들게 두어
          // 사냥터 전체가 시끄러워지지 않게 한다.
          GameAudio.play(Sfx.meleeHit, at: grid, volumeScale: 0.55);
        }
      }
      _playedAttackAt = attackAt;
    }

    final ratio = snapshot.hpRatio;
    // 값이 움직인 동안만 바를 띄운다. 다치는 쪽뿐 아니라 차오르는 쪽도 보여
    // 준다 — 회복하는 상대를 지금 칠지 기다릴지가 PK 의 판단거리다.
    if ((ratio - hpRatio).abs() > 0.001) _healthBarTimer = 3.0;
    hpRatio = ratio;
  }

  /// 새 서버 좌표를 받아 보간 구간을 연다.
  ///
  /// **같은 좌표가 다시 오면 아무것도 하지 않는다.** 게임 루프는 서버 갱신과
  /// 무관하게 매 프레임 스냅샷을 밀어 넣으므로, 올 때마다 구간을 다시 열면
  /// 지나온 시간이 매번 0 으로 돌아가 진행도가 영영 한 프레임분에 머문다.
  /// 그러면 남은 거리에 비례해 다가가는 꼴이 되어, 등속 보간이 우리가 걷어낸
  /// 지수 감쇠로 그대로 퇴화한다 — 화면에서는 다시 뚝뚝 끊긴다.
  void _beginSegment(Vector2 serverGrid) {
    if ((_segTo - serverGrid).length2 < 1e-6) return;

    final now = DateTime.now();
    final last = _lastServerAt;
    _lastServerAt = now;

    if (last != null) {
      final gap = now.difference(last).inMicroseconds / 1e6;
      // 터무니없는 값은 버린다 — 재구독이나 탭 전환으로 한참 만에 온 갱신까지
      // 평균에 넣으면 이후 움직임이 통째로 늘어진다.
      if (gap > 0.02 && gap < 1.5) {
        _tickEstimate = _tickEstimate * 0.7 + gap * 0.3;
      }
    }

    _segFrom.setFrom(grid);
    _segTo = serverGrid.clone();
    _segElapsed = 0;
    _segDuration = _tickEstimate * _segmentSlack;
  }

  @override
  void update(double dt) {
    _animTime += dt;
    if (_healthBarTimer > 0) _healthBarTimer -= dt;
    if (_swingTimer > 0) _swingTimer = math.max(0, _swingTimer - dt);

    // 멀리 벌어졌으면(접속 직후, 텔레포트, 오래 끊겼다 돌아옴) 걸어가는 시늉을
    // 하지 않고 곧바로 옮긴다. 월드를 가로질러 미끄러지는 모습이 더 이상하다.
    if ((_segTo - grid).length > 12) {
      grid.setFrom(_segTo);
      _segFrom.setFrom(_segTo);
      _segElapsed = _segDuration;
      _moving = false;
    } else {
      final span = _segTo - _segFrom;
      _moving = span.length > 0.02;

      // **구간을 시간으로 지나간다.** 남은 거리에 비례해 다가가면 도착 직전에
      // 기어가다 새 값이 오면 튀어 나가, 등속으로 걷는 대신 갱신마다 멈칫거리는
      // 모습이 된다.
      if (_segElapsed < _segDuration) {
        _segElapsed += dt;
        final t = (_segElapsed / _segDuration).clamp(0.0, 1.0);
        grid
          ..setFrom(_segFrom)
          ..addScaled(span, t);
      }

      // 서버가 준 방향이 언제나 이긴다. 이동에서 뽑는 것은 대체품이다 —
      // 멈춰 선 사람은 좌표가 그대로라 이동에서 아무것도 나오지 않는다.
      final server = _serverFacing;
      if (server != null && server.length2 > 0.0001) {
        _renderYaw = _yawFor(server);
      } else if (_moving) {
        _renderYaw = _yawFor(span);
      }
    }

    super.update(dt);
  }

  /// 남이 쏜 플라즈마 볼트. **연출 전용이다.**
  ///
  /// 발사한 본인 화면과 같은 속도·높이로 그려야 같은 장면이 된다. 다만 지연
  /// 때문에 이미 판정이 끝난 뒤에 날아가므로, 대상이 먼저 쓰러지고 탄이 그
  /// 자리를 지나가는 순간이 있을 수 있다 — 판정을 늦추는 것보다 낫다.
  void _spawnRemoteBolt(Vector2 direction) {
    game.spawnProjectile(
      Projectile(
        grid: grid + direction * 0.4,
        direction: direction,
        speed: 9.5,
        // 남의 탄은 내 화면에서 아무것도 깎지 않는다.
        damage: 0,
        owner: ProjectileOwner.player,
        z: 0.62,
      ),
    );
    GameAudio.play(Sfx.plasmaShot, at: grid, volumeScale: 0.6);
  }

  /// 공격 동작의 팔 각도.
  ///
  /// 뒤로 당겼다가 앞으로 내치는 두 박자다. 앞으로만 뻗으면 미는 동작처럼
  /// 보여서, 멀리서 보면 공격인지 알아채기 어렵다.
  double _attackArmSwing(double progress) {
    // 앞 30%는 뒤로 당기고(윈드업), 나머지는 앞으로 내친다.
    if (progress < 0.3) return 14 * (progress / 0.3);
    final strike = (progress - 0.3) / 0.7;
    return 14 - 40 * Curves.easeOutCubic.transform(strike);
  }

  /// 휘두르는 칼날과 그 궤적.
  ///
  /// **내 몸이 그리는 것과 같아야 한다**(`Player._renderBladeSwing`). 남의
  /// 공격만 흐릿한 호 하나로 지나가면, 데이터가 제대로 와도 눈에는 아무 일도
  /// 일어나지 않은 것처럼 보인다 — 그것이 "내 화면에만 칼이 보인다" 의 정체였다.
  ///
  /// 콤보 단계는 서버가 보내지 않으므로 기본 스윙 하나로 그린다. 방향과 시점은
  /// 서버가 준 값이라 모든 화면에서 같은 자리를 지나간다.
  void _renderBladeSwing(Canvas canvas, double progress) {
    const sweep = math.pi * 1.05;
    final start = _renderYaw - sweep / 2;
    final angle = start + sweep * progress;

    const pivot = Offset(0, -52);
    const length = 62.0;
    final fade = math.sin(progress * math.pi);

    // 지나온 자리에 남는 빛의 자취.
    canvas.drawArc(
      Rect.fromCircle(center: pivot, radius: length * 0.78),
      start,
      sweep * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16 * fade
        ..strokeCap = StrokeCap.round
        ..color = GamePalette.bladeGlow.withValues(alpha: 0.35 * fade)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // 칼날 — 번지는 빛 위에 또렷한 심을 겹쳐 그린다.
    final direction = Offset(math.cos(angle), math.sin(angle));
    final tip = pivot + direction * length;
    final hilt = pivot + direction * 18;
    canvas.drawLine(
      hilt,
      tip,
      Paint()
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round
        ..color = GamePalette.bladeGlow.withValues(alpha: 0.6)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawLine(
      hilt,
      tip,
      Paint()
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round
        ..color = GamePalette.bladeCore,
    );
  }

  /// 그리드 방향을 화면 기준 각도로 바꾼다.
  double _yawFor(Vector2 gridDir) {
    final screen = gridDirToScreenDir(gridDir.normalized());
    return math.atan2(screen.y, screen.x);
  }

  /// 눌린 지점이 이 몸 위인가.
  ///
  /// [IsoEntity] 는 `size` 를 잡지 않아(그리드 좌표만 다룬다) 기본 판정 영역이
  /// 없다. 그래서 몸이 실제로 그려지는 사각형을 여기서 직접 만든다 — 넣지
  /// 않으면 원격 요원을 눌러도 탭이 그대로 땅으로 내려가 이동이 된다.
  @override
  bool containsLocalPoint(Vector2 point) {
    if (!alive) return false;
    return point.x >= -_tapHalfWidth &&
        point.x <= _tapHalfWidth &&
        point.y >= -_tapHeight &&
        point.y <= _tapFootMargin;
  }

  /// 눌러서 이 요원을 고른다.
  ///
  /// 탭만 받는다. 끌기는 [TapCallbacks] 가 받지 않으므로 그대로 땅으로 내려가
  /// 이동이 되고, 몸 위를 스쳐 지나가도 걸음이 멈추지 않는다.
  ///
  /// 겹쳐 선 둘 중 누가 골라지는지는 [IsoEntity] 의 깊이 우선순위가 정한다 —
  /// 화면에서 앞에 그려진(아래쪽) 요원이 먼저 탭을 받는다. 눈에 보이는 대로다.
  @override
  void onTapUp(TapUpEvent event) {
    game.selectRemotePlayer(characterId);
  }

  @override
  void render(Canvas canvas) {
    if (!alive) {
      _renderDowned(canvas);
      return;
    }

    final cycle = _animTime * 9;
    final swing = _moving ? math.sin(cycle) : 0.0;
    final bob = _moving
        ? math.sin(cycle * 2) * 2.0 * design.bobScale
        : math.sin(_animTime * 2) * 1.2;

    // 휘두르는 중이면 걷기 대신 공격 동작이 팔을 지배한다. 둘을 섞으면 팔이
    // 어중간하게 흔들려 공격인지 걷는 중인지 구별되지 않는다.
    final swingProgress = isSwinging ? 1 - _swingTimer / _swingDuration : 0.0;
    final attackArm = isSwinging ? _attackArmSwing(swingProgress) : null;

    CyborgRenderer.drawBody(
      canvas,
      design: design,
      yaw: _renderYaw,
      baseY: -bob,
      swing: swing,
      // 등에 멘 칼은 늘 보인다. 내 몸과 같은 모습이어야 한다.
      //
      // 한때 이 값을 `isSwinging` 으로 두었는데, 그것은 오해였다 — 이 플래그는
      // **등에 멘** 칼을 그리는 것이지 휘두르는 칼날이 아니다. 그래서 휘두를
      // 때만 등에 칼이 나타났다 사라지는 반대 동작이 되었고, 정작 칼을 휘두르는
      // 모습은 한 번도 그려지지 않았다.
      showBlade: true,
      armSwing: attackArm ?? (_moving ? -swing * 6 : 0),
      time: _animTime,
    );

    if (isSwinging) _renderBladeSwing(canvas, swingProgress);
    _renderNameplate(canvas);
  }

  /// 쓰러진 몸. 아직 월드에 있지만 조종되지 않는 상태다.
  void _renderDowned(Canvas canvas) {
    canvas.save();
    canvas.translate(0, -6);
    canvas.scale(1.0, 0.35);
    canvas.drawCircle(
      Offset.zero,
      14,
      Paint()..color = GamePalette.shadow.withValues(alpha: 0.5),
    );
    canvas.restore();
    _renderNameplate(canvas);
  }

  /// 머리 위 이름표.
  ///
  /// 다른 요원을 **알아보는** 것이 이 몸을 그리는 이유의 절반이다. 누가 어느
  /// 수준인지 모르면 함께 사냥할지 피할지 판단할 수 없다.
  void _renderNameplate(Canvas canvas) {
    final label = 'Lv.$level $name';
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: alive ? GamePalette.textPrimary : GamePalette.textDim,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          shadows: const [
            Shadow(color: Colors.white, blurRadius: 3),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    const top = -78.0;
    final rect = Rect.fromCenter(
      center: Offset(0, top),
      width: painter.width + 12,
      height: painter.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(5)),
      Paint()..color = GamePalette.hudBackground.withValues(alpha: 0.85),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(5)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        // 내 몸(청록)과 구별되는 색으로 테두리를 둘러 한눈에 남임을 알린다.
        ..color = GamePalette.remotePlayer.withValues(alpha: 0.8),
    );
    painter.paint(canvas, Offset(-painter.width / 2, top - painter.height / 2));

    if (alive && _showHealthBar) _renderHealthBar(canvas, top);
  }

  /// 이름표 아래에 붙는 체력 바.
  ///
  /// 몹의 체력 바와 같은 자리·같은 크기로 그린다. 사냥터에서 눈이 한 곳만
  /// 훑으면 되도록 하려는 것이고, 색만 달리해 **사람과 로봇을 가른다.**
  void _renderHealthBar(Canvas canvas, double nameplateTop) {
    const width = 34.0;
    const height = 4.0;
    final y = nameplateTop + 11;
    final rect = Rect.fromLTWH(-width / 2, y, width, height);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(2)),
      Paint()..color = GamePalette.hudBackground.withValues(alpha: 0.85),
    );

    final filled = Rect.fromLTWH(
      rect.left,
      rect.top,
      width * hpRatio.clamp(0.0, 1.0),
      height,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(filled, const Radius.circular(2)),
      Paint()
        // 얼마 안 남았으면 붉게 바꾼다. 쓰러지기 직전인 사람은 한눈에 보여야
        // 구하러 갈지 덤빌지 정할 수 있다.
        ..color = hpRatio < 0.3
            ? GamePalette.hpFillLow
            : GamePalette.remotePlayer,
    );
  }
}
