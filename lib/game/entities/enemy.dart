import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flutter/material.dart';

import '../audio/game_audio.dart';
import '../fx/damage_text.dart';
import '../fx/explosion.dart';
import '../iso.dart';
import '../palette.dart';
import '../systems/level_system.dart';
import '../systems/monster_codex.dart';
import '../systems/monster_population.dart';
import 'iso_entity.dart';
import 'projectile.dart';

/// AI의 행동 단계.
enum EnemyPhase { idle, chase, telegraph, strike, recover, dead }

/// 추격을 포기하기까지 어그로 범위에 더해 주는 여유(미터).
///
/// 어그로 경계에서 추격/배회 상태가 매 프레임 뒤집히는 것을 막는다.
const double kAggroReleaseMargin = 2.5;

/// AI 로봇 적 유닛.
class Enemy extends IsoEntity with Damageable {
  Enemy({
    required this.species,
    required Vector2 grid,
    double hpMultiplier = 1.0,
  })  : stats = species.stats,
        _hpScale = hpMultiplier,
        super(
          grid: grid,
          bodyRadius: species.stats.bodyRadius,
          z: species.stats.hoverHeight,
        ) {
    _maxHp = stats.maxHp * _hpScale;
    _hp = _maxHp;
  }

  /// 이 개체가 속한 종. 레벨·이름·도색·수치가 모두 여기서 온다.
  final MonsterSpecies species;

  final MonsterStats stats;

  /// 개체별 체력 편차. 같은 종이라도 조금씩 질기다.
  ///
  /// 피해 쪽에는 이런 편차를 두지 않는다 — "레벨 N 몬스터는 정확히 N" 이라는
  /// 규격은 배율이 하나라도 끼면 깨지고, 화면의 피해 숫자는 반올림되어
  /// 표시되므로 어긋나도 눈에 띄지 않는다.
  final double _hpScale;

  /// 실루엣을 고르기 위한 골격 계통.
  MonsterBuild get build => species.build;

  /// 이 개체의 레벨(1~200).
  int get level => species.level;

  /// 도색. 종마다 다르다.
  MonsterPalette get palette => species.palette;

  /// 월드에 상주하는 개체라면 그 장부([MonsterSeed]).
  ///
  /// 웨이브로 투입된 추적대는 상주 개체가 아니므로 null이다.
  MonsterSeed? seed;

  /// 서버가 관리하는 개체라면 그 번호.
  ///
  /// 값이 있으면 **이 몹의 진실은 전부 서버에 있다.** 체력도 생사도 위치도
  /// 서버가 정하고, 이 컴포넌트는 그것을 그리기만 한다. 로컬에서 판정하면
  /// A 가 잡은 몹이 B 화면에 살아 있게 되어 "하나의 월드" 가 깨진다.
  int? serverId;

  /// 서버가 모는 개체인지.
  bool get isServerDriven => serverId != null;

  /// 서버가 모는 개체의 피해는 서버가 판정한다.
  ///
  /// 이 값이 참이면 **화면에서 무엇이 닿았든 그것만으로는 아무것도 깎이지 않는다.**
  /// 발사체처럼 이미 서버 판정이 끝난 뒤에 날아가는 연출이 또 공격을 보내는 것을
  /// 막는 데 쓴다([`Damageable.isServerJudged`]).
  @override
  bool get isServerJudged => isServerDriven;

  /// 서버가 알려 준 체력 비율. 로컬 계산을 쓰지 않는다.
  double _serverHpRatio = 1;

  /// 서버가 알려 준 생사.
  bool _serverAlive = true;

  /// 내가 선점한 몹인지. 크레딧이 나에게 오는지 색으로 알린다.
  bool taggedByMe = false;

  /// 서버가 알려 준 목표 좌표. 여기를 향해 미끄러진다.
  ///
  /// 받은 좌표로 곧바로 옮기지 않는 이유가 있다. 서버 AI 는 1/24 초마다(24 Hz)
  /// 도는데, 그 값을 즉시 반영하면 몹이 초당 스물네 번 계단을 밟듯 튄다. 목표를 향해
  /// 보간하면 같은 데이터로도 걸어오는 것처럼 보인다 — 화면을 부드럽게 하려는
  /// 것이지 판정을 흉내 내는 것이 아니다. 사거리·피해는 언제나 서버가 정한다.
  /// 이번 보간 구간의 시작점. 서버 갱신이 올 때의 **화면 위치**다.
  ///
  /// 서버가 준 이전 좌표가 아니라 지금 그려지고 있는 자리에서 출발해야 한다.
  /// 그러지 않으면 갱신마다 몸이 뒤로 튕겼다 다시 나아간다.
  Vector2? _segFrom;

  /// 이번 구간의 도착점. 서버가 마지막으로 알려 준 좌표다.
  Vector2? _segTo;

  /// 이 구간을 지나온 시간(초).
  double _segElapsed = 0;

  /// 이 구간에 배정한 시간(초). 실측 갱신 간격에서 뽑는다.
  double _segDuration = _defaultSegment;

  /// 서버 갱신 간격의 이동 평균(초).
  ///
  /// 서버 틱을 클라이언트가 상수로 알고 있으면 서버에서 그 값을 바꿀 때마다
  /// 양쪽을 함께 고쳐야 하고, 한쪽만 고치면 아무도 눈치채지 못한 채 움직임이
  /// 어색해진다. 실측해서 따라가면 그런 일이 없다.
  double _tickEstimate = _defaultSegment;

  /// 서버 갱신이 마지막으로 온 시각. 간격을 재는 기준이다.
  DateTime? _lastServerAt;

  /// 서버가 알려 준 바라보는 방향. 없으면 이동 방향에서 뽑는다.
  Vector2? _serverFacing;

  /// 마지막으로 **재생한** 타격의 서버 시각(마이크로초).
  ///
  /// `-1` 은 "아직 기준이 없다" 는 뜻이다. 첫 스냅샷이 그 값을 채우고, 그 뒤의
  /// 변화만 재생한다. 0 을 그 자리에 쓰면 **한 번도 때린 적 없는 몹의 첫
  /// 타격**(서버 기본값 epoch → 실제 시각)까지 함께 버려진다.
  int _playedAttackAt = -1;

  /// 남은 타격 동작 시간(초). 0 보다 크면 후려치는 중이다.
  double _serverStrike = 0;

  /// 타격 동작 한 번의 길이(초).
  ///
  /// 서버의 몹 공격 쿨다운(1.2초)보다 훨씬 짧게 잡는다. 길면 동작이 이어져
  /// 몇 대를 맞았는지 눈으로 셀 수 없다.
  static const double _serverStrikeDuration = 0.28;

  /// 갱신 간격을 아직 모를 때 쓰는 기본값(초). 서버 AI 틱(`MONSTER_AI_MICROS`
  /// = 41,667μs, 24 Hz)과 같은 값이다.
  ///
  /// 첫 갱신을 받기 전까지만 쓰인다. 그 뒤로는 [_tickEstimate] 가 실측으로
  /// 덮으므로, 서버 틱이 바뀌어도 여기가 어긋난 채 남을 일은 없다.
  static const double _defaultSegment = 1 / 24;

  /// 구간 길이에 곱하는 여유. 1 보다 커야 한다.
  ///
  /// **이 값이 끊김을 없애는 핵심이다.** 배정 시간을 실측 간격과 똑같이 잡으면
  /// 다음 갱신이 조금이라도 늦을 때마다 도착점에 닿아 **멈춘다** — 나아가다
  /// 서고, 새 값이 오면 다시 나아가는 그 반복이 "뚝뚝 끊기며 순간이동하는"
  /// 모습이다. 조금 느리게 지나가면 다음 값이 도착하기 전에 도달하지 않는다.
  static const double _segmentSlack = 1.25;

  /// 서버가 보낸 상태를 반영한다. 서버가 모는 개체에만 쓴다.
  void applyServerState({
    required Vector2 grid,
    required double hpRatio,
    required bool alive,
    required bool tagged,
    Vector2? facing,
    int lastAttackAtMicros = 0,
  }) {
    _beginSegment(grid);

    // **후려친 것은 사건이다.** 서버가 체력만 깎으면 어느 화면에서도 몹이
    // 때리는 장면이 나오지 않는다 — 조용히 다가와 선 채로 사람의 체력만
    // 줄어들어, 무엇에 맞았는지 알 수 없다.
    //
    // 첫 스냅샷에서는 재생하지 않는다. 시야에 들어오는 몹이 저마다 허공에
    // 한 번씩 휘두르는 것을 막기 위해서다.
    if (lastAttackAtMicros != _playedAttackAt) {
      // 첫 스냅샷은 기준만 세운다. 시야에 들어오는 몹이 저마다 허공에 한 번씩
      // 휘두르는 것을 막기 위해서다.
      if (_playedAttackAt >= 0 && lastAttackAtMicros != 0) {
        _serverStrike = _serverStrikeDuration;
      }
      _playedAttackAt = lastAttackAtMicros;
    }

    // 서버가 알려 준 방향이 있으면 그것이 맞다. **멈춰 있을 때가 이 값이 쓰이는
    // 자리다** — 좌표가 그대로면 움직임에서 방향을 뽑을 수 없다.
    if (facing != null && facing.length2 > 0.0001) {
      _serverFacing = (_serverFacing ?? Vector2.zero())..setFrom(facing);
    }
    if (hpRatio < _serverHpRatio) {
      // 남이 때린 것도 여기로 온다. 누가 때렸든 같은 연출이 나와야 여럿이
      // 함께 때리는 것이 화면에서 읽힌다.
      _hitFlash = 1;
      _healthBarTimer = 2.5;

      // **깎인 만큼을 숫자로 띄운다.** 서버로 판정을 옮기면서 이 숫자가 통째로
      // 사라졌다 — 때린 본인 화면에도 없었다. 얼마나 아픈지 보이지 않으면
      // 무기를 바꿀지 도망갈지 판단할 수 없다.
      //
      // 서버가 준 비율의 차이로 되짚는다. 정확한 피해량을 서버가 따로 보내지는
      // 않지만, 최대 체력을 곱하면 화면에 띄우기에 충분히 가깝다.
      final taken = (_serverHpRatio - hpRatio) * _maxHp;
      if (taken >= 1 && isMounted) {
        game.spawnEffect(
          DamageText(
            grid: grid.clone(),
            z: z + 0.9,
            amount: taken,
            color: taggedByMe ? GamePalette.bladeCore : GamePalette.textDim,
          ),
        );
      }
    }
    _serverHpRatio = hpRatio;

    // **쓰러짐은 사건이다.** 서버가 `alive` 를 내리는 순간을 붙잡아야 폭발과
    // 처치 점수가 나온다. 값만 갈아 두면 시체가 멀쩡히 선 채로 남고, 되살아날
    // 때까지(20초) 다른 사람들 화면에서는 "안 죽는 몹" 으로 보인다.
    //
    // 누가 막타를 넣었든 모두의 화면에서 같은 연출이 나와야 한다 — 함께 때린
    // 것이 화면에서 읽히는 유일한 순간이다.
    if (_serverAlive && !alive) {
      _serverAlive = false;
      taggedByMe = tagged;
      // 아직 월드에 붙지 않은 몸은 연출을 낼 곳이 없다. 스트리밍이 만든 직후
      // 첫 스냅샷을 넣는 순간이 그렇고, 그때 폭발을 시도하면 게임을 찾지 못해
      // 그 자리에서 죽는다. 상태만 내려 두면 붙지 않은 몸은 그려지지도 않는다.
      if (isMounted) _die();
      return;
    }

    _serverAlive = alive;
    taggedByMe = tagged;
  }

  late final double _maxHp;
  late double _hp;

  @override
  double get hp => isServerDriven ? _maxHp * _serverHpRatio : _hp;

  @override
  double get maxHp => _maxHp;

  /// 서버가 모는 개체의 생사는 서버가 정한다.
  ///
  /// 체력 비율로도 유추할 수 있지만, 되살아나는 순간(체력이 가득 찬 채로
  /// `alive` 만 바뀌는 경우)을 놓치지 않으려면 서버가 보낸 값을 그대로 쓴다.
  @override
  bool get isAlive => isServerDriven ? _serverAlive : hp > 0;

  EnemyPhase phase = EnemyPhase.idle;

  final Vector2 facing = Vector2(1, 1)..normalize();
  final Vector2 _knockback = Vector2.zero();
  final Vector2 _wanderTarget = Vector2.zero();

  double _animTime = 0;
  double _phaseTimer = 0;
  double _hitFlash = 0;
  double _healthBarTimer = 0;
  double _wanderTimer = 0;
  int _burstShotsLeft = 0;
  double _burstTimer = 0;

  static final math.Random _rng = math.Random();
  late final double _phaseOffset = _rng.nextDouble() * math.pi * 2;

  /// 이 개체가 플레이어를 알아채는 거리(타일 = 미터).
  ///
  /// 같은 종류라도 개체마다 다르며, 값은 언제나
  /// [kAggroMinMeters]~[kAggroMaxMeters] 사이에 놓인다.
  late final double aggroRange = _rollAggroRange();

  double _rollAggroRange() {
    final span = stats.aggroMaxMeters - stats.aggroMinMeters;
    final meters = stats.aggroMinMeters + _rng.nextDouble() * span;
    return metersToTiles(meters.clamp(kAggroMinMeters, kAggroMaxMeters));
  }

  /// 추격을 포기하는 거리. 어그로 경계에서 상태가 떨리지 않도록 여유를 둔다.
  double get _releaseRange => aggroRange + metersToTiles(kAggroReleaseMargin);

  /// 지금 플레이어를 노릴 수 있는지 여부.
  ///
  /// 안전지대 안으로 들어간 플레이어에게는 손을 댈 수 없다.
  bool get _canTargetPlayer {
    final player = game.player;
    return player.isAlive && !game.map.safeZone.containsPoint(player.grid);
  }

  bool get isBoss => species.isSovereign;

  @override
  void onMount() {
    super.onMount();
    // 스폰 지점이 안전지대와 겹치면 경계 바깥으로 밀어낸다.
    final zone = game.map.safeZone;
    if (zone.overlapsBody(grid.x, grid.y, bodyRadius)) {
      final outside = zone.pushOutside(grid, margin: bodyRadius + 0.2);
      grid.setFrom(game.map.nearestWalkable(outside));
      // 옮긴 좌표를 첫 프레임부터 반영한다.
      syncTransform();
    }
    _wanderTarget.setFrom(grid);
  }

  @override
  void update(double dt) {
    _animTime += dt;
    if (_hitFlash > 0) _hitFlash = math.max(0, _hitFlash - dt * 3.5);
    if (_healthBarTimer > 0) _healthBarTimer -= dt;

    // 서버가 모는 개체는 스스로 판단하지 않는다. 위치도 체력도 서버가 정하고
    // 여기서는 맞은 연출만 흐른다. 로컬 AI 를 돌리면 화면마다 다른 곳으로
    // 움직여, 같은 몹을 함께 때리는 일이 성립하지 않는다.
    if (isServerDriven) {
      _followServer(dt);
      super.update(dt);
      return;
    }

    if (!isAlive) {
      super.update(dt);
      return;
    }

    _updateAi(dt);
    _applyKnockback(dt);
    super.update(dt);
  }

  /// 새 서버 좌표를 받아 보간 구간을 연다.
  ///
  /// 갱신 간격을 실측해 구간 길이로 삼는다. 서버 틱이 바뀌어도 클라이언트가
  /// 저절로 따라가고, 네트워크가 흔들려도 평균 쪽으로 수렴한다.
  void _beginSegment(Vector2 serverGrid) {
    // **같은 좌표가 다시 오면 아무것도 하지 않는다.** 스트리밍은 서버 갱신과
    // 무관한 주기로 도므로, 올 때마다 구간을 다시 열면 지나온 시간이 매번 0 으로
    // 돌아가 진행도가 한 프레임분에 머문다. 그러면 등속 보간이 지수 감쇠로
    // 퇴화해 다시 끊겨 보인다.
    final to = _segTo;
    if (to != null && (to - serverGrid).length2 < 1e-6) return;

    final now = DateTime.now();
    final last = _lastServerAt;
    _lastServerAt = now;

    if (last != null) {
      final gap = now.difference(last).inMicroseconds / 1e6;
      // 터무니없는 값은 버린다 — 탭 전환으로 프레임이 멈췄거나 재구독으로
      // 한참 만에 온 갱신까지 평균에 넣으면 이후 움직임이 통째로 늘어진다.
      if (gap > 0.02 && gap < 1.0) {
        _tickEstimate = _tickEstimate * 0.7 + gap * 0.3;
      }
    }

    (_segFrom ??= Vector2.zero()).setFrom(grid);
    (_segTo ??= Vector2.zero()).setFrom(serverGrid);
    _segElapsed = 0;
    _segDuration = _tickEstimate * _segmentSlack;
  }

  /// 서버가 준 두 좌표 사이를 **시간으로** 지나간다.
  ///
  /// 화면을 부드럽게 하려는 것이지 판정을 흉내 내는 것이 아니다. 사거리·피해는
  /// 언제나 서버가 정하고, 여기서 계산한 위치는 그리기에만 쓴다.
  ///
  /// 목표를 향해 남은 거리에 비례해 다가가는 방식(지수 감쇠)을 쓰지 않는다.
  /// 그 방식은 가까워질수록 느려져 **도착 직전에 기어가다** 새 값이 오면 다시
  /// 튀어 나가므로, 등속으로 걷는 것이 아니라 매 갱신마다 멈칫거리는 모습이
  /// 된다. 구간을 시간으로 나누면 처음부터 끝까지 같은 속도로 지나간다.
  void _followServer(double dt) {
    final from = _segFrom;
    final to = _segTo;
    if (from == null || to == null) return;

    if ((to - grid).length > 8) {
      // 리스폰이나 텔레포트처럼 멀리 옮겨졌다. 월드를 가로질러 미끄러지는
      // 모습이 더 이상하므로 곧바로 옮긴다.
      grid.setFrom(to);
      from.setFrom(to);
      _segElapsed = _segDuration;
      phase = EnemyPhase.idle;
      _applyFacing(null);
      return;
    }

    final span = to - from;
    final moving = span.length > 0.01;

    if (_segElapsed < _segDuration) {
      _segElapsed += dt;
      final t = (_segElapsed / _segDuration).clamp(0.0, 1.0);
      grid
        ..setFrom(from)
        ..addScaled(span, t);
    }

    // 후려치는 중이면 그 자세가 이긴다. 렌더가 이 상태를 보고 공격 자세를
    // 그리므로, 걷는 모습으로 덮어 두면 때리는 장면이 사라진다.
    if (_serverStrike > 0) {
      _serverStrike = math.max(0, _serverStrike - dt);
      phase = EnemyPhase.strike;
    } else {
      phase = moving ? EnemyPhase.chase : EnemyPhase.idle;
    }
    _applyFacing(moving ? span : null);
  }

  /// 바라보는 쪽을 정한다. **서버가 준 방향이 언제나 이긴다.**
  ///
  /// 이동에서 뽑은 방향은 대체품이다 — 멈춰 서서 때리는 몹은 좌표가 그대로라
  /// 이동에서는 아무것도 나오지 않고, 그러면 마지막으로 걸어온 쪽을 계속
  /// 바라보게 된다. 옆으로 돌아 들어간 사람에게는 제 등을 향해 휘두르는
  /// 몹으로 보인다.
  void _applyFacing(Vector2? movement) {
    final server = _serverFacing;
    if (server != null && server.length2 > 0.0001) {
      facing.setFrom(server.normalized());
      return;
    }
    if (movement != null && movement.length2 > 0.0001) {
      facing.setFrom(movement.normalized());
    }
  }

  void _updateAi(double dt) {
    final player = game.player;
    final toPlayer = player.grid - grid;
    final distance = toPlayer.length;

    if (_phaseTimer > 0) _phaseTimer -= dt;

    switch (phase) {
      case EnemyPhase.idle:
        _wander(dt);
        if (_canTargetPlayer && distance <= aggroRange) {
          phase = EnemyPhase.chase;
          // 플레이어를 포착한 순간의 센서 경보음.
          GameAudio.play(Sfx.robotAlert, at: grid);
        }
      case EnemyPhase.chase:
        // 어그로가 풀리는 조건: 대상 사망, 안전지대 진입, 추격 한계 이탈.
        if (!_canTargetPlayer || distance > _releaseRange) {
          phase = EnemyPhase.idle;
          return;
        }
        if (distance > 0.01) facing.setFrom(toPlayer.normalized());
        if (distance <= stats.attackRange) {
          phase = EnemyPhase.telegraph;
          _phaseTimer = stats.telegraphTime;
          _burstShotsLeft = _burstCount;
          // 공격 예비 동작을 소리로도 알려 회피할 틈을 준다.
          GameAudio.play(Sfx.robotCharge, at: grid);
        } else {
          _moveToward(toPlayer.normalized(), stats.speed, dt);
        }
      case EnemyPhase.telegraph:
        // 예비 동작 중에 대상이 안전지대로 피하면 공격을 거둔다.
        if (!_canTargetPlayer) {
          phase = EnemyPhase.idle;
          return;
        }
        if (distance > 0.01) {
          facing.lerp(toPlayer.normalized(), (dt * 4).clamp(0.0, 1.0));
          facing.normalize();
        }
        if (_phaseTimer <= 0) {
          phase = EnemyPhase.strike;
          _phaseTimer = stats.strikeTime;
          _burstTimer = 0;
          if (!stats.ranged) _resolveMeleeStrike();
        }
      case EnemyPhase.strike:
        if (stats.ranged) {
          _burstTimer -= dt;
          if (_burstTimer <= 0 && _burstShotsLeft > 0) {
            _fire();
            _burstShotsLeft--;
            _burstTimer = 0.16;
          }
        }
        if (_phaseTimer <= 0) {
          phase = EnemyPhase.recover;
          _phaseTimer = stats.recoverTime;
        }
      case EnemyPhase.recover:
        if (_phaseTimer <= 0) {
          phase = EnemyPhase.chase;
        }
      case EnemyPhase.dead:
        break;
    }
  }

  int get _burstCount => switch (build) {
        MonsterBuild.siege => 3,
        MonsterBuild.sovereign => 5,
        _ => 1,
      };

  void _wander(double dt) {
    _wanderTimer -= dt;
    if (_wanderTimer <= 0) {
      _wanderTimer = 1.5 + _rng.nextDouble() * 2.5;
      final angle = _rng.nextDouble() * math.pi * 2;
      final radius = 1.5 + _rng.nextDouble() * 3;
      final target = Vector2(
        grid.x + math.cos(angle) * radius,
        grid.y + math.sin(angle) * radius,
      );
      // 배회 목표가 안전지대를 파고들지 않도록 경계 밖으로 되민다.
      _wanderTarget.setFrom(
        game.map.safeZone.pushOutside(target, margin: bodyRadius + 0.2),
      );
    }
    final toTarget = _wanderTarget - grid;
    if (toTarget.length2 < 0.05) return;
    final dir = toTarget.normalized();
    facing.setFrom(dir);
    _moveToward(dir, stats.speed * 0.4, dt);
  }

  /// 벽을 피하고 다른 적과 겹치지 않도록 이동한다.
  void _moveToward(Vector2 dir, double speed, double dt) {
    final steer = dir.clone();

    // 주변 유닛과의 분리(separation) 스티어링.
    final separation = Vector2.zero();
    for (final other in game.enemies) {
      if (identical(other, this) || !other.isAlive) continue;
      final away = grid - other.grid;
      final distance = away.length;
      final minDistance = bodyRadius + other.bodyRadius + 0.12;
      if (distance > 0.001 && distance < minDistance) {
        separation.add(away.normalized() * ((minDistance - distance) / minDistance));
      }
    }
    if (separation.length2 > 0.0001) {
      steer.add(separation * 1.6);
    }
    if (steer.length2 < 0.0001) return;
    steer.normalize();

    final delta = steer * speed * dt;
    _slideMove(delta);
  }

  void _slideMove(Vector2 delta) {
    final map = game.map;
    final zone = map.safeZone;
    final r = bodyRadius;

    bool free(double gx, double gy) {
      // 안전지대는 적에게 닫혀 있다. 몸통이 경계에 걸치는 것도 막는다.
      // 넉백도 이 경로를 지나므로 밀려서 들어가는 일 역시 없다.
      if (zone.overlapsBody(gx, gy, r)) return false;
      return map.isWalkableAt(gx - r, gy - r) &&
          map.isWalkableAt(gx + r, gy - r) &&
          map.isWalkableAt(gx - r, gy + r) &&
          map.isWalkableAt(gx + r, gy + r);
    }

    if (delta.x != 0 && free(grid.x + delta.x, grid.y)) grid.x += delta.x;
    if (delta.y != 0 && free(grid.x, grid.y + delta.y)) grid.y += delta.y;
  }

  void _applyKnockback(double dt) {
    if (_knockback.length2 < 0.0001) return;
    _slideMove(_knockback * dt);
    _knockback.scale(math.max(0, 1 - dt * 8));
  }

  void _resolveMeleeStrike() {
    final player = game.player;
    if (!_canTargetPlayer) return;
    final toPlayer = player.grid - grid;
    if (toPlayer.length > stats.attackRange + player.bodyRadius + 0.25) return;
    final knock = toPlayer.length2 > 0.001
        ? toPlayer.normalized() * 3.2
        : facing.clone() * 3.2;
    player.applyDamage(stats.damage, knockback: knock);
  }

  void _fire() {
    final player = game.player;
    if (!_canTargetPlayer) return;
    final aim = (player.grid - grid);
    if (aim.length2 < 0.0001) return;
    aim.normalize();

    // 지휘 유닛은 부채꼴로 흩뿌린다.
    final spread = isBoss ? 0.26 : 0.06;
    final offset = (_rng.nextDouble() - 0.5) * spread;
    final rotated = Vector2(
      aim.x * math.cos(offset) - aim.y * math.sin(offset),
      aim.x * math.sin(offset) + aim.y * math.cos(offset),
    );

    game.spawnProjectile(
      Projectile(
        grid: grid + rotated * (bodyRadius + 0.25),
        direction: rotated,
        speed: isBoss ? 7.0 : 6.2,
        damage: stats.damage,
        owner: ProjectileOwner.enemy,
        z: 0.7 * stats.scale,
        homing: isBoss ? 0.9 : 0,
      ),
    );
    GameAudio.play(isBoss ? Sfx.bossShot : Sfx.enemyShot, at: grid);
  }

  @override
  void applyDamage(double amount, {Vector2? knockback, bool critical = false}) {
    if (!isAlive) return;

    // 서버가 모는 개체는 **여기서 체력을 깎지 않는다.** 때렸다는 사실만 서버에
    // 알리고, 얼마나 깎였는지는 서버가 정해 표로 돌려준다. 로컬에서 미리 깎으면
    // 서버가 거절했을 때(사거리 밖·쿨다운) 화면과 서버가 어긋나고, 그 어긋남은
    // "분명히 때렸는데 안 죽는" 형태로 나타난다.
    if (isServerDriven) {
      game.presence.attack(serverId!);
      GameAudio.play(Sfx.robotHit, at: grid);
      return;
    }

    _hp = math.max(0, _hp - amount);
    _hitFlash = 1;
    _healthBarTimer = 2.5;
    GameAudio.play(Sfx.robotHit, at: grid);

    // 무거운 유닛일수록 넉백에 강하다.
    if (knockback != null) {
      final resistance = switch (build) {
        MonsterBuild.drone => 1.4,
        MonsterBuild.walker => 1.0,
        MonsterBuild.siege => 0.45,
        MonsterBuild.sovereign => 0.12,
      };
      _knockback.add(knockback * resistance);
    }

    game.spawnEffect(
      DamageText(
        grid: grid.clone(),
        z: z + 1.1 * stats.scale,
        amount: amount,
        color: critical ? GamePalette.hitSpark : GamePalette.textPrimary,
        critical: critical,
      ),
    );

    // 피격 시 추격 상태로 전환한다.
    if (phase == EnemyPhase.idle) phase = EnemyPhase.chase;

    if (_hp <= 0) _die();
  }

  /// 이 적의 경험치 가치. 웨이브 강화 배율까지 반영한 값이다.
  ///
  /// 플레이어 레벨에 따른 감소는 지급 시점에 [LevelSystem.killXp]가 처리한다.
  late final int xpValue =
      LevelSystem.enemyXpValue(stats.xp, hpScale: _hpScale);

  void _die() {
    phase = EnemyPhase.dead;
    game.spawnEffect(
      Explosion(
        grid: grid.clone(),
        z: z + 0.3,
        blastScale: stats.scale * (isBoss ? 2.2 : 1.0),
      ),
    );
    game.shakeCamera(isBoss ? 26 : 6, isBoss ? 0.6 : 0.15);
    GameAudio.play(
      isBoss ? Sfx.explosionBoss : Sfx.explosion,
      at: grid,
      // 덩치가 클수록 폭발이 묵직하게 들린다.
      volumeScale: stats.scale.clamp(0.8, 1.4),
    );
    game.onEnemyKilled(this);
    removeFromParent();
  }

  // ── 렌더링 ──────────────────────────────────────────────────────────

  @override
  void render(Canvas canvas) {
    final s = stats.scale;
    renderShadow(canvas, 20 * s, radiusY: 10 * s);

    // 등급 문양은 그림자 위, 본체 아래에 깔린다.
    canvas.save();
    canvas.scale(s);
    _drawTierCrest(canvas);
    canvas.restore();

    canvas.save();
    canvas.scale(s);
    if (!facesRight(facing)) canvas.scale(-1, 1);

    switch (build) {
      case MonsterBuild.drone:
        _renderScout(canvas);
      case MonsterBuild.walker:
        _renderSentry(canvas);
      case MonsterBuild.siege:
        _renderHeavy(canvas);
      case MonsterBuild.sovereign:
        _renderCommander(canvas);
    }
    canvas.restore();

    if (_hitFlash > 0) _renderHitFlash(canvas);
    if (_healthBarTimer > 0 || isBoss) _renderHealthBar(canvas);
    if (phase == EnemyPhase.telegraph) _renderTelegraph(canvas);
    if (_showNameTag) _renderNameTag(canvas);
  }

  /// 이름표를 띄울지 여부.
  ///
  /// 지휘급은 언제나, 나머지는 가까이 있거나 방금 맞았을 때만 보여 준다.
  /// 200종이 한꺼번에 이름을 달고 있으면 화면이 글자로 뒤덮인다.
  bool get _showNameTag {
    if (isBoss || _healthBarTimer > 0) return true;
    return (grid - game.player.grid).length2 <= _nameTagRangeSquared;
  }

  static const double _nameTagRangeSquared = 7.0 * 7.0;

  // ── 껍데기 붓 ───────────────────────────────────────────────────────
  //
  // 이 셋은 **한 기를 그리는 동안 네 번에서 열두 번까지 읽힌다**(종의 골격마다
  // 다르다). 읽을 때마다 [Paint] 를 새로 지으면 몹 한 기당 그만큼이 매 프레임
  // 태어나고, 화면에는 [ActionRpgGame._maxActiveMonsters] 만큼, 즉 360 기까지
  // 선다 — 초당 수십만 개다.
  //
  // 색이 달라지는 것은 피격 섬광([_hitFlash]) 하나뿐이고 [palette] 는 종이
  // 정한 값이라 개체가 사는 동안 바뀌지 않는다. 그래서 섬광이 움직였을 때만
  // 다시 칠하고, 그 외에는 같은 붓을 그대로 넘긴다.
  //
  // 🛑 **돌려받은 붓을 그리는 쪽에서 고치지 말 것.** 세 개를 온 개체가 돌려
  // 쓰므로 `..style` 이나 `..strokeWidth` 를 얹으면 그 뒤의 모든 그리기에
  // 남는다. 지금은 전부 `canvas.drawX(..., 붓)` 으로 넘기기만 한다.
  final Paint _shellPaint = Paint();
  final Paint _shellLightPaint = Paint();
  final Paint _shellDarkPaint = Paint();

  /// 세 붓을 마지막으로 칠했을 때의 [_hitFlash]. 음수면 아직 한 번도 칠하지 않았다.
  double _shellShadedAt = -1;

  void _refreshShellPaints() {
    if (_shellShadedAt == _hitFlash) return;
    _shellShadedAt = _hitFlash;
    _shellPaint.color =
        Color.lerp(palette.shell, Colors.white, _hitFlash * 0.7)!;
    _shellLightPaint.color =
        Color.lerp(palette.shellLight, Colors.white, _hitFlash * 0.7)!;
    _shellDarkPaint.color =
        Color.lerp(palette.shellDark, Colors.white, _hitFlash * 0.5)!;
  }

  Paint get _shell {
    _refreshShellPaints();
    return _shellPaint;
  }

  Paint get _shellLight {
    _refreshShellPaints();
    return _shellLightPaint;
  }

  Paint get _shellDark {
    _refreshShellPaints();
    return _shellDarkPaint;
  }

  /// 센서 아이(발광). 종의 눈 개수만큼 가로로 늘어놓는다.
  void _drawEye(Canvas canvas, Offset center, double radius) {
    final count = species.eyeCount;
    // 눈이 많아지면 하나하나는 작아져 머리 폭을 넘지 않는다.
    final r = radius / (1 + (count - 1) * 0.3);
    final gap = r * 2.4;
    final startX = center.dx - gap * (count - 1) / 2;

    for (var i = 0; i < count; i++) {
      final eye = Offset(startX + gap * i, center.dy);
      canvas.drawCircle(
        eye,
        r * 2.4,
        Paint()
          ..color = palette.eye.withValues(alpha: 0.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 2),
      );
      canvas.drawCircle(eye, r, Paint()..color = palette.eye);
      canvas.drawCircle(eye, r * 0.45, Paint()..color = palette.eyeGlow);
    }
  }

  /// 발밑에 깔리는 등급 문양. 상위 등급일수록 고리가 겹겹이 늘어난다.
  void _drawTierCrest(Canvas canvas) {
    final count = species.crestCount;
    if (count == 0) return;

    final pulse = 0.75 + math.sin(_animTime * 2.2 + _phaseOffset) * 0.25;
    for (var i = 0; i < count; i++) {
      final radiusX = 26.0 + i * 7;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: radiusX * 2,
          height: radiusX,
        ),
        Paint()
          // 밝은 바닥 위라 옅게 깔면 아예 보이지 않는다.
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = palette.energy.withValues(alpha: 0.55 * pulse),
      );
    }
  }

  void _renderScout(Canvas canvas) {
    final hover = math.sin(_animTime * 3.4 + _phaseOffset) * 3;
    final tilt = phase == EnemyPhase.chase
        ? math.sin(_animTime * 6) * 0.06
        : 0.0;

    canvas.save();
    canvas.translate(0, -34 + hover);
    canvas.rotate(tilt);

    // 회전하는 반중력 링
    final ringT = _animTime * 4;
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(0, 8),
        width: 46 + math.sin(ringT) * 3,
        height: 14,
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = palette.energy.withValues(alpha: 0.75)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // 역삼각형 동체
    final body = Path()
      ..moveTo(-17, -8)
      ..lineTo(17, -8)
      ..lineTo(8, 10)
      ..lineTo(-8, 10)
      ..close();
    canvas.drawPath(body, _shell);

    // 상단 장갑
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-14, -16, 28, 10),
        const Radius.circular(4),
      ),
      _shellLight,
    );

    // 센서
    _drawEye(canvas, const Offset(5, -2), 3.4);

    // 측면 부스터
    canvas.drawRect(Rect.fromLTWH(-22, -6, 6, 9), _shellDark);
    canvas.drawRect(Rect.fromLTWH(16, -6, 6, 9), _shellDark);
    final thrust = 0.5 + math.sin(_animTime * 18) * 0.5;
    canvas.drawCircle(
      Offset(-19, 5),
      3 * thrust + 1,
      Paint()
        ..color = palette.energy.withValues(alpha: 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(
      Offset(19, 5),
      3 * thrust + 1,
      Paint()
        ..color = palette.energy.withValues(alpha: 0.8)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    canvas.restore();
  }

  void _renderSentry(Canvas canvas) {
    final walking = phase == EnemyPhase.chase || phase == EnemyPhase.idle;
    final cycle = _animTime * 7 + _phaseOffset;
    final swing = walking ? math.sin(cycle) : 0.0;
    final bob = walking ? math.sin(cycle * 2).abs() * 2 : 0.0;
    final baseY = -bob;

    // 다리
    for (var i = 0; i < 2; i++) {
      final phaseSign = i == 0 ? swing : -swing;
      final legX = i == 0 ? -9.0 : 9.0;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(legX - 4, baseY - 36, 8, 22),
          const Radius.circular(3),
        ),
        i == 0 ? _shellDark : _shell,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(legX - 4 + phaseSign * 4, baseY - 16, 8, 14),
          const Radius.circular(3),
        ),
        _shellDark,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(legX - 7 + phaseSign * 4, baseY - 4, 15, 5),
          const Radius.circular(2),
        ),
        _shellDark,
      );
    }

    // 몸통
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-15, baseY - 66, 30, 32),
        const Radius.circular(5),
      ),
      _shell,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-11, baseY - 62, 14, 18),
        const Radius.circular(3),
      ),
      _shellLight,
    );
    // 흉부 발광 코어
    canvas.drawRect(
      Rect.fromLTWH(-4, baseY - 54, 14, 4),
      Paint()..color = palette.energy.withValues(alpha: 0.9),
    );

    // 팔(공격 모션에 따라 들어올림)
    final armLift = switch (phase) {
      EnemyPhase.telegraph => -14.0 * (1 - _phaseTimer / stats.telegraphTime),
      EnemyPhase.strike => -16.0,
      EnemyPhase.recover => -6.0,
      _ => math.sin(cycle) * 3,
    };
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-22, baseY - 62 - armLift * 0.3, 8, 26),
        const Radius.circular(3),
      ),
      _shellDark,
    );
    canvas.save();
    canvas.translate(16, baseY - 58);
    canvas.rotate(armLift * 0.055);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-4, 0, 9, 28),
        const Radius.circular(3),
      ),
      _shellLight,
    );
    // 집게형 타격구
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-7, 24, 15, 11),
        const Radius.circular(3),
      ),
      _shellDark,
    );
    canvas.restore();

    // 머리
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-10, baseY - 82, 20, 16),
        const Radius.circular(4),
      ),
      _shellLight,
    );
    _drawEye(canvas, Offset(3, baseY - 74), 3.6);
    // 안테나
    canvas.drawLine(
      Offset(-6, baseY - 82),
      Offset(-8, baseY - 92),
      Paint()
        ..color = palette.shellDark
        ..strokeWidth = 2,
    );
  }

  void _renderHeavy(Canvas canvas) {
    final idleSway = math.sin(_animTime * 2 + _phaseOffset) * 1.5;
    final walking = phase == EnemyPhase.chase;
    final cycle = _animTime * 4.5;
    final step = walking ? math.sin(cycle) : 0.0;
    final baseY = walking ? -math.sin(cycle * 2).abs() * 2 : idleSway * 0.3;

    // 굵은 다리
    for (var i = 0; i < 2; i++) {
      final legX = i == 0 ? -14.0 : 14.0;
      final phaseSign = i == 0 ? step : -step;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(legX - 8, baseY - 40, 16, 26),
          const Radius.circular(4),
        ),
        i == 0 ? _shellDark : _shell,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(legX - 10 + phaseSign * 3, baseY - 16, 20, 14),
          const Radius.circular(3),
        ),
        _shellDark,
      );
    }

    // 넓은 몸통
    final torso = Path()
      ..moveTo(-24, baseY - 78)
      ..lineTo(24, baseY - 78)
      ..lineTo(20, baseY - 38)
      ..lineTo(-20, baseY - 38)
      ..close();
    canvas.drawPath(torso, _shell);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-18, baseY - 74, 22, 24),
        const Radius.circular(4),
      ),
      _shellLight,
    );

    // 어깨 캐논
    final charging = phase == EnemyPhase.telegraph || phase == EnemyPhase.strike;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(12, baseY - 84, 26, 16),
        const Radius.circular(4),
      ),
      _shellDark,
    );
    canvas.drawRect(
      Rect.fromLTWH(34, baseY - 80, 14, 8),
      _shellLight,
    );
    if (charging) {
      final charge = phase == EnemyPhase.telegraph
          ? 1 - (_phaseTimer / stats.telegraphTime)
          : 1.0;
      canvas.drawCircle(
        Offset(50, baseY - 76),
        4 + charge * 6,
        Paint()
          ..color = palette.energy.withValues(alpha: 0.85)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + charge * 6),
      );
    }

    // 반대쪽 어깨 장갑
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-38, baseY - 82, 20, 22),
        const Radius.circular(6),
      ),
      _shellLight,
    );

    // 머리
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-12, baseY - 96, 24, 18),
        const Radius.circular(4),
      ),
      _shell,
    );
    _drawEye(canvas, Offset(0, baseY - 87), 5);
    // 배기구 발광
    canvas.drawRect(
      Rect.fromLTWH(-22, baseY - 56, 6, 12),
      Paint()..color = palette.energy.withValues(alpha: 0.6),
    );
  }

  void _renderCommander(Canvas canvas) {
    // 중장갑 메크를 기반으로 하되 위압적인 장식을 얹는다.
    _renderHeavy(canvas);

    final float = math.sin(_animTime * 1.6) * 2;

    // 등 뒤 부양 코어
    canvas.drawCircle(
      Offset(-4, -110 + float),
      13,
      Paint()
        ..color = palette.eye.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.drawCircle(
      Offset(-4, -110 + float),
      7,
      Paint()..color = palette.eyeGlow,
    );

    // 위성처럼 도는 방어 드론
    for (var i = 0; i < 3; i++) {
      final angle = _animTime * 1.8 + i * math.pi * 2 / 3;
      final orbit = Offset(math.cos(angle) * 48, math.sin(angle) * 18 - 92);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: orbit, width: 12, height: 8),
          const Radius.circular(3),
        ),
        _shellLight,
      );
      canvas.drawCircle(
        orbit,
        2.2,
        Paint()..color = palette.eye,
      );
    }

    // 지휘관 표식(뿔)
    final crown = Path()
      ..moveTo(-14, -96)
      ..lineTo(-8, -116)
      ..lineTo(-2, -98)
      ..close();
    canvas.drawPath(crown, _shellLight);
  }

  /// 머리 위 명판. `Lv.42 사냥개 MK-III` 처럼 레벨과 종 이름을 보여 준다.
  ///
  /// 글자 색은 플레이어와의 레벨 차이(위협도)를 나타내므로,
  /// 플레이어가 성장하면 명판을 다시 만든다.
  void _renderNameTag(Canvas canvas) {
    final playerLevel = game.player.level;
    var painter = _nameTagPainter;
    if (painter == null || _nameTagForLevel != playerLevel) {
      painter = TextPainter(
        text: TextSpan(
          text: 'Lv.${species.level}  ${species.name}',
          style: TextStyle(
            color: _threatColor(stats.damage, game.player.maxHp),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            height: 1,
            // 밝은 바닥 위에서도 글자가 뜨도록 흰 테두리를 깐다.
            shadows: const [
              Shadow(color: Colors.white, blurRadius: 4),
              Shadow(color: Colors.white, blurRadius: 8),
            ],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      _nameTagPainter = painter;
      _nameTagForLevel = playerLevel;
    }

    // 체력바보다 한 줄 더 위에 놓는다.
    final top = (isBoss ? -150.0 : -108.0 * stats.scale) - 14;
    painter.paint(canvas, Offset(-painter.width / 2, top));
  }

  TextPainter? _nameTagPainter;
  int _nameTagForLevel = -1;

  /// 레벨 차이를 색으로 알린다. 붉을수록 위험한 상대다.
  ///
  /// 무대가 흰빛 데이터 공간이라 글자는 어두워야 읽힌다.
  /// 밝은 글자는 바닥에 묻혀 명판 자체가 보이지 않는다.
  /// "몇 대 맞으면 쓰러지는가" 로 위협도를 나눈다.
  ///
  /// 몬스터의 피해가 곧 그 몬스터의 레벨이고 플레이어의 최대 체력을 알고
  /// 있으므로, 레벨 차보다 이쪽이 훨씬 정직한 지표다. 레벨 차로 재면
  /// 플레이어 상한이 30인데 몬스터는 200까지 있어 외곽에서는 무엇을 만나든
  /// 늘 같은 색이 된다.
  static Color _threatColor(double damage, double playerMaxHp) {
    final hits = playerMaxHp / math.max(1.0, damage);
    if (hits >= 2000) return GamePalette.textDim; // 사실상 무해
    if (hits >= 600) return GamePalette.textPrimary; // 보통
    if (hits >= 200) return const Color(0xFF9A5B00); // 주의
    if (hits >= 80) return const Color(0xFFC2341B); // 위험
    return GamePalette.robotEye; // 치명
  }

  void _renderHitFlash(Canvas canvas) {
    canvas.drawCircle(
      Offset(0, -30 * stats.scale),
      36 * stats.scale,
      Paint()
        ..color = Colors.white.withValues(alpha: _hitFlash * 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
  }

  void _renderHealthBar(Canvas canvas) {
    final s = stats.scale;
    final width = isBoss ? 96.0 : 46.0 * s;
    final height = isBoss ? 8.0 : 5.0;
    final top = isBoss ? -150.0 : -108.0 * s;
    // **`hp` 게터를 쓴다.** 서버가 모는 몹은 `_hp` 필드가 갱신되지 않으므로
    // 그것을 직접 읽으면 아무리 때려도 바가 가득 찬 채로 남는다 — 맞고 있는지
    // 조차 화면에서 읽히지 않는다.
    final ratio = (hp / _maxHp).clamp(0.0, 1.0);

    final rect = Rect.fromLTWH(-width / 2, top, width, height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.inflate(1.5), const Radius.circular(3)),
      Paint()..color = Colors.black.withValues(alpha: 0.65),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rect.left, rect.top, width * ratio, height),
        const Radius.circular(2),
      ),
      Paint()
        ..color = isBoss
            ? palette.eye
            : Color.lerp(GamePalette.hpFillLow, palette.energy, ratio)!,
    );
  }

  /// 공격 예비 동작을 알리는 지면 경고 표시.
  void _renderTelegraph(Canvas canvas) {
    final progress =
        (1 - (_phaseTimer / stats.telegraphTime)).clamp(0.0, 1.0).toDouble();
    final alpha = 0.25 + progress * 0.45;

    if (stats.ranged) {
      // 조준선
      final screenDir = gridDirToScreenDir(facing.normalized())..normalize();
      final length = stats.attackRange * kTileWidth * 0.5;
      canvas.drawLine(
        Offset(screenDir.x * 20, screenDir.y * 20 - 40 * stats.scale),
        Offset(screenDir.x * length, screenDir.y * length - 40 * stats.scale),
        Paint()
          ..strokeWidth = 1.6
          ..color = palette.eye.withValues(alpha: alpha * 0.8),
      );
    } else {
      // 근접 범위 원(아이소 타원)
      final radius = stats.attackRange * kHalfTileWidth;
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: radius * 2,
          height: radius,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = palette.eye.withValues(alpha: alpha),
      );
    }
  }
}
