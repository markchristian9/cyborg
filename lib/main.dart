import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'auth/cyborg_gate.dart';
import 'auth/cyborg_kind.dart';
import 'auth/cyborg_session.dart';
import 'dev/dev_frame_stats.dart';
import 'dev/dev_login.dart';
import 'game/action_rpg_game.dart';
import 'game/net/spacetime_game_sync.dart';
import 'game/palette.dart';
import 'spacetime/generated/player_character.dart';
import 'spacetime/spacetime_leaderboard.dart';
import 'spacetime/spacetime_party.dart';
import 'spacetime/spacetime_world_presence.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // `CYBORG_FRAME_STATS` 를 준 실행에서만 켜진다. 평소에는 아무 일도 하지 않는다.
  startFrameStats();
  runApp(const CyborgApp());
}

/// 게임 본체를 감싸는 앱 껍데기.
class CyborgApp extends StatelessWidget {
  const CyborgApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cyborg',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: GamePalette.hudBorder,
          brightness: Brightness.light,
        ),
      ),
      // 게임 화면 앞에 계정·캐릭터 관문을 둔다. 관문을 통과해야
      // [GameScreen]이 뜬다.
      home: const CyborgGate(),
    );
  }
}

/// [ActionRpgGame]을 띄우고 메뉴 오버레이를 붙이는 화면.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.session, this.character});

  /// 계정·캐릭터 상태. 월드 메뉴의 로그아웃이 이 세션을 접는다.
  final CyborgSession session;

  /// 출격한 캐릭터. 캐릭터 화면에 이름을 보여주는 데 쓴다.
  final PlayerCharacter? character;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  /// 게임 인스턴스는 화면이 사는 동안 한 번만 만든다. build마다 새로
  /// 만들면 월드가 통째로 다시 생성된다.
  late final ActionRpgGame _game = _createGame();

  /// 게임과 서버를 잇는다.
  ///
  /// 연결이 없으면 두 연동 모두 빼고 만든다. 게임은 [ActionRpgGame.sync]와
  /// [ActionRpgGame.leaderboard]가 없을 때를 전제로 설계되어 있으므로 오프라인
  /// 으로 그대로 돌아가고, 기록 전송과 순위 열람만 빠진다.
  ActionRpgGame _createGame() {
    final client = widget.session.client;
    final character = widget.character;

    // 서버에 저장된 누적 경험치로 출격한다. 이걸 넘기지 않으면 몸체는 1 레벨로
    // 태어나고, 서버는 이미 더 많은 누적을 알고 있어 뒤로 가는 보고를 전부
    // 버린다 — 예전 기록을 넘어설 때까지 순위가 멈춘다.
    //
    // 레벨을 따로 넘기지 않는 이유는 누적 하나로 정해지기 때문이다. 둘을 함께
    // 넘기면 서로 어긋난 상태를 만들 수 있다.
    final startTotalXp = character?.totalXp ?? 0;

    // 선택 화면에서 고른 몸을 그대로 들고 들어간다. 이걸 넘기지 않으면
    // 여성형을 골라도 월드에서는 기본 남성형으로 태어난다.
    final kind = character == null
        ? CyborgKind.male
        : CyborgKind.fromId(character.kind);

    return ActionRpgGame(
      onLogout: _confirmLogout,
      sync: client == null
          ? null
          : SpacetimeGameSync(client, startTotalXp: startTotalXp),
      leaderboard: client == null ? null : SpacetimeLeaderboard(client),
      // 같은 월드의 다른 요원. 연결이 없으면 혼자 플레이하는 모습이 된다.
      presence: client == null ? null : SpacetimeWorldPresence(client),
      // 파티. 연결이 없으면 파티가 없는 것과 화면에서 같은 모습이다.
      party: client == null ? null : SpacetimePartySession(client),
      startTotalXp: startTotalXp,
      design: kind.design,
      // 앱이 스스로 로그인하고 캐릭터까지 골라 들어왔다면 시작 메뉴에서
      // "접속하기" 를 눌러 줄 사람도 없다. 끝까지 스스로 들어간다.
      autoStart: devAutopilotEnabled,
    )..characterName = character?.name.toUpperCase() ?? 'UNIT-01';
  }

  /// 월드 메뉴에서 로그아웃을 골랐을 때. 되돌릴 수 없으니 한 번 되묻는다.
  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: GamePalette.hudBackground,
        title: const Text('로그아웃'),
        content: const Text('접속을 끊고 로그인 화면으로 돌아갑니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // 화면 전환은 하지 않는다. 세션이 끊기면 [CyborgGate]가 로그인 화면으로
    // 되돌린다. 여기서 Navigator를 건드리면 두 곳이 같은 결정을 내리게 된다.
    await widget.session.logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GamePalette.skyLow,
      body: GameWidget<ActionRpgGame>(
        game: _game,
        overlayBuilderMap: {
          Overlays.mainMenu: (context, game) => _MainMenu(game: game),
          Overlays.pauseMenu: (context, game) => _PauseMenu(game: game),
          Overlays.gameOver: (context, game) => _GameOverMenu(game: game),
        },
      ),
    );
  }
}

// ── 메인 메뉴 ─────────────────────────────────────────────────────────

class _MainMenu extends StatelessWidget {
  const _MainMenu({required this.game});

  final ActionRpgGame game;

  @override
  Widget build(BuildContext context) {
    return _MenuBackdrop(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'CYBORG',
            style: TextStyle(
              color: GamePalette.textPrimary,
              fontSize: 64,
              fontWeight: FontWeight.w900,
              letterSpacing: 14,
              shadows: [
                Shadow(color: GamePalette.playerAccent, blurRadius: 24),
              ],
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'AI가 점령한 세계, 사이보그가 반격한다',
            style: TextStyle(
              color: GamePalette.textDim,
              fontSize: 15,
              letterSpacing: 2,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 34),
          const _ControlsCard(),
          const SizedBox(height: 34),
          _MenuButton(
            label: '접속하기',
            primary: true,
            onPressed: game.startGame,
          ),
          const SizedBox(height: 12),
          const Text(
            'Enter를 눌러도 시작합니다',
            style: TextStyle(color: GamePalette.textDim, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// 조작 방법 안내표.
class _ControlsCard extends StatelessWidget {
  const _ControlsCard();

  static const List<(String, String)> _rows = [
    ('이동', 'WASD  ·  방향키'),
    ('클릭 이동', '빈 땅을 클릭 / 끌기'),
    ('근접 공격', 'Space  ·  J'),
    ('플라즈마 사격', 'K  ·  F'),
    ('대시', 'Shift  ·  L'),
    ('인벤토리', 'I  ·  Tab'),
    ('포션 사용', 'Q  ·  1~6'),
    ('일시정지', 'ESC  ·  P'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
      decoration: BoxDecoration(
        color: GamePalette.hudBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: GamePalette.hudBorder.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (label, keys) in _rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 118,
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: GamePalette.textDim,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 168,
                    child: Text(
                      keys,
                      style: const TextStyle(
                        color: GamePalette.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ── 일시정지 ──────────────────────────────────────────────────────────

class _PauseMenu extends StatelessWidget {
  const _PauseMenu({required this.game});

  final ActionRpgGame game;

  @override
  Widget build(BuildContext context) {
    return _MenuBackdrop(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '일시정지',
            style: TextStyle(
              color: GamePalette.textPrimary,
              fontSize: 38,
              fontWeight: FontWeight.w900,
              letterSpacing: 6,
            ),
          ),
          const SizedBox(height: 8),
          _StatLine(game: game),
          const SizedBox(height: 28),
          _MenuButton(
            label: '계속하기',
            primary: true,
            onPressed: game.resumeGame,
          ),
          const SizedBox(height: 12),
          _MenuButton(label: '새 월드로 재접속', onPressed: game.restart),
        ],
      ),
    );
  }
}

// ── 게임 오버 ─────────────────────────────────────────────────────────

/// 이 게임에는 원칙적으로 게임 오버가 없다(사망 시 안전지대에서 재가동).
/// 세션을 접는 흐름을 위해 오버레이만 준비해 둔다.
class _GameOverMenu extends StatelessWidget {
  const _GameOverMenu({required this.game});

  final ActionRpgGame game;

  @override
  Widget build(BuildContext context) {
    return _MenuBackdrop(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'CONNECTION LOST',
            style: TextStyle(
              color: GamePalette.hpFillLow,
              fontSize: 40,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 8),
          _StatLine(game: game),
          const SizedBox(height: 28),
          _MenuButton(
            label: '재접속',
            primary: true,
            onPressed: game.restart,
          ),
        ],
      ),
    );
  }
}

// ── 공용 조각 ─────────────────────────────────────────────────────────

/// 오버레이 공통 배경. 게임 화면을 흐리게 덮는다.
class _MenuBackdrop extends StatelessWidget {
  const _MenuBackdrop({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: GamePalette.skyLow.withValues(alpha: 0.88),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: child,
      ),
    );
  }
}

/// 처치 수·점수·재가동 횟수 한 줄 요약.
class _StatLine extends StatelessWidget {
  const _StatLine({required this.game});

  final ActionRpgGame game;

  @override
  Widget build(BuildContext context) {
    return Text(
      '처치 ${game.kills}   ·   점수 ${game.score}   ·   재가동 ${game.deaths}회',
      style: const TextStyle(
        color: GamePalette.textDim,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.label,
    required this.onPressed,
    this.primary = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor:
              primary ? GamePalette.hudBorder : GamePalette.hudInset,
          foregroundColor:
              primary ? Colors.white : GamePalette.textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            letterSpacing: 2,
          ),
        ),
      ),
    );
  }
}
