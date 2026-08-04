import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'auth/cyborg_gate.dart';
import 'game/action_rpg_game.dart';
import 'game/palette.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
      home: const GameScreen(),
    );
  }
}

/// [ActionRpgGame]을 띄우고 메뉴 오버레이를 붙이는 화면.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  /// 게임 인스턴스는 화면이 사는 동안 한 번만 만든다. build마다 새로
  /// 만들면 월드가 통째로 다시 생성된다.
  ///
  /// SpacetimeDB 연동은 [ActionRpgGame.sync]로 주입한다. null이면
  /// 완전 오프라인으로 동작한다.
  late final ActionRpgGame _game = ActionRpgGame();

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
